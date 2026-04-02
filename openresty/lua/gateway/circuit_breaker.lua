local M = {}

local dict = ngx.shared.gateway_circuit

local function open_key(route_id)
    return "open:" .. route_id
end

local function fail_key(route_id)
    return "fail:" .. route_id
end

function M.is_open(route_id)
    local opened_until = dict:get(open_key(route_id))
    return opened_until and opened_until > ngx.now()
end

function M.record(route_id, breaker_conf, failed)
    if not route_id or type(breaker_conf) ~= "table" then
        return
    end

    if not failed then
        dict:delete(fail_key(route_id))
        return
    end

    local fails = dict:incr(
        fail_key(route_id),
        1,
        0,
        breaker_conf.window_seconds or breaker_conf.open_seconds or 30
    )

    if fails and fails >= (breaker_conf.failure_threshold or 2) then
        dict:set(
            open_key(route_id),
            ngx.now() + (breaker_conf.open_seconds or 20),
            breaker_conf.open_seconds or 20
        )
        dict:delete(fail_key(route_id))
    end
end

return M
