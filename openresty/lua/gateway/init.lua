local circuit_breaker = require "gateway.circuit_breaker"
local config_loader = require "gateway.config_loader"
local jwt = require "gateway.jwt"
local redis_client = require "gateway.redis_client"
local request_id = require "gateway.request_id"
local response = require "gateway.response"
local rewrite = require "gateway.rewrite"
local risk = require "gateway.risk"
local router = require "gateway.router"
local signature = require "gateway.signature"
local util = require "gateway.util"

local M = {}

local state_dict = ngx.shared.gateway_state

local function metadata_cache_ttl()
    return tonumber(os.getenv("GATEWAY_METADATA_CACHE_TTL_SECONDS")) or 10
end

local function load_partner_metadata(route)
    if not route.partner_metadata_key_prefix then
        return nil
    end

    local partner_key = ngx.req.get_headers()["X-Partner-Key"]
    if not partner_key or partner_key == "" then
        return nil
    end

    ngx.ctx.partner_key = partner_key

    local cache_key = "partner_metadata:" .. partner_key
    local cached_payload = state_dict:get(cache_key)
    if cached_payload then
        local decoded_cached = util.decode_json(cached_payload)
        if decoded_cached then
            return decoded_cached
        end
    end

    local metadata, err = redis_client.get_json(route.partner_metadata_key_prefix .. partner_key)
    if err then
        ngx.log(ngx.ERR, "读取合作方配置失败: ", err)
        return nil, "redis_unavailable"
    end

    if metadata then
        state_dict:set(cache_key, util.encode_json(metadata), metadata_cache_ttl())
    end

    return metadata
end

local function bearer_token()
    local authorization = ngx.req.get_headers()["Authorization"] or ""
    return authorization:match("^Bearer%s+(.+)$")
end

local function enforce_auth(route)
    local auth = route.auth or {}
    if not next(auth) then
        return true
    end

    if auth.require_partner_key and not ngx.ctx.partner_key then
        return util.exit_json(401, "missing_partner_key", "缺少 X-Partner-Key")
    end

    if auth.require_hmac then
        local metadata = ngx.ctx.partner_metadata
        if not metadata or not metadata.hmac_secret then
            return util.exit_json(503, "missing_partner_hmac_secret", "合作方 HMAC 配置不存在")
        end

        local request_body = util.read_body()
        local ok, err = signature.verify(metadata.hmac_secret, request_body, auth.hmac_max_skew_seconds)
        if not ok then
            return util.exit_json(401, err, "HMAC 或时间戳校验失败")
        end
    end

    if auth.require_jwt then
        local metadata = ngx.ctx.partner_metadata
        if not metadata or not metadata.jwt_secret then
            return util.exit_json(503, "missing_partner_jwt_secret", "合作方 JWT 配置不存在")
        end

        local payload, err = jwt.verify_hs256(bearer_token(), metadata.jwt_secret)
        if not payload then
            return util.exit_json(401, err, "JWT 校验失败")
        end

        ngx.ctx.auth_subject = payload.sub or ""
    end

    return true
end

function M.access()
    request_id.ensure()
    risk.resolve_client_ip()

    local policy_name = ngx.var.gateway_policy
    local policy = config_loader.load_policy(policy_name)

    if not policy then
        return util.exit_json(500, "missing_policy", "未找到网关策略配置")
    end

    ngx.ctx.gateway_policy = policy_name
    ngx.var.gateway_gray_variant = "stable"

    local route, route_err = router.select(policy)
    if not route then
        return util.exit_json(404, route_err or "route_not_found", "未匹配到任何路由")
    end

    ngx.var.gateway_route = route.id
    ngx.var.gateway_gray_variant = ngx.ctx.gateway_gray_variant or "stable"
    ngx.ctx.selected_route = route
    ngx.ctx.partner_metadata, route_err = load_partner_metadata(route)

    if route_err == "redis_unavailable" then
        return util.exit_json(503, route_err, "Redis 不可用，无法读取合作方配置")
    end

    risk.enforce(policy.risk)
    risk.enforce(route.risk)
    enforce_auth(route)

    local selected_upstream = route.upstream
    local selected_upstream_uri = route.upstream_uri or ngx.var.request_uri

    if route.circuit_breaker and circuit_breaker.is_open(route.id) then
        ngx.var.gateway_circuit_state = "open"
        ngx.ctx.circuit_open = true

        if route.fallback_upstream then
            selected_upstream = route.fallback_upstream
            selected_upstream_uri = route.fallback_upstream_uri or ngx.var.request_uri
        else
            return util.exit_json(503, "circuit_open", "上游熔断已开启")
        end
    else
        ngx.var.gateway_circuit_state = "closed"
    end

    ngx.var.gateway_upstream = selected_upstream
    ngx.var.gateway_upstream_uri = selected_upstream_uri
    ngx.ctx.response_rewrite = route.response_rewrite

    rewrite.apply_request_rewrite(route.request_rewrite)
end

function M.header_filter()
    response.header_filter()
end

function M.body_filter()
    response.body_filter()
end

function M.log()
    local route = ngx.ctx.selected_route
    if not route or not route.circuit_breaker or ngx.ctx.circuit_open then
        return
    end

    local upstream_status = ngx.var.upstream_status or ""
    local failed = upstream_status:find("502", 1, true)
        or upstream_status:find("503", 1, true)
        or upstream_status:find("504", 1, true)
        or ngx.status >= 500

    circuit_breaker.record(route.id, route.circuit_breaker, failed)
end

return M
