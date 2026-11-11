terraform {
  required_version = ">= 0.12.26"
}

resource "aws_instance" "example_auth_to_vault" {
  ami           = var.ami_id
  instance_type = "t2.micro"
  subnet_id     = tolist(data.aws_subnet_ids.default.ids)[0]
  key_name      = var.ssh_key_name

  security_groups = [
    module.consul_cluster.security_group_id,
    aws_security_group.auth_instance.id,
  ]

  user_data            = data.template_file.user_data_auth_client.rendered
  iam_instance_profile = aws_iam_instance_profile.example_instance_profile.name
  ebs_optimized        = true
  monitoring           = true

  root_block_device {
    encrypted = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = var.auth_server_name
  }
}

resource "aws_iam_instance_profile" "example_instance_profile" {
  path = "/"
  role = module.vault_cluster.iam_role_name
}

data "template_file" "user_data_auth_client" {
  template = file("${path.module}/user-data-auth-client.sh")

  vars = {
    consul_cluster_tag_key   = var.consul_cluster_tag_key
    consul_cluster_tag_value = var.consul_cluster_name
    example_role_name        = var.example_role_name
  }
}

resource "aws_security_group" "auth_instance" {
  name        = var.auth_server_name
  description = "Security group for ${var.auth_server_name}"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_security_group_rule" "allow_inbound_api" {
  type        = "ingress"
  from_port   = "8080"
  to_port     = "8080"
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  description = "Allow inbound API traffic on port 8080"

  security_group_id = aws_security_group.auth_instance.id
}

module "vault_cluster" {
  source = "../../modules/vault-cluster"

  cluster_name  = var.vault_cluster_name
  cluster_size  = var.vault_cluster_size
  instance_type = var.vault_instance_type

  ami_id    = var.ami_id
  user_data = data.template_file.user_data_vault_cluster.rendered

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnet_ids.default.ids

  allowed_ssh_cidr_blocks              = [data.aws_vpc.default.cidr_block]
  allowed_inbound_cidr_blocks          = [data.aws_vpc.default.cidr_block]
  allowed_inbound_security_group_ids   = []
  allowed_inbound_security_group_count = 0
  ssh_key_name                         = var.ssh_key_name
}

module "consul_iam_policies_servers" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-iam-policies?ref=9bc4d60"

  iam_role_id = module.vault_cluster.iam_role_id
}

data "template_file" "user_data_vault_cluster" {
  template = file("${path.module}/user-data-vault.sh")

  vars = {
    aws_region               = data.aws_region.current.name
    consul_cluster_tag_key   = var.consul_cluster_tag_key
    consul_cluster_tag_value = var.consul_cluster_name
    example_role_name        = var.example_role_name
    example_secret           = var.example_secret
    ami_id                   = var.ami_id
  }
}

module "security_group_rules" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-client-security-group-rules?ref=9bc4d60"

  security_group_id = module.vault_cluster.security_group_id

  allowed_inbound_cidr_blocks = [data.aws_vpc.default.cidr_block]
}

module "consul_cluster" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-cluster?ref=9bc4d60"

  cluster_name  = var.consul_cluster_name
  cluster_size  = var.consul_cluster_size
  instance_type = var.consul_instance_type

  cluster_tag_key   = var.consul_cluster_tag_key
  cluster_tag_value = var.consul_cluster_name

  ami_id    = var.ami_id
  user_data = data.template_file.user_data_consul.rendered

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnet_ids.default.ids

  allowed_ssh_cidr_blocks     = [data.aws_vpc.default.cidr_block]
  allowed_inbound_cidr_blocks = [data.aws_vpc.default.cidr_block]
  allowed_egress_cidr_blocks  = [data.aws_vpc.default.cidr_block]
  ssh_key_name                = var.ssh_key_name
  root_volume_encrypted       = true

  metadata_options = {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
}

data "template_file" "user_data_consul" {
  template = file("${path.module}/user-data-consul.sh")

  vars = {
    consul_cluster_tag_key   = var.consul_cluster_tag_key
    consul_cluster_tag_value = var.consul_cluster_name
  }
}

