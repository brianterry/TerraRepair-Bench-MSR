resource "time_static" "time" {}

data "aws_dynamodb_table" "cmdb" {
  name     = var.backend_dynamodb_table
  provider = aws.cmdb
}

resource "aws_dynamodb_table_item" "cmdb" {
  provider   = aws.cmdb
  hash_key   = "LockID"
  table_name = data.aws_dynamodb_table.cmdb.name
  item       = <<ITEM
{
  "LockID": {"S": "${local.item_id_lock}"},
  "time_stamp": {"S": "${time_static.time.unix}"},
  "USER_ID": {"S": "${local.USER_ID}"},
  "ENV_ID": {"S": "${local.ENV_ID}"},
  "STACK_NAME": {"S": "${var.STACK_NAME}"},
  "STACK_TASK": {"S": "${var.STACK_TASK}"},
  "region": {"S": "${var.region}"}
}
ITEM
}

resource "aws_dynamodb_table_item" "cmdb_data" {
  provider   = aws.cmdb
  hash_key   = "LockID"
  table_name = data.aws_dynamodb_table.cmdb.name
  item       = <<ITEM
{
  "LockID": {"S": "${local.item_id_data}"},
  "time_stamp": {"S": "${time_static.time.unix}"},
  "USER_ID": {"S": "${local.USER_ID}"},
  "ENV_ID": {"S": "${local.ENV_ID}"},
  "STACK_NAME": {"S": "${var.STACK_NAME}"},
  "STACK_TASK": {"S": "${var.STACK_TASK}"},
  "vpc_id": {"S": "${aws_vpc.default.id}"},
  "subnets_az_cmdb": {"S": "${local.subnets_az_cmdb}"},
  "region": {"S": "${var.region}"}
}
ITEM
}

locals {
  USER_ID      = var.USER_ID == "" ? "defaultUser" : var.USER_ID
  ENV_ID       = var.ENV_ID == "" ? "defaultId" : var.ENV_ID
  prefix_id    = "${local.USER_ID}_${local.ENV_ID}"
  prefix       = "${local.prefix_id}_${var.prefix}"
  item_id_lock = "CMDB_lock_${local.USER_ID}_${local.ENV_ID}_${var.app_name}_${var.prefix}"
  item_id_data = "CMDB_data_${local.USER_ID}_${local.ENV_ID}_${var.app_name}_${var.prefix}"
  subnets_az = [
    for x in aws_subnet.subnets_pub :
    "${x.id}=${x.availability_zone}"
  ]
  subnets_az_cmdb = join(",", local.subnets_az)
  tags_app = {
    "Name"     = "${local.prefix}-${var.app_name}"
    "app_name" = var.app_name
  }
  tags_all = merge(var.tags_common, local.tags_app)
}

output "subnets_az" {
  value = local.subnets_az
}

output "subnets_az_cmdb" {
  value = local.subnets_az_cmdb
}

output "vpc_id" {
  value = aws_vpc.default.id
}

output "vpc_default_cidr" {
  value = var.vpc_default_cidr
}

output "env" {
  value = "${local.prefix}-${var.app_name} "
}

output "USER_ID" {
  value = local.USER_ID
}

output "ENV_ID" {
  value = local.ENV_ID
}

output "local_prefix" {
  value = local.prefix
}

provider "aws" {
  region = var.region
}

provider "aws" {
  alias  = "cmdb"
  region = var.region_cmdb
}

resource "aws_route_table" "pub" {
  depends_on = [aws_dynamodb_table_item.cmdb]
  vpc_id     = aws_vpc.default.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.default.id
  }
  tags = local.tags_all
}

resource "aws_route_table_association" "pub" {
  depends_on = [
    aws_subnet.subnets_pub,
    aws_dynamodb_table_item.cmdb
  ]
  for_each       = var.az_ids
  route_table_id = aws_route_table.pub.id
  subnet_id      = aws_subnet.subnets_pub["${each.key}"].id
}

resource "aws_subnet" "subnets_pub" {
  depends_on              = [aws_dynamodb_table_item.cmdb]
  vpc_id                  = aws_vpc.default.id
  for_each                = var.az_ids
  map_public_ip_on_launch = false
  cidr_block              = each.key
  availability_zone_id    = each.value
  tags                    = local.tags_all
  lifecycle {
    ignore_changes = [
      tags,
      tags_all
    ]
  }
}

variable "region" {}

variable "az_ids" {
  type = map(string)
}

variable "vpc_default_cidr" {}

variable "aws" {}

variable "prefix" {}

variable "app_name" {}

variable "USER_ID" {
  type    = string
  default = "defaultUser"
}

variable "ENV_ID" {
  type    = string
  default = "defaultId"
}

variable "STACK_NAME" {
  type    = string
  default = ""
}

variable "STACK_TASK" {
  type    = string
  default = ""
}

variable "tags_common" {
  type = map(string)
}

variable "region_cmdb" {}

variable "backend_dynamodb_table" {}

resource "aws_vpc" "default" {
  depends_on           = [aws_dynamodb_table_item.cmdb]
  cidr_block           = var.vpc_default_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = local.tags_all
}

resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
  tags   = local.tags_all
}

resource "aws_security_group" "default" {
  name        = "default-sg"
  description = "Default security group"
  vpc_id      = aws_vpc.default.id
  ingress {
    from_port = -1
    to_port   = -1
    protocol  = -1
    self      = true
  }
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }
  tags = local.tags_all
}

resource "aws_flow_log" "default" {
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = aws_cloudwatch_log_group.flow_log.arn
  traffic_type    = "REJECT"
  vpc_id          = aws_vpc.default.id
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name = "flow-log"
}

resource "aws_iam_role" "flow_log" {
  name        = "flow-log-role"
  description = "Role for flow log"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "flow_log" {
  name   = "flow-log-policy"
  role   = aws_iam_role.flow_log.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = aws_cloudwatch_log_group.flow_log.arn
      }
    ]
  })
}