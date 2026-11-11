# ----------------------------------------------------------------------------------------------------------------------
# REQUIRE A SPECIFIC TERRAFORM VERSION OR HIGHER
# ----------------------------------------------------------------------------------------------------------------------
terraform {
  # This module is now only being tested with Terraform 1.0.x. However, to make upgrading easier, we are setting
  # 0.12.26 as the minimum version, as that version added support for required_providers with source URLs, making it
  # forwards compatible with 1.0.x code.
  required_version = ">= 0.12.26"
}

# ---------------------------------------------------------------------------------------------------------------------
# INSTANCE THAT WILL AUTHENTICATE TO VAULT USING IAM METHOD
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_instance" "example_auth_to_vault" {
  ami                           = var.ami_id
  instance_type                 = "t2.micro"
  subnet_id                     = tolist(data.aws_subnet_ids.default.ids)[0]
  key_name                      = var.ssh_key_name
  block_device_mappings         = [
    {
      device_name = "/dev/sda1"
      encrypted   = true
    }
  ]
  enable_metadata_http_tokens   = true
  disable_api_termination      = true
  detailed_monitoring           = true
  user_data                    = data.template_file.user_data_auth_client.rendered
  security_groups              = [
    module.consul_cluster.security_group_id,
    aws_security_group.auth_instance.id,
  ]
  iam_instance_profile         = aws_iam_instance_profile.example_instance_profile.name
  tags = {
    Name = var.auth_server_name
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATES A ROLE THAT IS ATTACHED TO THE INSTANCE
# The arn of this AWS role is what the Vault server will use create the Vault Role
# so it can validate login requests from resources with this role
# ---------------------------------------------------------------------------------------------------------------------
resource "aws_iam_instance_profile" "example_instance_profile" {
  path = "/"
  role = aws_iam_role.example_instance_role.name
}

resource "aws_iam_role" "example_instance_role" {
  name_prefix        = "${var.auth_server_name}-role"
  assume_role_policy = data.aws_iam_policy_document.example_instance_role.json
}

data "aws_iam_policy_document" "example_instance_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Adds policies necessary for running consul
module "consul_iam_policies_for_client" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-iam-policies?ref=v0.8.0"

  iam_role_id = aws_iam_role.example_instance_role.id
}

# ---------------------------------------------------------------------------------------------------------------------
# THE USER DATA SCRIPT THAT WILL RUN ON THE INSTANCE
# This script will run consul, which is used for discovering vault cluster
# And perform the login operation
# ---------------------------------------------------------------------------------------------------------------------

data "template_file" "user_data_auth_client" {
  template = file("${path.module}/user-data-auth-client.sh")

  vars = {
    consul_cluster_tag_key   = var.consul_cluster_tag_key
    consul_cluster_tag_value = var.consul_cluster_name
    example_role_name        = var.example_role_name
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# ADDS A RULE TO OPEN PORT 8080 SINCE OUR EXAMPLE LAUNCHES A SIMPLE WEB SERVER
# This is here just for automated tests, not something that should be done with prod
# ---------------------------------------------------------------------------------------------------------------------

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
  description = "Allow inbound API traffic"
  security_group_id = aws_security_group.auth_instance.id
}

# ---------------------------------------------------------------------------------------------------------------------
# ADDS A POLICY TO THE VAULT CLUSTER ROLE SO VAULT CAN QUERY AWS IAM USERS AND ROLES
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role_policy" "vault_iam" {
  name   = "vault_iam"
  role   = module.vault_cluster.iam_role_id
  policy = data.aws_iam_policy_document.vault_iam.json
}

