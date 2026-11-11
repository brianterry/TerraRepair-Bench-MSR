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

resource "aws_key_pair" "http-rdir" {
  count = "${var.count}"
  key_name = "http-rdir-key-${count.index}"  
  public_key = "${tls_private_key.ssh.*.public_key_openssh[count.index]}"
}

resource "aws_instance" "http-rdir" {
  count = "${var.count}"
  
  tags = {
    Name = "http-rdir-${random_id.server.*.hex[count.index]}"
  }

  ami = "${var.amis[data.aws_region.current.name]}"
  instance_type = "${var.instance_type}"
  key_name = "${aws_key_pair.http-rdir.*.key_name[count.index]}"
  vpc_security_group_ids = ["${aws_security_group.http-rdir.id}"]
  subnet_id = "${var.subnet_id}"
  associate_public_ip_address = false
  iam_instance_profile = "${var.iam_instance_profile}"
  root_block_device {
    encrypted = true
  }
  disable_api_termination = true
  detailed_monitoring = true
  ebs_optimized = true
  metadata_options {
    http_tokens = "required"
    http_endpoint = "enabled"
    http_put_response_hop_limit = 1
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y tmux socat apache2 mosh",
      "sudo a2enmod rewrite proxy proxy_http ssl",
      "sudo systemctl stop apache2",
      "tmux new -d \"sudo socat TCP4-LISTEN:80,fork TCP4:${element(var.redirect_to, count.index)}:80\" ';' split \"sudo socat TCP4-LISTEN:443,fork TCP4:${element(var.redirect_to, count.index)}:443\""
    ]

    connection {
        type = "ssh"
        user = "admin"
        private_key = "${tls_private_key.ssh.*.private_key_pem[count.index]}"
    }
  }

  provisioner "local-exec" {
    command = "echo \"${tls_private_key.ssh.*.private_key_pem[count.index]}\" >./data/ssh_keys/${self.public_ip} && echo \"${tls_private_key.ssh.*.public_key_openssh[count.index]}\" >./data/ssh_keys/${self.public_ip}.pub && chmod 600./data/ssh_keys/*" 
  }

  provisioner "local-exec" {
    when = "destroy"
    command = "rm./data/ssh_keys/${self.public_ip}*"
  }

}

resource "null_resource" "ansible_provisioner" {
  count = "${signum(length(var.ansible_playbook)) == 1? var.count : 0}"

  depends_on = ["aws_instance.http-rdir"]

  triggers {
    droplet_creation = "${join(",", aws_instance.http-rdir.*.id)}"
    policy_sha1 = "${sha1(file(var.ansible_playbook))}"
  }

  provisioner "local-exec" {
    command = "ansible-playbook ${join(" ", compact(var.ansible_arguments))} --user=admin --private-key=./data/ssh_keys/${aws_instance.http-rdir.*.public_ip[count.index]} -e host=${aws_instance.http-rdir.*.public_ip[count.index]} ${var.ansible_playbook}"

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

  depends_on = ["aws_instance.http-rdir"]

  vars {
    name = "dns_rdir_${aws_instance.http-rdir.*.public_ip[count.index]}"
    hostname = "${aws_instance.http-rdir.*.public_ip[count.index]}"
    user = "admin"
    identityfile = "${path.root}/data/ssh_keys/${aws_instance.http-rdir.*.public_ip[count.index]}"
  }

}

resource "null_resource" "gen_ssh_config" {

  count = "${var.count}"

  triggers {
    template_rendered = "${data.template_file.ssh_config.*.rendered[count.index]}"
  }

  provisioner "local-exec" {
    command = "echo '${data.template_file.ssh_config.*.rendered[count.index]}' >./data/ssh_configs/config_${random_id.server.*.hex[count.index]}"
  }

  provisioner "local-exec" {
    when = "destroy"
    command = "rm./data/ssh_configs/config_${random_id.server.*.hex[count.index]}"
  }

}

output "ips" {
  value = ["${aws_instance.http-rdir.*.public_ip}"]
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

resource "aws_security_group" "http-rdir" {
  name = "http-rdir"
  description = "Security group created by Red Baron"
  vpc_id = "${var.vpc_id}"

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["${data.external.get_public_ip.result["ip"]}/32"]
    description = "Allow SSH access from specific IP"
  }
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTP access from internal network"
  }
  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTPS access from internal network"
  }
  ingress {
    from_port = 60000
    to_port = 61000
    protocol = "udp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow UDP traffic from internal network"
  }
  egress {
    from_port = 53
    to_port = 53
    protocol = "udp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow DNS queries to internal network"
  }
  egress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTP traffic to internal network"
  }
  egress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
    description = "Allow HTTPS traffic to internal network"
  }
}

variable "subnet_id" {}

variable "vpc_id" {}

variable "redirect_to" {
  type = "list"
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

variable "count" {
  default = 1
}

variable "instance_type" {
  default = "t2.medium"
}

variable "iam_instance_profile" {
  default = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

variable "amis" {
  type = "map"
  default = {

    // Taken from https://wiki.debian.org/Cloud/AmazonEC2Image/Stretch
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