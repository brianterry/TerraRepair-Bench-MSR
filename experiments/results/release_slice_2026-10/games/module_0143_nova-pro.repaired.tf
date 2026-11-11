resource "aws_s3_bucket" "logs" {
  bucket        = var.audit_s3_bucket_name
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
    target_bucket = var.audit_s3_bucket_name
    target_prefix = "logs/"
  }
  lifecycle_rule {
    id      = "logs-lifecycle-rule"
    enabled = true
    expiration {
      days = 30
    }
  }
  replication_configuration {
    role = aws_iam_role.s3_replication.arn

    rules = [
      {
        id          = "logs-replication-rule"
        status      = "Enabled"
        destination = {
          bucket = "arn:aws:s3:::your-destination-bucket"
        }
        prefix = ""
        delete_marker_replication = {
          status = "Disabled"
        }
      },
    ]
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "s3_replication" {
  name = "s3_replication_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_replication" {
  name = "s3_replication_policy"
  role = aws_iam_role.s3_replication.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ],
        Effect = "Allow",
        Resource = aws_s3_bucket.logs.arn
      },
      {
        Action = [
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ],
        Effect = "Allow",
        Resource = "${aws_s3_bucket.logs.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "logs" {
  bucket = aws_s3_bucket.logs.id

  lambda_function {
    lambda_function_arn = "arn:aws:lambda:your-lambda-function-arn"
    events              = ["s3:ObjectCreated:*"]
  }
}

resource "aws_iam_user" "admin" {
  name = "admin"
}