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


# Create AWS VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main"
  }
}

# Create VPC flow log
resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.vpc_flow_log.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_log.arn
  traffic_type    = "REJECT"
  vpc_id          = aws_vpc.main.id
}

# Create IAM role for VPC flow log
resource "aws_iam_role" "vpc_flow_log" {
  name        = "vpc-flow-log"
  description = "Allow VPC flow log to write logs to CloudWatch"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "vpc-flow-log.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

# Create IAM policy for VPC flow log
resource "aws_iam_role_policy" "vpc_flow_log" {
  name   = "vpc-flow-log"
  role   = aws_iam_role.vpc_flow_log.id
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "${aws_cloudwatch_log_group.vpc_flow_log.arn}:*"
    }
  ]
}
POLICY
}

# Create CloudWatch log group for VPC flow log
resource "aws_cloudwatch_log_group" "vpc_flow_log" {
  name = "/aws/vpc-flow-log"

  retention_in_days = 14
}

# Create KMS key for CloudWatch log group
resource "aws_kms_key" "cloudwatch_log_group" {
  description             = "KMS key for CloudWatch log group"
  deletion_window_in_days = 10
}

# Create KMS alias for CloudWatch log group
resource "aws_kms_alias" "cloudwatch_log_group" {
  name          = "alias/cloudwatch-log-group"
  target_key_id = aws_kms_key.cloudwatch_log_group.key_id
}

# Update CloudWatch log group to use KMS key
resource "aws_cloudwatch_log_group" "send_cloudwatch_alarms_to_slack" {
  name = "/aws/lambda/${aws_lambda_function.send_cloudwatch_alarms_to_slack.function_name}"

  retention_in_days = 365
  kms_key_id        = aws_kms_key.cloudwatch_log_group.arn
}

# Create an Internet Gateway to provide internet access for public subnets
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "igw"
  }
}

# Create a private subnet in us-east-1a availability zone
resource "aws_subnet" "private_us_east_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.0/19"
  availability_zone = "us-east-1a"

  tags = {
    "Name" = "private-us-east-1a"
  }
}

# Create a private subnet in us-east-1b availability zone
resource "aws_subnet" "private_us_east_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.32.0/19"
  availability_zone = "us-east-1b"

  tags = {
    "Name" = "private-us-east-1b"
  }
}

# Create a public subnet in us-east-1a availability zone
resource "aws_subnet" "public_us_east_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.64.0/19"
  availability_zone = "us-east-1a"

  tags = {
    "Name" = "public-us-east-1a"
  }
}

# Create a public subnet in us-east-1b availability zone
resource "aws_subnet" "public_us_east_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.96.0/19"
  availability_zone = "us-east-1b"

  tags = {
    "Name" = "public-us-east-1b"
  }
}

# Allocate static public IP address to use it with NAT
resource "aws_eip" "nat" {
  vpc = true

  tags = {
    Name = "nat"
  }
}

# Create NAT Gateway to provide internet access for private subnets
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_us_east_1a.id

  tags = {
    Name = "nat"
  }

  depends_on = [aws_internet_gateway.igw]
}

# Create a private route table with a default route to NAT Gateway
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

# Create a public route table with a default route to Internet Gateway
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

# Associate private-us-east-1a subnet with private route table
resource "aws_route_table_association" "private_us_east_1a" {
  subnet_id      = aws_subnet.private_us_east_1a.id
  route_table_id = aws_route_table.private.id
}

# Associate private-us-east-1b subnet with private route table
resource "aws_route_table_association" "private_us_east_1b" {
  subnet_id      = aws_subnet.private_us_east_1b.id
  route_table_id = aws_route_table.private.id
}

# Associate public-us-east-1a subnet with public route table
resource "aws_route_table_association" "public_us_east_1a" {
  subnet_id      = aws_subnet.public_us_east_1a.id
  route_table_id = aws_route_table.public.id
}

# Associate public-us-east-1b subnet with public route table
resource "aws_route_table_association" "public_us_east_1b" {
  subnet_id      = aws_subnet.public_us_east_1b.id
  route_table_id = aws_route_table.public.id
}

# Create a Security Group for our server
resource "aws_security_group" "my_server_ssh_access" {
  name        = "my-server-ssh-access"
  description = "Allow My Server SSH Access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow SSH from specific IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["your_ip_address/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = {
    Name = "my-server-ssh-access"
  }
}

# Find Ubuntu 22 LTS AMI image in AWS
data "aws_ami" "ubuntu" {
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

# Create EC2 instance with Ubuntu 22 LTS AMI image
resource "aws_instance" "my_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  # create devops key pair manually before you run terraform
  key_name = "devops"

  subnet_id              = aws_subnet.private_us_east_1a.id
  vpc_security_group_ids = [aws_security_group.my_server_ssh_access.id]

  associate_public_ip_address = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  ebs_block_device {
    device_name = "/dev/sda1"
    encrypted   = true
  }

  tags = {
    Name = "my-server"
  }
}

