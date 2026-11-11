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
      version = "~> 4.29.0"
    }
  }

  required_version = "~> 1.0"
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_security_group" "default" {
  vpc_id = data.aws_vpc.default.id

  filter {
    name   = "group-name"
    values = ["default"]
  }
}

resource "aws_kms_key" "main" {
  description             = "CMK for encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.us-east-1.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      },
      {
        Sid    = "Allow S3"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_key" "replica" {
  provider                = aws.replica
  description             = "CMK for replica encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_signer_signing_profile" "lambda" {
  platform_id = "AWSLambda-SHA384-ECDSA"
  name        = "lambdasigningprofile"
}

resource "aws_lambda_code_signing_config" "lambda" {
  allowed_publishers {
    signing_profile_version_arns = [aws_signer_signing_profile.lambda.version_arn]
  }

  policies {
    untrusted_artifact_on_deployment = "Warn"
  }
}

resource "aws_sqs_queue" "lambda_dlq" {
  name              = "lambda-dlq"
  kms_master_key_id = aws_kms_key.main.id
}

resource "aws_sns_topic" "s3_notifications" {
  name              = "s3-bucket-notifications"
  kms_master_key_id = aws_kms_key.main.id
}

resource "aws_sns_topic_policy" "s3_notifications" {
  arn = aws_sns_topic.s3_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.s3_notifications.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = [
              aws_s3_bucket.lambda_bucket.arn,
              aws_s3_bucket.images_bucket.arn
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role" "replication" {
  name = "s3-bucket-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "replication" {
  name = "s3-bucket-replication"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.lambda_bucket.arn,
          aws_s3_bucket.images_bucket.arn
        ]
      },
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.lambda_bucket.arn}/*",
          "${aws_s3_bucket.images_bucket.arn}/*"
        ]
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.lambda_bucket_replica.arn}/*",
          "${aws_s3_bucket.images_bucket_replica.arn}/*"
        ]
      },
      {
        Action = [
          "kms:Decrypt"
        ]
        Effect   = "Allow"
        Resource = [aws_kms_key.main.arn]
      },
      {
        Action = [
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Effect   = "Allow"
        Resource = [aws_kms_key.replica.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "replication" {
  role       = aws_iam_role.replication.name
  policy_arn = aws_iam_policy.replication.arn
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

resource "aws_s3_bucket_logging" "lambda_bucket" {
  bucket        = aws_s3_bucket.lambda_bucket.id
  target_bucket = aws_s3_bucket.images_bucket.id
  target_prefix = "logs/lambda/"
}

resource "aws_s3_bucket_lifecycle_configuration" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id

  rule {
    id     = "cleanup"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ServerAccessLogsPolicy"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.lambda_bucket.arn}/logs/*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.images_bucket.arn
          }
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id

  topic {
    topic_arn = aws_sns_topic.s3_notifications.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.s3_notifications]
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

resource "aws_s3_bucket_replication_configuration" "lambda_bucket" {
  depends_on = [
    aws_s3_bucket_versioning.lambda_bucket,
    aws_s3_bucket_versioning.lambda_bucket_replica
  ]

  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.lambda_bucket.id

  rule {
    id       = "replicate-all"
    status   = "Enabled"
    priority = 0

    delete_marker_replication {
      status = "Disabled"
    }

    filter {}

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

# Generate a random string to create a unique S3 bucket
resource "random_pet" "images_bucket_name" {
  prefix = "images"
  length = 2
}

# Create an S3 bucket to store images for benchmark test
resource "aws_s3_bucket" "images_bucket" {
  bucket        = random_pet.images_bucket_name.id
  force_destroy = true
}

# Disable all public access to the S3 bucket
resource "aws_s3_bucket_public_access_block" "images_bucket" {
  bucket = aws_s3_bucket.images_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "images_bucket" {
  bucket = aws_s3_bucket.images_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "images_bucket" {
  bucket = aws_s3_bucket.images_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.main.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_logging" "images_bucket" {
  bucket        = aws_s3_bucket.images_bucket.id
  target_bucket = aws_s3_bucket.lambda_bucket.id
  target_prefix = "logs/images/"
}

resource "aws_s3_bucket_lifecycle_configuration" "images_bucket" {
  bucket = aws_s3_bucket.images_bucket.id

  rule {
    id     = "cleanup"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "images_bucket" {
  bucket = aws_s3_bucket.images_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ServerAccessLogsPolicy"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.images_bucket.arn}/logs/*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.lambda_bucket.arn
          }
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "images_bucket" {
  bucket = aws_s3_bucket.images_bucket.id

  topic {
    topic_arn = aws_sns_topic.s3_notifications.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.s3_notifications]
}

resource "aws_s3_bucket" "images_bucket_replica" {
  provider      = aws.replica
  bucket        = "${random_pet.images_bucket_name.id}-replica"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "images_bucket_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.images_bucket_replica.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "images_bucket_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.images_bucket_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "images_bucket_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.images_bucket_replica.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.replica.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_replication_configuration" "images_bucket" {
  depends_on = [
    aws_s3_bucket_versioning.images_bucket,
    aws_s3_bucket_versioning.images_bucket_replica
  ]

  role   = aws_iam_role.replication.arn
  bucket = aws_s3_bucket.images_bucket.id

  rule {
    id       = "replicate-all"
    status   = "Enabled"
    priority = 0

    delete_marker_replication {
      status = "Disabled"
    }

    filter {}

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket        = aws_s3_bucket.images_bucket_replica.arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.replica.arn
      }
    }
  }
}

# Upload test image to S3 bucket
resource "aws_s3_object" "image" {
  bucket = aws_s3_bucket.images_bucket.id

  key    = "thumbnail.png"
  source = "../thumbnail.png"

  etag = filemd5("../thumbnail.png")
}


# Create DynamoDB table
resource "aws_dynamodb_table" "meta" {
  name           = "Meta"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 1000
  hash_key       = "LastModified"

  attribute {
    name = "LastModified"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.main.arn
  }
}

resource "aws_appautoscaling_target" "dynamodb_table_read_target" {
  max_capacity       = 100
  min_capacity       = 5
  resource_id        = "table/${aws_dynamodb_table.meta.name}"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_table_read_policy" {
  name               = "DynamoDBReadCapacityUtilization:${aws_appautoscaling_target.dynamodb_table_read_target.resource_id}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_table_read_target.resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_table_read_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_table_read_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }
    target_value = 70
  }
}

resource "aws_appautoscaling_target" "dynamodb_table_write_target" {
  max_capacity       = 2000
  min_capacity       = 5
  resource_id        = "table/${aws_dynamodb_table.meta.name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_table_write_policy" {
  name               = "DynamoDBWriteCapacityUtilization:${aws_appautoscaling_target.dynamodb_table_write_target.resource_id}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_table_write_target.resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_table_write_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_table_write_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
    target_value = 70
  }
}


resource "aws_iam_role" "nodejs_lambda_exec" {
  name = "nodejs-lambda"

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

resource "aws_iam_policy" "nodejs_s3_bucket_access" {
  name = "NodejsS3BucketAccess"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
        ]
        Effect   = "Allow"
        Resource = "arn:aws:s3:::${aws_s3_bucket.images_bucket.id}/*"
      },
    ]
  })
}

resource "aws_iam_policy" "nodejs_dynamodb_access" {
  name = "NodejsDynamoDBAccess"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:DeleteItem",
          "dynamodb:PutItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:BatchGetItem",
          "dynamodb:DescribeTable",
          "dynamodb:ConditionCheckItem"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:dynamodb:*:*:table/Meta"
      },
    ]
  })
}

resource "aws_iam_role_policy" "nodejs_extra" {
  name = "nodejs-extra"
  role = aws_iam_role.nodejs_lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [aws_kms_key.main.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = [aws_sqs_queue.lambda_dlq.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "nodejs_lambda_policy" {
  role       = aws_iam_role.nodejs_lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "nodejs_s3_bucket_access" {
  role       = aws_iam_role.nodejs_lambda_exec.name
  policy_arn = aws_iam_policy.nodejs_s3_bucket_access.arn
}

resource "aws_iam_role_policy_attachment" "nodejs_dynamodb_access" {
  role       = aws_iam_role.nodejs_lambda_exec.name
  policy_arn = aws_iam_policy.nodejs_dynamodb_access.arn
}

resource "aws_iam_role_policy_attachment" "nodejs_vpc" {
  role       = aws_iam_role.nodejs_lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "nodejs_xray" {
  role       = aws_iam_role.nodejs_lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_cloudwatch_log_group" "nodejs" {
  name              = "/aws/lambda/nodejs"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.main.arn
}

resource "aws_lambda_function" "nodejs" {
  function_name = "nodejs"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_nodejs.key

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.images_bucket.id
    }
  }

  runtime = "nodejs18.x"
  handler = "function.lambda_handler"

  source_code_hash = data.archive_file.lambda_nodejs.output_base64sha256

  role = aws_iam_role.nodejs_lambda_exec.arn

  kms_key_arn                      = aws_kms_key.main.arn
  reserved_concurrent_executions   = 10
  code_signing_config_arn          = aws_lambda_code_signing_config.lambda.arn

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  vpc_config {
    subnet_ids         = data.aws_subnets.default.ids
    security_group_ids = [data.aws_security_group.default.id]
  }

  depends_on = [aws_cloudwatch_log_group.nodejs]
}

data "archive_file" "lambda_nodejs" {
  type = "zip"

  source_dir  = "../${path.module}/functions/nodejs"
  output_path = "../${path.module}/functions/nodejs.zip"
}

resource "aws_s3_object" "lambda_nodejs" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "nodejs.zip"
  source = data.archive_file.lambda_nodejs.output_path

  source_hash = filemd5(data.archive_file.lambda_nodejs.output_path)
}

resource "aws_lambda_function_url" "lambda_nodejs" {
  function_name      = aws_lambda_function.nodejs.function_name
  authorization_type = "AWS_IAM"
}

output "nodejs_lambda_url" {
  value = aws_lambda_function_url.lambda_nodejs.function_url
}


resource "aws_iam_role" "python_lambda_exec" {
  name = "python-lambda"

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

resource "aws_iam_policy" "python_s3_bucket_access" {
  name = "pythonS3BucketAccess"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
        ]
        Effect   = "Allow"
        Resource = "arn:aws:s3:::${aws_s3_bucket.images_bucket.id}/*"
      },
    ]
  })
}

resource "aws_iam_policy" "python_dynamodb_access" {
  name = "pythonDynamoDBAccess"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:DeleteItem",
          "dynamodb:PutItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:BatchGetItem",
          "dynamodb:DescribeTable",
          "dynamodb:ConditionCheckItem"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:dynamodb:*:*:table/Meta"
      },
    ]
  })
}

resource "aws_iam_role_policy" "python_extra" {
  name = "python-extra"
  role = aws_iam_role.python_lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [aws_kms_key.main.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = [aws_sqs_queue.lambda_dlq.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "python_lambda_policy" {
  role       = aws_iam_role.python_lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "python_s3_bucket_access" {
  role       = aws_iam_role.python_lambda_exec.name
  policy_arn = aws_iam_policy.python_s3_bucket_access.arn
}

resource "aws_iam_role_policy_attachment" "python_dynamodb_access" {
  role       = aws_iam_role.python_lambda_exec.name
  policy_arn = aws_iam_policy.python_dynamodb_access.arn
}

resource "aws_iam_role_policy_attachment" "python_vpc" {
  role       = aws_iam_role.python_lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy_attachment" "python_xray" {
  role       = aws_iam_role.python_lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_cloudwatch_log_group" "python" {
  name              = "/aws/lambda/python"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.main.arn
}

resource "aws_lambda_function" "python" {
  function_name = "python"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_python.key

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.images_bucket.id
    }
  }

  runtime = "python3.12"
  handler = "function.lambda_handler"

  source_code_hash = data.archive_file.lambda_python.output_base64sha256

  role = aws_iam_role.python_lambda_exec.arn

  kms_key_arn                      = aws_kms_key.main.arn
  reserved_concurrent_executions   = 10
  code_signing_config_arn          = aws_lambda_code_signing_config.lambda.arn

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  vpc_config {
    subnet_ids         = data.aws_subnets.default.ids
    security_group_ids = [data.aws_security_group.default.id]
  }

  depends_on = [aws_cloudwatch_log_group.python]
}

data "archive_file" "lambda_python" {
  type = "zip"

  source_dir  = "../${path.module}/functions/python"
  output_path = "../${path.module}/functions/python.zip"
}

resource "aws_s3_object" "lambda_python" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "python.zip"
  source = data.archive_file.lambda_python.output_path

  source_hash = filemd5(data.archive_file.lambda_python.output_path)
}

resource "aws_lambda_function_url" "lambda_python" {
  function_name      = aws_lambda_function.python.function_name
  authorization_type = "AWS_IAM"
}

output "python_lambda_url" {
  value = aws_lambda_function_url.lambda_python.function_url
}