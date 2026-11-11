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
  internal           = true
  drop_invalid_header_fields = true
  enable_deletion_protection = true
  access_logs {
    bucket  = var.access_logs_bucket
    enabled = true
  }
}

resource "aws_wafv2_web_acl_association" "example" {
  resource_arn = aws_lb.example.arn
  web_acl_arn  = var.waf_web_acl_arn
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = local.https_port
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

resource "aws_security_group" "alb" {
  name        = var.alb_name
  description = "Security group for ALB"
}

resource "aws_security_group_rule" "allow_http_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTPS inbound traffic"

  from_port   = local.https_port
  to_port     = local.https_port
  protocol    = local.tcp_protocol
  cidr_blocks = var.allowed_cidr_blocks
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type              = "egress"
  security_group_id = aws_security_group.alb.id
  description       = "Allow outbound traffic to specific ports"

  from_port   = local.https_port
  to_port     = local.https_port
  protocol    = local.tcp_protocol
  cidr_blocks = var.allowed_cidr_blocks
}

locals {
  http_port    = 80
  https_port   = 443
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

variable "alb_name" {
  description = "The name to use for this ALB"
  type        = string
}

variable "subnet_ids" {
  description = "The subnet IDs to deploy to"
  type        = list(string)
}

variable "access_logs_bucket" {
  description = "S3 bucket for ALB access logs"
  type        = string
}

variable "waf_web_acl_arn" {
  description = "WAF Web ACL ARN to associate with the ALB"
  type        = string
}

variable "certificate_arn" {
  description = "ARN of the SSL certificate for HTTPS listener"
  type        = string
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the ALB"
  type        = list(string)
}