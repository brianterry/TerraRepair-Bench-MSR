provider "aws" {
  region = "${var.vpc_aws_region}"
}

# Declare the data source
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "vpc" {
  cidr_block           = "${var.vpc_cidr}"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags {
    Name = "${var.vpc_name}"
  }
}

data "aws_ami" "coreos_ami" {
  most_recent = true
  owners      = ["190570271432"]

  filter {
    name   = "name"
    values = ["CoreOS-stable-*"]
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
    values = ["190570271432"]
  }
}

resource "aws_instance" "bastion" {
  # 1st available AZ
  availability_zone      = "${data.aws_availability_zones.available.names[0]}"
  ami                    = "${data.aws_ami.coreos_ami.image_id}"
  instance_type          = "${var.instance_type}"
  subnet_id              = "${aws_subnet.pub_subnet_generic.id}"
  vpc_security_group_ids = ["${compact(concat(list(aws_security_group.powerdns.id), list(aws_security_group.vpn_sg.id)))}"]
  source_dest_check      = false
  key_name               = "${var.ssh_key}"
  user_data              = "${data.ignition_config.main.rendered}"
  ebs_optimized          = true
  monitoring             = true

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted = true
  }

  depends_on = ["aws_eip.ovpn_eip"]

  tags {
    Name = "${var.vpc_name}-server"
  }
}

data "ignition_config" "main" {
  files = ["${data.ignition_file.nginx_conf.id}"]

  systemd = ["${compact(list(
    data.ignition_systemd_unit.gateway_service.id,
    data.ignition_systemd_unit.nginx_service.id,
    data.ignition_systemd_unit.openvpn_service.id,
    data.ignition_systemd_unit.powerdns_service.id,
    data.ignition_systemd_unit.update-engine.id,
    data.ignition_systemd_unit.locksmithd.id,
   ))}"]
}

data "ignition_systemd_unit" "update-engine" {
  name = "update-engine.service"
  mask = true
}

data "ignition_systemd_unit" "locksmithd" {
  name = "locksmithd.service"
  mask = true
}

# IGW
resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags {
    Name = "${var.vpc_name}-igw"
  }
}

