variable "region" { default = "us-east-1" }
variable "platform" {
  type = object({
    name          = string, region = string, repository_url = string, cluster_arn = string, cluster_name = string,
    task_role_arn = string, execution_role_arn = string, log_group = string,
    subnet_ids    = list(string), security_group_id = string, target_group_arn = string, url = string
  })
}
variable "image_uri" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}[.]dkr[.]ecr[.][a-z0-9-]+[.]amazonaws[.]com/[a-z0-9/_-]+@sha256:[0-9a-f]{64}$", var.image_uri))
    error_message = "Use an immutable private ECR image URI with a sha256 digest."
  }
}
resource "aws_ecs_task_definition" "app" {
  skip_destroy             = true
  family                   = var.platform.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = var.platform.execution_role_arn
  task_role_arn            = var.platform.task_role_arn
  container_definitions = jsonencode([{
    name             = "app", image = var.image_uri, essential = true, user = "10001", readonlyRootFilesystem = false,
    portMappings     = [{ containerPort = 8000, protocol = "tcp" }],
    environment      = [{ name = "APP_ENVIRONMENT", value = "production" }],
    linuxParameters  = { capabilities = { drop = ["ALL"] } },
    logConfiguration = { logDriver = "awslogs", options = { awslogs-group = var.platform.log_group, awslogs-region = var.region, awslogs-stream-prefix = "app" } },
    healthCheck      = { command = ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2)"], interval = 30, timeout = 5, retries = 3, startPeriod = 30 }
  }])
  lifecycle {
    create_before_destroy = true
    precondition {
      condition     = startswith(var.image_uri, "${var.platform.repository_url}@sha256:") && var.region == var.platform.region
      error_message = "Image repository and region must match the provisioned platform."
    }
  }
}
resource "aws_ecs_service" "app" {
  name                               = var.platform.name
  cluster                            = var.platform.cluster_arn
  task_definition                    = aws_ecs_task_definition.app.arn
  desired_count                      = 2
  launch_type                        = "FARGATE"
  platform_version                   = "1.4.0"
  wait_for_steady_state              = true
  health_check_grace_period_seconds  = 60
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = var.platform.subnet_ids
    security_groups  = [var.platform.security_group_id]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = var.platform.target_group_arn
    container_name   = "app"
    container_port   = 8000
  }
  timeouts {
    create = "20m"
    update = "20m"
  }
}
output "task_definition_arn" { value = aws_ecs_task_definition.app.arn }
output "url" { value = var.platform.url }
