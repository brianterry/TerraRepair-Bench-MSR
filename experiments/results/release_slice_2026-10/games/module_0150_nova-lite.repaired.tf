locals {
  flow_logs_to_cw_logs = var.enable_flow_logs && var.flow_logs_destination_type == "cloud-watch-logs"
}

data "aws_subnets" "default" {
  filter {
    name   = "default-for-az"
    values = [true]
  }
}

data "aws_subnet" "default" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

# --------------------------------------------------------------------------------------------------
# Enable VPC Flow Logs for the default VPC.
# --------------------------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "default_vpc_flow_logs" {
  count = var.enable_flow_logs && local.flow_logs_to_cw_logs ? 1 : 0

  name              = var.flow_logs_log_group_name
  retention_in_days = var.flow_logs_retention_in_days
  kms_key_id        = var.flow_logs_kms_key_id

  tags = var.tags
}

resource "aws_flow_log" "default_vpc_flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  log_destination_type = var.flow_logs_destination_type
  log_destination      = local.flow_logs_to_cw_logs ? aws_cloudwatch_log_group.default_vpc_flow_logs[0].arn : "${var.flow_logs_s3_arn}/${var.flow_logs_s3_key_prefix}"
  iam_role_arn         = local.flow_logs_to_cw_logs ? var.flow_logs_iam_role_arn : null
  vpc_id               = aws_vpc.custom.id
  traffic_type         = "ALL"

  tags = var.tags
}

resource "aws_vpc" "custom" {
  cidr_block = "10.0.0.0/16"

  tags = merge(
    var.tags,
    { Name = "Custom VPC" }
  )
}

resource "aws_subnet" "custom" {
  for_each = data.aws_subnet.default
  vpc_id   = aws_vpc.custom.id
  cidr_block = each.value.cidr_block

  tags = merge(
    var.tags,
    { Name = "Custom Subnet" }
  )
}

resource "aws_internet_gateway" "custom" {
  vpc_id = aws_vpc.custom.id

  tags = merge(
    var.tags,
    { Name = "Custom Internet Gateway" }
  )
}

resource "aws_route_table" "custom" {
  vpc_id = aws_vpc.custom.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.custom.id
  }

  tags = merge(
    var.tags,
    { Name = "Custom Route Table" }
  )
}

resource "aws_route_table_association" "custom" {
  for_each = data.aws_subnet.default
  subnet_id = each.value.id
  route_table_id = aws_route_table.custom.id
}

resource "aws_security_group" "custom" {
  vpc_id = aws_vpc.custom.id

  tags = merge(
    var.tags,
    { Name = "Custom Security Group" }
  )
}

# --------------------------------------------------------------------------------------------------
# Clears rules associated with default resources.
# --------------------------------------------------------------------------------------------------

output "custom_vpc" {
  description = "The custom VPC."
  value       = aws_vpc.custom
}

output "custom_security_group" {
  description = "The custom security group."
  value       = aws_security_group.custom
}

output "custom_route_table" {
  description = "The custom route table."
  value       = aws_route_table.custom
}

output "vpc_flow_logs_group" {
  description = "The CloudWatch Logs log group which stores VPC Flow Logs."
  value       = local.flow_logs_to_cw_logs ? aws_cloudwatch_log_group.default_vpc_flow_logs[0] : null
}

variable "enable_flow_logs" {
  description = "The boolean flag whether to enable VPC Flow Logs in the default VPC"
  type        = bool
  default     = true
}

variable "flow_logs_destination_type" {
  description = "The type of the logging destination. Valid values: cloud-watch-logs, s3"
  type        = string
  default     = "cloud-watch-logs"
}

# --------------------------------------------------------------------------------------------------
# Variables for CloudWatch Logs logging.
# --------------------------------------------------------------------------------------------------

variable "flow_logs_log_group_name" {
  description = "The name of CloudWatch Logs group to which VPC Flow Logs are delivered if vpc_log_destination_type is cloud-watch-logs."
  type        = string
  default     = ""
}

variable "flow_logs_iam_role_arn" {
  description = "The ARN of the IAM Role which will be used by VPC Flow Logs if vpc_log_destination_type is cloud-watch-logs."
  type        = string
  default     = ""
}

variable "flow_logs_retention_in_days" {
  description = "Number of days to retain logs if vpc_log_destination_type is cloud-watch-logs. CIS recommends 365 days. Possible values are: 0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, and 3653. Set to 0 to keep logs indefinitely."
  type        = number
  default     = 365
}

variable "flow_logs_kms_key_id" {
  description = "The ARN of the KMS key to encrypt CloudWatch Logs."
  type        = string
  default     = ""
}

# --------------------------------------------------------------------------------------------------
# Variables for S3 logging.
# --------------------------------------------------------------------------------------------------

variable "flow_logs_s3_arn" {
  description = "The ARN of the S3 bucket to which VPC Flow Logs are delivered if vpc_log_destination_type is s3."
  type        = string
  default     = ""
}

variable "flow_logs_s3_key_prefix" {
  description = "The prefix used when VPC Flow Logs delivers logs to the S3 bucket."
  type        = string
  default     = "flow-logs"
}

variable "tags" {
  description = "Specifies object tags key and value. This applies to all resources created by this module."
  type        = map(string)
  default = {
    "Terraform" = "true"
  }
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