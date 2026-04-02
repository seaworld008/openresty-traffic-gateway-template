local M = {}

function M.load_policy(policy_name)
    local policies = require("gateway.policies")
    return policies[policy_name]
end

return M
