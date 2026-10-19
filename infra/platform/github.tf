resource "aws_iam_openid_connect_provider" "github" {
  count          = var.existing_oidc_provider_arn == null ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
locals {
  oidc_arn = var.existing_oidc_provider_arn == null ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn
}
resource "aws_iam_role" "github" {
  name = "${var.name}-github-deploy"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "sts:AssumeRoleWithWebIdentity", Principal = { Federated = local.oidc_arn },
    Condition = { StringEquals = {
      "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:environment:${var.github_environment}"
    } }
  }] })
}
resource "aws_iam_role_policy" "github" {
  role = aws_iam_role.github.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Sid = "ECRLogin", Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
    { Sid = "RepositoryDelivery", Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:DescribeImages"], Resource = aws_ecr_repository.app.arn },
    { Sid = "TaskRegistration", Effect = "Allow", Action = ["ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition"], Resource = "*" },
    { Sid = "ManageRelease", Effect = "Allow", Action = ["ecs:CreateService", "ecs:UpdateService", "ecs:DeleteService", "ecs:DescribeServices", "ecs:ListTagsForResource", "ecs:TagResource", "ecs:UntagResource"], Resource = local.service_arn },
    { Sid = "ManageTaskRevisions", Effect = "Allow", Action = ["ecs:DeregisterTaskDefinition", "ecs:TagResource", "ecs:UntagResource", "ecs:ListTagsForResource"], Resource = local.task_arn },
    { Sid = "PassOnlyTaskRoles", Effect = "Allow", Action = ["iam:PassRole"], Resource = [aws_iam_role.execution.arn, aws_iam_role.task.arn], Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } } },
    { Sid = "ReadDeploymentConfig", Effect = "Allow", Action = ["s3:GetObject"], Resource = "arn:aws:s3:::${var.state_bucket}/${var.state_prefix}/deployment.json" },
    { Sid = "ListApplicationState", Effect = "Allow", Action = ["s3:ListBucket"], Resource = "arn:aws:s3:::${var.state_bucket}", Condition = { StringLike = { "s3:prefix" = ["${var.state_prefix}/application.tfstate*", "env:/*"] } } },
    { Sid = "ApplicationState", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"], Resource = "arn:aws:s3:::${var.state_bucket}/${var.state_prefix}/application.tfstate" },
    { Sid = "ApplicationStateLock", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = "arn:aws:s3:::${var.state_bucket}/${var.state_prefix}/application.tfstate.tflock" }
  ] })
}