data "aws_vpc" "default" {
  default = var.vpc_id == null ? true : false
  id      = var.vpc_id
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

data "aws_region" "current" {
}

output "auth_client_public_ip" {
  value = aws_instance.example_auth_to_vault.public_ip
}

output "auth_client_instance_id" {
  value = aws_instance.example_auth_to_vault.id
}

output "asg_name_vault_cluster" {
  value = module.vault_cluster.asg_name
}

output "launch_config_name_vault_cluster" {
  value = module.vault_cluster.launch_config_name
}

output "iam_role_arn_vault_cluster" {
  value = module.vault_cluster.iam_role_arn
}

output "iam_role_id_vault_cluster" {
  value = module.vault_cluster.iam_role_id
}

output "security_group_id_vault_cluster" {
  value = module.vault_cluster.security_group_id
}

output "asg_name_consul_cluster" {
  value = module.consul_cluster.asg_name
}

output "launch_config_name_consul_cluster" {
  value = module.consul_cluster.launch_config_name
}

output "iam_role_arn_consul_cluster" {
  value = module.consul_cluster.iam_role_arn
}

output "iam_role_id_consul_cluster" {
  value = module.consul_cluster.iam_role_id
}

output "security_group_id_consul_cluster" {
  value = module.consul_cluster.security_group_id
}

output "aws_region" {
  value = data.aws_region.current.name
}

output "vault_servers_cluster_tag_key" {
  value = module.vault_cluster.cluster_tag_key
}

output "vault_servers_cluster_tag_value" {
  value = module.vault_cluster.cluster_tag_value
}

output "ssh_key_name" {
  value = var.ssh_key_name
}

output "vault_cluster_size" {
  value = var.vault_cluster_size
}

output "launch_config_name_servers" {
  value = module.consul_cluster.launch_config_name
}

output "iam_role_arn_servers" {
  value = module.consul_cluster.iam_role_arn
}

output "iam_role_id_servers" {
  value = module.consul_cluster.iam_role_id
}

output "security_group_id_servers" {
  value = module.consul_cluster.security_group_id
}

output "consul_cluster_cluster_tag_key" {
  value = module.consul_cluster.cluster_tag_key
}

output "consul_cluster_cluster_tag_value" {
  value = module.consul_cluster.cluster_tag_value
}

variable "ami_id" {
  description = "The ID of the AMI to run in the cluster. This should be an AMI built from the Packer template under examples/vault-consul-ami/vault-consul.json."
  type        = string
}

variable "ssh_key_name" {
  description = "The name of an EC2 Key Pair that can be used to SSH to the EC2 Instances in this cluster. Set to an empty string to not associate a Key Pair."
  type        = string
}

variable "example_secret" {
  description = "Example secret to be written into vault server"
  type        = string
}

variable "example_role_name" {
  description = "The name of the vault role"
  type        = string
  default     = "example-role"
}

variable "vault_cluster_name" {
  description = "What to name the Vault server cluster and all of its associated resources"
  type        = string
  default     = "vault-example"
}

variable "consul_cluster_name" {
  description = "What to name the Consul server cluster and all of its associated resources"
  type        = string
  default     = "consul-example"
}

variable "auth_server_name" {
  description = "What to name the server authenticating to vault"
  type        = string
  default     = "auth-example"
}

variable "vault_cluster_size" {
  description = "The number of Vault server nodes to deploy. We strongly recommend using 3 or 5."
  type        = number
  default     = 1
}

variable "consul_cluster_size" {
  description = "The number of Consul server nodes to deploy. We strongly recommend using 3 or 5."
  type        = number
  default     = 1
}

variable "vault_instance_type" {
  description = "The type of EC2 Instance to run in the Vault ASG"
  type        = string
  default     = "t2.micro"
}

variable "consul_instance_type" {
  description = "The type of EC2 Instance to run in the Consul ASG"
  type        = string
  default     = "t2.nano"
}

variable "consul_cluster_tag_key" {
  description = "The tag the Consul EC2 Instances will look for to automatically discover each other and form a cluster."
  type        = string
  default     = "consul-servers"
}

variable "vpc_id" {
  description = "The ID of the VPC to deploy into. Leave an empty string to use the Default VPC in this region."
  type        = string
  default     = null
}