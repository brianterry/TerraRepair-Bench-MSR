terraform {
  required_version = ">= 0.11.0"
}

data "aws_region" "current" {}

resource "random_id" "server" {
  count = "${var.count}"
  byte_length = 4
}

resource "tls_private_key" "ssh" {
  count = "${var.count}"
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "aws_key_pair" "http-c2" {
  count = "${var.count}"
  key_name = "http-c2-key-${count.index}"
  public_key = "${tls_private_key.ssh.*.public_key_openssh[count.index]}"
}

resource "aws_iam_role" "http-c2" {
  name = "http-c2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "http-c2" {
  name = "http-c2-profile"
  role = aws_iam_role.http-c2.name
}

resource "aws_instance" "http-c2" {
  count = "${var.count}"
  
  tags = {
    Name = "http-c2-${random_id.server.*.hex[count.index]}"
  }

  ami = "${var.amis[data.aws_region.current.name]}"
  instance_type = "${var.instance_type}"
  key_name = "${aws_key_pair.http-c2.*.key_name[count.index]}"
  vpc_security_group_ids = ["${aws_security_group.http-c2.id}"]
  subnet_id = "${var.subnet_id}"
  associate_public_ip_address = false
  iam_instance_profile = aws_iam_instance_profile.http-c2.name
  ebs_optimized = true
  monitoring = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted = true
  }

  provisioner "remote-exec" {
    scripts = "${concat(list("./scripts/core_deps.sh"), var.install)}"

    connection {
        type = "ssh"
        user = "admin"
        private_key = "${tls_private_key.ssh.*.private_key_pem[count.index]}"
    }
  }

  provisioner "local-exec" {
    command = "echo \"${tls_private_key.ssh.*.private_key_pem[count.index]}\" > ./data/ssh_keys/${self.private_ip} && echo \"${tls_private_key.ssh.*.public_key_openssh[count.index]}\" > ./data/ssh_keys/${self.private_ip}.pub && chmod 600 ./data/ssh_keys/*" 
  }

  provisioner "local-exec" {
    when = "destroy"
    command = "rm ./data/ssh_keys/${self.private_ip}*"
  }

}

resource "null_resource" "ansible_provisioner" {
  count = "${signum(length(var.ansible_playbook)) == 1 ? var.count : 0}"

  depends_on = ["aws_instance.http-c2"]

  triggers {
    droplet_creation = "${join("," , aws_instance.http-c2.*.id)}"
    policy_sha1 = "${sha1(file(var.ansible_playbook))}"
  }

  provisioner "local-exec" {
    command = "ansible-playbook ${join(" ", compact(var.ansible_arguments))} --user=admin --private-key=./data/ssh_keys/${aws_instance.http-c2.*.private_ip[count.index]} -e host=${aws_instance.http-c2.*.private_ip[count.index]} ${var.ansible_playbook}"

    environment {
      ANSIBLE_HOST_KEY_CHECKING = "False"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

data "template_file" "ssh_config" {

  count    = "${var.count}"

  template = "${file("./data/templates/ssh_config.tpl")}"

  depends_on = ["aws_instance.http-c2"]

  vars {
    name = "dns_rdir_${aws_instance.http-c2.*.private_ip[count.index]}"
    hostname = "${aws_instance.http-c2.*.private_ip[count.index]}"
    user = "admin"
    identityfile = "${path.root}/data/ssh_keys/${aws_instance.http-c2.*.private_ip[count.index]}"
  }

}

resource "null_resource" "gen_ssh_config" {

  count = "${var.count}"

  triggers {
    template_rendered = "${data.template_file.ssh_config.*.rendered[count.index]}"
  }

  provisioner "local-exec" {
    command = "echo '${data.template_file.ssh_config.*.rendered[count.index]}' > ./data/ssh_configs/config_${random_id.server.*.hex[count.index]}"
  }

  provisioner "local-exec" {
    when = "destroy"
    command = "rm ./data/ssh_configs/config_${random_id.server.*.hex[count.index]}"
  }

}

output "ips" {
  value = ["${aws_instance.http-c2.*.private_ip}"]
}

output "ssh_user" {
  value = "admin"
}

terraform {
  required_version = ">= 0.11.0"
}

data "external" "get_public_ip" {
  program = ["bash", "./scripts/get_public_ip.sh" ]
}

resource "aws_security_group" "http-c2" {
  name = "http-c2"
  description = "Security group created by Red Baron"
  vpc_id = "${var.vpc_id}"

  ingress {
    description = "SSH access from trusted IP"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["${data.external.get_public_ip.result["ip"]}/32"]
  }
  ingress {
    description = "HTTP access from trusted IP"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["${data.external.get_public_ip.result["ip"]}/32"]
  }
  ingress {
    description = "HTTPS access from trusted IP"
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["${data.external.get_public_ip.result["ip"]}/32"]
  }
  ingress {
    description = "Mosh access from trusted IP"
    from_port = 60000
    to_port = 61000
    protocol = "udp"
    cidr_blocks = ["${data.external.get_public_ip.result["ip"]}/32"]
  }
  egress {
    description = "DNS egress"
    from_port = 53
    to_port = 53
    protocol = "udp"
    cidr_blocks = ["${data.external.get_public_ip.result["ip"]}/32"]
  }
  egress {
    description = "HTTP egress"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["${data.external.get_public_ip.result["ip"]}/32"]
  }
  egress {
    description = "HTTPS egress"
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["${data.external.get_public_ip.result["ip"]}/32"]
  }
}


variable "subnet_id" {}

variable "vpc_id" {}

variable "count" {
  default = 1
}

variable "ansible_playbook" {
  default = ""
  description = "Ansible Playbook to run"
}

variable "ansible_arguments" {
  default = []
  type    = "list"
  description = "Additional Ansible Arguments"
}

variable "ansible_vars" {
  default = []
  type    = "list"
  description = "Environment variables"
}

variable "instance_type" {
  default = "t2.medium"
}

variable "install" {
  type = "list"
  default = []
}

variable "amis" {
  type = "map"
  default = {

    "ap-northeast-1" = "ami-b6b568d0"
    "ap-northeast-2" = "ami-b7479dd9"
    "ap-south-1" = "ami-02aded6d"
    "ap-southeast-1" = "ami-d76019b4"
    "ap-southeast-2" = "ami-8359bae1"
    "ca-central-1" = "ami-3709b053"
    "eu-central-1" = "ami-8bb70be4"
    "eu-west-1" = "ami-ce76a7b7"
    "eu-west-2" = "ami-a6f9ebc2"
    "sa-east-1" = "ami-f5c7b899"
    "us-east-1" = "ami-71b7750b"
    "us-east-2" = "ami-dab895bf"
    "us-west-1" = "ami-58eedd38"
    "us-west-2" = "ami-c032f6b8"

  }
}