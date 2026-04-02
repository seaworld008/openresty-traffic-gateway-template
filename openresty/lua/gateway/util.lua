local bit = require "bit"
local cjson = require "cjson.safe"
local resty_sha256 = require "resty.sha256"
local resty_string = require "resty.string"

local M = {}

local bxor = bit.bxor
local bor = bit.bor

function M.starts_with(value, prefix)
    return type(value) == "string" and value:sub(1, #prefix) == prefix
end

function M.base64url_decode(value)
    if not value or value == "" then
        return nil
    end

    local normalized = value:gsub("-", "+"):gsub("_", "/")
    local remainder = #normalized % 4

    if remainder == 2 then
        normalized = normalized .. "=="
    elseif remainder == 3 then
        normalized = normalized .. "="
    elseif remainder ~= 0 then
        return nil
    end

    return ngx.decode_base64(normalized)
end

function M.base64url_encode(value)
    return ngx.encode_base64(value):gsub("+", "-"):gsub("/", "_"):gsub("=", "")
end

function M.sha256_bin(value)
    local sha256 = resty_sha256:new()
    sha256:update(value)
    return sha256:final()
end

function M.hmac_sha256_bin(key, message)
    local block_size = 64

    if #key > block_size then
        key = M.sha256_bin(key)
    end

    if #key < block_size then
        key = key .. string.rep("\0", block_size - #key)
    end

    local ipad = {}
    local opad = {}

    for index = 1, block_size do
        local byte = key:byte(index)
        ipad[index] = string.char(bxor(byte, 0x36))
        opad[index] = string.char(bxor(byte, 0x5c))
    end

    local inner = M.sha256_bin(table.concat(ipad) .. message)
    return M.sha256_bin(table.concat(opad) .. inner)
end

function M.hmac_sha256_hex(key, message)
    return resty_string.to_hex(M.hmac_sha256_bin(key, message))
end

function M.constant_time_equals(left, right)
    if not left or not right or #left ~= #right then
        return false
    end

    local diff = 0

    for index = 1, #left do
        diff = bor(diff, bxor(left:byte(index), right:byte(index)))
    end

    return diff == 0
end

function M.decode_json(value)
    if not value or value == "" then
        return nil
    end

    return cjson.decode(value)
end

function M.encode_json(value)
    return cjson.encode(value)
end

function M.exit_json(status, code, message)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json; charset=utf-8"
    ngx.say(cjson.encode({
        code = code,
        message = message,
        request_id = ngx.ctx.gateway_request_id or ngx.var.request_id or "",
    }))
    return ngx.exit(status)
end

function M.read_body()
    ngx.req.read_body()
    return ngx.req.get_body_data() or ""
end

function M.set_body(body)
    ngx.req.set_body_data(body)
    ngx.req.set_header("Content-Length", #body)
end

function M.render_template(value, context)
    if type(value) ~= "string" then
        return value
    end

    return (value:gsub("{{([%w_]+)}}", function(key)
        local resolved = context[key]
        if resolved == nil then
            return ""
        end

        return tostring(resolved)
    end))
end

function M.ipv4_to_number(ip)
    local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then
        return nil
    end

    a = tonumber(a)
    b = tonumber(b)
    c = tonumber(c)
    d = tonumber(d)

    if not a or a > 255 or b > 255 or c > 255 or d > 255 then
        return nil
    end

    return ((a * 256 + b) * 256 + c) * 256 + d
end

function M.ip_in_cidr(ip, cidr)
    local base, mask_bits = cidr:match("^([%d%.]+)/(%d+)$")
    if not base then
        return ip == cidr
    end

    local ip_num = M.ipv4_to_number(ip)
    local base_num = M.ipv4_to_number(base)
    mask_bits = tonumber(mask_bits)

    if not ip_num or not base_num or not mask_bits or mask_bits < 0 or mask_bits > 32 then
        return false
    end

    if mask_bits == 0 then
        return true
    end

    local host_bits = 32 - mask_bits
    local divisor = 2 ^ host_bits

    return math.floor(ip_num / divisor) == math.floor(base_num / divisor)
end

function M.ip_matches(ip, rules)
    if not ip or type(rules) ~= "table" then
        return false
    end

    for _, rule in ipairs(rules) do
        if M.ip_in_cidr(ip, rule) then
            return true
        end
    end

    return false
end

function M.lower(value)
    if type(value) ~= "string" then
        return ""
    end

    return value:lower()
end

function M.ua_matches(user_agent, patterns)
    local normalized = M.lower(user_agent)

    for _, pattern in ipairs(patterns or {}) do
        if normalized:find(M.lower(pattern), 1, true) then
            return true
        end
    end

    return false
end

function M.cookie_value(name)
    return ngx.var["cookie_" .. name]
end

function M.request_hash_seed()
    local request_id = ngx.ctx.gateway_request_id or ngx.var.request_id or ""
    local remote_addr = ngx.var.remote_addr or ""
    return request_id .. ":" .. remote_addr
end

function M.choose_percent(percent)
    if not percent or percent <= 0 then
        return false
    end

    local bucket = ngx.crc32_short(M.request_hash_seed()) % 100
    return bucket < percent
end

function M.trim(value)
    if type(value) ~= "string" then
        return value
    end

    return value:match("^%s*(.-)%s*$")
end

return M
