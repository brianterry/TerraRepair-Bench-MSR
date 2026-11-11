resource "aws_s3_bucket" "website" {
  bucket = var.fqdn
  force_destroy = true

  versioning {
    enabled = true
  }

  logging {
    target_bucket = aws_s3_bucket.website.id
    target_prefix = "logs/"
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  lifecycle_rule {
    id      = "default"
    enabled = true

    transition {
      days          = 30
      storage_class = "GLACIER"
    }
  }

  website {
    index_document = var.index_page
    error_document = var.error_page
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_object" "index" {
  bucket  = aws_s3_bucket.website.id
  key     = var.index_page
  content = "You've reached the ${var.fqdn} index page"

  content_type = "text/plain"
  kms_key_id   = "alias/aws/s3"
}

resource "aws_s3_bucket_object" "error" {
  bucket  = aws_s3_bucket.website.id
  key     = var.error_page
  content = "You've reached the ${var.fqdn} error page"

  content_type = "text/plain"
  kms_key_id   = "alias/aws/s3"
}

resource "aws_iam_user" "website" {
  name = var.fqdn
}

resource "aws_iam_access_key" "website" {
  user = aws_iam_user.website.name
}

resource "aws_route53_record" "website" {
  zone_id = var.route_zone_id
  name    = var.sub_domain
  type    = "A"

  alias {
    name                   = aws_s3_bucket.website.website_domain
    zone_id                = aws_s3_bucket.website.hosted_zone_id
    evaluate_target_health = false
  }
}

output "domain"         { value = aws_s3_bucket.website.website_domain }
output "hosted_zone_id" { value = aws_s3_bucket.website.hosted_zone_id }
output "endpoint"       { value = aws_s3_bucket.website.website_endpoint }
output "fqdn"           { value = aws_route53_record.website.fqdn }