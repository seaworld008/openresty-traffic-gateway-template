local cjson = require "cjson.safe"
local gateway_util = require "gateway.util"

local M = {}

local function secret()
    return os.getenv("GATEWAY_QUEUE_SECRET") or "change-this-before-production"
end

function M.encode(payload)
    local payload_segment = gateway_util.base64url_encode(cjson.encode(payload))
    local signature = gateway_util.base64url_encode(
        gateway_util.hmac_sha256_bin(secret(), payload_segment)
    )
    return payload_segment .. "." .. signature
end

function M.decode(token)
    if not token or token == "" then
        return nil, "missing_token"
    end

    local payload_segment, signature_segment = token:match("^([^.]+)%.([^.]+)$")
    if not payload_segment then
        return nil, "invalid_token_format"
    end

    local expected_signature = gateway_util.base64url_encode(
        gateway_util.hmac_sha256_bin(secret(), payload_segment)
    )

    if not gateway_util.constant_time_equals(signature_segment, expected_signature) then
        return nil, "invalid_token_signature"
    end

    local payload_json = gateway_util.base64url_decode(payload_segment)
    if not payload_json then
        return nil, "invalid_token_payload"
    end

    local payload = cjson.decode(payload_json)
    if type(payload) ~= "table" then
        return nil, "invalid_token_json"
    end

    if tonumber(payload.expires_at or 0) <= ngx.time() then
        return nil, "token_expired"
    end

    return payload
end

return M
