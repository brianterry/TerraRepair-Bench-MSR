resource "aws_s3_bucket" "logs" {
  bucket        = var.audit_s3_bucket_name
  force_destroy = true

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_to_all_objects_by_default = true
      sse_algorithm                   = "aws:kms"
      kms_master_key_id             = aws_kms_key.logs.key_arn
    }
  }

  logging {
    target_bucket = self.id
    log_prefix    = "logs/"
  }

  lifecycle_configuration {
    rules {
      id     = "ExpireLogs"
      status = "Enabled"
      transitions {
        days          = 30
        storage_class = "STANDARD_IA"
      }
    }
  }

  replication_configuration {
    role = aws_iam_role.replication_role.arn

    rules {
      id     = "ReplicateLogs"
      status = "Enabled"
      destination {
        bucket = aws_s3_bucket.logs.arn
        storage_class = "STANDARD"
      }
    }
  }
}

resource "aws_s3_bucket_acl" "logs" {
  bucket = aws_s3_bucket.logs.id
  acl    = "private"
}

data "aws_iam_policy_document" "logs_bucket_policy" {
  statement {
    sid     = "AWSCloudTrailAclCheckForConfig"
    actions = ["s3:GetBucketAcl"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    resources = [aws_s3_bucket.logs.arn]
  }

  statement {
    sid     = "AWSCloudTrailWriteForConfig"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    resources = ["${aws_s3_bucket.logs.arn}/config/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid     = "AWSCloudTrailAclCheckForCloudTrail"
    actions = ["s3:GetBucketAcl"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = [aws_s3_bucket.logs.arn]
  }

  statement {
    sid     = "AWSCloudTrailWriteForCloudTrail"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = ["${aws_s3_bucket.logs.arn}/cloudtrail/AWSLogs/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs_bucket_policy.json
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_kms_key" "logs" {
  description             = "KMS key for S3 bucket encryption"
  deletion_window_in_days = 7
}

resource "aws_iam_role" "replication_role" {
  name = "s3_replication_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "replication_role_s3_full" {
  role       = aws_iam_role.replication_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_user" "admin" {
  name = "admin"
}

module "secure_baseline" {
  source = "../../"

  audit_log_bucket_name           = aws_s3_bucket.logs.id
  use_external_audit_log_bucket   = true
  aws_account_id                  = data.aws_caller_identity.current.account_id
  region                          = var.region
  support_iam_role_principal_arns = [aws_iam_user.admin.arn]

  providers = {
    aws                = aws
    aws.ap-northeast-1 = aws.ap-northeast-1
    aws.ap-northeast-2 = aws.ap-northeast-2
    aws.ap-northeast-3 = aws.ap-northeast-3
    aws.ap-south-1     = aws.ap-south-1
    aws.ap-southeast-1 = aws.ap-southeast-1
    aws.ap-southeast-2 = aws.ap-southeast-2
    aws.ca-central-1   = aws.ca-central-1
    aws.eu-central-1   = aws.eu-central-1
    aws.eu-north-1     = aws.eu-north-1
    aws.eu-west-1      = aws.eu-west-1
    aws.eu-west-2      = aws.eu-west-2
    aws.eu-west-3      = aws.eu-west-3
    aws.sa-east-1      = aws.sa-east-1
    aws.us-east-1      = aws.us-east-1
    aws.us-east-2      = aws.us-east-2
    aws.us-west-1      = aws.us-west-1
    aws.us-west-2      = aws.us-west-2
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {
}

terraform {
  required_version = ">= 1.1.4"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.3"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
  alias  = "ap-northeast-1"
}

provider "aws" {
  region = "ap-northeast-2"
  alias  = "ap-northeast-2"
}

provider "aws" {
  region = "ap-northeast-3"
  alias  = "ap-northeast-3"
}

provider "aws" {
  region = "ap-south-1"
  alias  = "ap-south-1"
}

provider "aws" {
  region = "ap-southeast-1"
  alias  = "ap-southeast-1"
}

provider "aws" {
  region = "ap-southeast-2"
  alias  = "ap-southeast-2"
}

provider "aws" {
  region = "ca-central-1"
  alias  = "ca-central-1"
}

provider "aws" {
  region = "eu-central-1"
  alias  = "eu-central-1"
}

provider "aws" {
  region = "eu-north-1"
  alias  = "eu-north-1"
}

provider "aws" {
  region = "eu-west-1"
  alias  = "eu-west-1"
}

provider "aws" {
  region = "eu-west-2"
  alias  = "eu-west-2"
}

provider "aws" {
  region = "eu-west-3"
  alias  = "eu-west-3"
}

provider "aws" {
  region = "sa-east-1"
  alias  = "sa-east-1"
}

provider "aws" {
  region = "us-east-1"
  alias  = "us-east-1"
}

provider "aws" {
  region = "us-east-2"
  alias  = "us-east-2"
}

provider "aws" {
  region = "us-west-1"
  alias  = "us-west-1"
}

provider "aws" {
  region = "us-west-2"
  alias  = "us-west-2"
}

variable "audit_s3_bucket_name" {
  description = "The name of the S3 bucket to store various audit logs."
  type        = string
}

variable "region" {
  description = "The AWS region in which global resources are set up."
  type        = string
  default     = "us-east-1"
}