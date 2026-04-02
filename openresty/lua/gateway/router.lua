local redis_client = require "gateway.redis_client"
local util = require "gateway.util"

local M = {}
local state_dict = ngx.shared.gateway_state

local function gray_flag_cache_ttl()
    return tonumber(os.getenv("GATEWAY_GRAY_FLAG_CACHE_TTL_SECONDS")) or 2
end

local function longest_prefix_match(routes, uri)
    local selected

    for _, route in ipairs(routes or {}) do
        if util.starts_with(uri, route.path_prefix or "/") then
            if not selected or #(route.path_prefix or "/") > #(selected.path_prefix or "/") then
                selected = route
            end
        end
    end

    return selected
end

local function resolve_header_route(route)
    if type(route.header_upstreams) ~= "table" then
        return route.upstream
    end

    for header_name, values in pairs(route.header_upstreams) do
        local header_value = ngx.req.get_headers()[header_name]
        if header_value and values[header_value] then
            return values[header_value], header_name, header_value
        end
    end

    return route.upstream
end

local function redis_gray_enabled(route)
    if not route.gray or not route.gray.redis_flag_key then
        return true
    end

    local cache_key = "gray_flag:" .. route.gray.redis_flag_key
    local cached = state_dict:get(cache_key)
    if cached ~= nil then
        return cached == 1
    end

    local flag, err = redis_client.get(route.gray.redis_flag_key)
    if err then
        ngx.log(ngx.ERR, "读取灰度 Redis 开关失败: ", err)
        return false
    end

    if not flag then
        state_dict:set(cache_key, 1, gray_flag_cache_ttl())
        return true
    end

    local enabled = flag ~= "0"
    state_dict:set(cache_key, enabled and 1 or 0, gray_flag_cache_ttl())
    return enabled
end

local function resolve_gray(route)
    if type(route.gray) ~= "table" then
        return route.upstream, "stable"
    end

    if not redis_gray_enabled(route) then
        return route.gray.stable_upstream or route.upstream, "stable"
    end

    local headers = ngx.req.get_headers()
    local header_name = route.gray.header_name
    local cookie_name = route.gray.cookie_name

    if header_name and headers[header_name] == route.gray.canary_value then
        return route.gray.canary_upstream, "canary"
    end

    if cookie_name and util.cookie_value(cookie_name) == route.gray.canary_value then
        return route.gray.canary_upstream, "canary"
    end

    if route.gray.percent and util.choose_percent(route.gray.percent) then
        return route.gray.canary_upstream, "canary"
    end

    return route.gray.stable_upstream or route.upstream, "stable"
end

function M.select(policy)
    local route = longest_prefix_match(policy.routes, ngx.var.uri or "/")
    if not route then
        return nil, "route_not_found"
    end

    local upstream = route.upstream
    local route_source = "static"

    if route.gray then
        upstream, ngx.ctx.gateway_gray_variant = resolve_gray(route)
        route_source = "gray"
    else
        upstream, ngx.ctx.gateway_route_decision_header, ngx.ctx.gateway_route_decision_value = resolve_header_route(route)
        ngx.ctx.gateway_gray_variant = "stable"
        if ngx.ctx.gateway_route_decision_header then
            route_source = "header"
        end
    end

    return {
        id = route.id,
        upstream = upstream,
        route_source = route_source,
        fallback_upstream = route.fallback_upstream,
        circuit_breaker = route.circuit_breaker,
        auth = route.auth or {},
        request_rewrite = route.request_rewrite,
        response_rewrite = route.response_rewrite,
        risk = route.risk,
        partner_metadata_key_prefix = route.partner_metadata_key_prefix,
    }
end

return M
