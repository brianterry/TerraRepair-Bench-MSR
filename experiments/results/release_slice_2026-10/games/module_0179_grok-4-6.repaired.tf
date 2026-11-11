# Default ALB implementation that can be used connect ECS instances to it

resource "aws_alb_target_group" "default" {
  name                 = "${var.alb_name}-default"
  port                 = 443
  protocol             = "HTTPS"
  vpc_id               = var.vpc_id
  deregistration_delay = var.deregistration_delay

  health_check {
    path     = var.health_check_path
    protocol = "HTTPS"
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_alb" "alb" {
  name                       = var.alb_name
  subnets                    = var.public_subnet_ids
  security_groups            = ["${aws_security_group.alb.id}"]
  internal                   = true
  drop_invalid_header_fields = true
  enable_deletion_protection = true

  access_logs {
    enabled = true
    bucket  = "${var.environment}-${var.alb_name}-alb-access-logs"
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_alb.alb.id
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = data.aws_acm_certificate.issued.arn

  default_action {
    target_group_arn = aws_alb_target_group.default.id
    type             = "forward"
  }
}

data "aws_acm_certificate" "issued" {
  most_recent = true
  statuses    = ["ISSUED"]
}

resource "aws_security_group" "alb" {
  name        = "${var.alb_name}_alb"
  description = "Security group for the ALB"
  vpc_id      = var.vpc_id

  tags = {
    Environment = var.environment
  }
}

resource "aws_security_group_rule" "https_from_anywhere" {
  type              = "ingress"
  description       = "Allow HTTPS inbound traffic to the ALB"
  from_port         = 443
  to_port           = 443
  protocol          = "TCP"
  cidr_blocks       = var.allow_cidr_block
  security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "outbound_internet_access" {
  type              = "egress"
  description       = "Allow outbound HTTPS to VPC targets"
  from_port         = 443
  to_port           = 443
  protocol          = "TCP"
  cidr_blocks       = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  security_group_id = aws_security_group.alb.id
}


output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "default_alb_target_group" {
  value = aws_alb_target_group.default.arn
}


variable "alb_name" {
  default     = "default"
  description = "The name of the loadbalancer"
}

variable "environment" {
  description = "The name of the environment"
}

variable "public_subnet_ids" {
  type        = list
  description = "List of public subnet ids to place the loadbalancer in"
}

variable "vpc_id" {
  description = "The VPC id"
}

variable "deregistration_delay" {
  default     = "300"
  description = "The default deregistration delay"
}

variable "health_check_path" {
  default     = "/"
  description = "The default health check path"
}

variable "allow_cidr_block" {
  default     = ["0.0.0.0/0"]
  description = "Specify cidr block that is allowed to access the LoadBalancer"
}