terraform {
  required_version = ">= 0.11.0"
}

resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "default"
  }

  flow_log {
    destination = "cloudwatch-logs"
    log_group_arn = aws_cloudwatch_log_group.default.arn
    traffic_type = "REJECT"
  }
}

resource "aws_subnet" "default" {
  vpc_id = aws_vpc.default.id
  cidr_block = "10.0.0.0/24"
}

resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
}

resource "aws_route_table" "default" {
  vpc_id = aws_vpc.default.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.default.id
  }
}

resource "aws_route_table_association" "default" {
  subnet_id = aws_subnet.default.id
  route_table_id = aws_route_table.default.id
}

resource "aws_security_group" "default" {
  name = "default"
  description = "Default security group for VPC"
  vpc_id = aws_vpc.default.id

  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }
}

resource "aws_cloudwatch_log_group" "default" {
  name = "vpc-flow-logs"
}

output "subnet_id" {
  value = aws_subnet.default.id
}

output "vpc_id" {
  value = aws_vpc.default.id
}