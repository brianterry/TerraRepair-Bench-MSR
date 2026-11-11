resource "aws_kms_key" "main" {
  description             = "KMS key for sadcloud elasticsearch and cloudwatch logs"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_elasticsearch_domain" "main" {
  count = var.elasticsearch_logging_disabled || var.elasticsearch_open_access ? 1 : 0

  domain_name           = var.name
  elasticsearch_version = "6.0"

  cluster_config {
    instance_type            = "t2.small.elasticsearch"
    dedicated_master_enabled = true
    dedicated_master_count   = 3
    dedicated_master_type    = "t2.small.elasticsearch"
    zone_awareness_enabled   = true

    zone_awareness_config {
      availability_zone_count = 3
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp2"
    volume_size = 10
  }

  encrypt_at_rest {
    enabled    = true
    kms_key_id = aws_kms_key.main.arn
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true

    master_user_options {
      master_user_name     = "admin"
      master_user_password = "ChangeMe123!"
    }
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.main.arn
    log_type                 = "INDEX_SLOW_LOGS"
    enabled                  = !var.elasticsearch_logging_disabled
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.main.arn
    log_type                 = "SEARCH_SLOW_LOGS"
    enabled                  = !var.elasticsearch_logging_disabled
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.main.arn
    log_type                 = "AUDIT_LOGS"
    enabled                  = !var.elasticsearch_logging_disabled
  }

  depends_on = [
    aws_cloudwatch_log_group.main
  ]
}

resource "aws_cloudwatch_log_group" "main" {

  name              = var.name
  retention_in_days = 365
  kms_key_id        = aws_kms_key.main.arn
}


resource "aws_cloudwatch_log_resource_policy" "main" {
  count = var.elasticsearch_open_access && !var.elasticsearch_logging_disabled ? 1 : 0

  policy_name = var.name

  policy_document = <<CONFIG
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "es.amazonaws.com"
      },
      "Action": [
        "logs:PutLogEvents",
        "logs:PutLogEventsBatch",
        "logs:CreateLogStream"
      ],
      "Resource": "arn:aws:logs:*"
    }
  ]
}
CONFIG
}

resource "aws_elasticsearch_domain_policy" "main" {
  count = var.elasticsearch_open_access ? 1 : 0

  domain_name = aws_elasticsearch_domain.main[0].domain_name

  access_policies = <<POLICIES
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "es:*",
            "Principal": "*",
            "Effect": "Allow",
            "Resource": "${aws_elasticsearch_domain.main[0].arn}/*"
        }
    ]
}
POLICIES
}




variable "name" {
  description = "es name"
  type        = string
  default     = "sadcloud"
}

variable "elasticsearch_logging_disabled" {
  description = "Elasticsearch Service domains have logging disabled"
  type        = bool
  default     = false
}

variable "elasticsearch_open_access" {
  description = "Elasticsearch Service domains have open access"
  type        = bool
  default     = false
}