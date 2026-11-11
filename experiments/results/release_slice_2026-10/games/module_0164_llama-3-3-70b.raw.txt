terraform {
  required_version = ">= 0.11.0"
}

resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_classiclink = false
}

resource "aws_flow_log" "default" {
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_cloudwatch_log_group.flow_log.arn
  traffic_type    = "REJECT"
  vpc_id          = aws_vpc.default.id
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name = "vpc-flow-logs"
}

resource "aws_iam_role" "flow_log" {
  name        = "vpc-flow-logs"
  description = "Allows VPC Flow Logs to publish to CloudWatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "flow_log" {
  name   = "vpc-flow-logs"
  role   = aws_iam_role.flow_log.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = aws_cloudwatch_log_group.flow_log.arn
      }
    ]
  })
}

resource "aws_security_group" "default" {
  name        = "default-sg"
  description = "Default security group"
  vpc_id      = aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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

output "subnet_id" {
  value = aws_subnet.default.id
}

output "vpc_id" {
  value = aws_vpc.default.id
}