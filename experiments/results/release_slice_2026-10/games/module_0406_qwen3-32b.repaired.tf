```hcl
variable "subject_alternative_names" {
  type        = list(string)
  description = "A list of domains that should be SANs in the issued certificate"
  default     = []
}

variable "domain_name" {
  type        = string
  description = "Domain name (E.g. staging.cloudposse.co)"
  default     = ""
}

locals {
  domain_name = var.domain_name != "" ? var.domain_name : module.dns.zone_name

  subject_alternative_names = distinct(
    concat(
      var.subject_alternative_names,
      formatlist("*.%s", [local.domain_name])
    )
  )
}

module "acm_request_certificate" {
  source                    = "git::https://github.com/cloudposse/terraform-aws-acm-request-certificate.git?ref=tags/0.4.0"
  domain_name               = local.domain_name
  ttl                       = 300
  subject_alternative_names = local.subject_alternative_names
  tags                      = var.tags
}


variable "alb_ingress_cidr_blocks_http" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "List of CIDR blocks allowed to access environment over HTTP"
}

variable "alb_ingress_cidr_blocks_https" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "List of CIDR blocks allowed to access environment over HTTPS"
}

module "alb" {
  source             = "git::https://github.com/cloudposse/terraform-aws-alb.git?ref=tags/0.7.0"
  name               = var.name
  namespace          = var.namespace
  stage              = var.stage
  attributes         = var.attributes
  vpc_id             = module.vpc.vpc_id
  ip_address_type    = "ipv4"
  subnet_ids         = [module.subnets.public_subnet_ids]
  security_group_ids = []
  access_logs_region = var.region

  https_enabled             = true
  http_ingress_cidr_blocks  = var.alb_ingress_cidr_blocks_http
  https_ingress_cidr_blocks = var.alb_ingress_cidr_blocks_https
  certificate_arn           = module.acm_request_certificate.arn
  health_check_interval     = 60
  load_balancer_type        = "application"
  drop_invalid_headers      = true
  ssl_policy                = "ELBSecurityPolicy-2016-08"
  alb_access_logs_s3_bucket_force_destroy = true
  access_logs_s3_bucket_public_access_block {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }
}


variable "atlantis_enabled" {
  type    = bool
  default = true
}

variable "atlantis_gh_team_whitelist" {
  type        = string
  description = "Atlantis GitHub team whitelist"
  default     = ""
}

variable "atlantis_gh_user" {
  type        = string
  description = "Atlantis GitHub user"
  default     = "undefined"
}

variable "atlantis_repo_config" {
  type        = string
  description = "Path to atlantis server-side repo config file (https://www.runatlantis.io/docs/server-side-repo-config.html)"
  default     = "atlantis-repo-config.yaml"
}

variable "atlantis_repo_whitelist" {
  type        = list(string)
  description = "Whitelist of repositories Atlantis will accept webhooks from"
  default     = []
}

variable "atlantis_branch" {
  type        = string
  default     = "master"
  description = "Atlantis branch Branch of the GitHub repository, _e.g._ `master`"
}

variable "atlantis_repo_name" {
  type        = string
  description = "GitHub repository name of the atlantis to be built and deployed to ECS."
}

variable "atlantis_repo_owner" {
  type        = string
  description = "GitHub organization containing the Atlantis repository"
  default     = "undefined"
}

variable "atlantis_container_cpu" {
  type        = number
  description = "The vCPU setting to control cpu limits of container. (If FARGATE launch type is used below, this must be a supported vCPU size from the table here: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html)"
  default     = 256
}

variable "atlantis_container_memory" {
  type        = number
  description = "The amount of RAM to allow container to use in MB. (If FARGATE launch type is used below, this must be a supported Memory size from the table here: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html)"
  default     = 512
}

variable "atlantis_authentication_type" {
  type        = string
  default     = ""
  description = "Authentication action type. Supported values are `COGNITO` and `OIDC`"
}

variable "atlantis_cognito_user_pool_arn" {
  type        = string
  description = "Cognito User Pool ARN"
  default     = ""
}

variable "atlantis_cognito_user_pool_arn_ssm_name" {
  type        = string
  description = "SSM param name to lookup `atlantis_cognito_user_pool_arn` if not provided"
  default     = ""
}

variable "atlantis_cognito_user_pool_client_id" {
  type        = string
  description = "Cognito User Pool Client ID"
  default     = ""
}

variable "atlantis_cognito_user_pool_client_id_ssm_name" {
  type        = string
  description = "SSM param name to lookup `atlantis_cognito_user_pool_client_id` if not provided"
  default     = ""
}

variable "atlantis_cognito_user_pool_domain" {
  type        = string
  description = "Cognito User Pool Domain. The User Pool Domain should be set to the domain prefix (`xxx`) instead of full domain (https://xxx.auth.us-west-2.amazoncognito.com)"
  default     = ""
}

variable "atlantis_cognito_user_pool_domain_ssm_name" {
  type        = string
  description = "SSM param name to lookup `atlantis_cognito_user_pool_domain` if not provided"
  default     = ""
}

variable "atlantis_oidc_client_id" {
  type        = string
  description = "OIDC Client ID"
  default     = ""
}

variable "atlantis_oidc_client_id_ssm_name" {
  type        = string
  description = "SSM param name to lookup `atlantis_oidc_client_id` if not provided"
  default     = ""
}

variable "atlantis_oidc_client_secret" {
  type        = string
  description = "OIDC Client Secret"
  default     = ""
}

variable "atlantis_oidc_client_secret_ssm_name" {
  type        = string
  description = "SSM param name to lookup `atlantis_oidc_client_secret` if not provided"
  default     = ""
}

variable "atlantis_oidc_issuer" {
  type        = string
  description = "OIDC Issuer"
  default     = ""
}

variable "atlantis_oidc_authorization_endpoint" {
  type        = string
  description = "OIDC Authorization Endpoint"
  default     = ""
}

variable "atlantis_oidc_token_endpoint" {
  type        = string
  description = "OIDC Token Endpoint"
  default     = ""
}

variable "atlantis_oidc_user_info_endpoint" {
  type        = string
  description = "OIDC User Info Endpoint"
  default     = ""
}

variable "atlantis_alb_ingress_listener_unauthenticated_priority" {
  type        = number
  default     = 50
  description = "The priority for the rules without authentication, between 1 and 50000 (1 being highest priority). Must be different from `alb_ingress_listener_authenticated_priority` since a listener can't have multiple rules with the same priority"
}

variable "atlantis_alb_ingress_listener_authenticated_priority" {
  type        = number
  default     = 100
  description = "The priority for the rules with authentication, between 1 and 50000 (1 being highest priority). Must be different from `alb_ingress_listener_unauthenticated_priority` since a listener can't have multiple rules with the same priority"
}

variable "atlantis_alb_ingress_unauthenticated_paths" {
  type        = list(string)
  default     = []
  description = "Unauthenticated path pattern to match (a maximum of 1 can be defined)"
}

variable "atlantis_alb_ingress_authenticated_paths" {
  type        = list(string)
  default     = []
  description = "Authenticated path pattern to match (a maximum of 1 can be defined)"
}

variable "atlantis_build_timeout" {
  type        = number
  description = "Time (in minutes) to allow for Atlantis build to complete before declaring it a failure"
  default     = 20
}

module "atlantis" {
  source    = "git::https://github.com/cloudposse/terraform-aws-ecs-atlantis.git?ref=tags/0.14.0"
  enabled   = var.atlantis_enabled
  name      = var.name
  namespace = var.namespace
  region    = var.region
  stage     = var.stage

  atlantis_gh_team_whitelist = var.atlantis_gh_team_whitelist
  atlantis_gh_user           = var.atlantis_gh_user
  atlantis_repo_whitelist    = var.atlantis_repo_whitelist
  atlantis_repo_config       = var.atlantis_repo_config

  alb_arn_suffix     = module.alb.alb_arn_suffix
  alb_dns_name       = module.alb.alb_dns_name
  alb_name           = module.alb.alb_name
  alb_zone_id        = module.alb.alb_zone_id
  alb_security_group = module.alb.security_group_id

  container_cpu    = var.atlantis_container_cpu
  container_memory = var.atlantis_container_memory

  branch             = var.atlantis_branch
  parent_zone_id     = module.dns.zone_id
  ecs_cluster_arn    = aws_ecs_cluster.default.arn
  ecs_cluster_name   = aws_ecs_cluster.default.name
  repo_name          = var.atlantis_repo_name
  repo_owner         = var.atlantis_repo_owner
  private_subnet_ids = module.subnets.private_subnet_ids
  vpc_id             = module.vpc.vpc_id

  alb_ingress_authenticated_listener_arns       = [module.alb.https_listener_arn]
  alb_ingress_authenticated_listener_arns_count = 1

  alb_ingress_unauthenticated_listener_arns       = module.alb.listener_arns
  alb_ingress_unauthenticated_listener_arns_count = 2

  alb_ingress_unauthenticated_paths             = var.atlantis_alb_ingress_unauthenticated_paths
  alb_ingress_listener_unauthenticated_priority = var.atlantis_alb_ingress_listener_unauthenticated_priority
  alb_ingress_authenticated_paths               = var.atlantis_alb_ingress_authenticated_paths
  alb_ingress_listener_authenticated_priority   = var.atlantis_alb_ingress_listener_authenticated_priority

  authentication_type                        = var.atlantis_authentication_type
  authentication_cognito_user_pool_arn       = var.atlantis_cognito_user_pool_arn
  authentication_cognito_user_pool_client_id = var.atlantis_cognito_user_pool_client_id
  authentication_cognito_user_pool_domain    = var.atlantis_cognito_user_pool_domain
  authentication_oidc_client_id              = var.atlantis_oidc_client_id
  authentication_oidc_client_secret          = var.atlantis_oidc_client_secret
  authentication_oidc_issuer                 = var.atlantis_oidc_issuer
  authentication_oidc_authorization_endpoint = var.atlantis_oidc_authorization_endpoint
  authentication_oidc_token_endpoint         = var.atlantis_oidc_token_endpoint
  authentication_oidc_user_info_endpoint     = var.atlantis_oidc_user_info_endpoint

  authentication_cognito_user_pool_arn_ssm_name       = var.atlantis_cognito_user_pool_arn_ssm_name
  authentication_cognito_user_pool_client_id_ssm_name = var.atlantis_cognito_user_pool_client_id_ssm_name
  authentication_cognito_user_pool_domain_ssm_name    = var.atlantis_cognito_user_pool_domain_ssm_name
  authentication_oidc_client_id_ssm_name              = var.atlantis_oidc_client_id_ssm_name
  authentication_oidc_client_secret_ssm_name          = var.atlantis_oidc_client_secret_ssm_name

  codepipeline_s3_bucket_force_destroy = true

  build_timeout = var.atlantis_build_timeout
}

output "atlantis_url" {
  value = module.atlantis.atlantis_url
}


variable "default_backend_image" {
  default = "cloudposse/default-backend:0.1.2"
}

variable "default_backend_name" {
  default = "404"
}

# default backend app
module "default_backend_web_app" {
  source     = "git::https://github.com/cloudposse/terraform-aws-ecs-web-app.git?ref=tags/0.24.0"
  name       = var.name
  namespace  = var.namespace
  stage      = var.stage
  attributes = concat(var.attributes, [var.default_backend_name])

  vpc_id = module.vpc.vpc_id
  region = var.region

  container_image  = var.default_backend_image
  container_cpu    = 256
  container_memory = 512
  container_port   = 80

  #launch_type                 = "FARGATE"
  aws_logs_region              = var.region
  ecs_cluster_arn              = aws_ecs_cluster.default.arn
  ecs_cluster_name             = aws_ecs_cluster.default.name
  ecs_private_subnet_ids       = module.subnets.private_subnet_ids
  alb_ingress_healthcheck_path = "/healthz"

  codepipeline_enabled = false
  ecs_alarms_enabled   = true
  autoscaling_enabled  = false

  alb_name                                        = module.alb.alb_name
  alb_arn_suffix                                  = module.alb.alb_arn_suffix
  alb_security_group                              = module.alb.security_group_id
  alb_target_group_alarms_enabled                 = true
  alb_target_group_alarms_3xx_threshold           = 25
  alb_target_group_alarms_4xx_threshold           = 25
  alb_target_group_alarms_5xx_threshold           = 25
  alb_target_group_alarms_response_time_threshold = 0.5
  alb_target_group_alarms_period                  = 300
  alb_target_group_alarms_evaluation_periods      = 1

  alb_ingress_unauthenticated_listener_arns       = module.alb.listener_arns
  alb_ingress_unauthenticated_listener_arns_count = 1

  alb_ingress_unauthenticated_paths = ["/*"]
  alb_ingress_authenticated_paths   = []

  repo_owner = var.atlantis_repo_owner

  webhook_enabled       = false
  github_oauth_token    = "NO_TOKEN"
  github_webhooks_token = "NO_TOKEN"
}


variable "dns_parent_zone_name" {
  description = "DNS zone of parent domain that will delegate NS records to this cluster zone (e.g. `prod.example.co`)"
}

variable "dns_enabled" {
  default = true
}

variable "dns_zone_name" {
  description = "Zone name template"
  default     = "$$${region}-$$${name}.$$${parent_zone_name}"
}

module "dns" {
  source           = "git::https://github.com/cloudposse/terraform-aws-route53-cluster-zone.git?ref=tags/0.4.0"
  enabled          = var.dns_enabled
  namespace        = var.namespace
  stage            = var.stage
  name             = var.name
  parent_zone_name = var.dns_parent_zone_name
  zone_name        = var.dns_zone_name
}

output "dns_zone_name" {
  value = module.dns.zone_name
}


module "ecs_cluster_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.16.0"
  name       = var.name
  namespace  = var.namespace
  stage      = var.stage
  tags       = var.tags
  attributes = var.attributes
  delimiter  = var.delimiter
}

# ECS Cluster (needed even if using FARGATE launch type)
resource "aws_ecs_cluster" "default" {
  name = module.ecs_cluster_label.id
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}


variable "flow_logs_enabled" {
  type    = string
  default = true
}

module "flow_logs" {
  source  = "git::https://github.com/cloudposse/terraform-aws-vpc-flow-logs-s3-bucket.git?ref=tags/0.2.0"
  enabled = var.flow_logs_enabled

  name       = var.name
  namespace  = var.namespace
  stage      = var.stage
  tags       = var.tags
  attributes = concat(var.attributes, ["flow-logs"])
  delimiter  = var.delimiter
  region     = var.region
  vpc_id     = module.vpc.vpc_id

  s3_bucket_versioning = true
  s3_bucket_encryption = true
  s3_bucket_access_block {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }
}

output "flow_logs_kms_key_arn" {
  value       = module.flow_logs.kms_key_arn
  description = "Flow logs KMS Key ARN"
}

output "flow_logs_kms_key_id" {
  value       = module.flow_logs.kms_key_id
  description = "Flow logs KMS Key ID"
}

output "flow_logs_kms_alias_arn" {
  value       = module.flow_logs.kms_alias_arn
  description = "Flow logs KMS Alias ARN"
}

output "flow_logs_kms_alias_name" {
  value       = module.flow_logs.kms_alias_name
  description = "Flow logs KMS Alias name"
}

output "flow_logs_bucket_domain_name" {
  value       = module.flow_logs.bucket_domain_name
  description = "Flow logs FQDN of bucket"
}

output "flow_logs_bucket_id" {
  value       = module.flow_logs.bucket_id
  description = "Flow logs bucket Name (aka ID)"
}

output "flow_logs_bucket_arn" {
  value       = module.flow_logs.bucket_arn
  description = "Flow logs bucket ARN"
}

output "flow_logs_bucket_prefix" {
  value       = module.flow_logs.bucket_prefix
  description = "Flow logs bucket prefix configured for lifecycle rules"
}

output "flow_logs_id" {
  value       = module.flow_logs.id
  description = "Flow logs ID"
}


terraform {
  required_version = ">= 0.11.2"

  backend "s3" {}
}

provider "aws" {
  assume_role {
    role_arn = var.aws_assume_role_arn
  }
  default_tags {
    tags = var.tags
  }
  default_tags {
    tags = {
      "Name" = var.name
    }
  }
  default_tags {
    tags = {
      "Project" = var.namespace
    }
  }
  default_tags {
    tags = {
      "Environment" = var.stage
    }
  }
  default_tags {
    tags = {
      "Region" = var.region
    }
  }
  default_tags {
    tags = {
      "Owner" = "cloudposse"
    }
  }
  default_tags {
    tags = {
      "Team" = "infrastructure"
    }
  }
  default_tags {
    tags = {
      "Contact" = "ops@example.com"
    }
  }
  default_tags {
    tags = {
      "CostCenter" = "123456"
    }
  }
  default_tags {
    tags = {
      "BusinessUnit" = "infrastructure"
    }
  }
  default_tags {
    tags = {
      "Application" = var.name
    }
  }
  default_tags {
    tags = {
      "Purpose" = "Terraform"
    }
  }
  default_tags {
    tags = {
      "Terraform" = "true"
    }
  }
  default_tags {
    tags = {
      "TerraformModule" = "cloudposse/terraform-aws-ecs"
    }
  }
  default_tags {
    tags = {
      "TerraformVersion" = "0.12.0"
    }
  }
  default_tags {
    tags = {
      "TerraformProvider" = "aws"
    }
  }
  default_tags {
    tags = {
      "TerraformProviderVersion" = "2.0"
    }
  }
  default_tags {
    tags = {
      "TerraformBackend" = "s3"
    }
  }
  default_tags {
    tags = {
      "TerraformBackendVersion" = "0.12.0"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredVersion" = ">= 0.11.2"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProviders" = "aws, template, null, local"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersVersion" = "aws ~> 2.0, template ~> 2.0, null ~> 2.0, local ~> 1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersSource" = "hashicorp/aws, hashicorp/template, hashicorp/null, hashicorp/local"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHash" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Hex" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Hex" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Hex" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Hex" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URL" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URL" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URL" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URL" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafe" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafe" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafe" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafe" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashMD5Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashCRC32Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA256Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0, local:1.3"
    }
  }
  default_tags {
    tags = {
      "TerraformRequiredProvidersHashSHA1Base64URLSafeNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPaddingNoPadding" = "aws:2.0, template:2.0, null:2.0