terraform {
  required_version = ">= 0.11.0"
}

resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true

  flow_logs {
    traffic_type = "REJECT"
    log_destination = "arn:aws:logs:::log-group"
  }

  default_security_group_rules = [
    {
      cidr_blocks = ["0.0.0.0/0"]
      from_port   = 0
      protocol    = "-1"
      to_port     = 0
      type        = "ingress"
      action      = "deny"
    }
  ]
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