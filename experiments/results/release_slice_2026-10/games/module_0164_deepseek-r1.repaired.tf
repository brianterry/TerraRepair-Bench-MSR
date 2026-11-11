terraform {
  required_version = ">= 0.11.0"
}

resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
}

resource "aws_default_security_group" "default" {
  vpc_id = "${aws_vpc.default.id}"

  ingress = []
  egress = []
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name = "vpc-flow-logs"
}

resource "aws_iam_role" "vpc_flow_log_role" {
  name = "vpc-flow-log-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
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

resource "aws_iam_role_policy" "flow_log_policy" {
  name = "flow-log-policy"
  role = "${aws_iam_role.vpc_flow_log_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_flow_log" "vpc_flow_log" {
  iam_role_arn    = "${aws_iam_role.vpc_flow_log_role.arn}"
  log_destination = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}"
  traffic_type    = "REJECT"
  vpc_id          = "${aws_vpc.default.id}"
}

resource "aws_subnet" "default" {
  vpc_id = "${aws_vpc.default.id}"
  cidr_block = "10.0.0.0/24"
}

resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.default.id}"
}

resource "aws_route_table" "default" {
  vpc_id = "${aws_vpc.default.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.default.id}"
  }
}

resource "aws_route_table_association" "default" {
  subnet_id = "${aws_subnet.default.id}"
  route_table_id = "${aws_route_table.default.id}"
}

output "subnet_id" {
  value = "${aws_subnet.default.id}"
}

output "vpc_id" {
  value = "${aws_vpc.default.id}"
}