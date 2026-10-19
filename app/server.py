import json
import logging
import os
import time
import uuid
from pathlib import Path
from flask import Flask, g, jsonify, render_template, request

app = Flask(__name__, root_path=str(Path(__file__).resolve().parent))
app.config["MAX_CONTENT_LENGTH"] = 4096
logging.basicConfig(level=logging.INFO, format="%(message)s")

@app.before_request
def start():
    g.started = time.monotonic()
    g.request_id = str(uuid.uuid4())

@app.after_request
def finish(response):
    response.headers["X-Request-ID"] = g.request_id
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Cache-Control"] = "no-store"
    response.headers["Content-Security-Policy"] = "default-src 'self'; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'"
    app.logger.info(json.dumps({"event":"request", "id":g.request_id,
        "method":request.method, "route":str(request.url_rule) if request.url_rule else "unmatched",
        "status":response.status_code, "duration_ms":round((time.monotonic()-g.started)*1000,2)}))
    return response

def version():
    return {"service":"delivery-platform", "revision":os.getenv("APP_REVISION", "local"),
            "environment":os.getenv("APP_ENVIRONMENT", "local")}

@app.get("/healthz")
def health():
    return jsonify(status="ok")

@app.get("/api/version")
def release():
    return jsonify(version())

@app.get("/")
def index():
    return render_template("index.html", **version())
