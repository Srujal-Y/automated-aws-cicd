mock_provider "aws" {
  mock_data "aws_availability_zones" { defaults = { names = ["us-east-1a", "us-east-1b"] } }
  mock_data "aws_caller_identity" { defaults = { account_id = "123456789012" } }
}
run "delivery_platform_controls" {
  command = plan
  variables {
    name                       = "delivery-platform"
    github_repository          = "example/delivery-platform"
    state_bucket               = "example-delivery-state"
    existing_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  }
  assert {
    condition     = aws_ecr_repository.app.image_tag_mutability == "IMMUTABLE" && aws_ecr_repository.app.image_scanning_configuration[0].scan_on_push
    error_message = "Release images must use immutable tags and scan on push."
  }
  assert {
    condition     = aws_cloudwatch_log_group.app.retention_in_days == 30
    error_message = "Application logs must have an explicit retention policy."
  }
  assert {
    condition     = jsondecode(aws_iam_role.github.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:example/delivery-platform:environment:production"
    error_message = "OIDC trust must be scoped to the exact repository and protected environment."
  }
  assert {
    condition     = jsondecode(aws_iam_role.github.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    error_message = "OIDC audience must be AWS STS."
  }
  assert {
    condition     = aws_lb_target_group.app.target_type == "ip" && aws_lb_target_group.app.health_check[0].path == "/healthz"
    error_message = "Fargate needs IP targets and an application health endpoint."
  }
}
