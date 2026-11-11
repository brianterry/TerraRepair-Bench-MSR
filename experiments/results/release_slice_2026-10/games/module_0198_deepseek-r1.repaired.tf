data "aws_availability_zones" "this" {
  state = "available"
}

data "aws_vpc" "this" {
  default = var.vpc_id == "" ? true : false
  id      = var.vpc_id
}

data "aws_subnet" "this" {
  vpc_id            = data.aws_vpc.this.id
  availability_zone = local.availability_zone
}

resource "aws_instance" "this" {
  instance_type          = var.instance_type
  ami                    = var.instance_ami
  availability_zone      = local.availability_zone
  key_name               = aws_key_pair.this.id
  vpc_security_group_ids = [aws_security_group.this.id]
  subnet_id              = data.aws_subnet.this.id
  user_data              = sha1(local.reprovision_trigger)
  tags                   = merge(var.tags, { "Name" = var.hostname })
  volume_tags            = merge(var.tags, { "Name" = var.hostname })
  ebs_optimized          = true
  monitoring             = true

  root_block_device {
    volume_size = var.root_volume_size
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  connection {
    user        = var.ssh_username
    private_key = file(var.ssh_private_key_path)
    agent       = false
  }

  provisioner "remote-exec" {
    inline = [
      "sudo hostnamectl set-hostname ${var.hostname}",
      "echo 127.0.0.1 ${var.hostname} | sudo tee -a /etc/hosts",
    ]
  }

  provisioner "remote-exec" {
    script = "${path.module}/provision-docker.sh"
  }

  provisioner "file" {
    source      = "${path.module}/provision-swap.sh"
    destination = "/home/${var.ssh_username}/provision-swap.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sh /home/${var.ssh_username}/provision-swap.sh ${var.swap_file_size} ${var.swap_swappiness}",
      "rm /home/${var.ssh_username}/provision-swap.sh",
    ]
  }
}

resource "aws_volume_attachment" "this" {
  count       = var.data_volume_id == "" ? 0 : 1
  device_name = "/dev/xvdh"
  instance_id = aws_instance.this.id
  volume_id   = var.data_volume_id
}

resource "null_resource" "provisioners" {
  count      = var.data_volume_id == "" ? 0 : 1
  depends_on = [aws_volume_attachment.this]

  connection {
    host        = aws_instance.this.public_ip
    user        = var.ssh_username
    private_key = file(var.ssh_private_key_path)
    agent       = false
  }

  provisioner "remote-exec" {
    script = "${path.module}/provision-ebs.sh"
  }

  provisioner "remote-exec" {
    when   = "destroy"
    inline = ["sudo umount -v ${aws_volume_attachment.this[0].device_name}"]
  }
}

output "hostname" {
  value = var.hostname
}

output "public_ip" {
  value = aws_instance.this.public_ip
}

output "instance_id" {
  value = aws_instance.this.id
}

output "availability_zone" {
  value = local.availability_zone
}

output "ssh_username" {
  value = var.ssh_username
}

output "ssh_private_key_path" {
  value = var.ssh_private_key_path
}

output "ssh_private_key" {
  value = file(var.ssh_private_key_path)
}

output "security_group_id" {
  value = aws_security_group.this.id
}

resource "aws_key_pair" "this" {
  public_key = file(var.ssh_public_key_path)
}

resource "aws_security_group" "this" {
  vpc_id      = data.aws_vpc.this.id
  tags        = merge(var.tags, { "Name" = var.hostname })
  description = "Default security group for EC2 instance"
}

resource "aws_security_group_rule" "incoming_ssh" {
  security_group_id = aws_security_group.this.id
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [data.aws_vpc.this.cidr_block]
  description       = "Allow SSH access from VPC CIDR"
}

resource "aws_security_group_rule" "incoming_http" {
  count             = var.allow_incoming_http ? 1 : 0
  security_group_id = aws_security_group.this.id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "incoming_https" {
  count             = var.allow_incoming_https ? 1 : 0
  security_group_id = aws_security_group.this.id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "incoming_dns_tcp" {
  count             = var.allow_incoming_dns ? 1 : 0
  security_group_id = aws_security_group.this.id
  type              = "ingress"
  from_port         = 53
  to_port           = 53
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "incoming_dns_udp" {
  count             = var.allow_incoming_dns ? 1 : 0
  security_group_id = aws_security_group.this.id
  type              = "ingress"
  from_port         = 53
  to_port           = 53
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
}

locals {
  reprovision_trigger = <<EOF
    ${var.hostname}
    ${var.ssh_username}
    ${var.ssh_private_key_path}
    ${var.ssh_public_key_path}
    ${var.swap_file_size}
    ${var.swap_swappiness}
    ${var.reprovision_trigger}
    ${file("${path.module}/provision-docker.sh")}
    ${file("${path.module}/provision-ebs.sh")}
    ${file("${path.module}/provision-swap.sh")}
  EOF

  availability_zone = data.aws_availability_zones.this.names[0]
}

variable "hostname" {
  default = "aws-ec2-ebs-docker-host"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "instance_ami" {
  default = "ami-0bdf93799014acdc4"
}

variable "ssh_private_key_path" {
  default = "ssh.private.key"
}

variable "ssh_public_key_path" {
  default = "ssh.public.key"
}

variable "ssh_username" {
  default = "ubuntu"
}

variable "vpc_id" {
  default = ""
}

variable "reprovision_trigger" {
  default = ""
}

variable "root_volume_size" {
  default = 8
}

variable "data_volume_id" {
  default = ""
}

variable "swap_file_size" {
  default = "512M"
}

variable "swap_swappiness" {
  default = "10"
}

variable "allow_incoming_http" {
  default = false
}

variable "allow_incoming_https" {
  default = false
}

variable "allow_incoming_dns" {
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}