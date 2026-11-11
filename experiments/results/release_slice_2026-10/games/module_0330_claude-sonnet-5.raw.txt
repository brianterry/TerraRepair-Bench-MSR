# create vpc
resource "aws_vpc" "main" {
  count = var.needs_network ? 1 : 0
  cidr_block = "10.0.0.0/16"

  assign_generated_ipv6_cidr_block = true
  enable_dns_hostnames = true # need to be enabled in order for publicly accessible RDS instance finding to work
  enable_dns_support = true # need to be enabled in order for publicly accessible RDS instance finding to work

  tags = {
    Name = "${var.name}_vpc"
  }
}

resource "aws_default_security_group" "main" {
  count  = var.needs_network ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  ingress = []
  egress  = []
}

resource "aws_flow_log" "main" {
  count           = var.needs_network ? 1 : 0
  iam_role_arn    = aws_iam_role.flow_log[0].arn
  log_destination = aws_cloudwatch_log_group.flow_log[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main[0].id
}

resource "aws_cloudwatch_log_group" "flow_log" {
  count = var.needs_network ? 1 : 0
  name  = "/vpc/flow-log/${var.name}"
}

resource "aws_iam_role" "flow_log" {
  count = var.needs_network ? 1 : 0
  name  = "${var.name}-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "flow_log" {
  count = var.needs_network ? 1 : 0
  name  = "${var.name}-flow-log-policy"
  role  = aws_iam_role.flow_log[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}

# grab AZs
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

# create subnet
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

# create internet gateway
resource "aws_internet_gateway" "main" {
  count = var.needs_network ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  tags = {
    Name = "${var.name}_ig"
  }
}

# create route table
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

# associate route table with subnet
resource "aws_route_table_association" "main" {
  count = var.needs_network ? 1 : 0
  subnet_id      = aws_subnet.main[0].id
  route_table_id = aws_route_table.main[0].id
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