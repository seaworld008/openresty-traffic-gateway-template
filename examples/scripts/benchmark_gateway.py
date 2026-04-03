#!/usr/bin/env python3

import argparse
import base64
import hashlib
import hmac
import json
import ssl
import statistics
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed


def b64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode()


def build_jwt(secret: str) -> str:
    header = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
    payload = b64url(json.dumps({"sub": "partner-user-1", "exp": int(time.time()) + 3600}, separators=(",", ":")).encode())
    signing_input = f"{header}.{payload}".encode()
    signature = b64url(hmac.new(secret.encode(), signing_input, hashlib.sha256).digest())
    return f"{header}.{payload}.{signature}"


def run_case(name: str, method: str, url: str, headers: dict, body: bytes | None, total: int, concurrency: int) -> dict:
    ssl_context = ssl._create_unverified_context()
    latencies = []
    statuses = {}
    status_lock = threading.Lock()

    def one_request():
        started = time.perf_counter()
        request = urllib.request.Request(url=url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=10, context=ssl_context) as response:
                response.read()
                status = response.status
        except urllib.error.HTTPError as exc:
            exc.read()
            status = exc.code
        except urllib.error.URLError:
            status = 599
        elapsed = time.perf_counter() - started
        with status_lock:
            latencies.append(elapsed)
            statuses[status] = statuses.get(status, 0) + 1

    started = time.perf_counter()
    with ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = [executor.submit(one_request) for _ in range(total)]
        for future in as_completed(futures):
            future.result()
    duration = time.perf_counter() - started

    latencies_ms = sorted(value * 1000 for value in latencies)

    def percentile(p: float) -> float:
        if not latencies_ms:
            return 0.0
        index = min(len(latencies_ms) - 1, int(len(latencies_ms) * p))
        return latencies_ms[index]

    success = sum(count for status, count in statuses.items() if 200 <= status < 400)
    result = {
        "case": name,
        "total": total,
        "concurrency": concurrency,
        "duration_seconds": round(duration, 3),
        "requests_per_second": round(total / duration, 2) if duration > 0 else 0,
        "success_rate": round(success / total * 100, 2),
        "status_counts": dict(sorted(statuses.items())),
        "p50_ms": round(statistics.median(latencies_ms), 2) if latencies_ms else 0,
        "p95_ms": round(percentile(0.95), 2),
        "p99_ms": round(percentile(0.99), 2),
    }
    return result


def main():
    parser = argparse.ArgumentParser(description="网关并发压测")
    parser.add_argument("--frontend-total", type=int, default=2000)
    parser.add_argument("--frontend-concurrency", type=int, default=200)
    parser.add_argument("--risk-total", type=int, default=1000)
    parser.add_argument("--risk-concurrency", type=int, default=100)
    parser.add_argument("--partner-total", type=int, default=500)
    parser.add_argument("--partner-concurrency", type=int, default=50)
    args = parser.parse_args()

    jwt_token = build_jwt("partner-jwt-secret")

    cases = [
        {
            "name": "www_frontend_plain",
            "method": "GET",
            "url": "https://127.0.0.1/",
            "headers": {
                "Host": "www.example.test",
                "Connection": "close",
            },
            "body": None,
            "total": args.frontend_total,
            "concurrency": args.frontend_concurrency,
        },
        {
            "name": "risk_gateway_default",
            "method": "GET",
            "url": "https://127.0.0.1/",
            "headers": {
                "Host": "risk-gateway.example.test",
                "Connection": "close",
            },
            "body": None,
            "total": args.risk_total,
            "concurrency": args.risk_concurrency,
        },
        {
            "name": "partner_api_orders",
            "method": "POST",
            "url": "https://127.0.0.1/v1/orders",
            "headers": {
                "Host": "partner-api.example.test",
                "Authorization": f"Bearer {jwt_token}",
                "X-Partner-Key": "test-client",
                "Content-Type": "application/json",
                "Connection": "close",
            },
            "body": b'{"order_id":"ORD-1001","amount":128}',
            "total": args.partner_total,
            "concurrency": args.partner_concurrency,
        },
    ]

    print("并发压测开始。")
    for case in cases:
        result = run_case(**case)
        print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
