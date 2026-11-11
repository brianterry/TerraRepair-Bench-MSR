data "aws_region" "current" {
  region = var.region
}

data "aws_canonical_user_id" "this" {
  count = local.create_bucket && local.create_bucket_acl && try(var.owner["id"], null) == null? 1 : 0
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}
locals {
  create_bucket = var.create_bucket && var.putin_khuylo

  create_bucket_acl = (var.acl!= null && var.acl!= "null") || length(local.grants) > 0

  attach_policy = var.attach_require_latest_tls_policy || var.attach_access_log_delivery_policy || var.attach_elb_log_delivery_policy || var.attach_lb_log_delivery_policy || var.attach_cloudtrail_log_delivery_policy || var.attach_deny_insecure_transport_policy || var.attach_inventory_destination_policy || var.attach_deny_incorrect_encryption_headers || var.attach_deny_incorrect_kms_key_sse || var.attach_deny_unencrypted_object_uploads || var.attach_deny_ssec_encrypted_object_uploads || var.attach_policy || var.attach_waf_log_delivery_policy

  policy_placeholders = {
    "_S3_BUCKET_ID_"   = try(var.is_directory_bucket? aws_s3_directory_bucket.this[0].bucket : aws_s3_bucket.this[0].id, null),
    "_S3_BUCKET_ARN_"  = try(var.is_directory_bucket? aws_s3_directory_bucket.this[0].arn : aws_s3_bucket.this[0].arn, null),
    "_AWS_ACCOUNT_ID_" = try(data.aws_caller_identity.current.account_id, null)
  }

  policy = local.create_bucket && local.attach_policy? replace(
    replace(
      replace(
        data.aws_iam_policy_document.combined[0].json,
        "_S3_BUCKET_ID_", local.policy_placeholders["_S3_BUCKET_ID_"]
      ),
      "_S3_BUCKET_ARN_", local.policy_placeholders["_S3_BUCKET_ARN_"]
    ),
    "_AWS_ACCOUNT_ID_", local.policy_placeholders["_AWS_ACCOUNT_ID_"]
  ) : ""

  grants               = try(jsondecode(var.grant), var.grant)
  cors_rules           = try(jsondecode(var.cors_rule), var.cors_rule)
  lifecycle_rules      = try(jsondecode(var.lifecycle_rule), var.lifecycle_rule)
  intelligent_tiering  = try(jsondecode(var.intelligent_tiering), var.intelligent_tiering)
  metric_configuration = try(jsondecode(var.metric_configuration), var.metric_configuration)
}

