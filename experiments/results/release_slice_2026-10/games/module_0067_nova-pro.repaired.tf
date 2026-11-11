provider "aws" {
  region = "us-east-1"
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.27.0"
    }
  }

  required_version = "~> 1.0"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main"
  }

  flow_log_id = aws_flow_log.main.id
}

resource "aws_flow_log" "main" {
  traffic_type = "REJECT"
  iam_role_arn = aws_iam_role.flow_log.arn

  vpc_id = aws_vpc.main.id
}

resource "aws_iam_role" "flow_log" {
  name = "flow-log-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_subnet" "public_us_east_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.64.0/19"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    "Name" = "public-us-east-1a"
  }
}

resource "aws_subnet" "public_us_east_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.96.0/19"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    "Name" = "public-us-east-1b"
  }
}

resource "aws_security_group" "my_server_ssh_access" {
  name        = "my-server-ssh-access"
  description = "Allow My Server SSH Access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow SSH from specific IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["192.0.2.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
}

resource "aws_instance" "my_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  key_name      = "devops"
  subnet_id              = aws_subnet.public_us_east_1a.id
  vpc_security_group_ids = [aws_security_group.my_server_ssh_access.id]
  associate_public_ip_address = true
  tags = {
    Name = "my-server"
  }

  metadata_options {
    http_tokens = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted = true
  }
}

resource "aws_sns_topic" "alarms" {
  name = "alarms"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket        = random_pet.lambda_bucket_name.id
  force_destroy = true
  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
        kms_master_key_id = "alias/aws/s3"
      }
    }
  }
  logging {
    target_bucket = aws_s3_bucket.lambda_bucket.id
    target_prefix = "logs/"
  }
}

resource "aws_cloudwatch_log_group" "send_cloudwatch_alarms_to_slack" {
  name          = "/aws/lambda/${aws_lambda_function.send_cloudwatch_alarms_to_slack.function_name}"
  retention_in_days = 14
  kms_key_id    = "alias/aws/lambda"
}

resource "aws_lambda_function" "send_cloudwatch_alarms_to_slack" {
  function_name = "send-cloudwatch-alarms-to-slack"
  s3_bucket     = aws_s3_bucket.lambda_bucket.id
  s3_key        = aws_s3_object.send_cloudwatch_alarms_to_slack.key
  runtime       = "python3.9"
  handler       = "function.lambda_handler"
  source_code_hash = data.archive_file.send_cloudwatch_alarms_to_slack.output_base64sha256
  role          = aws_iam_role.send_cloudwatch_alarms_to_slack.arn
  tracing_config {
    mode = "Active"
  }
}