data "aws_iam_policy_document" "vault_iam" {
  statement {
    effect  = "Allow"
    actions = ["iam:GetRole", "iam:GetUser"]

    # List of arns it can query, for more security, it could be set to specific roles or user
    # resources = ["${aws_iam_role.example_instance_role.arn}"]
    resources = [
      "arn:aws:iam::*:user/*",
      "arn:aws:iam::*:role/*",
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE VAULT SERVER CLUSTER
# ---------------------------------------------------------------------------------------------------------------------

module "vault_cluster" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "github.com/hashicorp/terraform-aws-vault.git//modules/vault-cluster?ref=v0.0.1"
  source = "../../modules/vault-cluster"

  cluster_name  = var.vault_cluster_name
  cluster_size  = var.vault_cluster_size
  instance_type = var.vault_instance_type

  ami_id    = var.ami_id
  user_data = data.template_file.user_data_vault_cluster.rendered

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnet_ids.default.ids

  # To make testing easier, we allow requests from any IP address here but in a production deployment, we *strongly*
  # recommend you limit this to the IP address ranges of known, trusted servers inside your VPC.

  allowed_ssh_cidr_blocks              = ["192.168.1.0/24"]
  allowed_inbound_cidr_blocks          = ["192.168.1.0/24"]
  allowed_inbound_security_group_ids   = []
  allowed_inbound_security_group_count = 0
  ssh_key_name                         = var.ssh_key_name
}

# ---------------------------------------------------------------------------------------------------------------------
# ATTACH IAM POLICIES FOR CONSUL
# To allow our Vault servers to automatically discover the Consul servers, we need to give them the IAM permissions from
# the Consul AWS Module's consul-iam-policies module.
# ---------------------------------------------------------------------------------------------------------------------

module "consul_iam_policies_servers" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-iam-policies?ref=v0.8.0"

  iam_role_id = module.vault_cluster.iam_role_id
}

# ---------------------------------------------------------------------------------------------------------------------
# THE USER DATA SCRIPT THAT WILL RUN ON EACH VAULT SERVER WHEN IT'S BOOTING
# This script will configure and start Vault
# ---------------------------------------------------------------------------------------------------------------------

data "template_file" "user_data_vault_cluster" {
  template = file("${path.module}/user-data-vault.sh")

  vars = {
    consul_cluster_tag_key   = var.consul_cluster_tag_key
    consul_cluster_tag_value = var.consul_cluster_name
    example_role_name        = var.example_role_name
    # Please note that normally we would never pass a secret this way
    # This is just for test purposes so we can verify that our example instance is authenticating correctly
    example_secret   = var.example_secret
    aws_iam_role_arn = aws_iam_role.example_instance_role.arn
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# PERMIT CONSUL SPECIFIC TRAFFIC IN VAULT CLUSTER
# To allow our Vault servers consul agents to communicate with other consul agents and participate in the LAN gossip,
# we open up the consul specific protocols and ports for consul traffic
# ---------------------------------------------------------------------------------------------------------------------

module "security_group_rules" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-client-security-group-rules?ref=v0.8.0"

  security_group_id = module.vault_cluster.security_group_id

  # To make testing easier, we allow requests from any IP address here but in a production deployment, we *strongly*
  # recommend you limit this to the IP address ranges of known, trusted servers inside your VPC.

  allowed_inbound_cidr_blocks = ["192.168.1.0/24"]
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE CONSUL SERVER CLUSTER
# ---------------------------------------------------------------------------------------------------------------------

module "consul_cluster" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-cluster?ref=v0.8.0"

  cluster_name  = var.consul_cluster_name
  cluster_size  = var.consul_cluster_size
  instance_type = var.consul_instance_type

  # The EC2 Instances will use these tags to automatically discover each other and form a cluster
  cluster_tag_key   = var.consul_cluster_tag_key
  cluster_tag_value = var.consul_cluster_name

  ami_id    = var.ami_id
  user_data = data.template_file.user_data_consul.rendered

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnet_ids.default.ids

  # To make testing easier, we allow Consul and SSH requests from any IP address here but in a production
  # deployment, we strongly recommend you limit this to the IP address ranges of known, trusted servers inside your VPC.

  allowed_ssh_cidr_blocks     = ["192.168.1.0/24"]
  allowed_inbound_cidr_blocks = ["192.168.1.0/24"]
  ssh_key_name                = var.ssh_key_name
}

# ---------------------------------------------------------------------------------------------------------------------
# THE USER DATA SCRIPT THAT WILL RUN ON EACH CONSUL SERVER WHEN IT'S BOOTING
# This script will configure and start Consul
# ---------------------------------------------------------------------------------------------------------------------

data "template_file" "user_data_consul" {
  template = file("${path.module}/user-data-consul.sh")

  vars = {
    consul_cluster_tag_key   = var.consul_cluster_tag_key
    consul_cluster_tag_value = var.consul_cluster_name
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE CLUSTERS IN THE DEFAULT VPC AND AVAILABILITY ZONES
# Using the default VPC and subnets makes this example easy to run and test, but it means Consul and Vault are
# accessible from the public Internet. In a production deployment, we strongly recommend deploying into a custom VPC
# and private subnets.
# ---------------------------------------------------------------------------------------------------------------------

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

output "auth_role_arn" {
  value = aws_iam_role.example_instance_role.arn
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

output "consul_cluster_cluster_tag_key" {
  value = module.consul_cluster.cluster_tag_key
}

output "consul_cluster_cluster_tag_value" {
  value = module.consul_cluster.cluster_tag_value
}

# ---------------------------------------------------------------------------------------------------------------------
# ENVIRONMENT VARIABLES
# Define these secrets as environment variables
# ---------------------------------------------------------------------------------------------------------------------

# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY
# AWS_DEFAULT_REGION

# ---------------------------------------------------------------------------------------------------------------------
# REQUIRED PARAMETERS
# You must provide a value for each of these parameters.
# ---------------------------------------------------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# These parameters have reasonable defaults.
# ---------------------------------------------------------------------------------------------------------------------

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
  default     = "t2.micro"
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