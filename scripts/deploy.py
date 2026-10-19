"""Deploy a digest-pinned release through Terraform, then verify ECS and HTTP."""
import argparse
import json
import re
import subprocess
from pathlib import Path

from smoke import check

ROOT = Path(__file__).resolve().parents[1]

def run(args, capture=False):
    result = subprocess.run(args, cwd=ROOT, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None

def release_variables(config, digest, revision):
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        raise ValueError("Image digest must be sha256 followed by 64 lowercase hexadecimal characters")
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Revision must be the full 40-character Git commit SHA")
    repository = config["repository_url"]
    if not re.fullmatch(r"[0-9]{12}[.]dkr[.]ecr[.][a-z0-9-]+[.]amazonaws[.]com/[a-z0-9/_-]+", repository):
        raise ValueError("Invalid private ECR repository URL")
    if not config["url"].startswith(("https://", "http://")):
        raise ValueError("Invalid service URL")
    if len(config["subnet_ids"]) < 2:
        raise ValueError("At least two application subnets are required")
    return {"region":config["region"], "platform":config,
            "image_uri":repository + "@" + digest}

def verify_service(description, desired_task):
    if description.get("failures") or len(description.get("services", [])) != 1:
        raise RuntimeError("ECS service is missing or inaccessible")
    service = description["services"][0]
    primary = [d for d in service.get("deployments", []) if d.get("status") == "PRIMARY"]
    if (service.get("taskDefinition") != desired_task or len(primary) != 1
        or primary[0].get("taskDefinition") != desired_task
        or primary[0].get("rolloutState") != "COMPLETED"
        or service.get("runningCount", 0) < service.get("desiredCount", 2)
        or service.get("desiredCount", 0) < 2):
        raise RuntimeError("Requested task revision did not complete; ECS may have rolled back")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="platform.json")
    parser.add_argument("--digest", required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--state-bucket", required=True)
    parser.add_argument("--state-prefix", default="delivery-platform/production")
    args = parser.parse_args()
    config = json.loads(Path(args.config).read_text(encoding="utf-8"))
    values = release_variables(config, args.digest, args.revision)
    artifact_dir = ROOT / "artifacts"
    artifact_dir.mkdir(exist_ok=True)
    (artifact_dir / "release.json").unlink(missing_ok=True)
    stack = "-chdir=infra/application"
    run(["terraform", stack, "init", "-input=false", "-reconfigure",
         "-backend-config=bucket=" + args.state_bucket,
         "-backend-config=key=" + args.state_prefix + "/application.tfstate",
         "-backend-config=region=" + config["region"],
         "-backend-config=encrypt=true", "-backend-config=use_lockfile=true"])
    variables_file = ROOT / "infra/application/release.auto.tfvars.json"
    variables_file.write_text(json.dumps(values), encoding="utf-8")
    try:
        run(["terraform", stack, "plan", "-input=false", "-lock-timeout=5m", "-out=release.tfplan"])
        run(["terraform", stack, "apply", "-input=false", "-lock-timeout=5m", "release.tfplan"])
        task = run(["terraform", stack, "output", "-raw", "task_definition_arn"], capture=True)
        description = json.loads(run(["aws", "ecs", "describe-services", "--cluster", config["cluster_name"],
                                     "--services", config["name"], "--region", config["region"], "--output", "json"], capture=True))
        verify_service(description, task)
        check(config["url"], args.revision)
        manifest = {"revision":args.revision, "image_uri":values["image_uri"],
                    "task_definition_arn":task, "url":config["url"], "status":"verified"}
        (artifact_dir / "release.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        print("PASS: deployed and verified " + args.revision)
    finally:
        variables_file.unlink(missing_ok=True)
        (ROOT / "infra/application/release.tfplan").unlink(missing_ok=True)

if __name__ == "__main__":
    main()
