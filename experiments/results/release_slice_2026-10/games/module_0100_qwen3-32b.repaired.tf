provider "aws" {
  region = "us-east-1"
}

terraform {
  required_version = ">= 1.0"

  backend "local" {
    path = "staging/vpc/terraform.tfstate"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.62"
    }
  }
}


resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "staging-main"
  }

  flow_logs {
    destination = "cloud-watch-logs"
    log_group_arn = "arn:aws:logs:us-east-1:123456789012:log-group:/vpc-flow-logs"
    log_destination_type = "cloud-watch-logs"
    log_format = "{\"version\":\"1\",\"log_status\":\"{status}\",\"account_id\":\"{owner_id}\",\"interface_id\":\"{interface_id}\",\"srcaddr\":\"{srcaddr}\",\"dstaddr\":\"{dstaddr}\",\"srcport\":\"{srcport}\",\"dstport\":\"{dstport}\",\"protocol\":\"{protocol}\",\"tcp_flags\":\"{tcp_flags}\",\"type\":\"{type}\",\"size\":\"{size}\",\"src_asn\":\"{src_asn}\",\"dst_asn\":\"{dst_asn}\",\"src_region\":\"{src_region}\",\"dst_region\":\"{dst_region}\",\"direction\":\"{direction}\"}"
    log_group_name = "/vpc-flow-logs"
    log_stream_name = "{vpc_id}"
    max_aggregation_interval = 600
    traffic_type = "REJECTS"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "staging-igw"
  }
}


resource "aws_subnet" "private_us_east_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.0/19"
  availability_zone = "us-east-1a"

  tags = {
    "Name"                               = "staging-private-us-east-1a"
    "kubernetes.io/role/internal-elb"    = "1"
    "kubernetes.io/cluster/staging-demo" = "owned"
  }
}

resource "aws_subnet" "private_us_east_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.32.0/19"
  availability_zone = "us-east-1b"

  tags = {
    "Name"                               = "staging-private-us-east-1b"
    "kubernetes.io/role/internal-elb"    = "1"
    "kubernetes.io/cluster/staging-demo" = "owned"
  }
}

resource "aws_subnet" "public_us_east_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.64.0/19"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    "Name"                               = "staging-public-us-east-1a"
    "kubernetes.io/role/elb"             = "1"
    "kubernetes.io/cluster/staging-demo" = "owned"
  }
}

resource "aws_subnet" "public_us_east_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.96.0/19"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    "Name"                               = "staging-public-us-east-1b"
    "kubernetes.io/role/elb"             = "1"
    "kubernetes.io/cluster/staging-demo" = "owned"
  }
}


resource "aws_eip" "nat" {
  vpc = true

  tags = {
    Name = "staging-nat"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_us_east_1a.id

  tags = {
    Name = "staging-nat"
  }

  depends_on = [aws_internet_gateway.igw]
}


resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "staging-private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "staging-public"
  }
}

resource "aws_route_table_association" "private_us_east_1a" {
  subnet_id      = aws_subnet.private_us_east_1a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_us_east_1b" {
  subnet_id      = aws_subnet.private_us_east_1b.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "public_us_east_1a" {
  subnet_id      = aws_subnet.public_us_east_1a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_us_east_1b" {
  subnet_id      = aws_subnet.public_us_east_1b.id
  route_table_id = aws_route_table.public.id
}


output "vpc_id" {
  value = aws_vpc.main.id
}