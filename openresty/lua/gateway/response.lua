local cjson = require "cjson.safe"
local util = require "gateway.util"

local M = {}

local function response_rewrite_max_bytes()
    return tonumber(os.getenv("GATEWAY_RESPONSE_REWRITE_MAX_BYTES")) or 262144
end

function M.header_filter()
    if ngx.ctx.response_rewrite and ngx.ctx.response_rewrite.json_inject then
        local content_length = tonumber(ngx.header["Content-Length"])
        if content_length and content_length > response_rewrite_max_bytes() then
            ngx.ctx.skip_response_rewrite = true
        end

        ngx.header["Content-Length"] = nil
    end

    if ngx.ctx.gateway_request_id then
        ngx.header["X-Request-Id"] = ngx.ctx.gateway_request_id
    end

    if ngx.var.gateway_route and ngx.var.gateway_route ~= "" then
        ngx.header["X-Gateway-Route"] = ngx.var.gateway_route
    end

    if ngx.var.gateway_circuit_state and ngx.var.gateway_circuit_state ~= "" then
        ngx.header["X-Gateway-Circuit-State"] = ngx.var.gateway_circuit_state
    end

    if ngx.var.gateway_gray_variant and ngx.var.gateway_gray_variant ~= "" then
        ngx.header["X-Gray-Variant"] = ngx.var.gateway_gray_variant
    end

    local rewrite_conf = ngx.ctx.response_rewrite
    if rewrite_conf and rewrite_conf.add_headers then
        local context = {
            request_id = ngx.ctx.gateway_request_id,
            route = ngx.var.gateway_route,
            gray_variant = ngx.var.gateway_gray_variant,
            tenant = ngx.ctx.partner_metadata and ngx.ctx.partner_metadata.tenant or "",
        }

        for header_name, header_value in pairs(rewrite_conf.add_headers) do
            ngx.header[header_name] = util.render_template(header_value, context)
        end
    end
end

function M.body_filter()
    local rewrite_conf = ngx.ctx.response_rewrite
    if not rewrite_conf or not rewrite_conf.json_inject then
        return
    end

    if ngx.ctx.skip_response_rewrite then
        return
    end

    local content_type = ngx.header["Content-Type"] or ""
    if not content_type:find("application/json", 1, true) then
        return
    end

    local chunk = ngx.arg[1]
    local eof = ngx.arg[2]

    ngx.ctx.response_chunks = ngx.ctx.response_chunks or {}

    if chunk and chunk ~= "" then
        ngx.ctx.response_chunks[#ngx.ctx.response_chunks + 1] = chunk
        ngx.ctx.response_bytes = (ngx.ctx.response_bytes or 0) + #chunk

        if ngx.ctx.response_bytes > response_rewrite_max_bytes() then
            ngx.ctx.skip_response_rewrite = true
            ngx.arg[1] = table.concat(ngx.ctx.response_chunks)
            ngx.ctx.response_chunks = nil
            return
        end

        ngx.arg[1] = nil
    end

    if not eof then
        return
    end

    if ngx.ctx.skip_response_rewrite then
        return
    end

    local payload = table.concat(ngx.ctx.response_chunks)
    local decoded_payload = cjson.decode(payload)
    if type(decoded_payload) ~= "table" then
        ngx.arg[1] = payload
        return
    end

    local context = {
        request_id = ngx.ctx.gateway_request_id,
        route = ngx.var.gateway_route,
        tenant = ngx.ctx.partner_metadata and ngx.ctx.partner_metadata.tenant or "",
        gray_variant = ngx.var.gateway_gray_variant,
    }

    for field_name, field_value in pairs(rewrite_conf.json_inject) do
        decoded_payload[field_name] = util.render_template(field_value, context)
    end

    local encoded_payload = cjson.encode(decoded_payload)
    ngx.arg[1] = encoded_payload
end

return M
