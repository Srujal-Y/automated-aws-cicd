"""Check the actual application revision instead of accepting any healthy response."""
import argparse
import json
import time
from urllib.error import HTTPError, URLError
from urllib.request import urlopen

def check(base, expected, attempts=30, delay=2):
    for attempt in range(attempts):
        try:
            with urlopen(base.rstrip("/") + "/healthz", timeout=5) as response:
                if response.status != 200 or json.load(response).get("status") != "ok":
                    raise ValueError("Health check failed")
            with urlopen(base.rstrip("/") + "/api/version", timeout=5) as response:
                actual = json.load(response).get("revision")
            if actual == expected:
                return actual
        except (URLError, HTTPError, TimeoutError, ConnectionError, ValueError):
            pass
        if attempt + 1 < attempts:
            time.sleep(delay)
    raise RuntimeError("Requested revision was not observed at the service endpoint")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://localhost:8090")
    parser.add_argument("--revision", default="local")
    args = parser.parse_args()
    print("PASS: healthy service running revision " + check(args.url, args.revision))
