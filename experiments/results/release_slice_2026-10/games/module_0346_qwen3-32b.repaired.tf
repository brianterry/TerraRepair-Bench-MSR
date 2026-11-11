provider "aws" {
  region = var.vpc_aws_region
}

# Declare the data source
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.vpc_name
  }
}

# VPC Flow Logs
resource "aws_flow_log" "vpc_flow_log" {
  iam_role_arn = aws_iam_role.flow_log_role.arn
  resource_id  = aws_vpc.vpc.id
  traffic_type = "REJECT"

  log_destination_type = "cloudwatch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_log_group.arn
}

resource "aws_iam_role" "flow_log_role" {
  name = "flow_log_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "flow_log_role_policy" {
  role       = aws_iam_role.flow_log_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_cloudwatch_log_group" "flow_log_group" {
  name = "/aws/vpc/flow-logs/${var.vpc_name}"
}

# Private DNS zone
resource "aws_route53_zone" "priv_zone" {
  name    = var.base_domain
  vpc_id  = aws_vpc.vpc.id
  comment = "Managed by Terraform"

  tags = {
    Name = var.vpc_name
  }

  query_logging_config {
    cloudwatch_log_log_group_arn = aws_cloudwatch_log_group.dns_query_log.arn
  }

  dnssec {
    signing_status = "ENABLE"
  }
}

resource "aws_cloudwatch_log_group" "dns_query_log" {
  name = "/aws/route53/${var.base_domain}"
}

# IGW
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

# NAT Gateway
resource "aws_eip" "natgw" {
  vpc = true
}

resource "aws_nat_gateway" "natgw" {
  allocation_id = aws_eip.natgw.id
  subnet_id     = aws_subnet.pub_subnet_generic.id
  depends_on    = [aws_internet_gateway.igw]
}

# General purpose public subnet. used for OVPN access and IGW/NAT attachment.
resource "aws_subnet" "pub_subnet_generic" {
  vpc_id = aws_vpc.vpc.id

  # 1st available AZ
  availability_zone       = data.aws_availability_zones.available.names[0]
  cidr_block              = "10.0.255.0/24"
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.vpc_name}-vpn"
  }
}

resource "aws_route_table_association" "pub_subnet_generic" {
  subnet_id      = aws_subnet.pub_subnet_generic.id
  route_table_id = aws_route_table.pub_rt.id
}

# public subnet route table
resource "aws_route_table" "pub_rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.vpc_name}-public"
  }
}

# private subnets
resource "aws_subnet" "priv_subnet" {
  count             = var.subnet_count
  vpc_id            = aws_vpc.vpc.id
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 100)

  tags = {
    Name = "${var.vpc_name}-${count.index}"
  }
}

resource "aws_route_table_association" "priv_subnet" {
  count          = var.subnet_count
  subnet_id      = element(aws_subnet.priv_subnet.*.id, count.index)
  route_table_id = aws_route_table.priv_rt.id
}

# private subnet route table
resource "aws_route_table" "priv_rt" {
  vpc_id           = aws_vpc.vpc.id
  propagating_vgws = [aws_vpn_gateway.vpg.id]

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.natgw.id
  }

  route {
    cidr_block = var.local_network_cidr
    gateway_id = aws_vpn_gateway.vpg.id
  }

  tags = {
    Name = "${var.vpc_name}-private"
  }
}

# placeholders for access_key / secret_key
# should be fed through env var or variable file
# https://www.terraform.io/docs/configuration/variables.html

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

output "ovpn_url" {
  value = "https://${aws_eip.ovpn_eip.public_ip}:443"
}

output "base_domain" {
  value = var.base_domain
}

output "private_zone_id" {
  value = aws_route53_zone.priv_zone.id
}

output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "vpc_dns" {
  value = cidrhost(var.vpc_cidr, 2)
}

output "subnets" {
  value = aws_subnet.priv_subnet.*.id
}

# For details see https://docs.openvpn.net/how-to-tutorialsguides/virtual-platforms/amazon-ec2-appliance-ami-quick-start-guide
data "aws_ami" "openvpn_ami" {
  most_recent = true

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
  vpc_id = aws_vpc.vpc.id

  # 1st available AZ
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.vpc_name}-vpg"
  }
}

resource "aws_instance" "ovpn" {
  # 1st available AZ
  availability_zone      = data.aws_availability_zones.available.names[0]
  ami                    = data.aws_ami.openvpn_ami.image_id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.pub_subnet_generic.id
  vpc_security_group_ids = [aws_security_group.vpn_sg.id]
  ebs_optimized          = true
  metadata_options {
    http_tokens          = "required"
    http_endpoint        = "enabled"
    http_put_response_hop_limit = 2
  }

  user_data = <<EOF
public_hostname=${aws_eip.ovpn_eip.public_ip}
admin_user=openvpn
admin_pw=${var.ovpn_password}
reroute_gw=1
reroute_dns=1
EOF

  depends_on = [aws_eip.ovpn_eip]

  tags = {
    Name = "${var.vpc_name}-ovpn-server"
  }

  root_block_device {
    encrypted = true
  }
}

resource "aws_eip" "ovpn_eip" {
  vpc = true
}

resource "aws_eip_association" "vpn_eip_assoc" {
  instance_id   = aws_instance.ovpn.id
  allocation_id = aws_eip.ovpn_eip.id
}

resource "aws_security_group" "vpn_sg" {
  name        = "ovpn-server-sg"
  description = "Allow all inbound traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 943
    to_port     = 943
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow OpenVPN HTTPS"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["192.168.0.0/24"]
    description = "Allow SSH from internal network"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS"
  }

  ingress {
    from_port   = 943
    to_port     = 943
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow OpenVPN HTTPS again"
  }

  ingress {
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow OpenVPN UDP"
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all egress"
  }

  tags = {
    Name = "${var.vpc_name}-ovpn-sg"
  }
}

resource "aws_customer_gateway" "customer_gateway" {
  bgp_asn    = 65000
  ip_address = aws_eip.ovpn_eip.public_ip
  type       = "ipsec.1"

  tags = {
    Name = "${var.vpc_name}-customer-gateway"
  }
}

resource "aws_vpn_connection" "main" {
  vpn_gateway_id      = aws_vpn_gateway.vpg.id
  customer_gateway_id = aws_customer_gateway.customer_gateway.id
  type                = "ipsec.1"
  static_routes_only  = true

  tags = {
    Name = "${var.vpc_name}-vpn-conn"
  }
}

resource "aws_iam_instance_profile" "ovpn_profile" {
  name = "ovpn-instance-profile"
  role = aws_iam_role.ovpn_role.name
}

resource "aws_iam_role" "ovpn_role" {
  name = "ovpn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ovpn_role_policy" {
  role       = aws_iam_role.ovpn_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile_attachment" "ovpn_profile_attachment" {
  instance_profile = aws_iam_instance_profile.ovpn_profile.name
  instance_id      = aws_instance.ovpn.id
}