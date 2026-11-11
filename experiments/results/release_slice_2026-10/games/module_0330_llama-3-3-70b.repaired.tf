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

resource "aws_security_group" "default" {
  count = var.needs_network ? 1 : 0
  vpc_id = aws_vpc.main[0].id
  name        = "default-sg"
  description = "Default security group"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}_default_sg"
  }
}

resource "aws_flow_log" "main" {
  count = var.needs_network ? 1 : 0
  iam_role_arn    = aws_iam_role.flow_log[0].arn
  log_destination = aws_cloudwatch_log_group.flow_log[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main[0].id
}

resource "aws_iam_role" "flow_log" {
  count = var.needs_network ? 1 : 0
  name        = "${var.name}_flow_log"
  description = "Flow log role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "flow_log" {
  count = var.needs_network ? 1 : 0
  name   = "${var.name}_flow_log_policy"
  role   = aws_iam_role.flow_log[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "flow_log" {
  count = var.needs_network ? 1 : 0
  name = "${var.name}_flow_log"
}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
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
  value       = length(aws_vpc.main) > 0 ? aws_vpc.main[0].cidr_block : null
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