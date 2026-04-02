local util = require "gateway.util"

local M = {}

local function reject(status, code, message)
    return util.exit_json(status, code, message)
end

function M.resolve_client_ip()
    local client_ip = ngx.var.remote_addr or ""
    ngx.ctx.gateway_client_ip = client_ip
    ngx.var.gateway_client_ip = client_ip
    return client_ip
end

function M.enforce(risk_conf)
    if type(risk_conf) ~= "table" then
        return true
    end

    local client_ip = ngx.ctx.gateway_client_ip or M.resolve_client_ip()
    local user_agent = ngx.req.get_headers()["User-Agent"] or ""

    if risk_conf.whitelist_ips and #risk_conf.whitelist_ips > 0 then
        if not util.ip_matches(client_ip, risk_conf.whitelist_ips) then
            return reject(403, "ip_not_allowed", "当前来源 IP 不在白名单内")
        end
    end

    if risk_conf.blacklist_ips and util.ip_matches(client_ip, risk_conf.blacklist_ips) then
        return reject(403, "ip_blocked", "当前来源 IP 已被封禁")
    end

    if risk_conf.blocked_ua_patterns and util.ua_matches(user_agent, risk_conf.blocked_ua_patterns) then
        return reject(403, "ua_blocked", "当前 User-Agent 已被风控拦截")
    end

    return true
end

return M