resource "aws_s3_bucket" "this" {
  count = local.create_bucket &&!var.is_directory_bucket? 1 : 0

  region = var.region

  bucket        = var.bucket
  bucket_prefix = var.bucket_prefix

  force_destroy       = var.force_destroy
  object_lock_enabled = var.object_lock_enabled
  tags                = var.tags

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

  lifecycle_rule {
    id     = "logs"
    status = "Enabled"

    expiration {
      days = 365
    }
  }

  lifecycle_rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  public_access_block_configuration {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }

  logging {
    target_bucket = var.logging["target_bucket"]
    target_prefix = var.logging["target_prefix"]
  }

  website {
    index_document = var.website["index_document"]
    error_document = var.website["error_document"]
  }

  if (var.cors_rule) {
    cors_rule = var.cors_rule
  }

  if (var.versioning) {
    versioning {
      enabled = var.versioning["enabled"]
      mfa_delete = var.versioning["mfa_delete"]
    }
  }

  if (var.server_side_encryption_configuration) {
    server_side_encryption_configuration {
      rule {
        apply_server_side_encryption_by_default {
          sse_algorithm = var.server_side_encryption_configuration["sse_algorithm"]
          kms_master_key_id = var.server_side_encryption_configuration["kms_master_key_id"]
        }
      }
    }
  }

  if (var.acceleration_status) {
    accelerate_configuration {
      status = var.acceleration_status
    }
  }

  if (var.request_payer) {
    request_payment_configuration {
      payer = var.request_payer
    }
  }

  if (var.cors_rules) {
    cors_configuration {
      cors_rule {
        id              = try(cors_rule.value.id, null)
        allowed_methods = cors_rule.value.allowed_methods
        allowed_origins = cors_rule.value.allowed_origins
        allowed_headers = try(cors_rule.value.allowed_headers, null)
        expose_headers  = try(cors_rule.value.expose_headers, null)
        max_age_seconds = try(cors_rule.value.max_age_seconds, null)
      }
    }
  }

  if (var.lifecycle_rules) {
    lifecycle_configuration {
      rule {
        id     = try(rule.value.id, null)
        status = try(rule.value.enabled? "Enabled" : "Disabled", tobool(rule.value.status)? "Enabled" : "Disabled", title(lower(rule.value.status)))

        expiration {
          days = try(rule.value.expiration.days, null)
        }

        transition {
          storage_class = try(rule.value.transition.storage_class, null)
          days = try(rule.value.transition.days, null)
        }

        noncurrent_version_transition {
          storage_class = try(rule.value.noncurrent_version_transition.storage_class, null)
          days = try(rule.value.noncurrent_version_transition.days, null)
        }

        filter {
          prefix = try(rule.value.filter.prefix, null)
        }
      }
    }
  }

  if (var.object_lock_enabled) {
    object_lock_configuration {
      rule {
        default_retention {
          mode  = var.object_lock_configuration.rule.default_retention.mode
          days  = try(var.object_lock_configuration.rule.default_retention.days, null)
          years = try(var.object_lock_configuration.rule.default_retention.years, null)
        }
      }
    }
  }

  if (var.replication_configuration) {
    replication_configuration {
      rule {
        id       = try(rule.value.id, null)
        priority = try(rule.value.priority, null)
        status   = try(tobool(rule.value.status)? "Enabled" : "Disabled", title(lower(rule.value.status)), "Enabled")

        destination {
          bucket = try(rule.value.destination.bucket, null)
          storage_class = try(rule.value.destination.storage_class, null)
          account = try(rule.value.destination.account_id, null)
        }
      }
    }
  }

  if (var.metric_configuration) {
    metric_configuration {
      name = try(metric_configuration.value.name, null)
      filter {
        prefix = try(metric_configuration.value.filter.prefix, null)
      }
    }
  }

  if (var.inventory_configuration) {
    inventory_configuration {
      name = try(inventory_configuration.value.name, null)
      enabled = try(inventory_configuration.value.enabled, true)
      optional_fields = try(inventory_configuration.value.optional_fields, null)
      destination {
        bucket {
          bucket_arn = try(inventory_configuration.value.destination.bucket_arn, null)
          format = try(inventory_configuration.value.destination.format, null)
          account_id = try(inventory_configuration.value.destination.account_id, null)
          prefix = try(inventory_configuration.value.destination.prefix, null)
        }
      }
      schedule {
        frequency = try(inventory_configuration.value.frequency, null)
      }
    }
  }

  if (var.analytics_configuration) {
    analytics_configuration {
      name = try(analytics_configuration.value.name, null)
      filter {
        prefix = try(analytics_configuration.value.filter.prefix, null)
      }
      storage_class_analysis {
        data_export {
          output_schema_version = try(analytics_configuration.value.storage_class_analysis.output_schema_version, null)
          destination {
            s3_bucket_destination {
              bucket_arn = try(analytics_configuration.value.storage_class_analysis.destination_bucket_arn, null)
              bucket_account_id = try(analytics_configuration.value.storage_class_analysis.destination_account_id, null)
              format = try(analytics_configuration.value.storage_class_analysis.export_format, "CSV")
              prefix = try(analytics_configuration.value.storage_class_analysis.export_prefix, null)
            }
          }
        }
      }
    }
  }

  if (var.metadata_configuration) {
    metadata_configuration {
      inventory_table_configuration {
        configuration_state = var.metadata_inventory_table_configuration_state
        encryption_configuration {
          kms_key_arn = try(var.metadata_encryption_configuration.kms_key_arn, null)
          sse_algorithm = try(var.metadata_encryption_configuration.sse_algorithm, null)
        }
      }
      journal_table_configuration {
        record_expiration {
          days = var.metadata_journal_table_record_expiration_days
          expiration = var.metadata_journal_table_record_expiration
        }
      }
    }
  }

  if (var.attach_policy) {
    policy = var.policy
  }

  if (var.attach_public_policy) {
    public_access_block_configuration {
      block_public_acls = var.block_public_acls
      block_public_policy = var.block_public_policy
      ignore_public_acls = var.ignore_public_acls
      restrict_public_buckets = var.restrict_public_buckets
    }
  }

  if (var.control_object_ownership) {
    ownership_controls {
      rule {
        object_ownership = var.object_ownership
      }
    }
  }
}

