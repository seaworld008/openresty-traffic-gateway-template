local gateway_util = require "gateway.util"
local redis_client = require "gateway.redis_client"

local M = {}

local function user_hash(user_id)
    return ngx.md5(user_id)
end

local function key(prefix, ...)
    local parts = { "admission3", prefix }
    for index = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(index, ...))
    end
    return table.concat(parts, ":")
end

local function decode_json(value)
    if not value or value == ngx.null then
        return nil
    end
    return gateway_util.decode_json(value)
end

local function shared_keys(policy, user_id)
    local activity_id = policy.activity_id
    local hashed_user = user_hash(user_id)

    return {
        active = key("active", activity_id),
        queue = key("queue", activity_id),
        user_active = key("user_active", activity_id, hashed_user),
        user_ticket = key("user_ticket", activity_id, hashed_user),
        sequence = key("sequence", activity_id),
        grant_prefix = key("grant", activity_id) .. ":",
        ticket_prefix = key("ticket", activity_id) .. ":",
    }
end

function M.connect()
    return redis_client.connect()
end

function M.close(client)
    return redis_client.close(client)
end

function M.load_existing_admission(client, policy, user_id)
    local keys = shared_keys(policy, user_id)
    local token_id = client:get(keys.user_active)
    if not token_id or token_id == ngx.null then
        return nil
    end

    return decode_json(client:get(keys.grant_prefix .. token_id))
end

function M.join_or_queue_atomic(client, policy, user_id, steady_payload, burst_payload, ticket_payload)
    local keys = shared_keys(policy, user_id)

    local script = [[
        local active_key = KEYS[1]
        local queue_key = KEYS[2]
        local user_active_key = KEYS[3]
        local user_ticket_key = KEYS[4]
        local sequence_key = KEYS[5]

        local now = tonumber(ARGV[1])
        local cleanup_batch = tonumber(ARGV[2])
        local steady_limit = tonumber(ARGV[3])
        local burst_limit = tonumber(ARGV[4])
        local token_ttl = tonumber(ARGV[5])
        local queue_ttl = tonumber(ARGV[6])
        local grant_prefix = ARGV[7]
        local ticket_prefix = ARGV[8]
        local steady_token_id = ARGV[9]
        local steady_payload = ARGV[10]
        local steady_expires_at = tonumber(ARGV[11])
        local burst_token_id = ARGV[12]
        local burst_payload = ARGV[13]
        local burst_expires_at = tonumber(ARGV[14])
        local ticket_id = ARGV[15]
        local ticket_payload = ARGV[16]

        redis.call("ZREMRANGEBYSCORE", active_key, "-inf", now)

        local head = redis.call("ZRANGE", queue_key, 0, cleanup_batch - 1)
        for _, member in ipairs(head) do
            if not redis.call("GET", ticket_prefix .. member) then
                redis.call("ZREM", queue_key, member)
            end
        end

        local existing_token_id = redis.call("GET", user_active_key)
        if existing_token_id then
            local existing_payload = redis.call("GET", grant_prefix .. existing_token_id)
            if existing_payload then
                local active_count = tonumber(redis.call("ZCARD", active_key)) or 0
                return { "admitted_existing", existing_payload, tostring(active_count) }
            end
            redis.call("DEL", user_active_key)
        end

        local active_count = tonumber(redis.call("ZCARD", active_key)) or 0
        if active_count < steady_limit then
            redis.call("SETEX", grant_prefix .. steady_token_id, token_ttl, steady_payload)
            redis.call("SETEX", user_active_key, token_ttl, steady_token_id)
            redis.call("ZADD", active_key, steady_expires_at, steady_token_id)
            return { "admitted", steady_payload, tostring(active_count + 1) }
        end

        if active_count < burst_limit then
            redis.call("SETEX", grant_prefix .. burst_token_id, token_ttl, burst_payload)
            redis.call("SETEX", user_active_key, token_ttl, burst_token_id)
            redis.call("ZADD", active_key, burst_expires_at, burst_token_id)
            return { "admitted", burst_payload, tostring(active_count + 1) }
        end

        local existing_ticket_id = redis.call("GET", user_ticket_key)
        if existing_ticket_id then
            local existing_ticket_payload = redis.call("GET", ticket_prefix .. existing_ticket_id)
            if existing_ticket_payload then
                local rank = redis.call("ZRANK", queue_key, existing_ticket_id)
                return { "queued_existing", existing_ticket_payload, tostring((rank or 0) + 1), tostring(active_count) }
            end
            redis.call("DEL", user_ticket_key)
            redis.call("ZREM", queue_key, existing_ticket_id)
        end

        local sequence = redis.call("INCR", sequence_key)
        redis.call("SETEX", ticket_prefix .. ticket_id, queue_ttl, ticket_payload)
        redis.call("SETEX", user_ticket_key, queue_ttl, ticket_id)
        redis.call("ZADD", queue_key, sequence, ticket_id)
        local rank = redis.call("ZRANK", queue_key, ticket_id)
        return { "queued", ticket_payload, tostring((rank or 0) + 1), tostring(active_count) }
    ]]

    local result, err = client:eval(
        script,
        5,
        keys.active,
        keys.queue,
        keys.user_active,
        keys.user_ticket,
        keys.sequence,
        ngx.time(),
        policy.queue.cleanup_batch,
        policy.capacity.steady,
        policy.capacity.burst,
        policy.token.ttl_seconds,
        policy.queue.ttl_seconds,
        keys.grant_prefix,
        keys.ticket_prefix,
        steady_payload.token_id,
        gateway_util.encode_json(steady_payload),
        steady_payload.expires_at,
        burst_payload.token_id,
        gateway_util.encode_json(burst_payload),
        burst_payload.expires_at,
        ticket_payload.ticket_id,
        gateway_util.encode_json(ticket_payload)
    )

    if not result then
        return nil, err
    end

    local mode = result[1]
    if mode == "admitted" or mode == "admitted_existing" then
        return {
            status = "admitted",
            payload = decode_json(result[2]),
            active_count = tonumber(result[3]) or 0,
        }
    end

    return {
        status = "queued",
        payload = decode_json(result[2]),
        position = tonumber(result[3]) or 1,
        active_count = tonumber(result[4]) or 0,
    }
