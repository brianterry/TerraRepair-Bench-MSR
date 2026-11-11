resource "aws_elasticsearch_domain" "main" {
  count = var.elasticsearch_logging_disabled || var.elasticsearch_open_access ? 1 : 0

  domain_name           = var.name
  elasticsearch_version = "7.10"

  cluster_config {
    instance_type = "t2.small.elasticsearch"
    zone_awareness_enabled = true
    zone_awareness_config {
      availability_zone_count = 3
    }
    dedicated_master_enabled = true
    dedicated_master_count = 3
    dedicated_master_type = "t2.small.elasticsearch"
  }

  vpc_options {
    security_group_ids = [aws_security_group.main.id]
    subnet_ids         = [aws_subnet.main.id]
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp2"
    volume_size = 10
  }

  encrypt_at_rest {
    enabled = true
    kms_key_id = aws_kms_key.main.arn
  }

  node_to_node_encryption {
    enabled = true
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.main.arn
    log_type                 = "INDEX_SLOW_LOGS"
    enabled = !var.elasticsearch_logging_disabled
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.main.arn
    log_type                 = "SEARCH_SLOW_LOGS"
    enabled = !var.elasticsearch_logging_disabled
  }

  depends_on = [
    aws_cloudwatch_log_group.main,
    aws_kms_key.main,
    aws_security_group.main,
    aws_subnet.main
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
            "Principal": {
              "AWS": "*"
            },
            "Effect": "Allow",
            "Resource": "${aws_elasticsearch_domain.main[0].arn}/*",
            "Condition": {
              "IpAddress": {
                "aws:SourceIp": "0.0.0.0/0"
              }
            }
        }
    ]
}
POLICIES
}

resource "aws_kms_key" "main" {
}

resource "aws_security_group" "main" {
  name        = var.name
  description = "Elasticsearch security group"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "main" {
  cidr_block = "10.0.1.0/24"
  vpc_id     = aws_vpc.main.id
  availability_zone = "us-west-2a"
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