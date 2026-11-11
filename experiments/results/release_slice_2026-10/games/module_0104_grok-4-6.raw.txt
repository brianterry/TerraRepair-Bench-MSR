provider "aws" {
  region = "us-east-2"
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

resource "aws_iam_role" "example" {
  name        = "example-ec2-role"
  description = "IAM role for EC2 instances"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "example" {
  name = "example-ec2-profile"
  role = aws_iam_role.example.name
}

resource "aws_instance" "example" {
  ami                  = "ami-0a695f0d95cefc163"
  instance_type        = "t3.micro"
  ebs_optimized        = true
  monitoring           = true
  iam_instance_profile = aws_iam_instance_profile.example.name

  vpc_security_group_ids = [aws_security_group.instance.id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted = true
  }

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF

  user_data_replace_on_change = true

  tags = {
    Name = "my-ubuntu"
  }
}

resource "aws_launch_template" "example" {
  image_id      = "ami-0a695f0d95cefc163"
  instance_type = "t3.micro"
  ebs_optimized = true

  vpc_security_group_ids = [aws_security_group.instance.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.example.name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      encrypted   = true
      volume_size = 8
    }
  }

  monitoring {
    enabled = true
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "instance" {
  name        = "web"
  description = "Security group for web instances"

  ingress {
    description     = "Allow application traffic from ALB"
    from_port       = var.server_port
    to_port         = var.server_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
}

resource "aws_autoscaling_group" "example" {
  vpc_zone_identifier = data.aws_subnets.default.ids

  launch_template {
    id      = aws_launch_template.example.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"

  min_size = 2
  max_size = 10

  tag {
    key                 = "Name"
    value               = "web"
    propagate_at_launch = true
  }
}

resource "aws_lb" "example" {
  name                       = "web"
  load_balancer_type         = "application"
  subnets                    = data.aws_subnets.default.ids
  security_groups            = [aws_security_group.alb.id]
  internal                   = true
  drop_invalid_header_fields = true
  enable_deletion_protection = true

  access_logs {
    bucket  = "web-alb-access-logs"
    enabled = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = "arn:aws:acm:us-east-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_security_group" "alb" {
  name        = "web-alb"
  description = "Security group for the application load balancer"

  ingress {
    description = "Allow HTTPS inbound from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    description = "Allow outbound to web instances"
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }
}

resource "aws_lb_target_group" "asg" {
  name     = "web-example"
  port     = var.server_port
  protocol = "HTTPS"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTPS"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
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

output "alb_dns_name" {
  value       = aws_lb.example.dns_name
  description = "DNS of the application load balancer"
}

variable "server_port" {
  description = "The port that the server will use to handle HTTP requests"
  type        = number
  default     = 8080
}