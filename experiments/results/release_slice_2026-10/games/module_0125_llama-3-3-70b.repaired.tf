variable "cidr" {
  description = "The CIDR block for the VPC."
}

variable "external_subnets" {
  description = "List of external subnets"
  type        = "list"
}

variable "internal_subnets" {
  description = "List of internal subnets"
  type        = "list"
}

variable "environment" {
  description = "Environment tag, e.g prod"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = "list"
}

variable "name" {
  description = "Name tag, e.g stack"
  default     = "stack"
}

variable "use_nat_instances" {
  description = "If true, use EC2 NAT instances instead of the AWS NAT gateway service."
  default     = false
}

variable "nat_instance_type" {
  description = "Only if use_nat_instances is true, which EC2 instance type to use for the NAT instances."
  default     = "t2.nano"
}

variable "use_eip_with_nat_instances" {
  description = "Only if use_nat_instances is true, whether to assign Elastic IPs to the NAT instances. IF this is set to false, NAT instances use dynamically assigned IPs."
  default     = false
}

variable "nat_instance_ssh_key_name" {
  description = "Only if use_nat_instance is true, the optional SSH key-pair to assign to NAT instances."
  default     = ""
}

data "aws_ami" "nat_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-vpc-nat*"]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = "${var.cidr}"
  enable_dns_support   = true
  enable_dns_hostnames = true
  enable_classiclink   = false

  tags {
    Name        = "${var.name}"
    Environment = "${var.environment}"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = "${aws_vpc.main.id}"

  tags {
    Name        = "${var.name}"
    Environment = "${var.environment}"
  }
}

resource "aws_nat_gateway" "main" {
  count         = "${(1 - var.use_nat_instances) * length(var.internal_subnets)}"
  allocation_id = "${element(aws_eip.nat.*.id, count.index)}"
  subnet_id     = "${element(aws_subnet.external.*.id, count.index)}"
  depends_on    = ["aws_internet_gateway.main"]
}

resource "aws_eip" "nat" {
  count = "${signum((var.use_nat_instances * var.use_eip_with_nat_instances) + (var.use_nat_instances == 0 ? 1 : 0)) * length(var.internal_subnets)}"

  vpc = true
}

resource "aws_security_group" "nat_instances" {
  count       = "${0 + var.use_nat_instances}"
  name        = "nat"
  description = "Allow traffic from clients into NAT instances"

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = "${var.internal_subnets}"
    description = "Allow UDP traffic from internal subnets"
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = "${var.internal_subnets}"
    description = "Allow TCP traffic from internal subnets"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all egress traffic"
  }

  vpc_id = "${aws_vpc.main.id}"
}

resource "aws_instance" "nat_instance" {
  count             = "${(0 + var.use_nat_instances) * length(var.internal_subnets)}"
  availability_zone = "${element(var.availability_zones, count.index)}"

  tags {
    Name        = "${var.name}-${format("internal-%03d NAT", count.index+1)}"
    Environment = "${var.environment}"
  }

  volume_tags {
    Name        = "${var.name}-${format("internal-%03d NAT", count.index+1)}"
    Environment = "${var.environment}"
  }

  key_name               = "${var.nat_instance_ssh_key_name}"
  ami                    = "${data.aws_ami.nat_ami.id}"
  instance_type          = "${var.nat_instance_type}"
  source_dest_check      = false
  vpc_security_group_ids = ["${aws_security_group.nat_instances.id}"]
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  ebs_block_device {
    device_name = "/dev/sda1"
    encrypted   = true
  }

  subnet_id = "${element(aws_subnet.external.*.id, count.index)}"

  lifecycle {
    ignore_changes = ["ami"]
  }
}

resource "aws_eip_association" "nat_instance_eip" {
  count         = "${(0 + (var.use_nat_instances * var.use_eip_with_nat_instances)) * length(var.internal_subnets)}"
  instance_id   = "${element(aws_instance.nat_instance.*.id, count.index)}"
  allocation_id = "${element(aws_eip.nat.*.id, count.index)}"
}

resource "aws_subnet" "internal" {
  vpc_id            = "${aws_vpc.main.id}"
  cidr_block        = "${element(var.internal_subnets, count.index)}"
  availability_zone = "${element(var.availability_zones, count.index)}"
  count             = "${length(var.internal_subnets)}"

  tags {
    Name        = "${var.name}-${format("internal-%03d", count.index+1)}"
    Environment = "${var.environment}"
  }
}

resource "aws_subnet" "external" {
  vpc_id                  = "${aws_vpc.main.id}"
  cidr_block              = "${element(var.external_subnets, count.index)}"
  availability_zone       = "${element(var.availability_zones, count.index)}"
  count                   = "${length(var.external_subnets)}"
  map_public_ip_on_launch = false

  tags {
    Name        = "${var.name}-${format("external-%03d", count.index+1)}"
    Environment = "${var.environment}"
  }
}

resource "aws_flow_log" "main" {
  iam_role_arn    = "${aws_iam_role.flow_log.arn}"
  log_destination = "${aws_cloudwatch_log_group.flow_log.arn}"
  traffic_type    = "REJECT"
  vpc_id          = "${aws_vpc.main.id}"
}

