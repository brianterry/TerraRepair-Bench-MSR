variable "azs" {}
variable "cidr" {}
variable "hyperkube-tag" {}
variable "depends-id" {}
variable "name" {}
variable "region" {}

output "depends-id" { value = "${null_resource.dummy_dependency.id}" }
output "gateway-id" { value = "${ aws_internet_gateway.main.id }" }
output "id" { value = "${ aws_vpc.main.id }" }
output "route-table-id" { value = "${ aws_route_table.private.id }" }
output "subnet-ids-private" { value = "${ join(",", aws_subnet.private.*.id) }" }
output "subnet-ids-public" { value = "${ join(",", aws_subnet.public.*.id) }" }


resource "aws_eip" "nat" { vpc = true }

resource "aws_nat_gateway" "nat" {
  depends_on = [
    "aws_eip.nat",
    "aws_internet_gateway.main",
  ]

  allocation_id = "${ aws_eip.nat.id }"
  subnet_id = "${ aws_subnet.public.0.id }"
}

resource "aws_subnet" "private" {
  count = "${ length( split(",", var.azs) ) }"

  availability_zone = "${ element( split(",", var.azs), count.index ) }"
  cidr_block = "${ cidrsubnet(var.cidr, 8, count.index + 10) }"
  vpc_id = "${ aws_vpc.main.id }"

  tags {
    "kubernetes.io/role/internal-elb" = "${ var.name }"
    builtWith = "terraform"
    KubernetesCluster = "${ var.name }"
    kz8s = "${ var.name }"
    Name = "kz8s-${ var.name }-private"
    visibility = "private"
  }
}

resource "aws_route_table" "private" {
  vpc_id = "${ aws_vpc.main.id }"

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = "${ aws_nat_gateway.nat.id }"
  }

  tags {
    builtWith = "terraform"
    KubernetesCluster = "${ var.name }"
    kz8s = "${ var.name }"
    Name = "kz8s-${ var.name }"
    visibility = "private"
  }
}

resource "aws_route_table_association" "private" {
  count = "${ length(split(",", var.azs)) }"

  route_table_id = "${ aws_route_table.private.id }"
  subnet_id = "${ element(aws_subnet.private.*.id, count.index) }"
}


resource "aws_internet_gateway" "main" {
  vpc_id = "${ aws_vpc.main.id }"

  tags {
    builtWith = "terraform"
    KubernetesCluster = "${ var.name }"
    kz8s = "${ var.name }"
    Name = "kz8s-${ var.name }"
    version = "${ var.hyperkube-tag }"
  }
}

resource "aws_subnet" "public" {
  count = "${ length( split(",", var.azs) ) }"

  availability_zone = "${ element( split(",", var.azs), count.index ) }"
  cidr_block = "${ cidrsubnet(var.cidr, 8, count.index) }"
  vpc_id = "${ aws_vpc.main.id }"

  tags {
    "kubernetes.io/role/elb" = "${ var.name }"
    builtWith = "terraform"
    KubernetesCluster = "${ var.name }"
    kz8s = "${ var.name }"
    Name = "kz8s-${ var.name }-public"
    version = "${ var.hyperkube-tag }"
    visibility = "public"
  }
}

resource "aws_route" "public" {
  route_table_id = "${ aws_vpc.main.main_route_table_id }"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = "${ aws_internet_gateway.main.id }"
}

resource "aws_route_table_association" "public" {
  count = "${ length(split(",", var.azs)) }"

  route_table_id = "${ aws_vpc.main.main_route_table_id }"
  subnet_id = "${ element(aws_subnet.public.*.id, count.index) }"
}

resource "aws_vpc" "main" {
  cidr_block = "${ var.cidr }"

  enable_dns_hostnames = true
  enable_dns_support = true
  enable_flow_logs = true

  flow_log {
    log_destination_type = "cloud_watch_logs"
    log_destination = "arn:aws:logs:${var.region}:123456789012:log-group:/vpc-flow-logs"
    traffic = "REJECT"
  }

  tags {
    builtWith = "terraform"
    KubernetesCluster = "${ var.name }"
    kz8s = "${ var.name }"
    Name = "kz8s-${ var.name }"
    version = "${ var.hyperkube-tag }"
    visibility = "private,public"
  }
}

resource "aws_security_group" "default" {
  name = "default"
  description = "Default security group for VPC"
  vpc_id = "${ aws_vpc.main.id }"

  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = merge(
    {
      "Name" = "default"
    },
    aws_vpc.main.tags
  )
}

resource "null_resource" "dummy_dependency" {
  depends_on = [
    "aws_vpc.main",
    "aws_nat_gateway.nat"
  ]
}