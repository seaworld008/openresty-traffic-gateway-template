local admission_util = require "admission.util"
local gateway_util = require "gateway.util"
local policies = require "admission.policies"
local store = require "admission.store"
local token = require "admission.token"

local M = {}

local state_dict = ngx.shared.gateway_state

local function current_policy()
    return policies[ngx.var.admission_policy]
end

local function active_cache_key(activity_id, user_id)
    return "admission_cache:" .. activity_id .. ":" .. ngx.md5(user_id)
end

local function cache_active(payload, user_id)
    state_dict:set(
        active_cache_key(payload.activity_id, user_id),
        gateway_util.encode_json(payload),
        math.max(1, tonumber(payload.expires_at or 0) - ngx.time())
    )
end

local function cached_active(activity_id, user_id)
    local raw = state_dict:get(active_cache_key(activity_id, user_id))
    if not raw then
        return nil
    end
    return gateway_util.decode_json(raw)
end

local function build_admission_payload(policy, user_id, tier)
    return {
        token_id = ngx.md5(policy.activity_id .. ":" .. user_id .. ":" .. tier .. ":" .. ngx.var.request_id .. ":" .. ngx.now()),
        activity_id = policy.activity_id,
        policy_id = policy.policy_id,
        user_id = user_id,
        admission_tier = tier,
        issued_at = ngx.time(),
        expires_at = ngx.time() + policy.token.ttl_seconds,
    }
end

local function build_ticket_payload(policy, user_id)
    return {
        ticket_id = ngx.md5(policy.activity_id .. ":" .. user_id .. ":" .. ngx.var.request_id .. ":" .. ngx.now()),
        activity_id = policy.activity_id,
        policy_id = policy.policy_id,
        user_id = user_id,
        created_at = ngx.time(),
        expires_at = ngx.time() + policy.queue.ttl_seconds,
    }
end

local function existing_valid_token(policy, user_id)
    local payload, err = token.decode(admission_util.current_cookie())
    if not payload then
        return nil, err
    end

    if payload.policy_id ~= policy.policy_id then
        return nil, "policy_mismatch"
    end

    if payload.activity_id ~= policy.activity_id then
        return nil, "activity_mismatch"
    end

    if payload.user_id ~= user_id then
        return nil, "user_mismatch"
    end

    return payload
end

local function estimated_wait_seconds(policy, ahead_count)
    if not ahead_count or ahead_count <= 0 then
        return 0
    end

    return ahead_count * policy.queue.poll_interval_seconds
end

local function admitted_response(policy, user_id, payload, active_count)
    admission_util.set_cookie(token.encode(payload), payload.expires_at - ngx.time())
    cache_active(payload, user_id)

    return admission_util.json_response(200, {
        status = "admitted",
        policy_id = policy.policy_id,
        activity_id = policy.activity_id,
        user_id = user_id,
        admission_tier = payload.admission_tier,
        expires_at = payload.expires_at,
        active_count = active_count,
        steady_capacity = policy.capacity.steady,
        burst_capacity = policy.capacity.burst,
        waitroom_path = policy.paths.waitroom,
    })
end

function M.handle_join()
    local policy = current_policy()
    if not policy then
        return admission_util.bad_request("missing_policy", "未找到等待室策略")
    end

    local user_id = admission_util.resolve_user_id()
    if user_id == "" then
        return admission_util.bad_request("missing_user_id", "缺少用户标识，无法进入等待室")
    end

    local local_payload = existing_valid_token(policy, user_id)
    if local_payload then
        return admitted_response(policy, user_id, local_payload, nil)
    end

    local cached_payload = cached_active(policy.activity_id, user_id)
    if cached_payload and tonumber(cached_payload.expires_at or 0) > ngx.time() then
        return admitted_response(policy, user_id, cached_payload, nil)
    end

    local client, err = store.connect()
    if not client then
        return admission_util.service_unavailable("redis_unavailable", "等待室状态存储不可用", err)
    end

    local decision, decision_err = store.join_or_queue_atomic(
        client,
        policy,
        user_id,
        build_admission_payload(policy, user_id, "steady"),
        build_admission_payload(policy, user_id, "burst"),
        build_ticket_payload(policy, user_id)
    )
    store.close(client)

    if not decision then
        return admission_util.service_unavailable("queue_atomic_failed", "等待室原子准入失败", decision_err)
    end

    if decision.status == "admitted" then
        return admitted_response(policy, user_id, decision.payload, decision.active_count)
    end

    return admission_util.json_response(202, {
        status = "queued",
        policy_id = policy.policy_id,
        activity_id = policy.activity_id,
        ticket_id = decision.payload.ticket_id,
        queue_position = decision.position,
        ahead_count = math.max(0, decision.position - 1),
        estimated_wait_seconds = estimated_wait_seconds(policy, decision.position - 1),
        active_count = decision.active_count,
        steady_capacity = policy.capacity.steady,
        burst_capacity = policy.capacity.burst,
        poll_after_seconds = policy.queue.poll_interval_seconds,
        waitroom_path = policy.paths.waitroom,
    })