resource "aws_s3_directory_bucket" "this" {
  count = local.create_bucket && var.is_directory_bucket? 1 : 0

  region = var.region

  bucket          = "${var.bucket}--${var.availability_zone_id}--x-s3"
  data_redundancy = var.data_redundancy
  force_destroy   = var.force_destroy
  type            = var.type

  location {
    name = var.availability_zone_id
    type = var.location_type
  }

  tags = var.tags

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

  lifecycle_rule {
    id     = "logs"
    status = "Enabled"

    expiration {
      days = 365
    }
  }

  lifecycle_rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  public_access_block_configuration {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }

  logging {
    target_bucket = var.logging["target_bucket"]
    target_prefix = var.logging["target_prefix"]
  }

  website {
    index_document = var.website["index_document"]
    error_document = var.website["error_document"]
  }

  if (var.cors_rule) {
    cors_rule = var.cors_rule
  }

  if (var.versioning) {
    versioning {
      enabled = var.versioning["enabled"]
      mfa_delete = var.versioning["mfa_delete"]
    }
  }

  if (var.server_side_encryption_configuration) {
    server_side_encryption_configuration {
      rule {
        apply_server_side_encryption_by_default {
          sse_algorithm = var.server_side_encryption_configuration["sse_algorithm"]
          kms_master_key_id = var.server_side_encryption_configuration["kms_master_key_id"]
        }
      }
    }
  }

  if (var.acceleration_status) {
    accelerate_configuration {
      status = var.acceleration_status
    }
  }

  if (var.request_payer) {
    request_payment_configuration {
      payer = var.request_payer
    }
  }

  if (var.cors_rules) {
    cors_configuration {
      cors_rule {
        id              = try(cors_rule.value.id, null)
        allowed_methods = cors_rule.value.allowed_methods
        allowed_origins = cors_rule.value.allowed_origins
        allowed_headers = try(cors_rule.value.allowed_headers, null)
        expose_headers  = try(cors_rule.value.expose_headers, null)
        max_age_seconds = try(cors_rule.value.max_age_seconds, null)
      }
    }
  }

  if (var.lifecycle_rules) {
    lifecycle_configuration {
      rule {
        id     = try(rule.value.id, null)
        status = try(rule.value.enabled? "Enabled" : "Disabled", tobool(rule.value.status)? "Enabled" : "Disabled", title(lower(rule.value.status)))

        expiration {
          days = try(rule.value.expiration.days, null)
        }

        transition {
          storage_class = try(rule.value.transition.storage_class, null)
          days = try(rule.value.transition.days, null)
        }

        noncurrent_version_transition {
          storage_class = try(rule.value.noncurrent_version_transition.storage_class, null)
          days = try(rule.value.noncurrent_version_transition.days, null)
        }

        filter {
          prefix = try(rule.value.filter.prefix, null)
        }
      }
    }
  }

  if (var.object_lock_enabled) {
    object_lock_configuration {
      rule {
        default_retention {
          mode  = var.object_lock_configuration.rule.default_retention.mode
          days  = try(var.object_lock_configuration.rule.default_retention.days, null)
          years = try(var.object_lock_configuration.rule.default_retention.years, null)
        }
      }
    }
  }

  if (var.replication_configuration) {
    replication_configuration {
      rule {
        id       = try(rule.value.id, null)
        priority = try(rule.value.priority, null)
        status   = try(tobool(rule.value.status)? "Enabled" : "Disabled", title(lower(rule.value.status)), "Enabled")

        destination {
          bucket = try(rule.value.destination.bucket, null)
          storage_class = try(rule.value.destination.storage_class, null)
          account = try(rule.value.destination.account_id, null)
        }
      }
    }
  }

  if (var.metric_configuration) {
    metric_configuration {
      name = try(metric_configuration.value.name, null)
      filter {
        prefix = try(metric_configuration.value.filter.prefix, null)
      }
    }
  }

  if (var.inventory_configuration) {
    inventory_configuration {
      name = try(inventory_configuration.value.name, null)
      enabled = try(inventory_configuration.value.enabled, true)
      optional_fields = try(inventory_configuration.value.optional_fields, null)
      destination {
        bucket {
          bucket_arn = try(inventory_configuration.value.destination.bucket_arn, null)
          format = try(inventory_configuration.value.destination.format, null)
          account_id = try(inventory_configuration.value.destination.account_id, null)
          prefix = try(inventory_configuration.value.destination.prefix, null)
        }
      }
      schedule {
        frequency = try(inventory_configuration.value.frequency, null)
      }
    }
  }

  if (var.analytics_configuration) {
    analytics_configuration {
      name = try(analytics_configuration.value.name, null)
      filter {
        prefix = try(analytics_configuration.value.filter.prefix, null)
      }
      storage_class_analysis {
        data_export {
          output_schema_version = try(analytics_configuration.value.storage_class_analysis.output_schema_version, null)
          destination {
            s3_bucket_destination {
              bucket_arn = try(analytics_configuration.value.storage_class_analysis.destination_bucket_arn, null)
              bucket_account_id = try(analytics_configuration.value.storage_class_analysis.destination_account_id, null)
              format = try(analytics_configuration.value.storage_class_analysis.export_format, "CSV")
              prefix = try(analytics_configuration.value.storage_class_analysis.export_prefix, null)
            }
          }
        }
      }
    }
  }

  if (var.metadata_configuration) {
    metadata_configuration {
      inventory_table_configuration {
        configuration_state = var.metadata_inventory_table_configuration_state
        encryption_configuration {
          kms_key_arn = try(var.metadata_encryption_configuration.kms_key_arn, null)
          sse_algorithm = try(var.metadata_encryption_configuration.sse_algorithm, null)
        }
      }
      journal_table_configuration {
        record_expiration {
          days = var.metadata_journal_table_record_expiration_days
          expiration = var.metadata_journal_table_record_expiration
        }
      }
    }
  }

  if (var.attach_policy) {
    policy = var.policy
  }

  if (var.attach_public_policy) {
    public_access_block_configuration {
      block_public_acls = var.block_public_acls
      block_public_policy = var.block_public_policy
      ignore_public_acls = var.ignore_public_acls
      restrict_public_buckets = var.restrict_public_buckets
    }
  }

  if (var.control_object_ownership) {
    ownership_controls {
      rule {
        object_ownership = var.object_ownership
      }
    }
  }
}

