provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "replica"
  region = "us-west-2"
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

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_kms_key" "main" {
  description             = "CMK for encrypting SNS, S3, CloudWatch Logs, SQS and EBS"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow CloudWatch Logs",
      "Effect": "Allow",
      "Principal": {
        "Service": "logs.${data.aws_region.current.name}.amazonaws.com"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:CreateGrant",
        "kms:DescribeKey"
      ],
      "Resource": "*",
      "Condition": {
        "ArnLike": {
          "kms:EncryptionContext:aws:logs:arn": "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
        }
      }
    },
    {
      "Sid": "Allow SNS",
      "Effect": "Allow",
      "Principal": {
        "Service": "sns.amazonaws.com"
      },
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Allow S3",
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey*"
      ],
      "Resource": "*"
    }
  ]
}
POLICY
}

resource "aws_kms_key" "replica" {
  provider                = aws.replica
  description             = "CMK for replica S3 bucket encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
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

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/main-flow-logs"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.main.arn
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "vpc-flow-logs"

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

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "vpc-flow-logs"
  role = aws_iam_role.vpc_flow_logs.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }
  ]
}
POLICY
}

resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.vpc_flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
  traffic_type    = "REJECT"
  vpc_id          = aws_vpc.main.id
}

# Create a CloudWatch alarm to trigger an alert when a CPU utilization 
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
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.64.0/19"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    "Name" = "public-us-east-1a"
  }
}

# Create a public subnet in us-east-1b availability zone
resource "aws_subnet" "public_us_east_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.96.0/19"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

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
  description = "Allow My Server SSH Accesss"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "Allow HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow HTTP outbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow DNS outbound"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
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

resource "aws_iam_role" "my_server" {
  name = "my-server"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_instance_profile" "my_server" {
  name = "my-server"
  role = aws_iam_role.my_server.name
}

# Create EC2 instance with Ubuntu 22 LTS AMI image
resource "aws_instance" "my_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  # create devops key pair manually before you run terraform
  key_name = "devops"

  subnet_id              = aws_subnet.public_us_east_1a.id
  vpc_security_group_ids = [aws_security_group.my_server_ssh_access.id]

  associate_public_ip_address = false
  ebs_optimized               = true
  monitoring                  = true
  iam_instance_profile        = aws_iam_instance_profile.my_server.name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted  = true
    kms_key_id = aws_kms_key.main.arn
  }

  tags = {
    Name = "my-server"
  }
}


# Create an IAM role for the SNS with access to CloudWatch
resource "aws_iam_role" "sns_logs" {
  name = "sns-logs"

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

  kms_master_key_id = aws_kms_key.main.id

  # Important! Only for testing, set to log every single message 
  # For production, set it to 0 or close
  lambda_success_feedback_sample_rate = 100

  lambda_failure_feedback_role_arn = aws_iam_role.sns_logs.arn
  lambda_success_feedback_role_arn = aws_iam_role.sns_logs.arn
}

resource "aws_sns_topic_policy" "alarms" {
  arn = aws_sns_topic.alarms.arn

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3Publish",
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "SNS:Publish",
      "Resource": "${aws_sns_topic.alarms.arn}",
      "Condition": {
        "ArnLike": {
          "aws:SourceArn": "${aws_s3_bucket.lambda_bucket.arn}"
        }
      }
    }
  ]
}
POLICY
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
}

# Disable all public access to the S3 bucket
resource "aws_s3_bucket_public_access_block" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.main.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket" "lambda_bucket_logs" {
  bucket        = "${random_pet.lambda_bucket_name.id}-logs"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "lambda_bucket_logs" {
  bucket = aws_s3_bucket.lambda_bucket_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lambda_bucket_logs" {
  bucket = aws_s3_bucket.lambda_bucket_logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.main.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_policy" "lambda_bucket_logs" {
  bucket = aws_s3_bucket.lambda_bucket_logs.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3ServerAccessLogsPolicy",
      "Effect": "Allow",
      "Principal": {
        "Service": "logging.s3.amazonaws.com"
      },
      "Action": "s3:PutObject",
      "Resource": "${aws_s3_bucket.lambda_bucket_logs.arn}/*",
      "Condition": {
        "ArnLike": {
          "aws:SourceArn": "${aws_s3_bucket.lambda_bucket.arn}"
        },
        "StringEquals": {
          "aws:SourceAccount": "${data.aws_caller_identity.current.account_id}"
        }
      }
    }
  ]
}
POLICY
}

resource "aws_s3_bucket_logging" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id

  target_bucket = aws_s3_bucket.lambda_bucket_logs.id
  target_prefix = "log/"
}

resource "aws_s3_bucket_notification" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id

  topic {
    topic_arn = aws_sns_topic.alarms.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.alarms]
}

