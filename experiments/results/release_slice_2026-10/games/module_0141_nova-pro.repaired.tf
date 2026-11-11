terraform {
  required_version = ">= 0.12.0"
}

variable "letters" {
  description = "a list of letters"
  default = ["a", "b", "c"]
}

output "upper-case-list" {
  value = [for l in var.letters: upper(l)]
}

output "upper-case-map" {
  value = {for l in var.letters: l => upper(l)}
}

terraform {
  required_version = ">= 0.12.0"
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "my_vpc" {
  cidr_block = "172.16.0.0/16"

  tags = {
    Name = "tf-0.12-for-example"
  }

  enable_flow_log = true
}

resource "aws_subnet" "my_subnet" {
  vpc_id = aws_vpc.my_vpc.id
  cidr_block = "172.16.10.0/24"

  tags = {
    Name = "tf-0.12-for-example"
  }
}

data "aws_ami" "ubuntu_14_04" {
  most_recent      = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm/ubuntu-trusty-14.04-amd64-server-*"]
  }

  owners     = ["099720109477"]
}

resource "aws_instance" "ubuntu" {
  count = 3
  ami = data.aws_ami.ubuntu_14_04.image_id
  instance_type = "t2.micro"
  associate_public_ip_address = ( count.index == 1 ? true : false)
  subnet_id = aws_subnet.my_subnet.id
  ebs_optimized = true
  monitoring = true
  metadata_options {
    http_tokens = "required"
    http_endpoint = true
    http_put_response_hop_limit = 2
  }
  root_block_device {
    volume_type = "gp2"
    volume_size = 8
    encrypted = true
  }

  tags = {
    Name  = format("terraform-0.12-for-demo-%d", count.index)
  }
}

output "private_addresses_old" {
  value = aws_instance.ubuntu.*.private_dns
}

output "private_addresses_full_splat" {
  value = [ aws_instance.ubuntu[*].private_dns ]
}

output "private_addresses_new" {
  value = [
    for instance in aws_instance.ubuntu:
    instance.private_dns
  ]
}

output "ips_with_list_interpolation" {
  value = [
    for instance in aws_instance.ubuntu:
    (instance.public_ip!= ""? list(instance.private_ip, instance.public_ip) : list(instance.private_ip))
  ]
}

output "ips_with_list_in_brackets" {
  value = [
    for instance in aws_instance.ubuntu:
    (instance.public_ip!= ""? [instance.private_ip, instance.public_ip] : [instance.private_ip])
  ]
}