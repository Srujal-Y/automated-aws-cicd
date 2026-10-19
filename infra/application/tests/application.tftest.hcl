mock_provider "aws" {}
variables {
  region    = "us-east-1"
  image_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/delivery-platform@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  platform = {
    name               = "delivery-platform", region = "us-east-1",
    repository_url     = "123456789012.dkr.ecr.us-east-1.amazonaws.com/delivery-platform",
    cluster_arn        = "arn:aws:ecs:us-east-1:123456789012:cluster/delivery-platform", cluster_name = "delivery-platform",
    task_role_arn      = "arn:aws:iam::123456789012:role/delivery-platform-task",
    execution_role_arn = "arn:aws:iam::123456789012:role/delivery-platform-execution",
    log_group          = "/ecs/delivery-platform", subnet_ids = ["subnet-12345678", "subnet-87654321"], security_group_id = "sg-12345678",
    target_group_arn   = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/delivery-platform/1234567890123456",
    url                = "http://example.test"
  }
}
run "rolling_release_controls" {
  command = plan
  assert {
    condition     = aws_ecs_service.app.desired_count == 2 && aws_ecs_service.app.deployment_minimum_healthy_percent == 100 && aws_ecs_service.app.deployment_maximum_percent == 200
    error_message = "Rolling releases must preserve capacity with at least two tasks."
  }
  assert {
    condition     = aws_ecs_service.app.deployment_circuit_breaker[0].enable && aws_ecs_service.app.deployment_circuit_breaker[0].rollback
    error_message = "Failed ECS deployments must support automatic rollback."
  }
  assert {
    condition     = !aws_ecs_service.app.network_configuration[0].assign_public_ip
    error_message = "Application tasks must not receive public IP addresses."
  }
  assert {
    condition     = jsondecode(aws_ecs_task_definition.app.container_definitions)[0].image == var.image_uri && jsondecode(aws_ecs_task_definition.app.container_definitions)[0].user == "10001"
    error_message = "Tasks must run the requested digest as a non-root user."
  }
}
run "reject_wrong_repository" {
  command = plan
  variables { image_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/other@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  expect_failures = [aws_ecs_task_definition.app]
}
run "reject_mutable_image_tag" {
  command = plan
  variables { image_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/delivery-platform:latest" }
  expect_failures = [var.image_uri]
}
