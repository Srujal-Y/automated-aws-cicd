data "aws_caller_identity" "current" {}
module "network" {
  source = "../modules/network"
  name   = var.name
}
resource "aws_ecr_repository" "app" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
}
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy     = jsonencode({ rules = [{ rulePriority = 1, description = "Expire untagged builds after seven days", selection = { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 7 }, action = { type = "expire" } }] })
}
resource "aws_ecs_cluster" "app" {
  name = var.name
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.name}"
  retention_in_days = 30
}
locals {
  task_trust  = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  service_arn = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:service/${var.name}/${var.name}"
  task_arn    = "arn:aws:ecs:${var.region}:${data.aws_caller_identity.current.account_id}:task-definition/${var.name}:*"
}
resource "aws_iam_role" "execution" {
  name               = "${var.name}-execution"
  assume_role_policy = local.task_trust
}
resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = local.task_trust
}
resource "aws_lb" "app" {
  name                       = var.name
  load_balancer_type         = "application"
  subnets                    = module.network.public_subnets
  security_groups            = [module.network.alb_sg]
  drop_invalid_header_fields = true
}
resource "aws_lb_target_group" "app" {
  name                 = var.name
  vpc_id               = module.network.vpc_id
  port                 = 8000
  protocol             = "HTTP"
  target_type          = "ip"
  deregistration_delay = 30
  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = var.certificate_arn == null ? "forward" : "redirect"
    target_group_arn = var.certificate_arn == null ? aws_lb_target_group.app.arn : null
    dynamic "redirect" {
      for_each = var.certificate_arn == null ? [] : [1]
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }
}
resource "aws_lb_listener" "https" {
  count             = var.certificate_arn == null ? 0 : 1
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
  lifecycle {
    precondition {
      condition     = var.public_hostname != null
      error_message = "HTTPS requires public_hostname matching the certificate and ALB DNS alias."
    }
  }
}
locals {
  deployment_config = {
    name               = var.name
    region             = var.region
    repository_url     = aws_ecr_repository.app.repository_url
    cluster_arn        = aws_ecs_cluster.app.arn
    cluster_name       = aws_ecs_cluster.app.name
    task_role_arn      = aws_iam_role.task.arn
    execution_role_arn = aws_iam_role.execution.arn
    log_group          = aws_cloudwatch_log_group.app.name
    subnet_ids         = module.network.private_subnets
    security_group_id  = module.network.task_sg
    target_group_arn   = aws_lb_target_group.app.arn
    url                = var.certificate_arn == null ? "http://${aws_lb.app.dns_name}" : "https://${var.public_hostname}"
  }
}
resource "aws_s3_object" "deployment_config" {
  bucket       = var.state_bucket
  key          = "${var.state_prefix}/deployment.json"
  content      = jsonencode(local.deployment_config)
  content_type = "application/json"
  depends_on   = [aws_lb_listener.http, aws_lb_listener.https, aws_iam_role_policy_attachment.execution]
}
output "deployment_role_arn" { value = aws_iam_role.github.arn }
output "configuration_uri" { value = "s3://${var.state_bucket}/${aws_s3_object.deployment_config.key}" }
output "url" { value = local.deployment_config.url }
output "repository_url" { value = aws_ecr_repository.app.repository_url }
