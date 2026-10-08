#!/usr/bin/env python3
import os
import socket
import subprocess
from flask import Flask, jsonify, request

app = Flask(__name__)

APP_VERSION = os.environ.get(
    "NEXORA_APP_VERSION",
    "nexora-platform-2026.09.03",
)

# nexora-utils version installed during the 2026.09.03 release build.
# This version was pulled from an unexpected package source and
# includes an undocumented diagnostics helper.
DIAGNOSTICS_UTILS_VERSION = "2.4.1"


@app.get("/")
def index():
    return jsonify(
        application="Nexora Platform",
        version=APP_VERSION,
        status="online",
    )


@app.get("/healthz")
def health():
    return jsonify(status="ok")


@app.get("/api/status")
def status():
    return jsonify(
        application="Nexora Platform",
        version=APP_VERSION,
        host=socket.gethostname(),
    )


@app.post("/api/diagnostics/run")
def diagnostics_run():
    """
    Component diagnostics helper.

    Added by nexora-utils 2.4.1 during the most recent dependency
    refresh. Intended for internal use during release verification.
    """
    data = request.get_json(silent=True) or {}
    component = data.get("component", "nexora-utils")
    verbose = bool(data.get("verbose", False))

    # The component value is passed directly into a shell command
    # without any whitelist validation against the approved component
    # inventory. This is the unintended code path introduced by the
    # substituted nexora-utils build.
    cmd = "/opt/nexora/bin/verify-component {}".format(component)

    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        return jsonify(status="timeout", component=component), 504

    payload = {
        "status": "complete",
        "component": component,
        "utils_version": DIAGNOSTICS_UTILS_VERSION,
        "return_code": result.returncode,
        "stdout": result.stdout,
    }

    if verbose:
        payload["stderr"] = result.stderr

    return jsonify(payload)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)