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
  kms_key_id        = var.flow_logs_log_group_kms_key_id

  tags = var.tags
}

resource "aws_flow_log" "default_vpc_flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  log_destination_type = var.flow_logs_destination_type
  log_destination      = local.flow_logs_to_cw_logs ? aws_cloudwatch_log_group.default_vpc_flow_logs[0].arn : "${var.flow_logs_s3_arn}/${var.flow_logs_s3_key_prefix}"
  iam_role_arn         = local.flow_logs_to_cw_logs ? var.flow_logs_iam_role_arn : null
  vpc_id               = data.aws_vpc.default.id
  traffic_type         = "ALL"

  tags = var.tags
}

# --------------------------------------------------------------------------------------------------
# Clears rules associated with default resources.
# --------------------------------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

resource "aws_default_subnet" "default" {
  for_each = data.aws_subnet.default

  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    { Name = "Default Subnet" }
  )
}

resource "aws_default_route_table" "default" {
  default_route_table_id = data.aws_vpc.default.default_route_table_id

  tags = merge(
    var.tags,
    { Name = "Default Route Table" }
  )
}

# Ignore "subnet_ids" changes to avoid the known issue below.
# https://github.com/hashicorp/terraform/issues/9824
# https://github.com/terraform-providers/terraform-provider-aws/issues/346
resource "aws_default_network_acl" "default" {
  default_network_acl_id = data.aws_vpc.default.default_network_acl_id

  tags = merge(
    var.tags,
    { Name = "Default Network ACL" }
  )

  lifecycle {
    ignore_changes = [subnet_ids]
  }
}

resource "aws_default_security_group" "default" {
  vpc_id = data.aws_vpc.default.id

  tags = merge(
    var.tags,
    { Name = "Default Security Group" }
  )
}


# --------------------------------------------------------------------------------------------------
# Migrations to 0.31.0
# Removing `enabled` argument.
# --------------------------------------------------------------------------------------------------

moved {
  from = aws_default_vpc.default[0]
  to   = aws_default_vpc.default
}

moved {
  from = aws_default_route_table.default[0]
  to   = aws_default_route_table.default
}

moved {
  from = aws_default_network_acl.default[0]
  to   = aws_default_network_acl.default
}

moved {
  from = aws_default_security_group.default[0]
  to   = aws_default_security_group.default
}


output "default_vpc" {
  description = "The default VPC."
  value       = data.aws_vpc.default
}

output "default_security_group" {
  description = "The default security group."
  value       = aws_default_security_group.default
}

output "default_network_acl" {
  description = "The default network ACL."
  value       = aws_default_network_acl.default
}

output "default_route_table" {
  description = "The default route table."
  value       = aws_default_route_table.default
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

variable "flow_logs_log_group_kms_key_id" {
  description = "The ID or ARN of the KMS key to use for encrypting CloudWatch Logs log group data."
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