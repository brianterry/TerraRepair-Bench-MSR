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
  internal                   = false
  drop_invalid_header_fields = true
  enable_deletion_protection = true

  access_logs {
    enabled = true
    bucket  = var.alb_access_logs_bucket
    prefix  = var.alb_name
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_alb.alb.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_alb_listener" "https" {
  load_balancer_arn = aws_alb.alb.id
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    target_group_arn = aws_alb_target_group.default.id
    type             = "forward"
  }
}

resource "aws_security_group" "alb" {
  name        = "${var.alb_name}_alb"
  description = "Security group for ALB ${var.alb_name}"
  vpc_id      = var.vpc_id

  tags = {
    Environment = var.environment
  }
}

resource "aws_security_group_rule" "https_from_anywhere" {
  description       = "Allow HTTPS ingress from specified CIDR blocks"
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "TCP"
  cidr_blocks       = var.allow_cidr_block
  security_group_id = aws_security_group.alb.id
}

resource "aws_security_group_rule" "outbound_internet_access" {
  description       = "Allow restricted egress to specific CIDR blocks"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = var.egress_cidr_blocks
  security_group_id = aws_security_group.alb.id
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_alb.alb.arn
  web_acl_arn  = var.waf_web_acl_arn
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

variable "alb_access_logs_bucket" {
  description = "S3 bucket for ALB access logs"
}

variable "certificate_arn" {
  description = "ARN of the SSL certificate for the ALB"
}

variable "egress_cidr_blocks" {
  description = "CIDR blocks for restricted egress traffic"
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

variable "waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL to associate with the ALB"
}