output "s3_bucket_id" {
  description = "The name of the bucket."
  value       = try(aws_s3_bucket.this[0].id, aws_s3_directory_bucket.this[0].bucket, "")
}

output "s3_bucket_arn" {
  description = "The ARN of the bucket. Will be of format arn:aws:s3:::bucketname."
  value       = try(aws_s3_bucket.this[0].arn, "")
}

output "s3_bucket_bucket_domain_name" {
  description = "The bucket domain name. Will be of format bucketname.s3.amazonaws.com."
  value       = try(aws_s3_bucket.this[0].bucket_domain_name, "")
}

output "s3_bucket_bucket_regional_domain_name" {
  description = "The bucket region-specific domain name. The bucket domain name including the region name, please refer here for format. Note: The AWS CloudFront allows specifying S3 region-specific endpoint when creating S3 origin, it will prevent redirect issues from CloudFront to S3 Origin URL."
  value       = try(aws_s3_bucket.this[0].bucket_regional_domain_name, "")
}

output "s3_bucket_hosted_zone_id" {
  description = "The Route 53 Hosted Zone ID for this bucket's region."
  value       = try(aws_s3_bucket.this[0].hosted_zone_id, "")
}

output "s3_bucket_lifecycle_configuration_rules" {
  description = "The lifecycle rules of the bucket, if the bucket is configured with lifecycle rules. If not, this will be an empty string."
  value       = try(aws_s3_bucket.this[0].lifecycle_configuration.rule, "")
}

output "s3_bucket_policy" {
  description = "The policy of the bucket, if the bucket is configured with a policy. If not, this will be an empty string."
  value       = try(aws_s3_bucket.this[0].policy, "")
}

output "s3_bucket_region" {
  description = "The AWS region this bucket resides in."
  value       = try(aws_s3_bucket.this[0].bucket_region, "")
}

output "s3_bucket_website_endpoint" {
  description = "The website endpoint, if the bucket is configured with a website. If not, this will be an empty string."
  value       = try(aws_s3_bucket.this[0].website_endpoint, "")
}

output "s3_bucket_website_domain" {
  description = "The domain of the website endpoint, if the bucket is configured with a website. If not, this will be an empty string. This is used to create Route 53 alias records."
  value       = try(aws_s3_bucket.this[0].website_domain, "")
}

output "s3_directory_bucket_name" {
  description = "Name of the directory bucket."
  value       = try(aws_s3_directory_bucket.this[0].bucket, null)
}

output "s3_directory_bucket_arn" {
  description = "ARN of the directory bucket."
  value       = try(aws_s3_directory_bucket.this[0].arn, null)
}

output "aws_s3_bucket_versioning_status" {
  description = "The versioning status of the bucket. Will be 'Enabled', 'Suspended', or 'Disabled'."
  value       = try(aws_s3_bucket.this[0].versioning_status, null)
}

output "s3_bucket_tags" {
  description = "Tags of the bucket."
  value       = try(aws_s3_bucket.this[0].tags, {})
}

terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.28"
    }
  }

  provider_meta "aws" {
    user_agent = [
      "github.com/terraform-aws-modules/terraform-aws-s3-bucket"
    ]
  }
}