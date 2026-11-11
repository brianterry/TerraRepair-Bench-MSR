resource "aws_instance" "blue" {
  count                  = var.enable_blue_env ? var.blue_instance_count : 0
  ami                    = local.ubuntu_ami
  instance_type          = "t2.micro"
  subnet_id              = local.private_a_subnet_id
  vpc_security_group_ids = [aws_security_group.web.id]
  user_data              = templatefile("./init-script.sh", { file_content = "blue version 1.2 - ${count.index}" })
  tags                   = { Name = "blue version 1.2 - ${count.index}" }
  metadata_options       = { http_tokens = "required", http_endpoint = "enabled" }
  root_block_device      = [{ encrypted = true }]
  ebs_optimized          = true
  monitoring             = { enabled = true }
  iam_instance_profile   = { name = "ec2-instance-profile" }
}

resource "aws_lb_target_group" "blue" {
  name     = "blue-tg-blue-lb"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = local.vpc_id
  health_check {
    port     = 443
    protocol = "HTTPS"
    timeout  = 5
    interval = 10
  }
}

resource "aws_lb_target_group_attachment" "blue" {
  count            = length(aws_instance.blue)
  target_group_arn = aws_lb_target_group.blue.arn
  target_id        = aws_instance.blue[count.index].id
  port             = 443
}

resource "aws_instance" "green" {
  count                  = var.enable_green_env ? var.green_instance_count : 0
  ami                    = local.ubuntu_ami
  instance_type          = "t2.micro"
  subnet_id              = local.private_a_subnet_id
  vpc_security_group_ids = [aws_security_group.web.id]
  user_data              = templatefile("./init-script.sh", { file_content = "green version 1.1 - ${count.index}" })
  tags                   = { Name = "green version 1.1 - ${count.index}" }
  metadata_options       = { http_tokens = "required", http_endpoint = "enabled" }
  root_block_device      = [{ encrypted = true }]
  ebs_optimized          = true
  monitoring             = { enabled = true }
  iam_instance_profile   = { name = "ec2-instance-profile" }
}

resource "aws_lb_target_group" "green" {
  name     = "green-tg-green-lb"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = local.vpc_id
  health_check {
    port     = 443
    protocol = "HTTPS"
    timeout  = 5
    interval = 10
  }
}

resource "aws_lb_target_group_attachment" "green" {
  count            = length(aws_instance.green)
  target_group_arn = aws_lb_target_group.green.arn
  target_id        = aws_instance.green[count.index].id
  port             = 443
}

resource "aws_security_group" "web" {
  name        = "web-sg"
  description = "Security group for web-servers with HTTPS ports open within VPC"
  vpc_id      = local.vpc_id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS from anywhere"
  }
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS to anywhere"
  }
}

resource "aws_lb" "app" {
  name               = "app-lb"
  internal           = true
  load_balancer_type = "application"
  subnets            = [local.public_a_subnet_id, local.public_b_subnet_id]
  security_groups    = [aws_security_group.web.id]
  enable_deletion_protection = true
  access_logs {
    bucket  = "app-lb-logs"
    prefix  = "app-lb"
  }
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS12-Ext-1-2-2021-06"
  certificate_arn   = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  default_action {
    type = "forward"
    forward {
      target_group_arn = aws_lb_target_group.blue.arn
      weight           = lookup(local.traffic_dist_map[var.traffic_distribution], "blue", 100)
    }
    target_group_arn = aws_lb_target_group.green.arn
    weight           = lookup(local.traffic_dist_map[var.traffic_distribution], "green", 0)
  }
}