# Create an IAM role for the SNS with access to CloudWatch
resource "aws_iam_role" "sns_logs" {
  name        = "sns-logs"
  description = "Allow SNS to write logs to CloudWatch"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "sns.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

# Allow SNS to write logs to CloudWatch
resource "aws_iam_role_policy_attachment" "sns_logs" {
  role       = aws_iam_role.sns_logs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonSNSRole"
}

# Create an SNS topic to receive notifications from CloudWatch
resource "aws_sns_topic" "alarms" {
  name = "alarms"

  # Important! Only for testing, set to log every single message 
  # For production, set it to 0 or close
  lambda_success_feedback_sample_rate = 100

  lambda_failure_feedback_role_arn = aws_iam_role.sns_logs.arn
  lambda_success_feedback_role_arn = aws_iam_role.sns_logs.arn

  kms_master_key_id = aws_kms_key.sns_topic.arn
}

# Create KMS key for SNS topic
resource "aws_kms_key" "sns_topic" {
  description             = "KMS key for SNS topic"
  deletion_window_in_days = 10
}

# Create KMS alias for SNS topic
resource "aws_kms_alias" "sns_topic" {
  name          = "alias/sns-topic"
  target_key_id = aws_kms_key.sns_topic.key_id
}

# Generate a random string to create a unique S3 bucket
resource "random_pet" "lambda_bucket_name" {
  prefix = "lambda"
  length = 2
}

# Create an S3 bucket to store lambda source code (zip archives)
resource "aws_s3_bucket" "lambda_bucket" {
  bucket        = random_pet.lambda_bucket_name.id
  force_destroy = true

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.lambda_bucket.arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  logging {
    target_bucket = aws_s3_bucket.lambda_bucket.id
    target_prefix = "/logs/"
  }
}

# Create KMS key for S3 bucket
resource "aws_kms_key" "lambda_bucket" {
  description             = "KMS key for S3 bucket"
  deletion_window_in_days = 10
}

# Create KMS alias for S3 bucket
resource "aws_kms_alias" "lambda_bucket" {
  name          = "alias/lambda-bucket"
  target_key_id = aws_kms_key.lambda_bucket.key_id
}

# Disable all public access to the S3 bucket
resource "aws_s3_bucket_public_access_block" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create an IAM role for the lambda function
resource "aws_iam_role" "send_cloudwatch_alarms_to_slack" {
  name        = "send-cloudwatch-alarms-to-slack"
  description = "Allow lambda to write logs to CloudWatch"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

# Allow lambda to write logs to CloudWatch
resource "aws_iam_role_policy_attachment" "send_cloudwatch_alarms_to_slack_basic" {
  role       = aws_iam_role.send_cloudwatch_alarms_to_slack.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Create ZIP archive with a lambda function
data "archive_file" "send_cloudwatch_alarms_to_slack" {
  type = "zip"

  source_dir  = "../${path.module}/functions/send-cloudwatch-alarms-to-slack"
  output_path = "../${path.module}/functions/send-cloudwatch-alarms-to-slack.zip"
}

# Upload ZIP archive with lambda to S3 bucket
resource "aws_s3_object" "send_cloudwatch_alarms_to_slack" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "send-cloudwatch-alarms-to-slack.zip"
  source = data.archive_file.send_cloudwatch_alarms_to_slack.output_path

  etag = filemd5(data.archive_file.send_cloudwatch_alarms_to_slack.output_path)
}

# Create lambda function using ZIP archive from S3 bucket
resource "aws_lambda_function" "send_cloudwatch_alarms_to_slack" {
  function_name = "send-cloudwatch-alarms-to-slack"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.send_cloudwatch_alarms_to_slack.key

  runtime = "python3.9"
  handler = "function.lambda_handler"

  source_code_hash = data.archive_file.send_cloudwatch_alarms_to_slack.output_base64sha256

  role = aws_iam_role.send_cloudwatch_alarms_to_slack.arn

  tracing_config {
    mode = "Active"
  }
}

# Create CloudWatch alarm to trigger an alert when a CPU utilization 
# for a specific VM is higher than 80 percent
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name  = "EC2 High CPU (${aws_instance.my_server.id})"
  namespace   = "AWS/EC2"
  metric_name = "CPUUtilization"
  # You have to create a separate alarm for each EC2 instance
  dimensions = {
    InstanceId = aws_instance.my_server.id
  }
  comparison_operator       = "GreaterThanOrEqualToThreshold"
  evaluation_periods        = "1"
  period                    = "300"
  statistic                 = "Average"
  threshold                 = "80"
  alarm_description         = "This metric monitors CPU utilization for the following instance: ${aws_instance.my_server.id}. If the CPU usage exceeds 80%, you'll get an alert."
  insufficient_data_actions = []

  ok_actions    = [aws_sns_topic.alarms.arn]
  alarm_actions = [aws_sns_topic.alarms.arn]
}

# Grant access to SNS topic to invoke a lambda function
resource "aws_lambda_permission" "sns_alarms" {
  statement_id  = "AllowExecutionFromSNSAlarms"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.send_cloudwatch_alarms_to_slack.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alarms.arn
}

# Trigger lambda function when a message is published to "alarms" topic
resource "aws_sns_topic_subscription" "alarms" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.send_cloudwatch_alarms_to_slack.arn
}