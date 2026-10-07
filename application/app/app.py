#!/usr/bin/env python3

import os
import socket

from flask import Flask, jsonify


app = Flask(__name__)

APP_VERSION = os.environ.get(
    "NEXORA_APP_VERSION",
    "nexora-platform-2026.09.03",
)


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
        status="online",
    )


if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=5000,
        debug=False,
        use_reloader=False,
    )