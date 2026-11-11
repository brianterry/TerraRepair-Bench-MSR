provider "aws" {
  region = "us-east-1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.56"
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

  enable_classiclink = false
  enable_classiclink_dns_support = false

  flow_log {
    traffic_type = "REJECT"
    iam_role_id  = aws_iam_role.vpc_flow_logs.id
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "vpc_flow_logs_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "vpc_flow_logs_policy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      Effect = "Allow",
      Resource = "*"
    }]
  })
}

resource "aws_subnet" "public_us_east_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.64.0/19"
  availability_zone = "us-east-1a"

  tags = {
    "Name"                       = "public-us-east-1a"
    "kubernetes.io/role/elb"     = "1"
    "kubernetes.io/cluster/demo" = "owned"
  }
}

resource "aws_subnet" "public_us_east_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.96.0/19"
  availability_zone = "us-east-1b"

  tags = {
    "Name"                       = "public-us-east-1b"
    "kubernetes.io/role/elb"     = "1"
    "kubernetes.io/cluster/demo" = "owned"
  }
}

resource "aws_eks_cluster" "demo" {
  name     = "demo"
  version  = "1.25"
  role_arn = aws_iam_role.demo.arn

  encryption_config {
    resources = ["secrets"]
  }

  vpc_config {
    subnet_ids = [
      aws_subnet.private_us_east_1a.id,
      aws_subnet.private_us_east_1b.id,
      aws_subnet.public_us_east_1a.id,
      aws_subnet.public_us_east_1b.id
    ]
  }

  logging {
    cluster_logging {
      enabled_types = [
        { type = "api" },
        { type = "audit" },
        { type = "authenticator" },
        { type = "controllerManager" },
        { type = "scheduler" }
      ]
    }
  }

  endpoint_public_access = false
  endpoint_private_access = true

  depends_on = [aws_iam_role_policy_attachment.demo_amazon_eks_cluster_policy]
}