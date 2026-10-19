"""Run the same credential-free checks as CI from a development checkout."""
import argparse
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
ACTIONLINT = "rhysd/actionlint@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667"

def run(*args):
    print("+ " + " ".join(args), flush=True)
    subprocess.run(args, cwd=ROOT, check=True)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-containers", action="store_true")
    args = parser.parse_args()
    run(sys.executable, "-m", "pip_audit", "-r", "app/requirements.txt")
    run(sys.executable, "-m", "unittest", "discover", "-s", "tests", "-v")
    run("terraform", "fmt", "-check", "-recursive", "infra")
    for stack in ("state", "platform", "application"):
        root = "-chdir=infra/" + stack
        run("terraform", root, "init", "-backend=false", "-input=false")
        run("terraform", root, "validate")
        run("terraform", root, "test")
    if not args.skip_containers:
        run("docker", "run", "--rm", "--mount", "type=bind,source=" + str(ROOT) + ",target=/repo,readonly",
            "--workdir", "/repo", ACTIONLINT, ".github/workflows/delivery.yml", ".github/workflows/rollback.yml")
        run("docker", "compose", "up", "--build", "-d", "--wait")
        run(sys.executable, "scripts/smoke.py", "--revision", os.getenv("APP_REVISION", "local"))
    print("PASS: local validation complete; AWS deployment was not attempted")

if __name__ == "__main__":
    main()
