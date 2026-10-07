#!/usr/bin/env python3
"""
Patched comparison version of the Nexora application.

The only change versus the vulnerable version is the diagnostics
endpoint. The patched version validates the component name against a
fixed allow-list and invokes the helper using an argv array rather
than a shell string.

This file is not built into the running container. It exists as
design evidence showing the intended remediation.
"""
import os
import socket
import subprocess
from flask import Flask, jsonify, request

app = Flask(__name__)

APP_VERSION = os.environ.get(
    "NEXORA_APP_VERSION",
    "nexora-platform-2026.09.03",
)

APPROVED_COMPONENTS = {
    "nexora-utils",
    "nexora-core",
    "nexora-platform",
}


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
    data = request.get_json(silent=True) or {}
    component = data.get("component", "nexora-utils")
    verbose = bool(data.get("verbose", False))

    if component not in APPROVED_COMPONENTS:
        return jsonify(
            status="rejected",
            reason="unknown-component",
        ), 400

    cmd = ["/opt/nexora/bin/verify-component", component]

    try:
        result = subprocess.run(
            cmd,
            shell=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        return jsonify(status="timeout", component=component), 504

    payload = {
        "status": "complete",
        "component": component,
        "return_code": result.returncode,
        "stdout": result.stdout,
    }

    if verbose:
        payload["stderr"] = result.stderr

    return jsonify(payload)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
