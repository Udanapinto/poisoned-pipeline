#!/usr/bin/env python3
"""
CTFd challenge configuration helper for Operation Poisoned Pipeline.

This script uses the CTFd REST API to create or update the six challenges.
It requires an admin API token and the real flag values.

Usage:
    python3 scripts/ctfd-apply-challenges.py --token <CTFD_API_TOKEN> --base https://10.13.10.20
"""

import argparse
import json
import sys
import urllib.request
import urllib.error
import ssl


def api_request(base, token, method, path, payload=None):
    url = f"{base.rstrip('/')}{path}"
    data = json.dumps(payload).encode("utf-8") if payload is not None else None

    request = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": f"Token {token}",
            "Content-Type": "application/json",
        },
        method=method,
    )

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        with urllib.request.urlopen(request, context=ctx, timeout=20) as response:
            body = response.read().decode("utf-8")
            return response.status, json.loads(body) if body else {}
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8")
        return exc.code, {"error": body}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="https://10.13.10.20")
    parser.add_argument("--token", required=True)
    args = parser.parse_args()

    print("CTFd API helper: not fully automated in this reference.")
    print("Use the CTFd admin UI to create the six challenges with the")
    print("values documented in scripts/ctfd-export-challenges.sh.")
    print()
    print("This helper is provided as a starting point if you choose")
    print("to automate challenge creation later.")


if __name__ == "__main__":
    main()
