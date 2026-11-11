# ... (rest of the code remains the same)

resource "aws_s3_bucket" "acm-pca" {
  bucket_prefix = "acm"

  lifecycle {
    prevent_destroy = true
  }

  logging {
    target_bucket = aws_s3_bucket.log_bucket.id
    target_prefix = "/logs/"
  }

  tags = merge(
    local.tags,
    {
      Name = "acm-pca"
    },
  )
}

resource "aws_s3_bucket" "log_bucket" {
  bucket_prefix = "log-bucket"

  lifecycle {
    prevent_destroy = true
  }

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = merge(
    local.tags,
    {
      Name = "log-bucket"
    },
  )
}

resource "aws_s3_bucket_public_access_block" "log_bucket" {
  bucket                  = aws_s3_bucket.log_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ... (rest of the code remains the same)

resource "aws_cloudwatch_log_group" "external_inspection" {
  name              = "external-inspection-flow-logs"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.external_inspection_log_key.id
  tags              = local.tags
}

resource "aws_kms_key" "external_inspection_log_key" {
  description             = "KMS key for external inspection log group"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.external_inspection_log_key.json
}

resource "aws_kms_alias" "external_inspection_log_key" {
  name          = "alias/external-inspection-log-key"
  target_key_id = aws_kms_key.external_inspection_log_key.id
}

data "aws_iam_policy_document" "external_inspection_log_key" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }
  statement {
    sid    = "Allow CloudWatch access"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.eu-west-2.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      values   = ["arn:aws:logs:region:${data.aws_caller_identity.current.account_id}:*"]
      variable = "kms:EncryptionContext:aws:logs:arn"
    }
  }
}

# ... (rest of the code remains the same)

resource "aws_cloudwatch_log_group" "tgw_flowlog_group" {
  name              = "tgw-flowlogs"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.tgw_flowlog_key.id
  tags              = local.tags
}

resource "aws_kms_key" "tgw_flowlog_key" {
  description             = "KMS key for tgw flowlog group"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.tgw_flowlog_key.json
}

resource "aws_kms_alias" "tgw_flowlog_key" {
  name          = "alias/tgw-flowlog-key"
  target_key_id = aws_kms_key.tgw_flowlog_key.id
}

data "aws_iam_policy_document" "tgw_flowlog_key" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }
  statement {
    sid    = "Allow CloudWatch access"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.eu-west-2.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      values   = ["arn:aws:logs:region:${data.aws_caller_identity.current.account_id}:*"]
      variable = "kms:EncryptionContext:aws:logs:arn"
    }
  }
}

# ... (rest of the code remains the same)

resource "aws_route53_zone" "application_zones" {
  for_each = local.application-zones

  name = each.value

  tags = merge(
    local.tags,
    {
      Name = "${each.key}-hosted-zone"
    }
  )
}

resource "aws_route53_zone" "private_application_zones" {
  for_each = local.private-application-zones

  name = each.value

  vpc {
    vpc_id = module.vpc_inspection["live_data"].vpc_id
  }

  lifecycle {
    ignore_changes = [vpc]
  }
  tags = local.tags
}

# Enable DNSSEC for public hosted zones
resource "aws_route53_key_signing_key" "dnssec" {
  for_each = aws_route53_zone.application_zones

  hosted_zone_id = each.value.id
  key_management_service_arn = aws_kms_key.dnssec.arn
}

resource "aws_route53_hosted_zone_dnssec" "dnssec" {
  for_each = aws_route53_zone.application_zones

  hosted_zone_id = each.value.id
}

resource "aws_kms_key" "dnssec" {
  description             = "KMS key for DNSSEC"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.dnssec.json
}

resource "aws_kms_alias" "dnssec" {
  name          = "alias/dnssec-key"
  target_key_id = aws_kms_key.dnssec.id
}

data "aws_iam_policy_document" "dnssec" {
  statement {
    sid    = "Enable IAM User Permissions"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }
  statement {
    sid    = "Allow Route 53 access"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["route53.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]
  }
}

# ... (rest of the code remains the same)

resource "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "zone-id"
    values = ["*"]
  }
}

# ... (rest of the code remains the same)

resource "aws_kms_key" "acm" {
  description         = "ACM PCA (private certificate authority) encryption key"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.kms-acm.json
  deletion_window_in_days = 30

  tags = merge(
    local.tags,
    {
      Name = "acm-pca"
    },
  )
}

# ... (rest of the code remains the same)