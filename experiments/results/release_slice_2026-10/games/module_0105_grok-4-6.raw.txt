provider "aws" {
  region = "us-east-2"
}

provider "aws" {
  alias  = "replica"
  region = "us-west-2"
}

resource "aws_kms_key" "terraform_state" {
  description             = "CMK for terraform state encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_kms_key" "terraform_state_replica" {
  provider                = aws.replica
  description             = "CMK for terraform state replica encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "antonputra-terraform-state"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "terraform_state_logs" {
  bucket = "antonputra-terraform-state-logs"
}

resource "aws_s3_bucket_public_access_block" "terraform_state_logs" {
  bucket                  = aws_s3_bucket.terraform_state_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_logs" {
  bucket = aws_s3_bucket.terraform_state_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_policy" "terraform_state_logs" {
  bucket = aws_s3_bucket.terraform_state_logs.id

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
        Resource = "${aws_s3_bucket.terraform_state_logs.arn}/*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.terraform_state.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_logging" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  target_bucket = aws_s3_bucket.terraform_state_logs.id
  target_prefix = "logs/"
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

resource "aws_sns_topic" "terraform_state" {
  name              = "terraform-state-events"
  kms_master_key_id = aws_kms_key.terraform_state.id
}

resource "aws_sns_topic_policy" "terraform_state" {
  arn = aws_sns_topic.terraform_state.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3Publish"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.terraform_state.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.terraform_state.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  topic {
    topic_arn = aws_sns_topic.terraform_state.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.terraform_state]
}

resource "aws_s3_bucket" "terraform_state_replica" {
  provider = aws.replica
  bucket   = "antonputra-terraform-state-replica"
}

resource "aws_s3_bucket_versioning" "terraform_state_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.terraform_state_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.terraform_state_replica.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state_replica.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state_replica" {
  provider                = aws.replica
  bucket                  = aws_s3_bucket.terraform_state_replica.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "replication" {
  name = "terraform-state-replication"

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

  inline_policy {
    name = "replication"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "s3:GetReplicationConfiguration",
            "s3:ListBucket"
          ]
          Effect   = "Allow"
          Resource = aws_s3_bucket.terraform_state.arn
        },
        {
          Action = [
            "s3:GetObjectVersionForReplication",
            "s3:GetObjectVersionAcl",
            "s3:GetObjectVersionTagging"
          ]
          Effect   = "Allow"
          Resource = "${aws_s3_bucket.terraform_state.arn}/*"
        },
        {
          Action = [
            "s3:ReplicateObject",
            "s3:ReplicateDelete",
            "s3:ReplicateTags"
          ]
          Effect   = "Allow"
          Resource = "${aws_s3_bucket.terraform_state_replica.arn}/*"
        },
        {
          Action = [
            "kms:Decrypt"
          ]
          Effect   = "Allow"
          Resource = aws_kms_key.terraform_state.arn
        },
        {
          Action = [
            "kms:Encrypt",
            "kms:GenerateDataKey"
          ]
          Effect   = "Allow"
          Resource = aws_kms_key.terraform_state_replica.arn
        }
      ]
    })
  }
}

resource "aws_s3_bucket_replication_configuration" "terraform_state" {
  depends_on = [aws_s3_bucket_versioning.terraform_state, aws_s3_bucket_versioning.terraform_state_replica]

  bucket = aws_s3_bucket.terraform_state.id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "replicate-all"
    status = "Enabled"

    filter {
      prefix = ""
    }

    delete_marker_replication {
      status = "Enabled"
    }

    destination {
      bucket        = aws_s3_bucket.terraform_state_replica.arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.terraform_state_replica.arn
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }
  }
}

resource "aws_dynamodb_table" "terraform_state" {
  name         = "terraform-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.terraform_state.arn
  }
}

# variable "bucket" {
#   default = "antonputra-terraform-state"
# }

terraform {
  backend "s3" {
    key = "global/s3/terraform.tfstate"
  }
}

output "s3_bucket_arn" {
  value       = aws_s3_bucket.terraform_state.arn
  description = "The ARN of the S3 bucket"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.terraform_state.name
  description = "The name of the DynamoDB table"
}

# resource "aws_instance" "example" {
#   ami           = "ami-024e6efaf93d85776"
#   instance_type = "t2.micro"

#   vpc_security_group_ids = ["sg-02d2f7dd78a77231f"]

#   tags = {
#     Name = "bastion"
#   }
# }