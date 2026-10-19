import json
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).parents[1] / "scripts"))
import deploy

class ReleaseExecutionTests(unittest.TestCase):
    def exercise(self, mode):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "infra/application").mkdir(parents=True)
            (root / "artifacts").mkdir()
            manifest = root / "artifacts/release.json"
            manifest.write_text('{"status":"stale-success"}')
            config = {"repository_url":"123456789012.dkr.ecr.us-east-1.amazonaws.com/delivery-platform",
                      "region":"us-east-1", "url":"http://example.test", "subnet_ids":["a","b"],
                      "cluster_name":"delivery-platform", "name":"delivery-platform"}
            config_file = root / "platform.json"
            config_file.write_text(json.dumps(config))
            calls = []
            def run(args, capture=False):
                calls.append(args)
                if "plan" in args:
                    (root / "infra/application/release.tfplan").write_text("temporary-plan")
                if "apply" in args and mode == "apply_failure":
                    raise subprocess.CalledProcessError(1, args)
                if "output" in args:
                    return "task:2"
                if "describe-services" in args:
                    task = "task:1" if mode == "rollback" else "task:2"
                    return json.dumps({"services":[{"taskDefinition":task,"runningCount":2,"desiredCount":2,
                        "deployments":[{"status":"PRIMARY","taskDefinition":task,"rolloutState":"COMPLETED"}]}]})
            argv = ["deploy.py", "--config",str(config_file),"--digest","sha256:"+"a"*64,
                    "--revision","b"*40,"--state-bucket","example-state"]
            with patch.object(deploy,"ROOT",root), patch.object(deploy,"run",side_effect=run), \
                 patch.object(deploy,"check") as smoke, patch.object(sys,"argv",argv):
                if mode == "success":
                    deploy.main()
                    self.assertEqual(json.loads(manifest.read_text())["status"],"verified")
                    smoke.assert_called_once_with("http://example.test","b"*40)
                    self.assertLess(next(i for i,c in enumerate(calls) if "plan" in c),next(i for i,c in enumerate(calls) if "apply" in c))
                else:
                    with self.assertRaises((RuntimeError,subprocess.CalledProcessError)):
                        deploy.main()
                    self.assertFalse(manifest.exists())
                    smoke.assert_not_called()
            self.assertFalse((root / "infra/application/release.auto.tfvars.json").exists())
            self.assertFalse((root / "infra/application/release.tfplan").exists())
    def test_verified_release_records_manifest_and_cleans_plan(self):
        self.exercise("success")
    def test_failed_apply_cannot_leave_success_manifest(self):
        self.exercise("apply_failure")
    def test_healthy_rollback_is_rejected_and_cleans_generated_files(self):
        self.exercise("rollback")
