terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

resource "aws_launch_configuration" "example" {
  image_id        = "ami-0fb653ca2d3203ac1"
  instance_type   = var.instance_type
  security_groups = [aws_security_group.instance.id]

  user_data = templatefile("${path.module}/user-data.sh", {
    server_port = var.server_port
    db_address  = data.terraform_remote_state.db.outputs.address
    db_port     = data.terraform_remote_state.db.outputs.port
  })

  encrypted_block_device = true

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "example" {
  launch_template {
    name       = aws_launch_template.example.name
    version    = aws_launch_template.example.latest_version
  }

  vpc_zone_identifier  = data.aws_subnets.default.ids
  target_group_arns    = [aws_lb_target_group.asg.arn]
  health_check_type    = "ELB"

  min_size = var.min_size
  max_size = var.max_size

  tag {
    key                 = "Name"
    value               = var.cluster_name
    propagate_at_launch = true
  }
}

resource "aws_security_group" "instance" {
  name        = "${var.cluster_name}-instance"
  description = "Security group for instance"
}

resource "aws_security_group_rule" "allow_server_http_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.instance.id

  from_port   = var.server_port
  to_port     = var.server_port
  protocol    = local.tcp_protocol
  cidr_blocks = local.all_ips

  description = "Allow inbound HTTP traffic from all IPs"
}

resource "aws_lb" "example" {
  name               = var.cluster_name
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.alb.id]

  deletion_protection = true
  access_logs_enabled  = true
  drop_invalid_headers = true

  description = "Application Load Balancer for the cluster"
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.example.arn
  port              = local.https_port
  protocol          = "HTTPS"

  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.certificate_arn

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

resource "aws_lb_target_group" "asg" {
  name     = var.cluster_name
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

resource "aws_security_group" "alb" {
  name        = "${var.cluster_name}-alb"
  description = "Security group for ALB"
}

resource "aws_security_group_rule" "allow_http_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id

  from_port   = local.http_port
  to_port     = local.http_port
  protocol    = local.tcp_protocol
  cidr_blocks = ["10.0.0.0/16"]

  description = "Allow inbound HTTP traffic from the VPC"
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type              = "egress"
  security_group_id = aws_security_group.alb.id

  from_port   = local.any_port
  to_port     = local.any_port
  protocol    = local.any_protocol
  cidr_blocks = ["0.0.0.0/0"]

  description = "Allow all outbound traffic"
}

resource "aws_waf_web_acl" "example" {
  name        = "example-waf"
  metric_name = "example-waf"

  default_action {
    type = "allow"
  }

  scope = "REGIONAL"

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name               = "example-waf"
    sampled_requests_enabled  = true
  }

  rule {
    action {
      block = true
    }

    priority = 1

    statement {
      and_statement {
        not_statement {
          ip_set_reference_statement {
            arn = aws_waf_ip_set.good_ips.arn
          }
        }

        sqli_match_statement {
          field_to_match {
            all_query_arguments = true
          }

          comparison_operator = "EQ"
          text_transformation = "URL_DECODE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name               = "example-waf-sqli"
      sampled_requests_enabled   = true
    }
  }

  rule {
    action {
      allow = true
    }

    priority = 2

    statement {
      ip_set_reference_statement {
        arn = aws_waf_ip_set.good_ips.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name               = "example-waf-allow"
      sampled_requests_enabled  = true
    }
  }

  tags = {
    Name = "example-waf"
  }
}

resource "aws_waf_ip_set" "good_ips" {
  name        = "example-good-ips"
  description = "IPs that are allowed to access the ALB"

  ip_addresses = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

data "terraform_remote_state" "db" {
  backend = "s3"

  config = {
    bucket = var.db_remote_state_bucket
    key    = var.db_remote_state_key
    region = "us-east-2"
  }
}

locals {
  http_port    = 80
  https_port   = 443
  any_port     = 0
  any_protocol = "-1"
  tcp_protocol = "tcp"
  all_ips      = ["0.0.0.0/0"]
  certificate_arn = var.certificate_arn
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

output "alb_dns_name" {
  value       = aws_lb.example.dns_name
  description = "The domain name of the load balancer"
}

output "asg_name" {
  value       = aws_autoscaling_group.example.name
  description = "The name of the Auto Scaling Group"
}

output "alb_security_group_id" {
  value       = aws_security_group.alb.id
  description = "The ID of the Security Group attached to the load balancer"
}

variable "cluster_name" {
  description = "The name to use for all the cluster resources"
  type        = string
}

variable "db_remote_state_bucket" {
  description = "The name of the S3 bucket for the database's remote state"
  type        = string
}

variable "db_remote_state_key" {
  description = "The path for the database's remote state in S3"
  type        = string
}

variable "instance_type" {
  description = "The type of EC2 Instances to run (e.g. t2.micro)"
  type        = string
}

variable "min_size" {
  description = "The minimum number of EC2 Instances in the ASG"
  type        = number
}

variable "max_size" {
  description = "The maximum number of EC2 Instances in the ASG"
  type        = number
}

variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type        = number
  default     = 8080
}

variable "certificate_arn" {
  description = "The ARN of the SSL certificate to use for HTTPS"
  type        = string
}