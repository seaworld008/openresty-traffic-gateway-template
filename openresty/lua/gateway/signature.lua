local util = require "gateway.util"

local M = {}

function M.verify(secret, request_body, max_skew_seconds)
    local headers = ngx.req.get_headers()
    local timestamp = headers["X-Timestamp"]
    local signature = headers["X-Signature"]

    if not timestamp or not signature then
        return nil, "missing_signature_headers"
    end

    local ts = tonumber(timestamp)
    if not ts then
        return nil, "invalid_timestamp"
    end

    local skew = math.abs(ngx.time() - ts)
    if skew > (max_skew_seconds or 300) then
        return nil, "timestamp_expired"
    end

    local canonical = table.concat({
        ngx.req.get_method(),
        ngx.var.uri or "/",
        timestamp,
        request_body or "",
    }, "\n")

    local expected = util.hmac_sha256_hex(secret, canonical)

    if not util.constant_time_equals(signature:lower(), expected) then
        return nil, "invalid_signature"
    end

    return true
end

return M
