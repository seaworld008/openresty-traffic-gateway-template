return {
    risk_gateway = {
        risk = {
            blocked_ua_patterns = {
                "sqlmap",
                "scanner",
                "evil-bot",
            },
        },
        routes = {
            {
                id = "risk_unstable",
                path_prefix = "/unstable",
                upstream = "http://127.0.0.1:65535",
                fallback_upstream = "http://frontend:80",
                circuit_breaker = {
                    failure_threshold = 2,
                    open_seconds = 20,
                    window_seconds = 20,
                },
            },
            {
                id = "risk_allowlist",
                path_prefix = "/allowlist",
                upstream = "http://frontend:80",
                risk = {
                    whitelist_ips = {
                        "203.0.113.10/32",
                    },
                },
            },
            {
                id = "risk_denylist",
                path_prefix = "/denylist",
                upstream = "http://frontend:80",
                risk = {
                    blacklist_ips = {
                        "198.51.100.24/32",
                    },
                },
            },
            {
                id = "risk_default",
                path_prefix = "/",
                upstream = "http://frontend:80",
                response_rewrite = {
                    add_headers = {
                        ["X-Gateway-Case"] = "risk-gateway",
                    },
                },
            },
        },
    },
    partner_api = {
        risk = {
            blocked_ua_patterns = {
                "scanner",
                "sqlmap",
            },
        },
        routes = {
            {
                id = "partner_hook_inventory",
                path_prefix = "/v1/hooks/inventory",
                upstream = "http://echo-service:8080/anything/hooks/inventory",
                partner_metadata_key_prefix = "gateway:partner:",
                auth = {
                    require_partner_key = true,
                    require_hmac = true,
                    hmac_max_skew_seconds = 300,
                },
                request_rewrite = {
                    add_headers = {
                        ["X-Gateway-Case"] = "partner-api",
                        ["X-Partner-Tenant"] = "{{tenant}}",
                    },
                    remove_headers = {
                        "X-Remove-Me",
                    },
                },
                response_rewrite = {
                    json_inject = {
                        gateway_request_id = "{{request_id}}",
                        gateway_route = "{{route}}",
                        partner_tenant = "{{tenant}}",
                    },
                    add_headers = {
                        ["X-Gateway-Case"] = "partner-api",
                    },
                },
            },
            {
                id = "partner_orders",
                path_prefix = "/v1/orders",
                upstream = "http://echo-service:8080/anything/orders",
                partner_metadata_key_prefix = "gateway:partner:",
                auth = {
                    require_partner_key = true,
                    require_jwt = true,
                },
                request_rewrite = {
                    add_headers = {
                        ["X-Gateway-Case"] = "partner-api",
                        ["X-Partner-Tenant"] = "{{tenant}}",
                    },
                    remove_headers = {
                        "X-Remove-Me",
                    },
                    json_body_inject = {
                        gateway_request_id = "{{request_id}}",
                        gateway_route = "{{route}}",
                        partner_tenant = "{{tenant}}",
                    },
                },
                response_rewrite = {
                    json_inject = {
                        gateway_request_id = "{{request_id}}",
                        gateway_route = "{{route}}",
                        partner_tenant = "{{tenant}}",
                    },
                    add_headers = {
                        ["X-Gateway-Case"] = "partner-api",
                    },
                },
            },
            {
                id = "partner_dispatch",
                path_prefix = "/v1/dispatch",
                upstream = "http://api-service:80",
                partner_metadata_key_prefix = "gateway:partner:",
                auth = {
                    require_partner_key = true,
                    require_jwt = true,
                },
                header_upstreams = {
                    ["X-Route-Version"] = {
                        echo = "http://echo-service:8080/anything/dispatch",
                    },
                },
                response_rewrite = {
                    add_headers = {
                        ["X-Gateway-Case"] = "partner-api",
                    },
                },
            },
            {
                id = "partner_default",
                path_prefix = "/",
                upstream = "http://api-service:80",
            },
        },
    },
    gray_release = {
        routes = {
            {
                id = "gray_release",
                path_prefix = "/",
                upstream = "http://frontend:80",
                gray = {
                    header_name = "X-Gray-Release",
                    cookie_name = "gray_release",
                    canary_value = "canary",
                    canary_upstream = "http://echo-service:8080/anything/gray-release",
                    stable_upstream = "http://frontend:80",
                    percent = 20,
                    redis_flag_key = "gateway:gray:enabled",
                },
                response_rewrite = {
                    add_headers = {
                        ["X-Gateway-Case"] = "gray-release",
                    },
                },
            },
        },
    },
}