end

function M.status_or_admit_atomic(client, policy, user_id, ticket_id, steady_payload, burst_payload)
    local keys = shared_keys(policy, user_id)

    local script = [[
        local active_key = KEYS[1]
        local queue_key = KEYS[2]
        local user_ticket_key = KEYS[3]
        local user_active_key = KEYS[4]

        local now = tonumber(ARGV[1])
        local cleanup_batch = tonumber(ARGV[2])
        local ticket_id = ARGV[3]
        local steady_limit = tonumber(ARGV[4])
        local burst_limit = tonumber(ARGV[5])
        local token_ttl = tonumber(ARGV[6])
        local grant_prefix = ARGV[7]
        local ticket_prefix = ARGV[8]
        local steady_token_id = ARGV[9]
        local steady_payload = ARGV[10]
        local steady_expires_at = tonumber(ARGV[11])
        local burst_token_id = ARGV[12]
        local burst_payload = ARGV[13]
        local burst_expires_at = tonumber(ARGV[14])

        redis.call("ZREMRANGEBYSCORE", active_key, "-inf", now)

        local head = redis.call("ZRANGE", queue_key, 0, cleanup_batch - 1)
        for _, member in ipairs(head) do
            if not redis.call("GET", ticket_prefix .. member) then
                redis.call("ZREM", queue_key, member)
            end
        end

        local existing_token_id = redis.call("GET", user_active_key)
        if existing_token_id then
            local existing_payload = redis.call("GET", grant_prefix .. existing_token_id)
            if existing_payload then
                local active_count = tonumber(redis.call("ZCARD", active_key)) or 0
                return { "admitted_existing", existing_payload, tostring(active_count) }
            end
            redis.call("DEL", user_active_key)
        end

        local ticket_payload = redis.call("GET", ticket_prefix .. ticket_id)
        if not ticket_payload then
            redis.call("DEL", user_ticket_key)
            redis.call("ZREM", queue_key, ticket_id)
            return { "expired" }
        end

        local rank = redis.call("ZRANK", queue_key, ticket_id)
        if rank == false or rank == nil then
            redis.call("DEL", user_ticket_key)
            return { "expired" }
        end

        local active_count = tonumber(redis.call("ZCARD", active_key)) or 0

        if active_count < steady_limit and (rank + 1) <= (steady_limit - active_count) then
            redis.call("DEL", ticket_prefix .. ticket_id)
            redis.call("DEL", user_ticket_key)
            redis.call("ZREM", queue_key, ticket_id)
            redis.call("SETEX", grant_prefix .. steady_token_id, token_ttl, steady_payload)
            redis.call("SETEX", user_active_key, token_ttl, steady_token_id)
            redis.call("ZADD", active_key, steady_expires_at, steady_token_id)
            return { "admitted", steady_payload, tostring(active_count + 1) }
        end

        if active_count < burst_limit and (rank + 1) <= (burst_limit - active_count) then
            redis.call("DEL", ticket_prefix .. ticket_id)
            redis.call("DEL", user_ticket_key)
            redis.call("ZREM", queue_key, ticket_id)
            redis.call("SETEX", grant_prefix .. burst_token_id, token_ttl, burst_payload)
            redis.call("SETEX", user_active_key, token_ttl, burst_token_id)
            redis.call("ZADD", active_key, burst_expires_at, burst_token_id)
            return { "admitted", burst_payload, tostring(active_count + 1) }
        end

        return { "queued", tostring(rank + 1), tostring(active_count) }
    ]]

    local result, err = client:eval(
        script,
        4,
        keys.active,
        keys.queue,
        keys.user_ticket,
        keys.user_active,
        ngx.time(),
        policy.queue.cleanup_batch,
        ticket_id,
        policy.capacity.steady,
        policy.capacity.burst,
        policy.token.ttl_seconds,
        keys.grant_prefix,
        keys.ticket_prefix,
        steady_payload.token_id,
        gateway_util.encode_json(steady_payload),
        steady_payload.expires_at,
        burst_payload.token_id,
        gateway_util.encode_json(burst_payload),
        burst_payload.expires_at
    )

    if not result then
        return nil, err
    end

    if result[1] == "expired" then
        return { status = "expired" }
    end

    if result[1] == "admitted" or result[1] == "admitted_existing" then
        return {
            status = "admitted",
            payload = decode_json(result[2]),
            active_count = tonumber(result[3]) or 0,
        }
    end

    return {
        status = "queued",
        position = tonumber(result[2]) or 1,
        active_count = tonumber(result[3]) or 0,
    }
end

function M.queue_metrics(client, policy, user_id, ticket_id)
    local keys = shared_keys(policy, user_id)
    local active_count = tonumber(client:zcard(keys.active)) or 0
    local position = client:zrank(keys.queue, ticket_id)
    local queue_total = tonumber(client:zcard(keys.queue)) or 0

    return {
        active_count = active_count,
        queue_position = position and (tonumber(position) + 1) or nil,
        queue_total = queue_total,
    }
end

function M.summary(client, policy)
    local activity_id = policy.activity_id
    local active_key = key("active", activity_id)
    local queue_key = key("queue", activity_id)
    local ticket_prefix = key("ticket", activity_id) .. ":"

    client:zremrangebyscore(active_key, "-inf", ngx.time())

    local head = client:zrange(queue_key, 0, (policy.queue.cleanup_batch or 20) - 1)
    if type(head) == "table" then
        for _, member in ipairs(head) do
            if not client:get(ticket_prefix .. member) then
                client:zrem(queue_key, member)
            end
        end
    end

    return {
        active_count = tonumber(client:zcard(active_key)) or 0,
        queue_total = tonumber(client:zcard(queue_key)) or 0,
        head_ticket = client:zrange(queue_key, 0, 0)[1],
    }
end

return M
