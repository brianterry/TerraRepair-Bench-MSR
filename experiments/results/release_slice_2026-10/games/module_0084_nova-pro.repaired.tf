provider "aws" {
  region = "us-east-1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.48"
    }
  }
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main"
  }

  flow_log {
    iam_role_arn = aws_iam_role.flow_logs.arn
    traffic_type = "REJECT"
  }
}

resource "aws_iam_role" "flow_logs" {
  name = "flow_logs_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        },
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_instance" "traefik" {
  ami                    = data.aws_ami.ubuntu_jammy.id
  instance_type          = "t3a.small"
  subnet_id              = aws_subnet.public_us_east_1a.id
  vpc_security_group_ids = [aws_security_group.proxy.id]

  iam_instance_profile = aws_iam_instance_profile.ssm_core.name

  tags = {
    Name             = "traefik.antonputra.com"
    node-exporter    = "true"
    traefik-exporter = "true"
  }

  metadata_options {
    http_tokens = "required"
    http_endpoint = true
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted = true
  }

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_type = "gp2"
    volume_size = 8
    encrypted   = true
  }

  monitoring {
    enabled = true
  }
}

output "traefik" {
  value = aws_instance.traefik.id
}

resource "aws_instance" "nginx" {
  ami                    = data.aws_ami.ubuntu_jammy.id
  instance_type          = "t3a.small"
  subnet_id              = aws_subnet.public_us_east_1a.id
  vpc_security_group_ids = [aws_security_group.proxy.id]

  iam_instance_profile = aws_iam_instance_profile.ssm_core.name

  tags = {
    Name           = "nginx.antonputra.com"
    node-exporter  = "true"
    nginx-exporter = "true"
  }

  metadata_options {
    http_tokens = "required"
    http_endpoint = true
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted = true
  }

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_type = "gp2"
    volume_size = 8
    encrypted   = true
  }

  monitoring {
    enabled = true
  }
}

output "nginx" {
  value = aws_instance.nginx.id
}

module "prometheus" {
  source = "git@github.com:antonputra/terraform-aws-prometheus.git//?ref=v0.0.1"

  vpc_id             = aws_vpc.main.id
  subnet_id          = aws_subnet.private_us_east_1a.id
  prometheus_version = "2.41.0"
  instance_type      = "t3a.small"
  disk_size          = 50
  prometheus_config  = <<EOT
---
global:
  scrape_interval: 5s
  evaluation_interval: 5s
scrape_configs:

- job_name: ec2-traefik-exporter
  ec2_sd_configs:
  - region: us-east-1
    port: 8082
    filters:
    - name: tag:traefik-exporter
      values:
      - true
  relabel_configs:
  - source_labels: [__meta_ec2_tag_Name]
    target_label: instance
  - regex: "__meta_ec2_tag_(.+)"
    action: labelmap

- job_name: ec2-nginx-exporter
  ec2_sd_configs:
  - region: us-east-1
    port: 9150
    filters:
    - name: tag:nginx-exporter
      values:
      - true
  relabel_configs:
  - source_labels: [__meta_ec2_tag_Name]
    target_label: instance
  - regex: "__meta_ec2_tag_(.+)"
    action: labelmap

- job_name: ec2-node-exporter
  ec2_sd_configs:
  - region: us-east-1
    port: 9100
    filters:
    - name: tag:node-exporter
      values:
      - true
  relabel_configs:
  - source_labels: [__meta_ec2_tag_Name]
    target_label: instance
  - regex: "__meta_ec2_tag_(.+)"
    action: labelmap
EOT
}

output "prometheus" {
  value = module.prometheus
}

resource "aws_instance" "client" {
  ami                    = data.aws_ami.ubuntu_jammy.id
  instance_type          = "t3a.xlarge"
  subnet_id              = aws_subnet.public_us_east_1a.id
  vpc_security_group_ids = [aws_security_group.client.id]

  iam_instance_profile = aws_iam_instance_profile.ssm_core.name

  tags = {
    Name = "client.antonputra.com"
  }

  metadata_options {
    http_tokens = "required"
    http_endpoint = true
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted = true
  }

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_type = "gp2"
    volume_size = 8
    encrypted   = true
  }

  monitoring {
    enabled = true
  }
}

