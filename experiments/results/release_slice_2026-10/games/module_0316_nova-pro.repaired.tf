terraform {
  required_version = ">= 0.12.26"
}

data "aws_kms_alias" "vault-example" {
  name = "alias/${var.auto_unseal_kms_key_alias}"
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

  enable_auto_unseal = true

  auto_unseal_kms_key_arn = data.aws_kms_alias.vault-example.target_key_arn

  allowed_ssh_cidr_blocks              = ["0.0.0.0/0"]
  allowed_inbound_cidr_blocks          = ["0.0.0.0/0"]
  allowed_inbound_security_group_ids   = []
  allowed_inbound_security_group_count = 0
  ssh_key_name                         = var.ssh_key_name
}

module "consul_iam_policies_servers" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-iam-policies?ref=v0.8.0"

  iam_role_id = module.vault_cluster.iam_role_id
}

data "template_file" "user_data_vault_cluster" {
  template = file("${path.module}/user-data-vault.sh")

  vars = {
    consul_cluster_tag_key   = var.consul_cluster_tag_key
    consul_cluster_tag_value = var.consul_cluster_name
    kms_key_id               = data.aws_kms_alias.vault-example.target_key_id
    aws_region               = data.aws_region.current.name
  }
}

module "security_group_rules" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-client-security-group-rules?ref=v0.8.0"

  security_group_id = module.vault_cluster.security_group_id

  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]
}

module "consul_cluster" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-cluster?ref=v0.8.0"

  cluster_name  = var.consul_cluster_name
  cluster_size  = var.consul_cluster_size
  instance_type = var.consul_instance_type

  cluster_tag_key   = var.consul_cluster_tag_key
  cluster_tag_value = var.consul_cluster_name

  ami_id    = var.ami_id
  user_data = data.template_file.user_data_consul.rendered

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnet_ids.default.ids

  allowed_ssh_cidr_blocks     = ["0.0.0.0/0"]
  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]
  ssh_key_name                = var.ssh_key_name

  encrypted_block_device = true

  security_group_rules = [
    {
      type              = "egress"
      protocol         = "-1"
      from_port         = 0
      to_port           = 0
      cidr_blocks      = ["0.0.0.0/0"]
      description      = "Allow all outbound traffic"
    },
    {
      type              = "ingress"
      protocol         = "tcp"
      from_port         = 22
      to_port           = 22
      cidr_blocks      = ["0.0.0.0/0"]
      description      = "Allow SSH access from any IP"
    }
  ]

  metadata_options {
    http_tokens = "required"
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

data "aws_region" "current" {}

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

variable "auto_unseal_kms_key_alias" {
  description = "The alias of AWS KMS key used for encryption and decryption"
  type        = string
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
  default     = 3
}

variable "consul_cluster_size" {
  description = "The number of Consul server nodes to deploy. We strongly recommend using 3 or 5."
  type        = number
  default     = 3
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