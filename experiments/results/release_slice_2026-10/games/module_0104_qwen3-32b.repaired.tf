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

resource "aws_instance" "example" {
  ami           = "ami-0a695f0d95cefc163"
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.instance.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF

  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_path_style             = true
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = true
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name = "my-ubuntu"
  }
}

resource "aws_launch_configuration" "example" {
  image_id        = "ami-0a695f0d95cefc163"
  instance_type   = "t3.micro"
  security_groups = [aws_security_group.instance.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF

  metadata_options {
    http_endpoint               = "enabled"
    http_path_style             = true
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = true
  }

  root_block_device {
    encrypted = true
  }

  # Required with an autoscaling group.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "instance" {
  name = "web"

  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  description = "Security group for EC2 instances"
}

resource "aws_autoscaling_group" "example" {
  launch_configuration = aws_launch_configuration.example.name
  vpc_zone_identifier  = data.aws_subnets.default.ids

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
  name               = "web"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.alb.id]

  drop_invalid_header = true
  deletion_protection = true
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = 443
  protocol          = "HTTPS"

  default_action {
    type = "forward"

    forward {
      target_group {
        arn = aws_lb_target_group.asg.arn
      }
    }
  }
}

resource "aws_security_group" "alb" {
  name = "web-alb"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  description = "Security group for ALB"
}

resource "aws_lb_target_group" "asg" {
  name     = "web-example"
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