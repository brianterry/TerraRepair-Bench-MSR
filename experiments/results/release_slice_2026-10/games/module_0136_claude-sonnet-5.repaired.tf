terraform {
  required_version = ">= 0.11.0"
}

// Vault provider
// Set VAULT_ADDR and VAULT_TOKEN environment variables
provider "vault" {}

// AWS credentials from Vault
data "vault_aws_access_credentials" "aws_creds" {
  backend = "aws"
  role = "deploy"
}

//  Setup the core provider information.
provider "aws" {
  access_key = "${data.vault_aws_access_credentials.aws_creds.access_key}"
  secret_key = "${data.vault_aws_access_credentials.aws_creds.secret_key}"
  region  = "${var.region}"
}

data "aws_availability_zones" "main" {
  state = "available"
}


resource "aws_security_group_rule" "ssh" {
  security_group_id = "${aws_security_group.egress_public.id}"
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_blocks       = ["${var.vpc_cidr}"]
  description       = "Allow SSH access from within the VPC"
}


resource "aws_security_group" "egress_public" {
  name        = "${var.environment_name}-egress_public"
  description = "${var.environment_name}-egress_public"
  vpc_id      = "${aws_vpc.main.id}"
}

resource "aws_security_group_rule" "egress_public" {
  security_group_id = "${aws_security_group.egress_public.id}"
  type              = "egress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  cidr_blocks       = ["${var.vpc_cidr}"]
  description       = "Allow outbound traffic within the VPC"
}

resource "aws_security_group_rule" "ingress_internal" {
  security_group_id = "${aws_security_group.egress_public.id}"
  type              = "ingress"
  protocol          = "-1"
  from_port         = 0
  to_port           = 0
  self              = "true"
  description       = "Allow internal ingress traffic from members of this security group"
}


resource "aws_internet_gateway" "main" {
  vpc_id = "${aws_vpc.main.id}"

  tags {
    Name = "${var.environment_name}"
  }
}

resource "aws_nat_gateway" "nat" {
  count = "${length(var.vpc_cidrs_public)}"

  allocation_id = "${element(aws_eip.nat.*.id,count.index)}"
  subnet_id     = "${element(aws_subnet.public.*.id,count.index)}"
}

resource "aws_eip" "nat" {
  count = "${length(var.vpc_cidrs_public)}"

  vpc = true
}


#
# Public
#
resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.main.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.main.id}"
  }

  tags {
    Name = "${var.environment_name}-public"
  }
}

resource "aws_route_table_association" "public" {
  count = "${length(var.vpc_cidrs_public)}"

  subnet_id      = "${element(aws_subnet.public.*.id,count.index)}"
  route_table_id = "${aws_route_table.public.id}"
}



resource "aws_subnet" "public" {
  count = "${length(var.vpc_cidrs_public)}"

  vpc_id                  = "${aws_vpc.main.id}"
  availability_zone       = "${element(data.aws_availability_zones.main.names,count.index)}"
  cidr_block              = "${element(var.vpc_cidrs_public,count.index)}"
  map_public_ip_on_launch = false

  tags {
    Name = "${var.environment_name}-public-${count.index}"
  }
}


resource "aws_vpc" "main" {
  cidr_block           = "${var.vpc_cidr}"
  enable_dns_hostnames = true

  tags {
    Name = "${var.environment_name}"
  }
}


# Outputs
output "vpc_id" {
  value = "${aws_vpc.main.id}"
}

output "subnet_public_ids" {
  value = ["${aws_subnet.public.*.id}"]
}

output "security_group_apps" {
  value = "${aws_security_group.egress_public.id}"
}


# Required variables
variable "environment_name" {
  description = "Environment Name"
  default = "Acme"
}

variable "region" {
  description = "AWS region"
  default = "us-west-2"
}

# Optional variables
variable "vpc_cidr" {
  default = "172.19.0.0/16"
}

variable "vpc_cidrs_public" {
  default = [
    "172.19.0.0/20",
  ]
}