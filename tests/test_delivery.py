import sys
from pathlib import Path
import unittest
from unittest.mock import patch, MagicMock
sys.path.insert(0, str(Path(__file__).parents[1] / "scripts"))
from deploy import release_variables, verify_service
from smoke import check

class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.config = {"repository_url":"123456789012.dkr.ecr.us-east-1.amazonaws.com/delivery-platform",
                       "region":"us-east-1", "url":"http://example.test", "subnet_ids":["subnet-a","subnet-b"]}
        self.description = {"services":[{"taskDefinition":"task:2", "desiredCount":2, "runningCount":2,
            "deployments":[{"status":"PRIMARY", "taskDefinition":"task:2", "rolloutState":"COMPLETED"}]}]}
    def test_digest_pinned_image(self):
        values = release_variables(self.config, "sha256:"+"a"*64, "b"*40)
        self.assertEqual(values["image_uri"], self.config["repository_url"]+"@sha256:"+"a"*64)
    def test_reject_mutable_tag_and_invalid_revision(self):
        for digest, revision in [("latest","a"*40),("sha256:"+"a"*64,"main")]:
            with self.assertRaises(ValueError): release_variables(self.config,digest,revision)
    def test_require_two_subnets(self):
        self.config["subnet_ids"] = ["subnet-a"]
        with self.assertRaises(ValueError): release_variables(self.config,"sha256:"+"a"*64,"b"*40)
    def test_completed_deployment(self):
        verify_service(self.description,"task:2")
    def test_healthy_previous_release_is_not_success(self):
        with self.assertRaises(RuntimeError): verify_service(self.description,"task:3")
    def test_failed_rollout_is_not_success(self):
        self.description["services"][0]["deployments"][0]["rolloutState"] = "FAILED"
        with self.assertRaises(RuntimeError): verify_service(self.description,"task:2")
    def test_missing_running_tasks(self):
        self.description["services"][0]["runningCount"] = 1
        with self.assertRaises(RuntimeError): verify_service(self.description,"task:2")
    def test_service_not_found(self):
        with self.assertRaises(RuntimeError): verify_service({"failures":[{"reason":"MISSING"}]},"task:2")
    def test_http_revision_mismatch_is_rejected(self):
        response = MagicMock()
        response.__enter__.return_value = response
        response.status = 200
        with patch("smoke.urlopen", return_value=response), patch("smoke.json.load", side_effect=[{"status":"ok"},{"revision":"old"}]):
            with self.assertRaises(RuntimeError): check("http://example.test","new",attempts=1)
    def test_http_expected_revision(self):
        response = MagicMock()
        response.__enter__.return_value = response
        response.status = 200
        with patch("smoke.urlopen",return_value=response), patch("smoke.json.load",side_effect=[{"status":"ok"},{"revision":"new"}]):
            self.assertEqual(check("http://example.test","new",attempts=1),"new")
