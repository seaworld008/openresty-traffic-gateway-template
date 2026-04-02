return {
    course_enroll_demo = {
        policy_id = "course_enroll_demo",
        activity_id = "course-enroll-demo",
        paths = {
            join = "/api/enroll/submit",
            status = "/api/queue/status",
            waitroom = "/waitroom.html",
        },
        capacity = {
            steady = 2,
            burst = 4,
        },
        token = {
            ttl_seconds = 12,
        },
        queue = {
            ttl_seconds = 300,
            poll_interval_seconds = 3,
            cleanup_batch = 20,
        },
        protected = {
            paths = {
                ["/api/cart/add"] = true,
                ["/api/checkout/confirm"] = true,
                ["/api/pay/create"] = true,
                ["/api/order/status"] = true,
            },
        },
    },
}
