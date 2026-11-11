terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

resource "aws_lb" "example" {
  name               = var.alb_name
  load_balancer_type = "application"

  subnets            = var.subnet_ids

  security_groups    = [aws_security_group.alb.id]

  drop_invalid_header_fields = true
  deletion_protection        = true
  access_logs {
    enabled = true
    s3_bucket = "your-s3-bucket-name"
    s3_prefix = "your-s3-prefix"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = local.http_port
  protocol          = "HTTPS"

  ssl_policy        = "ELBSecurityPolicy-2016-08"
  tls_min_protocol_version = "TLSv1.2"

  default_action {
    type = "redirect"

    redirect {
      protocol = "HTTPS"
      port     = "443"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.example.arn
  port              = 443
  protocol          = "HTTPS"

  ssl_policy        = "ELBSecurityPolicy-2016-08"
  tls_min_protocol_version = "TLSv1.2"

  certificate_arn = var.certificate_arn

  default_action {
    type = "forward"

    forward {
      target_group_arn = aws_target_group.example.arn
    }
  }
}

resource "aws_security_group" "alb" {
  name        = var.alb_name
  description = "Security group for ALB"

  vpc_id = var.vpc_id
}

resource "aws_security_group_rule" "allow_http_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id

  from_port   = local.http_port
  to_port     = local.http_port
  protocol    = local.tcp_protocol
  cidr_blocks = local.all_ips

  description = "Allow HTTP inbound traffic"
}

resource "aws_security_group_rule" "allow_https_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id

  from_port   = 443
  to_port     = 443
  protocol    = "tcp"

  description = "Allow HTTPS inbound traffic"
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type              = "egress"
  security_group_id = aws_security_group.alb.id

  from_port   = 0
  to_port     = 0
  protocol    = "-1"

  description = "Allow all outbound traffic"
}

locals {
  http_port    = 80
  any_port     = 0
  any_protocol = "-1"
  tcp_protocol = "tcp"
  all_ips      = ["0.0.0.0/0"]
}

output "alb_dns_name" {
  value       = aws_lb.example.dns_name
  description = "The domain name of the load balancer"
}

output "alb_http_listener_arn" {
  value       = aws_lb_listener.http.arn
  description = "The ARN of the HTTP listener"
}

output "alb_security_group_id" {
  value       = aws_security_group.alb.id
  description = "The ALB Security Group ID"
}

# ---------------------------------------------------------------------------------------------------------------------
# REQUIRED PARAMETERS
# You must provide a value for each of these parameters.
# ---------------------------------------------------------------------------------------------------------------------

variable "alb_name" {
  description = "The name to use for this ALB"
  type        = string
}

variable "subnet_ids" {
  description = "The subnet IDs to deploy to"
  type        = list(string)
}

variable "vpc_id" {
  description = "The VPC ID to deploy to"
  type        = string
}

variable "certificate_arn" {
  description = "The ARN of the SSL certificate"
  type        = string
}