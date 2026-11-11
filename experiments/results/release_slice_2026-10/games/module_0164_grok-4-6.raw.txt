terraform {
  required_version = ">= 0.11.0"
}

// Currently, variables in provider fields are not supported :(
// This severely limits our ability to spin up instances in diffrent regions 
// https://github.com/hashicorp/terraform/issues/11578

resource "aws_vpc" "default" {
  //count = "${var.count}"
  //provider = "aws.${element(var.regions, count.index)}"

  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
}

resource "aws_default_security_group" "default" {
  vpc_id = "${aws_vpc.default.id}"
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name = "vpc-flow-log-default"
}

resource "aws_iam_role" "flow_log" {
  name = "vpc-flow-log-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "flow_log" {
  name = "vpc-flow-log-policy"
  role = "${aws_iam_role.flow_log.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_flow_log" "default" {
  iam_role_arn    = "${aws_iam_role.flow_log.arn}"
  log_destination = "${aws_cloudwatch_log_group.flow_log.arn}"
  traffic_type    = "REJECT"
  vpc_id          = "${aws_vpc.default.id}"
}

resource "aws_subnet" "default" {
  //count = "${var.count}"
  //provider = "aws.${element(var.regions, count.index)}"

  vpc_id = "${aws_vpc.default.id}"
  cidr_block = "10.0.0.0/24"
}

resource "aws_internet_gateway" "default" {
  //count = "${var.count}"
  //provider = "aws.${element(var.regions, count.index)}"

  vpc_id = "${aws_vpc.default.id}"
}

resource "aws_route_table" "default" {
  //count = "${var.count}"
  //provider = "aws.${element(var.regions, count.index)}"

  vpc_id = "${aws_vpc.default.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.default.id}"
  }
}

resource "aws_route_table_association" "default" {
  //count = "${var.count}"
  //provider = "aws.${element(var.regions, count.index)}"

  subnet_id = "${aws_subnet.default.id}"
  route_table_id = "${aws_route_table.default.id}"
}


output "subnet_id" {
  value = "${aws_subnet.default.id}"
}

output "vpc_id" {
  value = "${aws_vpc.default.id}"
}

/*
variable "count" {
  default = 1
}
*/