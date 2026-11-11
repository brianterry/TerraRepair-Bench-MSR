resource "aws_instance" "blue" {
  count = var.enable_blue_env ? var.blue_instance_count : 0

  ami                    = local.ubuntu_ami
  instance_type          = "t2.micro"
  subnet_id              = local.private_a_subnet_id
  vpc_security_group_ids = [aws_security_group.web.id]
  ebs_optimized          = true
  monitoring             = true

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted = true
  }

  user_data = templatefile("./init-script.sh", {
    file_content = "blue version 1.2 - ${count.index}"
  })

  tags = {
    Name = "blue version 1.2 - ${count.index}"
  }
}

resource "aws_lb_target_group" "blue" {
  name     = "blue-tg-blue-lb"
  port     = 80
  protocol = "HTTP"
  vpc_id   = local.vpc_id

  health_check {
    enabled  = true
    port     = 80
    protocol = "HTTP"
    timeout  = 5
    interval = 10
    path     = "/"
    matcher  = "200"
  }
}

resource "aws_lb_target_group_attachment" "blue" {
  count            = length(aws_instance.blue)
  target_group_arn = aws_lb_target_group.blue.arn
  target_id        = aws_instance.blue[count.index].id
  port             = 80
}

resource "aws_instance" "green" {
  count = var.enable_green_env ? var.green_instance_count : 0

  ami                    = local.ubuntu_ami
  instance_type          = "t2.micro"
  subnet_id              = local.private_a_subnet_id
  vpc_security_group_ids = [aws_security_group.web.id]
  ebs_optimized          = true
  monitoring             = true

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted = true
  }

  user_data = templatefile("./init-script.sh", {
    file_content = "green version 1.1 - ${count.index}"
  })

  tags = {
    Name = "green version 1.1 - ${count.index}"
  }
}

resource "aws_lb_target_group" "green" {
  name     = "green-tg-green-lb"
  port     = 80
  protocol = "HTTP"
  vpc_id   = local.vpc_id

  health_check {
    enabled  = true
    port     = 80
    protocol = "HTTP"
    timeout  = 5
    interval = 10
    path     = "/"
    matcher  = "200"
  }
}

resource "aws_lb_target_group_attachment" "green" {
  count            = length(aws_instance.green)
  target_group_arn = aws_lb_target_group.green.arn
  target_id        = aws_instance.green[count.index].id
  port             = 80
}


locals {
  vpc_id              = "vpc-08a51e4a8e1a4226b"
  private_a_subnet_id = "subnet-0e0317ff5d26c8b12"
  private_b_subnet_id = "subnet-0f4ec7d0ea60605bd"
  public_a_subnet_id  = "subnet-09316aa45c8669d28"
  public_b_subnet_id  = "subnet-08c7b53b2ca1d202b"

  ubuntu_ami = "ami-042e8287309f5df03"

  traffic_dist_map = {
    blue = {
      blue  = 100
      green = 0
    }
    blue-90 = {
      blue  = 90
      green = 10
    }
    split = {
      blue  = 50
      green = 50
    }
    green-90 = {
      blue  = 10
      green = 90
    }
    green = {
      blue  = 0
      green = 100
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_security_group" "web" {
  name        = "web-sg"
  description = "Security group for web-servers with HTTP ports open within VPC"
  vpc_id      = local.vpc_id

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description      = "Allow HTTPS outbound"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "app" {
  name                       = "app-lb"
  internal                   = true
  load_balancer_type         = "application"
  subnets = [
    local.public_a_subnet_id,
    local.public_b_subnet_id
  ]
  security_groups            = [aws_security_group.web.id]
  drop_invalid_header_fields = true
  enable_deletion_protection = true

  access_logs {
    enabled = true
    bucket  = ""
  }
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = ""

  default_action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.blue.arn
        weight = lookup(local.traffic_dist_map[var.traffic_distribution], "blue", 100)
      }

      target_group {
        arn    = aws_lb_target_group.green.arn
        weight = lookup(local.traffic_dist_map[var.traffic_distribution], "green", 0)
      }

      stickiness {
        enabled  = false
        duration = 1
      }
    }
  }
}


output "lb_dns_name" {
  value = aws_lb.app.dns_name
}


variable "enable_blue_env" {
  description = "Enable blue environment"
  type        = bool
  default     = true
}

variable "blue_instance_count" {
  description = "Number of instances in blue environment"
  type        = number
  default     = 2
}

variable "enable_green_env" {
  description = "Enable green environment"
  type        = bool
  default     = false
}

variable "green_instance_count" {
  description = "Number of instances in green environment"
  type        = number
  default     = 2
}

variable "traffic_distribution" {
  description = "Levels of traffic distribution"
  type        = string
}


terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.20.0"
    }
  }
  required_version = "~> 0.14"
}