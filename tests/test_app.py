import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("server", Path(__file__).parents[1] / "app/server.py")
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)

class ApplicationTests(unittest.TestCase):
    def setUp(self):
        self.client = server.app.test_client()
    def test_health(self):
        response = self.client.get("/healthz")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json, {"status":"ok"})
    def test_revision_comes_from_image_environment(self):
        with patch.dict(os.environ, {"APP_REVISION":"a"*40, "APP_ENVIRONMENT":"production"}):
            self.assertEqual(self.client.get("/api/version").json["revision"], "a"*40)
    def test_page_escapes_revision(self):
        with patch.dict(os.environ, {"APP_REVISION":"<script>alert(1)</script>"}):
            response = self.client.get("/")
            self.assertNotIn(b"<script>", response.data)
            self.assertIn(b"&lt;script&gt;", response.data)
    def test_request_ids_are_unique(self):
        first = self.client.get("/healthz")
        second = self.client.get("/healthz")
        self.assertNotEqual(first.headers["X-Request-ID"], second.headers["X-Request-ID"])
        self.assertEqual(first.headers["Cache-Control"], "no-store")
        self.assertIn("frame-ancestors 'none'", first.headers["Content-Security-Policy"])
    def test_unknown_route(self):
        self.assertEqual(self.client.get("/missing").status_code, 404)
