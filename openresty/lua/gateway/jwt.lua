local cjson = require "cjson.safe"
local util = require "gateway.util"

local M = {}

function M.verify_hs256(token, secret)
    if not token or token == "" then
        return nil, "missing_jwt"
    end

    local header_segment, payload_segment, signature_segment = token:match("^([^.]+)%.([^.]+)%.([^.]+)$")
    if not header_segment then
        return nil, "invalid_jwt_format"
    end

    local header_json = util.base64url_decode(header_segment)
    local payload_json = util.base64url_decode(payload_segment)
    local signature = util.base64url_decode(signature_segment)

    if not header_json or not payload_json or not signature then
        return nil, "invalid_jwt_encoding"
    end

    local header = cjson.decode(header_json)
    local payload = cjson.decode(payload_json)

    if not header or not payload then
        return nil, "invalid_jwt_json"
    end

    if header.alg ~= "HS256" then
        return nil, "unsupported_jwt_alg"
    end

    local signing_input = header_segment .. "." .. payload_segment
    local expected_signature = util.hmac_sha256_bin(secret, signing_input)

    if not util.constant_time_equals(signature, expected_signature) then
        return nil, "invalid_jwt_signature"
    end

    local now = ngx.time()

    if payload.exp and tonumber(payload.exp) and now >= tonumber(payload.exp) then
        return nil, "jwt_expired"
    end

    if payload.nbf and tonumber(payload.nbf) and now < tonumber(payload.nbf) then
        return nil, "jwt_not_before"
    end

    return payload
end

return M
