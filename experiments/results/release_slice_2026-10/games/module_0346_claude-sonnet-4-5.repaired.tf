provider "aws" {
  region = "${var.vpc_aws_region}"
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "aws_vpc" "vpc" {
  cidr_block           = "${var.vpc_cidr}"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags {
    Name = "${var.vpc_name}"
  }
}

resource "aws_flow_log" "vpc_flow_log" {
  iam_role_arn    = "${aws_iam_role.vpc_flow_log_role.arn}"
  log_destination = "${aws_cloudwatch_log_group.vpc_flow_log_group.arn}"
  traffic_type    = "REJECT"
  vpc_id          = "${aws_vpc.vpc.id}"
}

resource "aws_cloudwatch_log_group" "vpc_flow_log_group" {
  name = "/aws/vpc/${var.vpc_name}-flow-logs"
}

resource "aws_iam_role" "vpc_flow_log_role" {
  name = "${var.vpc_name}-vpc-flow-log-role"

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

resource "aws_iam_role_policy" "vpc_flow_log_policy" {
  name = "${var.vpc_name}-vpc-flow-log-policy"
  role = "${aws_iam_role.vpc_flow_log_role.id}"

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

resource "aws_default_security_group" "default" {
  vpc_id = "${aws_vpc.vpc.id}"
}

resource "aws_route53_zone" "priv_zone" {
  name    = "${var.base_domain}"
  vpc_id  = "${aws_vpc.vpc.id}"
  comment = "Managed by Terraform"

  tags {
    Name = "${var.vpc_name}"
  }
}

resource "aws_cloudwatch_log_group" "route53_query_log_group" {
  name = "/aws/route53/${var.vpc_name}-query-logs"
}

resource "aws_route53_query_log" "priv_zone_query_log" {
  cloudwatch_log_group_arn = "${aws_cloudwatch_log_group.route53_query_log_group.arn}"
  zone_id                  = "${aws_route53_zone.priv_zone.id}"
}

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags {
    Name = "${var.vpc_name}-igw"
  }
}

resource "aws_eip" "natgw" {
  vpc = true
}

resource "aws_nat_gateway" "natgw" {
  allocation_id = "${aws_eip.natgw.id}"
  subnet_id     = "${aws_subnet.pub_subnet_generic.id}"
  depends_on    = ["aws_internet_gateway.igw"]
}

resource "aws_subnet" "pub_subnet_generic" {
  vpc_id = "${aws_vpc.vpc.id}"

  availability_zone       = "${data.aws_availability_zones.available.names[0]}"
  cidr_block              = "10.0.255.0/24"
  map_public_ip_on_launch = false

  tags {
    Name = "${var.vpc_name}-vpn"
  }
}

resource "aws_route_table_association" "pub_subnet_generic" {
  subnet_id      = "${aws_subnet.pub_subnet_generic.id}"
  route_table_id = "${aws_route_table.pub_rt.id}"
}

resource "aws_route_table" "pub_rt" {
  vpc_id = "${aws_vpc.vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }

  tags {
    Name = "${var.vpc_name}-public"
  }
}

resource "aws_subnet" "priv_subnet" {
  count             = "${var.subnet_count}"
  vpc_id            = "${aws_vpc.vpc.id}"
  availability_zone = "${element(data.aws_availability_zones.available.names, count.index)}"
  cidr_block        = "${cidrsubnet(var.vpc_cidr, 8, count.index + 100)}"

  tags {
    Name = "${var.vpc_name}-${count.index}"
  }
}

resource "aws_route_table_association" "priv_subnet" {
  count          = "${var.subnet_count}"
  subnet_id      = "${aws_subnet.priv_subnet.*.id[count.index]}"
  route_table_id = "${aws_route_table.priv_rt.id}"
}

resource "aws_route_table" "priv_rt" {
  vpc_id           = "${aws_vpc.vpc.id}"
  propagating_vgws = ["${aws_vpn_gateway.vpg.id}"]

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = "${aws_nat_gateway.natgw.id}"
  }

  route {
    cidr_block = "${var.local_network_cidr}"
    gateway_id = "${aws_vpn_gateway.vpg.id}"
  }

  tags {
    Name = "${var.vpc_name}-private"
  }
}


variable vpc_name {
  description = "The name of the VPC to identify created resources."
}

variable base_domain {
  default     = "tectonic-ci.de"
  description = "The base domain for this cluster's FQDN"
}

variable vpc_aws_region {
  description = "The target AWS region for the cluster"
}

variable vpc_cidr {
  default     = "10.0.0.0/16"
  description = "The CIDR range used for your entire VPC"
}

variable subnet_count {
  default     = 4
  description = "Number of private subnets to pre-create"
}

variable local_network_cidr {
  default     = "10.7.0.0/16"
  description = "IP range in the network your laptop is on (dosn't actually matter unless your instances need to connect to the local network your laptop is on)"
}

variable ovpn_password {
  default     = "PASSWORD"
  description = "password to use when connecting"
}

variable ssh_allowed_cidr {
  default     = "10.0.0.0/8"
  description = "CIDR block allowed to SSH to the VPN instance"
}

output "ovpn_url" {
  value = "https://${aws_eip.ovpn_eip.public_ip}:443"
}

output "base_domain" {
  value = "${var.base_domain}"
}

output "private_zone_id" {
  value = "${aws_route53_zone.priv_zone.id}"
}

output "vpc_id" {
  value = "${aws_vpc.vpc.id}"
}

output "vpc_dns" {
  value = "${cidrhost(var.vpc_cidr, 2)}"
}

output "subnets" {
  value = "${aws_subnet.priv_subnet.*.id}"
}


data "aws_ami" "openvpn_ami" {
  most_recent = true
  owners      = ["679593333241"]

  filter {
    name   = "name"
    values = ["OpenVPN Access Server*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "owner-id"
    values = ["679593333241"]
  }
}

resource "aws_vpn_gateway" "vpg" {
  vpc_id = "${aws_vpc.vpc.id}"

  availability_zone = "${data.aws_availability_zones.available.names[0]}"

  tags {
    Name = "${var.vpc_name}-vpg"
  }
}

resource "aws_iam_role" "ovpn_role" {
  name = "${var.vpc_name}-ovpn-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "ovpn_profile" {
  name = "${var.vpc_name}-ovpn-profile"
  role = "${aws_iam_role.ovpn_role.name}"
}

resource "aws_instance" "ovpn" {
  availability_zone           = "${data.aws_availability_zones.available.names[0]}"
  ami                         = "${data.aws_ami.openvpn_ami.image_id}"
  instance_type               = "t2.micro"
  subnet_id                   = "${aws_subnet.pub_subnet_generic.id}"
  vpc_security_group_ids      = ["${aws_security_group.vpn_sg.id}"]
  iam_instance_profile        = "${aws_iam_instance_profile.ovpn_profile.name}"
  ebs_optimized               = true
  monitoring                  = true

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted = true
  }

  user_data = <<EOF
public_hostname=${aws_eip.ovpn_eip.public_ip}
admin_user=openvpn
admin_pw=${var.ovpn_password}
reroute_gw=1
reroute_dns=1
EOF

  depends_on = ["aws_eip.ovpn_eip"]

  tags {
    Name = "${var.vpc_name}-ovpn-server"
  }
}

resource "aws_eip" "ovpn_eip" {
  vpc = true
}

resource "aws_eip_association" "vpn_eip_assoc" {
  instance_id   = "${aws_instance.ovpn.id}"
  allocation_id = "${aws_eip.ovpn_eip.id}"
}

resource "aws_security_group" "vpn_sg" {
  name        = "ovpn-server-sg"
  description = "Allow all inbound traffic"
  vpc_id      = "${aws_vpc.vpc.id}"

  ingress {
    description = "OpenVPN Admin UI"
    from_port   = 943
    to_port     = 943
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.ssh_allowed_cidr}"]
  }

  ingress {
    description = "HTTPS access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "OpenVPN TCP"
    from_port   = 943
    to_port     = 943
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "OpenVPN UDP"
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP outbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS outbound"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "VPN traffic"
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${var.vpc_name}-ovpn-sg"
  }
}

resource "aws_customer_gateway" "customer_gateway" {
  bgp_asn    = 65000
  ip_address = "${aws_eip.ovpn_eip.public_ip}"
  type       = "ipsec.1"

  tags {
    Name = "${var.vpc_name}-customer-gateway"
  }
}

resource "aws_vpn_connection" "main" {
  vpn_gateway_id      = "${aws_vpn_gateway.vpg.id}"
  customer_gateway_id = "${aws_customer_gateway.customer_gateway.id}"
  type                = "ipsec.1"
  static_routes_only  = true

  tags {
    Name = "${var.vpc_name}-vpn-conn"
  }
}