end

function M.handle_status()
    local policy = current_policy()
    if not policy then
        return admission_util.bad_request("missing_policy", "未找到等待室策略")
    end

    local user_id = admission_util.resolve_user_id()
    if user_id == "" then
        return admission_util.bad_request("missing_user_id", "缺少用户标识，无法查询排队状态")
    end

    local local_payload = existing_valid_token(policy, user_id)
    if local_payload then
        return admission_util.json_response(200, {
            status = "admitted",
            policy_id = policy.policy_id,
            activity_id = policy.activity_id,
            user_id = user_id,
            admission_tier = local_payload.admission_tier,
            expires_at = local_payload.expires_at,
        })
    end

    local ticket_id = ngx.var.arg_ticket or ""
    if ticket_id == "" then
        return admission_util.bad_request("missing_ticket", "缺少 ticket 参数")
    end

    local client, err = store.connect()
    if not client then
        return admission_util.service_unavailable("redis_unavailable", "等待室状态存储不可用", err)
    end

    local decision, decision_err = store.status_or_admit_atomic(
        client,
        policy,
        user_id,
        ticket_id,
        build_admission_payload(policy, user_id, "steady"),
        build_admission_payload(policy, user_id, "burst")
    )

    if not decision then
        store.close(client)
        return admission_util.service_unavailable("queue_atomic_failed", "排队状态原子处理失败", decision_err)
    end

    if decision.status == "expired" then
        store.close(client)
        return admission_util.json_response(410, {
            status = "expired",
            policy_id = policy.policy_id,
            activity_id = policy.activity_id,
            message = "排队凭证已过期，请重新进入等待室",
        })
    end

    if decision.status == "admitted" then
        store.close(client)
        return admitted_response(policy, user_id, decision.payload, decision.active_count)
    end

    local metrics = store.queue_metrics(client, policy, user_id, ticket_id)
    store.close(client)

    local position = decision.position or metrics.queue_position or 1
    return admission_util.json_response(202, {
        status = "queued",
        policy_id = policy.policy_id,
        activity_id = policy.activity_id,
        ticket_id = ticket_id,
        queue_position = position,
        ahead_count = math.max(0, position - 1),
        queue_total = metrics.queue_total,
        active_count = metrics.active_count,
        steady_capacity = policy.capacity.steady,
        burst_capacity = policy.capacity.burst,
        estimated_wait_seconds = estimated_wait_seconds(policy, position - 1),
        poll_after_seconds = policy.queue.poll_interval_seconds,
    })
end

function M.enforce_protected()
    local policy = current_policy()
    if not policy then
        return admission_util.precondition_required("missing_policy", "未找到准入保护策略")
    end

    local route = ngx.var.uri
    if not policy.protected.paths[route] then
        return
    end

    local user_id = admission_util.resolve_user_id()
    if user_id == "" then
        return admission_util.precondition_required("missing_user_id", "缺少用户标识，无法继续关键流程")
    end

    local payload, err = existing_valid_token(policy, user_id)
    if not payload then
        return admission_util.precondition_required(err or "missing_token", "当前请求没有有效准入资格")
    end

    ngx.req.set_header("X-Admission-Policy", payload.policy_id)
    ngx.req.set_header("X-Admission-Activity", payload.activity_id)
    ngx.req.set_header("X-Admission-Token-Id", payload.token_id)
    ngx.req.set_header("X-Admission-Expires-At", tostring(payload.expires_at))
    ngx.req.set_header("X-Admission-Tier", payload.admission_tier or "steady")
end

function M.handle_summary()
    local policy = current_policy()
    if not policy then
        return admission_util.bad_request("missing_policy", "未找到等待室策略")
    end

    local access = admission_util.require_ops_access()
    if access ~= true then
        return access
    end

    local client, err = store.connect()
    if not client then
        return admission_util.service_unavailable("redis_unavailable", "等待室状态存储不可用", err)
    end

    local summary = store.summary(client, policy)
    store.close(client)

    return admission_util.json_response(200, {
        policy_id = policy.policy_id,
        activity_id = policy.activity_id,
        steady_capacity = policy.capacity.steady,
        burst_capacity = policy.capacity.burst,
        token_ttl_seconds = policy.token.ttl_seconds,
        queue_poll_interval_seconds = policy.queue.poll_interval_seconds,
        active_count = summary.active_count,
        queue_total = summary.queue_total,
        head_ticket = summary.head_ticket,
        protected_paths = policy.protected.paths,
    })
end

return M
