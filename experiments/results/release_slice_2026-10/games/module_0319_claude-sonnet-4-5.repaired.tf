terraform {
  required_version = ">= 0.12.26"
}

data "aws_ami" "vault_consul" {
  most_recent = true

  owners = ["562637147889"]

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "is-public"
    values = ["true"]
  }

  filter {
    name   = "name"
    values = ["vault-consul-ubuntu-*"]
  }
}

module "vault_cluster" {
  source = "./modules/vault-cluster"

  cluster_name  = var.vault_cluster_name
  cluster_size  = var.vault_cluster_size
  instance_type = var.vault_instance_type

  ami_id    = var.ami_id == null ? data.aws_ami.vault_consul.image_id : var.ami_id
  user_data = data.template_file.user_data_vault_cluster.rendered

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnet_ids.default.ids

  health_check_type = "EC2"

  allowed_ssh_cidr_blocks              = ["0.0.0.0/0"]
  allowed_inbound_cidr_blocks          = ["0.0.0.0/0"]
  allowed_inbound_security_group_ids   = []
  allowed_inbound_security_group_count = 0
  ssh_key_name                         = var.ssh_key_name
}

module "consul_iam_policies_servers" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-iam-policies?ref=94dd31b89a345e8b78c4b2e111ab1d0c8a1e1913"

  iam_role_id = module.vault_cluster.iam_role_id
}

data "template_file" "user_data_vault_cluster" {
  template = file("${path.module}/examples/root-example/user-data-vault.sh")

  vars = {
    aws_region               = data.aws_region.current.name
    consul_cluster_tag_key   = var.consul_cluster_tag_key
    consul_cluster_tag_value = var.consul_cluster_name
  }
}

module "security_group_rules" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-client-security-group-rules?ref=94dd31b89a345e8b78c4b2e111ab1d0c8a1e1913"

  security_group_id = module.vault_cluster.security_group_id

  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]
}

module "vault_elb" {
  source = "./modules/vault-elb"

  name = var.vault_cluster_name

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnet_ids.default.ids

  vault_asg_name = module.vault_cluster.asg_name

  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]

  create_dns_entry = var.create_dns_entry

  hosted_zone_id = var.create_dns_entry ? join("", data.aws_route53_zone.selected.*.zone_id) : ""

  domain_name = var.vault_domain_name
}

data "aws_route53_zone" "selected" {
  count = var.create_dns_entry ? 1 : 0
  name  = "${var.hosted_zone_domain_name}."
}

module "consul_cluster" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-cluster?ref=94dd31b89a345e8b78c4b2e111ab1d0c8a1e1913"

  cluster_name  = var.consul_cluster_name
  cluster_size  = var.consul_cluster_size
  instance_type = var.consul_instance_type

  cluster_tag_key   = var.consul_cluster_tag_key
  cluster_tag_value = var.consul_cluster_name

  ami_id    = var.ami_id == null ? data.aws_ami.vault_consul.image_id : var.ami_id
  user_data = data.template_file.user_data_consul.rendered

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnet_ids.default.ids

  allowed_ssh_cidr_blocks     = ["0.0.0.0/0"]
  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]
  ssh_key_name                = var.ssh_key_name
}

data "template_file" "user_data_consul" {
  template = file("${path.module}/examples/root-example/user-data-consul.sh")

  vars = {
    consul_cluster_tag_key   = var.consul_cluster_tag_key
    consul_cluster_tag_value = var.consul_cluster_name
  }
}

data "aws_vpc" "default" {
  default = var.use_default_vpc
  tags    = var.vpc_tags
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
  tags   = var.subnet_tags
}

data "aws_region" "current" {
}

output "vault_fully_qualified_domain_name" {
  value = module.vault_elb.fully_qualified_domain_name
}

output "vault_elb_dns_name" {
  value = module.vault_elb.load_balancer_dns_name
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

variable "create_dns_entry" {
  description = "If set to true, this module will create a Route 53 DNS A record for the ELB in the var.hosted_zone_id hosted zone with the domain name in var.vault_domain_name."
  type        = bool
  default     = false
}

variable "hosted_zone_domain_name" {
  description = "The domain name of the Route 53 Hosted Zone in which to add a DNS entry for Vault (e.g. example.com). Only used if var.create_dns_entry is true."
  type        = string
  default     = null
}

variable "vault_domain_name" {
  description = "The domain name to use in the DNS A record for the Vault ELB (e.g. vault.example.com). Make sure that a) this is a domain within the var.hosted_zone_domain_name hosted zone and b) this is the same domain name you used in the TLS certificates for Vault. Only used if var.create_dns_entry is true."
  type        = string
  default     = null
}

variable "ami_id" {
  description = "The ID of the AMI to run in the cluster. This should be an AMI built from the Packer template under examples/vault-consul-ami/vault-consul.json. If no AMI is specified, the template will 'just work' by using the example public AMIs. WARNING! Do not use the example AMIs in a production setting!"
  type        = string
  default     = null
}

variable "ssh_key_name" {
  description = "The name of an EC2 Key Pair that can be used to SSH to the EC2 Instances in this cluster. Set to an empty string to not associate a Key Pair."
  type        = string
  default     = null
}

variable "subnet_tags" {
  description = "Tags used to find subnets for vault and consul servers"
  type        = map(string)
  default     = {}
}

variable "vpc_tags" {
  description = "Tags used to find a vpc for building resources in"
  type        = map(string)
  default     = {}
}

variable "use_default_vpc" {
  description = "Whether to use the default VPC - NOT recommended for production! - should more likely change this to false and use the vpc_tags to find your vpc"
  type        = bool
  default     = true
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