output "client" {
  value = aws_instance.client.id
}

resource "aws_route53_zone" "antonputra" {
  name = "antonputra.pvt"

  vpc {
    vpc_id = aws_vpc.main.id
  }
}

resource "aws_route53_record" "api_traefik" {
  zone_id = aws_route53_zone.antonputra.zone_id
  name    = "api.traefik"
  type    = "A"
  ttl     = 300
  records = [aws_instance.traefik.private_ip]
}

resource "aws_route53_record" "api_nginx" {
  zone_id = aws_route53_zone.antonputra.zone_id
  name    = "api.nginx"
  type    = "A"
  ttl     = 300
  records = [aws_instance.nginx.private_ip]
}

resource "aws_route53_record" "grpc_traefik" {
  zone_id = aws_route53_zone.antonputra.zone_id
  name    = "grpc.traefik"
  type    = "A"
  ttl     = 300
  records = [aws_instance.traefik.private_ip]
}

resource "aws_route53_record" "grpc_nginx" {
  zone_id = aws_route53_zone.antonputra.zone_id
  name    = "grpc.nginx"
  type    = "A"
  ttl     = 300
  records = [aws_instance.nginx.private_ip]
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "igw"
  }
}

resource "aws_subnet" "public_us_east_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/19"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    "Name" = "public-us-east-1a"
  }
}

resource "aws_subnet" "private_us_east_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.32.0/19"
  availability_zone = "us-east-1a"

  tags = {
    "Name" = "private-us-east-1a"
  }
}

resource "aws_eip" "nat" {
  vpc = true

  tags = {
    Name = "nat"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_us_east_1a.id

  tags = {
    Name = "nat"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "private"
  }
}

resource "aws_route_table_association" "public_us_east_1a" {
  subnet_id      = aws_subnet.public_us_east_1a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_us_east_1a" {
  subnet_id      = aws_subnet.private_us_east_1a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_iam_instance_profile" "ssm_core" {
  name = "ssm-core"
  role = aws_iam_role.ssm.name
}

resource "aws_iam_role" "ssm" {
  name = "ssm-core"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ssm_code" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_security_group" "proxy" {
  name   = "proxy"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 9150
    to_port         = 9150
    protocol        = "tcp"
    security_groups = [module.prometheus.security_group_id]
  }

  ingress {
    from_port       = 8082
    to_port         = 8082
    protocol        = "tcp"
    security_groups = [module.prometheus.security_group_id]
  }

  ingress {
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [module.prometheus.security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  description = "Security group for proxy"
}

resource "aws_security_group" "myapp" {
  name   = "myapp"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 8080
    to_port         = 8082
    protocol        = "tcp"
    security_groups = [aws_security_group.proxy.id]
  }

  ingress {
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [module.prometheus.security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  description = "Security group for myapp"
}

resource "aws_security_group" "client" {
  name   = "client"
  vpc_id = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  description = "Security group for client"
}

data "aws_ami" "ubuntu_jammy" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

resource "aws_network_interface" "myapp" {
  subnet_id       = aws_subnet.private_us_east_1a.id
  security_groups = [aws_security_group.myapp.id]
  private_ips     = ["10.0.32.200"]

  tags = {
    Name = "myapp.antonputra.pvt"
  }
}

resource "aws_instance" "myapp" {
  ami                  = data.aws_ami.ubuntu_jammy.id
  instance_type        = "t3a.large"
  iam_instance_profile = aws_iam_instance_profile.ssm_core.name

  network_interface {
    network_interface_id = aws_network_interface.myapp.id
    device_index         = 0
  }

  tags = {
    Name          = "myapp.antonputra.pvt"
    node-exporter = "true"
  }

  metadata_options {
    http_tokens = "required"
    http_endpoint = true
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted = true
  }

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_type = "gp2"
    volume_size = 8
    encrypted   = true
  }

  monitoring {
    enabled = true
  }
}

output "myapp" {
  value = aws_instance.myapp.id
}