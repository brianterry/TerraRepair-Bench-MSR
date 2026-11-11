provider "aws" {
  region = "us-east-1"
}

# 1
# Main VPC
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/18"

  tags = {
    Name = "main"
  }
}

resource "aws_default_security_group" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name = "/vpc/flow-log/main"
}

resource "aws_iam_role" "flow_log" {
  name = "vpc-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "flow_log" {
  name = "vpc-flow-log-policy"
  role = aws_iam_role.flow_log.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_cloudwatch_log_group.flow_log.arn
  traffic_type    = "REJECT"
  vpc_id          = aws_vpc.main.id
}

# 2
# Public Subnet with Default Route to Internet Gateway
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet
resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.0.0/24"

  tags = {
    Name = "public"
  }
}

# Private Subnet with Default Route to NAT Gateway
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet
resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "private"
  }
}

# 3
# Main Internal Gateway for VPC
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "igw"
  }
}

# 4
# Elastic IP for NAT Gateway
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip
resource "aws_eip" "nat_eip" {
  vpc        = true
  depends_on = [aws_internet_gateway.igw]
}

# 5
# Main NAT Gateway for VPC
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "nat"
  }
}

# 6
# Route Table for Public Subnet
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table
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

# Association between Public Subnet and Public Route Table
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Route Table for Private Subnet
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table
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

# Association between Private Subnet and Private Route Table
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# 7
#  Resource: aws_security_group
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group
resource "aws_security_group" "nginx" {
  name        = "nginx"
  description = "Access for Nginx"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Web Access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH Access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Outbound access within VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }
}

resource "aws_iam_role" "nginx" {
  name = "nginx-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_instance_profile" "nginx" {
  name = "nginx-profile"
  role  = aws_iam_role.nginx.name
}

# Resource: aws_instance
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance
resource "aws_instance" "nginx" {
  ami                    = "ami-0dba2cb6798deb6d8"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.nginx.id]
  key_name               = "devops"
  iam_instance_profile    = aws_iam_instance_profile.nginx.name
  ebs_optimized           = true
  monitoring              = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name = "Nginx"
  }
}

# 8
# Manages a Route53 Hosted Zone
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone
resource "aws_route53_zone" "devops" {
  name    = "devopsbyexample.io"
  comment = ""
}

resource "aws_kms_key" "dnssec" {
  customer_master_key_spec = "ECC_NIST_P256"
  deletion_window_in_days  = 7
  key_usage                = "SIGN_VERIFY"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "Enable IAM policies"
      Effect    = "Allow"
      Principal = { AWS = "*" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })
}

resource "aws_route53_key_signing_key" "devops" {
  hosted_zone_id             = aws_route53_zone.devops.id
  key_management_service_arn = aws_kms_key.dnssec.arn
  name                        = "devops"
}

resource "aws_route53_hosted_zone_dnssec" "devops" {
  hosted_zone_id = aws_route53_key_signing_key.devops.hosted_zone_id
}

resource "aws_cloudwatch_log_group" "query_log" {
  name = "/aws/route53/devopsbyexample.io"
}

resource "aws_route53_query_log" "devops" {
  cloudwatch_log_group_arn = aws_cloudwatch_log_group.query_log.arn
  zone_id                  = aws_route53_zone.devops.zone_id
}

# Provides a Route53 record resource
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record
resource "aws_route53_record" "nginx" {
  zone_id = aws_route53_zone.devops.zone_id
  name    = "api.devopsbyexample.io"
  type    = "A"
  ttl     = "300"
  records = [aws_instance.nginx.public_ip]
}