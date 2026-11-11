terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.21.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2.0"
    }
  }

  required_version = "~> 1.0"
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 10
  enable_key_rotation    = true
}

resource "aws_kms_key" "logs" {
  description             = "KMS key for CloudWatch Logs encryption"
  deletion_window_in_days = 10
  enable_key_rotation    = true
}

resource "random_pet" "lambda_bucket_name" {
  prefix = "lambda"
  length = 2
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket        = random_pet.lambda_bucket_name.id
  force_destroy = true
}

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

resource "aws_s3_bucket_logging" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id

  target_bucket = aws_s3_bucket.lambda_bucket.id
  target_prefix = "logs/"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

resource "aws_s3_bucket_notification" "lambda_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.s3_bucket]
}

resource "aws_iam_role" "hello_lambda_exec" {
  name = "hello-lambda"

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

resource "aws_iam_role_policy_attachment" "hello_lambda_policy" {
  role       = aws_iam_role.hello_lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "hello" {
  function_name = "hello"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_hello.key

  runtime = "nodejs18.x"
  handler = "function.handler"

  source_code_hash = data.archive_file.lambda_hello.output_base64sha256

  role = aws_iam_role.hello_lambda_exec.arn

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.hello_dlq.arn
  }

  reserved_concurrent_executions = 10

  code_signing_config_arn = aws_lambda_code_signing_config.hello.arn

  vpc_config {
    subnet_ids         = []
    security_group_ids = []
  }
}

resource "aws_sqs_queue" "hello_dlq" {
  name = "hello-dlq"
}

resource "aws_lambda_code_signing_config" "hello" {
  allowed_publishers {
    signing_profile_version_arns = []
  }
}

resource "aws_cloudwatch_log_group" "hello" {
  name = "/aws/lambda/${aws_lambda_function.hello.function_name}"

  retention_in_days = 365
  kms_key_id        = aws_kms_key.logs.arn
}

data "archive_file" "lambda_hello" {
  type = "zip"

  source_dir  = "../${path.module}/hello"
  output_path = "../${path.module}/hello.zip"
}

resource "aws_s3_object" "lambda_hello" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "hello.zip"
  source = data.archive_file.lambda_hello.output_path

  etag = filemd5(data.archive_file.lambda_hello.output_path)
}

resource "aws_apigatewayv2_api" "main" {
  name          = "main"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "dev" {
  api_id = aws_apigatewayv2_api.main.id

  name        = "dev"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.main_api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_cloudwatch_log_group" "main_api_gw" {
  name = "/aws/api-gw/${aws_apigatewayv2_api.main.name}"

  retention_in_days = 365
  kms_key_id        = aws_kms_key.logs.arn
}

resource "aws_apigatewayv2_integration" "lambda_hello" {
  api_id = aws_apigatewayv2_api.main.id

  integration_uri    = aws_lambda_function.hello.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "get_hello" {
  api_id = aws_apigatewayv2_api.main.id

  route_key = "GET /hello"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_hello.id}"
  authorization_type = "NONE"
}

resource "aws_apigatewayv2_route" "post_hello" {
  api_id = aws_apigatewayv2_api.main.id

  route_key = "POST /hello"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_hello.id}"
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

output "hello_base_url" {
  value = aws_apigatewayv2_stage.dev.invoke_url
}

resource "random_pet" "test_bucket_name" {
  prefix = "test"
  length = 2
}

resource "aws_s3_bucket" "test" {
  bucket        = random_pet.test_bucket_name.id
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "test" {
  bucket = aws_s3_bucket.test.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "test" {
  bucket = aws_s3_bucket.test.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "test" {
  bucket = aws_s3_bucket.test.id

  target_bucket = aws_s3_bucket.test.id
  target_prefix = "logs/"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "test" {
  bucket = aws_s3_bucket.test.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "test" {
  bucket = aws_s3_bucket.test.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

resource "aws_s3_bucket_notification" "test" {
  bucket = aws_s3_bucket.test.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.s3_bucket]
}

resource "aws_s3_object" "test" {
  bucket = aws_s3_bucket.test.id

  key     = "hello.json"
  content = jsonencode({ name = "S3" })
}

output "test_s3_bucket" {
  value = random_pet.test_bucket_name.id
}

resource "aws_iam_role" "s3_lambda_exec" {
  name = "s3-lambda"

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

resource "aws_iam_role_policy_attachment" "s3_lambda_policy" {
  role       = aws_iam_role.s3_lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "test_s3_bucket_access" {
  name        = "TestS3BucketAccess"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
        ]
        Effect   = "Allow"
        Resource = "arn:aws:s3:::${aws_s3_bucket.test.id}/*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_lambda_test_s3_bucket_access" {
  role       = aws_iam_role.s3_lambda_exec.name
  policy_arn = aws_iam_policy.test_s3_bucket_access.arn
}

resource "aws_lambda_function" "s3" {
  function_name = "s3"

  s3_bucket = aws_s3_bucket.lambda_bucket.id
  s3_key    = aws_s3_object.lambda_s3.key

  runtime = "nodejs18.x"
  handler = "function.handler"

  source_code_hash = data.archive_file.lambda_s3.output_base64sha256

  role = aws_iam_role.s3_lambda_exec.arn

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.s3_dlq.arn
  }

  reserved_concurrent_executions = 10

  code_signing_config_arn = aws_lambda_code_signing_config.s3.arn

  vpc_config {
    subnet_ids         = []
    security_group_ids = []
  }
}

resource "aws_sqs_queue" "s3_dlq" {
  name = "s3-dlq"
}

resource "aws_lambda_code_signing_config" "s3" {
  allowed_publishers {
    signing_profile_version_arns = []
  }
}

resource "aws_lambda_permission" "s3_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.lambda_bucket.arn
}

resource "aws_cloudwatch_log_group" "s3" {
  name = "/aws/lambda/${aws_lambda_function.s3.function_name}"

  retention_in_days = 365
  kms_key_id        = aws_kms_key.logs.arn
}

data "archive_file" "lambda_s3" {
  type = "zip"

  source_dir  = "../${path.module}/s3"
  output_path = "../${path.module}/s3.zip"
}

resource "aws_s3_object" "lambda_s3" {
  bucket = aws_s3_bucket.lambda_bucket.id

  key    = "s3.zip"
  source = data.archive_file.lambda_s3.output_path
  
  source_hash = filemd5(data.archive_file.lambda_s3.output_path)
}