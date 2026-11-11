provider "aws" {
  region = "us-east-1"
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

resource "random_pet" "lambda_bucket_name" {
  prefix = "lambda"
  length = 2
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
        kms_master_key_id = aws_kms_key.lambda_bucket_key.id
        sse_algorithm     = "aws:kms"
      }
    }
  }
  logging {
    target_bucket = aws_s3_bucket.lambda_bucket.id
    target_prefix = "/logs/"
  }
}

resource "aws_s3_bucket_public_access_block" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_kms_key" "lambda_bucket_key" {
  description             = "KMS key for lambda bucket"
  deletion_window_in_days = 10
}

resource "aws_kms_alias" "lambda_bucket_key_alias" {
  name          = "alias/lambda-bucket-key"
  target_key_id = aws_kms_key.lambda_bucket_key.id
}

resource "random_pet" "images_bucket_name" {
  prefix = "images"
  length = 2
}

resource "aws_s3_bucket" "images_bucket" {
  bucket        = random_pet.images_bucket_name.id
  force_destroy = true
  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.images_bucket_key.id
        sse_algorithm     = "aws:kms"
      }
    }
  }
  logging {
    target_bucket = aws_s3_bucket.images_bucket.id
    target_prefix = "/logs/"
  }
}

resource "aws_s3_bucket_public_access_block" "images_bucket" {
  bucket = aws_s3_bucket.images_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_kms_key" "images_bucket_key" {
  description             = "KMS key for images bucket"
  deletion_window_in_days = 10
}

resource "aws_kms_alias" "images_bucket_key_alias" {
  name          = "alias/images-bucket-key"
  target_key_id = aws_kms_key.images_bucket_key.id
}

resource "aws_s3_object" "image" {
  bucket = aws_s3_bucket.images_bucket.id

  key    = "thumbnail.png"
  source = "../thumbnail.png"

  etag = filemd5("../thumbnail.png")
}

resource "aws_dynamodb_table" "meta" {
  name           = "Meta"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 1000
  hash_key       = "LastModified"
  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled = true
    kms_key_arn = aws_kms_key.meta_key.arn
  }

  attribute {
    name = "LastModified"
    type = "S"
  }
}

resource "aws_kms_key" "meta_key" {
  description             = "KMS key for meta table"
  deletion_window_in_days = 10
}

resource "aws_kms_alias" "meta_key_alias" {
  name          = "alias/meta-key"
  target_key_id = aws_kms_key.meta_key.id
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

resource "aws_lambda_function" "nodejs" {
  function_name = "nodejs"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_nodejs.key

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.images_bucket.id
    }
  }

  runtime = "nodejs16.x"
  handler = "function.lambda_handler"

  source_code_hash = data.archive_file.lambda_nodejs.output_base64sha256

  role = aws_iam_role.nodejs_lambda_exec.arn
  vpc_config {
    security_group_ids = []
    subnet_ids         = []
  }
  dead_letter_config {
    type = "SQS"
  }
  tracing_config {
    mode = "Active"
  }
}

resource "aws_cloudwatch_log_group" "nodejs" {
  name = "/aws/lambda/${aws_lambda_function.nodejs.function_name}"

  retention_in_days = 365
  kms_key_id        = aws_kms_key.nodejs_log_key.id
}

resource "aws_kms_key" "nodejs_log_key" {
  description             = "KMS key for nodejs log"
  deletion_window_in_days = 10
}

resource "aws_kms_alias" "nodejs_log_key_alias" {
  name          = "alias/nodejs-log-key"
  target_key_id = aws_kms_key.nodejs_log_key.id
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

resource "aws_lambda_function" "python" {
  function_name = "python"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_python.key

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.images_bucket.id
    }
  }

  runtime = "python3.9"
  handler = "function.lambda_handler"

  source_code_hash = data.archive_file.lambda_python.output_base64sha256

  role = aws_iam_role.python_lambda_exec.arn
  vpc_config {
    security_group_ids = []
    subnet_ids         = []
  }
  dead_letter_config {
    type = "SQS"
  }
  tracing_config {
    mode = "Active"
  }
}

resource "aws_cloudwatch_log_group" "python" {
  name = "/aws/lambda/${aws_lambda_function.python.function_name}"

  retention_in_days = 365
  kms_key_id        = aws_kms_key.python_log_key.id
}

resource "aws_kms_key" "python_log_key" {
  description             = "KMS key for python log"
  deletion_window_in_days = 10
}

resource "aws_kms_alias" "python_log_key_alias" {
  name          = "alias/python-log-key"
  target_key_id = aws_kms_key.python_log_key.id
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