resource "aws_cloudwatch_log_group" "flow_log" {
  name = "${var.name}-flow-log"
}

resource "aws_iam_role" "flow_log" {
  name        = "${var.name}-flow-log"
  description = "Flow log role"

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

resource "aws_iam_policy" "flow_log" {
  name        = "${var.name}-flow-log"
  description = "Flow log policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "logs:CreateLogStream",
      "Resource": "${aws_cloudwatch_log_group.flow_log.arn}",
      "Effect": "Allow"
    },
    {
      "Action": "logs:PutLogEvents",
      "Resource": "${aws_cloudwatch_log_group.flow_log.arn}",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "flow_log" {
  role       = "${aws_iam_role.flow_log.name}"
  policy_arn = "${aws_iam_policy.flow_log.arn}"
}

resource "aws_route_table" "external" {
  vpc_id = "${aws_vpc.main.id}"

  tags {
    Name        = "${var.name}-external-001"
    Environment = "${var.environment}"
  }
}

resource "aws_route" "external" {
  route_table_id         = "${aws_route_table.external.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.main.id}"
}

resource "aws_route_table" "internal" {
  count  = "${length(var.internal_subnets)}"
  vpc_id = "${aws_vpc.main.id}"

  tags {
    Name        = "${var.name}-${format("internal-%03d", count.index+1)}"
    Environment = "${var.environment}"
  }
}

resource "aws_route" "internal" {
  count                  = "${(1 - var.use_nat_instances) * length(compact(var.internal_subnets))}"
  route_table_id         = "${element(aws_route_table.internal.*.id, count.index)}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${element(aws_nat_gateway.main.*.id, count.index)}"
}

resource "aws_route" "internal_nat_instance" {
  count                  = "${(0 + var.use_nat_instances) * length(compact(var.internal_subnets))}"
  route_table_id         = "${element(aws_route_table.internal.*.id, count.index)}"
  destination_cidr_block = "0.0.0.0/0"
  instance_id            = "${element(aws_instance.nat_instance.*.id, count.index)}"
}

resource "aws_route_table_association" "internal" {
  count          = "${length(var.internal_subnets)}"
  subnet_id      = "${element(aws_subnet.internal.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.internal.*.id, count.index)}"
}

resource "aws_route_table_association" "external" {
  count          = "${length(var.external_subnets)}"
  subnet_id      = "${element(aws_subnet.external.*.id, count.index)}"
  route_table_id = "${aws_route_table.external.id}"
}

resource "aws_iam_role" "nat_instance" {
  name        = "${var.name}-nat-instance"
  description = "NAT instance role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "nat_instance" {
  name        = "${var.name}-nat-instance"
  description = "NAT instance policy"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "ec2:Describe*",
      "Resource": "*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "nat_instance" {
  role       = "${aws_iam_role.nat_instance.name}"
  policy_arn = "${aws_iam_policy.nat_instance.arn}"
}

resource "aws_iam_instance_profile" "nat_instance" {
  name = "${var.name}-nat-instance"
  role = "${aws_iam_role.nat_instance.name}"
}

resource "aws_instance" "nat_instance_with_profile" {
  count             = "${(0 + var.use_nat_instances) * length(var.internal_subnets)}"
  availability_zone = "${element(var.availability_zones, count.index)}"

  tags {
    Name        = "${var.name}-${format("internal-%03d NAT", count.index+1)}"
    Environment = "${var.environment}"
  }

  volume_tags {
    Name        = "${var.name}-${format("internal-%03d NAT", count.index+1)}"
    Environment = "${var.environment}"
  }

  key_name               = "${var.nat_instance_ssh_key_name}"
  ami                    = "${data.aws_ami.nat_ami.id}"
  instance_type          = "${var.nat_instance_type}"
  source_dest_check      = false
  vpc_security_group_ids = ["${aws_security_group.nat_instances.id}"]
  iam_instance_profile {
    name = "${aws_iam_instance_profile.nat_instance.name}"
  }
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  ebs_block_device {
    device_name = "/dev/sda1"
    encrypted   = true
  }

  subnet_id = "${element(aws_subnet.external.*.id, count.index)}"

  lifecycle {
    ignore_changes = ["ami"]
  }
}

output "id" {
  value = "${aws_vpc.main.id}"
}

output "cidr_block" {
  value = "${aws_vpc.main.cidr_block}"
}

output "external_subnets" {
  value = ["${aws_subnet.external.*.id}"]
}

output "internal_subnets" {
  value = ["${aws_subnet.internal.*.id}"]
}

output "security_group" {
  value = "${aws_vpc.main.default_security_group_id}"
}

output "availability_zones" {
  value = ["${aws_subnet.external.*.availability_zone}"]
}

output "internal_rtb_id" {
  value = "${join(",", aws_route_table.internal.*.id)}"
}

output "external_rtb_id" {
  value = "${aws_route_table.external.id}"
}

output "internal_nat_ips" {
  value = ["${aws_eip.nat.*.public_ip}"]
}