local M = {}

function M.ensure()
    local request_id = ngx.req.get_headers()["X-Request-Id"]

    if not request_id or request_id == "" then
        request_id = ngx.var.request_id
    end

    if not request_id or request_id == "" then
        request_id = string.format("%d-%d-%s", ngx.time(), ngx.worker.pid(), ngx.var.connection or "0")
    end

    ngx.ctx.gateway_request_id = request_id
    ngx.var.gateway_request_id = request_id
    ngx.req.set_header("X-Request-Id", request_id)

    return request_id
end

return M