resource "aws_s3_bucket" "lambda_bucket_replica" {
  provider      = aws.replica
  bucket        = "${random_pet.lambda_bucket_name.id}-replica"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "lambda_bucket_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.lambda_bucket_replica.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "lambda_bucket_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.lambda_bucket_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lambda_bucket_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.lambda_bucket_replica.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.replica.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_iam_role" "lambda_bucket_replication" {
  name = "lambda-bucket-replication"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy" "lambda_bucket_replication" {
  name = "lambda-bucket-replication"
  role = aws_iam_role.lambda_bucket_replication.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetReplicationConfiguration",
        "s3:ListBucket"
      ],
      "Resource": "${aws_s3_bucket.lambda_bucket.arn}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObjectVersionForReplication",
        "s3:GetObjectVersionAcl",
        "s3:GetObjectVersionTagging",
        "s3:GetObjectRetention",
        "s3:GetObjectLegalHold"
      ],
      "Resource": "${aws_s3_bucket.lambda_bucket.arn}/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ReplicateObject",
        "s3:ReplicateDelete",
        "s3:ReplicateTags"
      ],
      "Resource": "${aws_s3_bucket.lambda_bucket_replica.arn}/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:DescribeKey"
      ],
      "Resource": "${aws_kms_key.main.arn}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ],
      "Resource": "${aws_kms_key.replica.arn}"
    }
  ]
}
POLICY
}

resource "aws_s3_bucket_replication_configuration" "lambda_bucket" {
  depends_on = [
    aws_s3_bucket_versioning.lambda_bucket,
    aws_s3_bucket_versioning.lambda_bucket_replica
  ]

  bucket = aws_s3_bucket.lambda_bucket.id
  role   = aws_iam_role.lambda_bucket_replication.arn

  rule {
    id     = "replicate-all"
    status = "Enabled"

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket        = aws_s3_bucket.lambda_bucket_replica.arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.replica.arn
      }
    }
  }
}


# Create an IAM role for the lambda function
resource "aws_iam_role" "send_cloudwatch_alarms_to_slack" {
  name = "send-cloudwatch-alarms-to-slack"

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

resource "aws_iam_role_policy_attachment" "send_cloudwatch_alarms_to_slack_vpc" {
  role       = aws_iam_role.send_cloudwatch_alarms_to_slack.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "send_cloudwatch_alarms_to_slack_xray" {
  role       = aws_iam_role.send_cloudwatch_alarms_to_slack.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_sqs_queue" "lambda_dlq" {
  name              = "send-cloudwatch-alarms-to-slack-dlq"
  kms_master_key_id = aws_kms_key.main.id
}

resource "aws_iam_role_policy" "send_cloudwatch_alarms_to_slack_dlq" {
  name = "send-cloudwatch-alarms-to-slack-dlq"
  role = aws_iam_role.send_cloudwatch_alarms_to_slack.id

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage"
      ],
      "Resource": "${aws_sqs_queue.lambda_dlq.arn}"
    }
  ]
}
POLICY
}

resource "aws_signer_signing_profile" "lambda" {
  platform_id = "AWSLambda-SHA384-ECDSA"
  name        = "lambda_signing_profile"
}

resource "aws_lambda_code_signing_config" "send_cloudwatch_alarms_to_slack" {
  allowed_publishers {
    signing_profile_version_arns = [aws_signer_signing_profile.lambda.version_arn]
  }

  policies {
    untrusted_artifact_on_deployment = "Warn"
  }
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

  etag                   = filemd5(data.archive_file.send_cloudwatch_alarms_to_slack.output_path)
  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.main.arn
}

# Create lambda function using ZIP archive from S3 bucket
resource "aws_lambda_function" "send_cloudwatch_alarms_to_slack" {
  function_name = "send-cloudwatch-alarms-to-slack"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.send_cloudwatch_alarms_to_slack.key

  runtime = "python3.12"
  handler = "function.lambda_handler"

  source_code_hash = data.archive_file.send_cloudwatch_alarms_to_slack.output_base64sha256

  role = aws_iam_role.send_cloudwatch_alarms_to_slack.arn

  reserved_concurrent_executions = 5
  code_signing_config_arn        = aws_lambda_code_signing_config.send_cloudwatch_alarms_to_slack.arn

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private_us_east_1a.id, aws_subnet.private_us_east_1b.id]
    security_group_ids = [aws_security_group.my_server_ssh_access.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.send_cloudwatch_alarms_to_slack_vpc,
    aws_cloudwatch_log_group.send_cloudwatch_alarms_to_slack
  ]
}

# Create CloudWatch log group with 2 weeks retention policy
resource "aws_cloudwatch_log_group" "send_cloudwatch_alarms_to_slack" {
  name = "/aws/lambda/send-cloudwatch-alarms-to-slack"

  retention_in_days = 365
  kms_key_id        = aws_kms_key.main.arn
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