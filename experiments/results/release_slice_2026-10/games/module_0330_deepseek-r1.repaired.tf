resource "aws_vpc" "main" {
  count = var.needs_network ? 1 : 0
  cidr_block = "10.0.0.0/16"

  assign_generated_ipv6_cidr_block = true
  enable_dns_hostnames = true
  enable_dns_support = true

  tags = {
    Name = "${var.name}_vpc"
  }
}

data "aws_availability_zones" "available" {
  state                   = "available"
  all_availability_zones = true
}

resource "aws_subnet" "main" {
  count = var.needs_network ? 1 : 0
  vpc_id     = aws_vpc.main[0].id
  cidr_block = "10.0.3.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  map_public_ip_on_launch = true

  ipv6_cidr_block = cidrsubnet(aws_vpc.main[0].ipv6_cidr_block, 8, 1)
  assign_ipv6_address_on_creation = true

  tags = {
    Name = "${var.name}_subnet"
  }
}

resource "aws_subnet" "secondary" {
  count = var.needs_network ? 1 : 0
  vpc_id     = aws_vpc.main[0].id
  cidr_block = "10.0.4.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]
}

resource "aws_internet_gateway" "main" {
  count = var.needs_network ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  tags = {
    Name = "${var.name}_ig"
  }
}

resource "aws_route_table" "main" {
  count = var.needs_network ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  route {
      ipv6_cidr_block = "::/0"
      gateway_id = aws_internet_gateway.main[0].id
  }

  tags = {
    Name = "${var.name}_routes"
  }
}

resource "aws_route_table_association" "main" {
  count = var.needs_network ? 1 : 0
  subnet_id      = aws_subnet.main[0].id
  route_table_id = aws_route_table.main[0].id
}

resource "aws_default_security_group" "default" {
  count = var.needs_network ? 1 : 0
  vpc_id = aws_vpc.main[0].id
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count = var.needs_network ? 1 : 0
  name = "/aws/vpc/flowlogs"
}

resource "aws_flow_log" "vpc_flow_log" {
  count = var.needs_network ? 1 : 0
  vpc_id       = aws_vpc.main[0].id
  traffic_type = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_group_name = aws_cloudwatch_log_group.vpc_flow_logs[0].name
}

output "vpc_id" {
  description = "ID of created VPC"
  value       = length(aws_vpc.main) > 0 ? aws_vpc.main[0].id : null
}

output "vpc_cidr" {
  description = "CIDR of created VPC"
  value       = length(aws_vpc.main) > 0 ? aws_vpc.main[0].cidr_block : null
}

output "main_subnet_id" {
  description = "ID of created subnet"
  value       = length(aws_subnet.main) > 0 ? aws_subnet.main[0].id : null
}

output "secondary_subnet_id" {
  description = "ID of created secondary subnet"
  value       = length(aws_subnet.secondary) > 0 ? aws_subnet.secondary[0].id : null
}

output "subnet_cidr" {
  description = "CIDR of created subnet"
  value       = length(aws_vpc.main) > 0 ? aws_vpc.main[0].id : null
}

variable "name" {
  description = "Name for instances and group"
  type        = string
  default     = "sadcloud"
}

variable "needs_network" {
  description = "Do we need to create a network or not"
  type = bool
  default = false
}