# General purpose public subnet. used for OVPN access and IGW/NAT attachment.
resource "aws_subnet" "pub_subnet_generic" {
  vpc_id = "${aws_vpc.vpc.id}"

  # 1st available AZ
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

# public subnet route table
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

# private subnets
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

# private subnet route table
resource "aws_route_table" "priv_rt" {
  vpc_id           = "${aws_vpc.vpc.id}"
  propagating_vgws = ["${aws_vpn_gateway.vpg.id}"]

  route {
    cidr_block  = "0.0.0.0/0"
    instance_id = "${aws_instance.bastion.id}"
  }

  route {
    cidr_block = "${var.local_network_cidr}"
    gateway_id = "${aws_vpn_gateway.vpg.id}"
  }

  tags {
    Name = "${var.vpc_name}-private"
  }
}


# Security Group
resource "aws_security_group" "powerdns" {
  vpc_id      = "${aws_vpc.vpc.id}"
  description = "Security group for PowerDNS service"
}

resource "aws_security_group_rule" "powerdns_egress" {
  type              = "egress"
  security_group_id = "${aws_security_group.powerdns.id}"
  description       = "Allow outbound traffic within the VPC"

  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["${var.vpc_cidr}"]
}

resource "aws_security_group_rule" "powerdns_ingress_ssh" {
  type              = "ingress"
  security_group_id = "${aws_security_group.powerdns.id}"
  description       = "Allow SSH access from trusted network"

  protocol    = "tcp"
  cidr_blocks = ["${var.local_network_cidr}"]
  from_port   = 22
  to_port     = 22
}

resource "aws_security_group_rule" "powerdns_ingress_http" {
  type              = "ingress"
  security_group_id = "${aws_security_group.powerdns.id}"
  description       = "Allow HTTP access from trusted network"

  protocol    = "tcp"
  cidr_blocks = ["${var.local_network_cidr}"]
  from_port   = 80
  to_port     = 80
}

resource "aws_security_group_rule" "powerdns_ingress_https" {
  type              = "ingress"
  security_group_id = "${aws_security_group.powerdns.id}"
  description       = "Allow HTTPS access"

  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  from_port   = 443
  to_port     = 443
}

resource "aws_security_group_rule" "powerdns_ingress_api" {
  type              = "ingress"
  security_group_id = "${aws_security_group.powerdns.id}"
  description       = "Allow access to PowerDNS API"

  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  from_port   = 8081
  to_port     = 8081
}

resource "aws_security_group_rule" "powerdns_ingress_dns" {
  type              = "ingress"
  security_group_id = "${aws_security_group.powerdns.id}"
  description       = "Allow DNS TCP queries"

  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  from_port   = 53
  to_port     = 53
}

resource "aws_security_group_rule" "powerdns_ingress_dns_udp" {
  type              = "ingress"
  security_group_id = "${aws_security_group.powerdns.id}"
  description       = "Allow DNS UDP queries"

  protocol    = "udp"
  cidr_blocks = ["0.0.0.0/0"]
  from_port   = 53
  to_port     = 53
}


data "template_file" "gateway_service" {
  template = "${file("${path.module}/resources/gateway.service")}"

  vars {
    private_cidr = "${cidrsubnet(var.vpc_cidr, 6, 25)}"
  }
}

data "ignition_systemd_unit" "gateway_service" {
  name    = "gateway.service"
  enabled = true
  content = "${data.template_file.gateway_service.rendered}"
}

data "template_file" "nginx_service" {
  template = "${file("${path.module}/resources/nginx.service")}"

  vars {
    username    = "${var.nginx_username}"
    password    = "${var.nginx_password}"
    nginx_image = "${var.container_images["nginx"]}"
  }
}

data "ignition_systemd_unit" "nginx_service" {
  name    = "nginx.service"
  enabled = true
  content = "${data.template_file.nginx_service.rendered}"
}

data "template_file" "nginx_conf" {
  template = "${file("${path.module}/resources/nginx.conf")}"
}

data "ignition_file" "nginx_conf" {
  filesystem = "root"
  path       = "/home/core/nginx-config/default.conf"
  mode       = 0644

  content {
    content = "${data.template_file.nginx_conf.rendered}"
  }
}

data "template_file" "openvpn_service" {
  template = "${file("${path.module}/resources/openvpn.service")}"

  vars {
    ip            = "${aws_eip.ovpn_eip.public_ip}"
    openvpn_image = "${var.container_images["openvpn"]}"
  }
}

data "ignition_systemd_unit" "openvpn_service" {
  name    = "openvpn.service"
  enabled = true
  content = "${data.template_file.openvpn_service.rendered}"
}

data "template_file" "powerdns_service" {
  template = "${file("${path.module}/resources/powerdns.service")}"

  vars {
    dns_zone       = "${var.base_domain}"
    pdns_api_key   = "${var.pdns_api_key}"
    mysql_password = "${var.mysql_password}"
    powerdns_image = "${var.container_images["powerdns"]}"
    mysql_image    = "${var.container_images["mysql"]}"
  }
}

data "ignition_systemd_unit" "powerdns_service" {
  name    = "powerdns.service"
  enabled = true
  content = "${data.template_file.powerdns_service.rendered}"
}


# placeholders for access_key / secret_key
# should be fed through env var or variable file
# https://www.terraform.io/docs/configuration/variables.html

variable "vpc_name" {
  description = "The name of the VPC to identify created resources."
  default     = "bastion"
}

variable "instance_type" {
  description = "The type of the ec2 machine."
  default     = "t2.micro"
}

variable "base_domain" {
  default     = "tectonic-ci.de"
  description = "The base domain for this cluster's FQDN"
}

variable "vpc_aws_region" {
  description = "The target AWS region for the cluster"
  default     = "us-gov-west-1"
}

variable "vpc_cidr" {
  default     = "10.0.0.0/16"
  description = "The CIDR range used for your entire VPC"
}

variable "subnet_count" {
  default     = 4
  description = "Number of private subnets to pre-create"
}

variable "local_network_cidr" {
  default     = "10.7.0.0/16"
  description = "IP range in the network your laptop is on (dosn't actually matter unless your instances need to connect to the local network your laptop is on)"
}

variable "ssh_key" {
  description = "Name of an SSH key located within the AWS region. Example: coreos-user."
  default     = ""
}

variable "nginx_username" {
  description = "Used for retrieving the OpenVPN client config file."
}

variable "nginx_password" {
  description = "Used for retrieving the OpenVPN client config file."
}

variable "mysql_password" {
  description = "Used as PowerDNS backend."
}

variable "pdns_api_key" {
  description = "Used by clients to communicate with the PowerDNS API."
}

variable "container_images" {
  description = "Container images to use"
  type        = "map"

  default = {
    powerdns = "quay.io/coreos/pdns:20678f8bffc316579367d885ca4fcb229b1dbc1d"
    mysql    = "quay.io/coreos/mysql:5.7.21"
    openvpn  = "quay.io/coreos/openvpn:2.4"
    nginx    = "quay.io/coreos/nginx:1.13.7-alpine"
  }
}

output "ovpn_url" {
  value = "http://${aws_eip.ovpn_eip.public_ip}"
}

output "base_domain" {
  value = "${var.base_domain}"
}

output "vpc_id" {
  value = "${aws_vpc.vpc.id}"
}

output "vpc_dns_ip" {
  value = "${aws_instance.bastion.private_ip}"
}

output "dns_api_url" {
  value = "http://${aws_instance.bastion.private_ip}:8081"
}

output "subnets" {
  value = "${aws_subnet.priv_subnet.*.id}"
}


resource "aws_vpn_gateway" "vpg" {
  vpc_id = "${aws_vpc.vpc.id}"

  # 1st available AZ
  availability_zone = "${data.aws_availability_zones.available.names[0]}"

  tags {
    Name = "${var.vpc_name}-vpg"
  }
}

resource "aws_eip" "ovpn_eip" {
  vpc = true
}

resource "aws_eip_association" "vpn_eip_assoc" {
  instance_id   = "${aws_instance.bastion.id}"
  allocation_id = "${aws_eip.ovpn_eip.id}"
}

resource "aws_security_group" "vpn_sg" {
  name        = "ovpn-server-sg"
  description = "Allow required inbound and outbound traffic for OpenVPN server"
  vpc_id      = "${aws_vpc.vpc.id}"

  ingress {
    description = "Allow TCP traffic from internal private subnet range"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["${cidrsubnet(var.vpc_cidr, 6, 25)}"]
  }

  ingress {
    description = "Allow OpenVPN admin UI access"
    from_port   = 943
    to_port     = 943
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH access from trusted network"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.local_network_cidr}"]
  }

  ingress {
    description = "Allow HTTP access from trusted network"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${var.local_network_cidr}"]
  }

  ingress {
    description = "Allow HTTPS access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow OpenVPN admin UI access (duplicate)"
    from_port   = 943
    to_port     = 943
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow OpenVPN UDP traffic"
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound traffic within the VPC"
    from_port = 0
    to_port   = 0

    # all
    protocol    = "-1"
    cidr_blocks = ["${var.vpc_cidr}"]
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