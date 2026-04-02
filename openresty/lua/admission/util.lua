local gateway_util = require "gateway.util"

local M = {}

local function cookie_name()
    return os.getenv("GATEWAY_ADMISSION_COOKIE_NAME") or "gw_admission"
end

local function ops_token()
    return os.getenv("GATEWAY_OPS_TOKEN") or ""
end

function M.resolve_user_id()
    local headers = ngx.req.get_headers()
    return headers["X-User-Id"]
        or ngx.var.cookie_app_user_id
        or ngx.var.arg_user_id
        or ""
end

function M.cookie_name()
    return cookie_name()
end

function M.current_cookie()
    return ngx.var["cookie_" .. cookie_name()]
end

function M.set_cookie(token, max_age)
    local parts = {
        cookie_name() .. "=" .. token,
        "Path=/",
        "HttpOnly",
        "SameSite=Lax",
        "Max-Age=" .. tostring(max_age),
    }

    if ngx.var.scheme == "https" then
        parts[#parts + 1] = "Secure"
    end

    ngx.header["Set-Cookie"] = table.concat(parts, "; ")
end

function M.json_response(status, payload)
    ngx.status = status
    ngx.header["Cache-Control"] = "no-store"
    ngx.header["Content-Type"] = "application/json; charset=utf-8"
    ngx.say(gateway_util.encode_json(payload))
    return ngx.exit(status)
end

function M.bad_request(code, message)
    return M.json_response(400, {
        code = code,
        message = message,
        request_id = ngx.var.request_id,
    })
end

function M.unauthorized(code, message)
    return M.json_response(428, {
        code = code,
        message = message,
        request_id = ngx.var.request_id,
        waitroom_path = "/waitroom.html",
    })
end

function M.precondition_required(code, message)
    return M.unauthorized(code, message)
end

function M.service_unavailable(code, message, detail)
    return M.json_response(503, {
        code = code,
        message = message,
        detail = detail,
        request_id = ngx.var.request_id,
    })
end

function M.forbidden(code, message)
    return M.json_response(403, {
        code = code,
        message = message,
        request_id = ngx.var.request_id,
    })
end

function M.require_ops_access()
    local expected = ops_token()
    if expected == "" then
        return true
    end

    local provided = ngx.req.get_headers()["X-Ops-Token"] or ""
    if provided == expected then
        return true
    end

    return M.forbidden("ops_token_invalid", "缺少或错误的运维访问令牌")
end

return M
