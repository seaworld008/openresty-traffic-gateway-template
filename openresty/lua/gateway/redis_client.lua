local cjson = require "cjson.safe"
local redis = require "resty.redis"

local M = {}

local function timeout_ms()
    return tonumber(os.getenv("GATEWAY_REDIS_TIMEOUT_MS")) or 1000
end

function M.connect()
    local client = redis:new()
    client:set_timeout(timeout_ms())

    local ok, err = client:connect(
        os.getenv("GATEWAY_REDIS_HOST") or "redis",
        tonumber(os.getenv("GATEWAY_REDIS_PORT")) or 6379
    )

    if not ok then
        return nil, err
    end

    local password = os.getenv("GATEWAY_REDIS_PASSWORD")
    if password and password ~= "" then
        local authenticated, auth_err = client:auth(password)
        if not authenticated then
            return nil, auth_err
        end
    end

    local db = tonumber(os.getenv("GATEWAY_REDIS_DB")) or 0
    if db > 0 then
        local selected, select_err = client:select(db)
        if not selected then
            return nil, select_err
        end
    end

    return client
end

function M.close(client)
    if client then
        client:set_keepalive(60000, 20)
    end
end

function M.get(key)
    local client, err = M.connect()
    if not client then
        return nil, err
    end

    local value, get_err = client:get(key)
    M.close(client)

    if value == ngx.null then
        return nil
    end

    return value, get_err
end

function M.get_json(key)
    local value, err = M.get(key)
    if not value then
        return nil, err
    end

    return cjson.decode(value)
end

return M
