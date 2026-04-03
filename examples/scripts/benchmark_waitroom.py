#!/usr/bin/env python3

import argparse
import json
import ssl
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed


SSL_CONTEXT = ssl._create_unverified_context()


def post_join(user_id: str) -> dict:
    request = urllib.request.Request(
        url="https://127.0.0.1/api/enroll/submit",
        method="POST",
        headers={
            "Host": "enroll.example.test",
            "X-User-Id": user_id,
            "X-Forwarded-For": f"198.51.100.{int(user_id.split('-')[-1]) % 200 + 1}",
            "Connection": "close",
        },
    )

    try:
        with urllib.request.urlopen(request, context=SSL_CONTEXT, timeout=10) as response:
            payload = json.loads(response.read().decode())
            return {
                "status_code": response.status,
                "payload_status": payload.get("status"),
                "ticket_id": payload.get("ticket_id"),
            }
    except urllib.error.HTTPError as exc:
        payload = json.loads(exc.read().decode())
        return {
            "status_code": exc.code,
            "payload_status": payload.get("status"),
            "ticket_id": payload.get("ticket_id"),
        }


def main():
    parser = argparse.ArgumentParser(description="等待室入口并发模拟")
    parser.add_argument("--total", type=int, default=30)
    parser.add_argument("--concurrency", type=int, default=30)
    args = parser.parse_args()

    total = args.total
    concurrency = args.concurrency
    started = time.perf_counter()
    results = []

    with ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = [executor.submit(post_join, f"bench-user-{index:03d}") for index in range(total)]
        for future in as_completed(futures):
            results.append(future.result())

    duration = time.perf_counter() - started
    admitted = sum(1 for item in results if item["payload_status"] == "admitted")
    queued = sum(1 for item in results if item["payload_status"] == "queued")
    status_counts = {}

    for item in results:
        status_counts[item["status_code"]] = status_counts.get(item["status_code"], 0) + 1

    print(json.dumps({
        "case": "waitroom_join_burst",
        "total_requests": total,
        "duration_seconds": round(duration, 3),
        "requests_per_second": round(total / duration, 2),
        "http_status_counts": status_counts,
        "admitted_count": admitted,
        "queued_count": queued,
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
