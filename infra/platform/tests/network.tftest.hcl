mock_provider "aws" {
  mock_data "aws_availability_zones" { defaults = { names = ["us-east-1a", "us-east-1b"] } }
}
run "private_two_az_network" {
  command = plan
  module { source = "../modules/network" }
  variables { name = "delivery-test" }
  assert {
    condition     = length(aws_subnet.private) == 2 && length(aws_subnet.public) == 2 && length(aws_nat_gateway.this) == 2
    error_message = "Application subnets and NAT gateways must span two AZs."
  }
  assert {
    condition     = alltrue([for subnet in aws_subnet.private : subnet.map_public_ip_on_launch == false])
    error_message = "Private application subnets must not auto-assign public IPs."
  }
  assert {
    condition     = alltrue([for rule in aws_security_group.task.egress : rule.from_port == 443 && rule.to_port == 443 && rule.protocol == "tcp"])
    error_message = "Tasks must have HTTPS-only internet egress."
  }
}
