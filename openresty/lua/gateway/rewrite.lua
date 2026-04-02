local cjson = require "cjson.safe"
local util = require "gateway.util"

local M = {}

local function context_values(extra)
    local values = {
        request_id = ngx.ctx.gateway_request_id,
        route = ngx.var.gateway_route,
        partner_key = ngx.ctx.partner_key,
        tenant = ngx.ctx.partner_metadata and ngx.ctx.partner_metadata.tenant or "",
        gray_variant = ngx.var.gateway_gray_variant,
    }

    if type(extra) == "table" then
        for key, value in pairs(extra) do
            values[key] = value
        end
    end

    return values
end

function M.apply_request_rewrite(rewrite_conf)
    if type(rewrite_conf) ~= "table" then
        return
    end

    local headers = rewrite_conf.add_headers or {}
    local header_context = context_values()

    for header_name, header_value in pairs(headers) do
        ngx.req.set_header(header_name, util.render_template(header_value, header_context))
    end

    for _, header_name in ipairs(rewrite_conf.remove_headers or {}) do
        ngx.req.clear_header(header_name)
    end

    if rewrite_conf.json_body_inject then
        local content_type = ngx.req.get_headers()["Content-Type"] or ""
        if content_type:find("application/json", 1, true) then
            local raw_body = util.read_body()
            local decoded_body = cjson.decode(raw_body)

            if type(decoded_body) == "table" then
                local body_context = context_values()
                for field_name, field_value in pairs(rewrite_conf.json_body_inject) do
                    decoded_body[field_name] = util.render_template(field_value, body_context)
                end

                local encoded_body = cjson.encode(decoded_body)
                util.set_body(encoded_body)
            end
        end
    end
end

return M
