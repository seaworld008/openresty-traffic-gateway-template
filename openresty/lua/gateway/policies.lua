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
                upstream = "risk_unstable_backend",
                upstream_uri = "/unstable",
                fallback_upstream = "frontend_backend",
                fallback_upstream_uri = "/unstable",
                circuit_breaker = {
                    failure_threshold = 2,
                    open_seconds = 20,
                    window_seconds = 20,
                },
            },
            {
                id = "risk_allowlist",
                path_prefix = "/allowlist",
                upstream = "frontend_backend",
                risk = {
                    whitelist_ips = {
                        "203.0.113.10/32",
                    },
                },
            },
            {
                id = "risk_denylist",
                path_prefix = "/denylist",
                upstream = "frontend_backend",
                risk = {
                    blacklist_ips = {
                        "198.51.100.24/32",
                    },
                },
            },
            {
                id = "risk_default",
                path_prefix = "/",
                upstream = "frontend_backend",
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
                upstream = "echo_backend",
                upstream_uri = "/anything/hooks/inventory",
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
                upstream = "echo_backend",
                upstream_uri = "/anything/orders",
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
                upstream = "api_backend",
                partner_metadata_key_prefix = "gateway:partner:",
                auth = {
                    require_partner_key = true,
                    require_jwt = true,
                },
                header_upstreams = {
                    ["X-Route-Version"] = {
                        echo = {
                            upstream = "echo_backend",
                            upstream_uri = "/anything/dispatch",
                        },
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
                upstream = "api_backend",
            },
        },
    },
    gray_release = {
        routes = {
            {
                id = "gray_release",
                path_prefix = "/",
                upstream = "frontend_backend",
                gray = {
                    header_name = "X-Gray-Release",
                    cookie_name = "gray_release",
                    canary_value = "canary",
                    canary_upstream = "echo_backend",
                    canary_upstream_uri = "/anything/gray-release",
                    stable_upstream = "frontend_backend",
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
