terraform {
  required_version = ">= 0.12.26"
}

resource "aws_elb" "vault" {
  name = var.name

  internal                    = true
  cross_zone_load_balancing   = var.cross_zone_load_balancing
  idle_timeout                = var.idle_timeout
  connection_draining         = var.connection_draining
  connection_draining_timeout = var.connection_draining_timeout

  security_groups = [aws_security_group.vault.id]
  subnets         = var.subnet_ids

  dynamic "access_logs" {
    for_each = var.access_logs == null ? [] : ["once"]

    content {
      enabled       = lookup(access_logs.value, "enabled", lookup(access_logs.value, "bucket", null))
      bucket        = lookup(access_logs.value, "bucket", null)
      bucket_prefix = lookup(access_logs.value, "bucket_prefix", null)
      interval      = lookup(access_logs.value, "interval", null)
    }
  }

  listener {
    lb_port           = var.lb_port
    lb_protocol       = "SSL"
    instance_port     = var.vault_api_port
    instance_protocol = "TCP"
    ssl_certificate_id = var.ssl_certificate_arn
  }

  health_check {
    target              = "${var.health_check_protocol}:${var.health_check_port == 0 ? var.vault_api_port : var.health_check_port}${var.health_check_path}"
    interval            = var.health_check_interval
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    timeout             = var.health_check_timeout
  }

  tags = merge(
    var.load_balancer_tags,
    {
      "Name" = var.name
    },
  )
}

resource "aws_autoscaling_attachment" "vault" {
  autoscaling_group_name = var.vault_asg_name
  elb                    = aws_elb.vault.id
}

resource "aws_autoscaling_group" "vault_health_check" {
  count = var.enable_asg_health_check ? 1 : 0
  name  = var.vault_asg_name
  health_check_type = "ELB"
  health_check_grace_period = 300
}

resource "aws_security_group" "vault" {
  name        = "${var.name}-elb"
  description = "Security group for the ${var.name} ELB"
  vpc_id      = var.vpc_id

  tags = var.security_group_tags
}

resource "aws_security_group_rule" "allow_inbound_api" {
  type        = "ingress"
  from_port   = var.lb_port
  to_port     = var.lb_port
  protocol    = "tcp"
  cidr_blocks = var.allowed_inbound_cidr_blocks
  description = "Allow inbound API traffic on port ${var.lb_port}"

  security_group_id = aws_security_group.vault.id
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type        = "egress"
  from_port   = var.vault_api_port
  to_port     = var.vault_api_port
  protocol    = "tcp"
  cidr_blocks = var.allowed_outbound_cidr_blocks
  description = "Allow outbound traffic to Vault instances"

  security_group_id = aws_security_group.vault.id
}

resource "aws_route53_record" "vault_elb" {
  count = var.create_dns_entry ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name    = aws_elb.vault.dns_name
    zone_id = aws_elb.vault.zone_id

    evaluate_target_health = false
  }
}


output "load_balancer_name" {
  value = aws_elb.vault.name
}

output "load_balancer_dns_name" {
  value = aws_elb.vault.dns_name
}

output "load_balancer_zone_id" {
  value = aws_elb.vault.zone_id
}

output "load_balancer_security_group_id" {
  value = aws_security_group.vault.id
}

output "fully_qualified_domain_name" {
  value = element(concat(aws_route53_record.vault_elb.*.fqdn, [""]), 0)
}



variable "name" {
  description = "The name to use for the ELB and all other resources in this module."
}

variable "vpc_id" {
  description = "The ID of the VPC into which the ELB should be deployed."
}

variable "allowed_inbound_cidr_blocks" {
  description = "A list of CIDR-formatted IP address ranges from which the ELB will accept requests."
  type        = list(string)
}

variable "vault_asg_name" {
  description = "Name of the Vault Autoscaling Group"
}

variable "access_logs" {
  description = "If specified, enables access logging for the ELB. This variable should be set to a map with the same keys and values as in the access_log block of the aws_elb resource (https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elb), including bucket, bucket_prefix, interval, and enabled."
  type        = any
  default     = null
}

variable "subnet_ids" {
  description = "The subnet IDs into which the ELB should be deployed. You will typically want to deploy the ELB into public subnets so your Vault cluster can run in private subnets."
  type        = list(string)
  default     = []
}

variable "create_dns_entry" {
  description = "If set to true, this module will create a Route 53 DNS A record for the ELB in the var.hosted_zone_id hosted zone with the domain name in var.domain_name."
  default     = false
}

variable "hosted_zone_id" {
  description = "The Route 53 hosted zone ID in which to create a DNS A record. Only used if var.create_dns_entry is true."
  default     = "replace-me"
}

variable "domain_name" {
  description = "The domain name to use in the DNS A record for the ELB (e.g. vault.example.com). Only used if var.create_dns_entry is true."
  default     = "replace-me"
}

variable "lb_port" {
  description = "The port the load balancer should listen on for API requests."
  default     = 443
}

variable "vault_api_port" {
  description = "The port to listen on for API requests."
  default     = 8200
}

variable "internal" {
  description = "If set to true, this will be an internal ELB, accessible only within the VPC. The main reason to use an ELB with Vault is to make it publicly accessible, so this should typically be set to false."
  default     = false
}

variable "cross_zone_load_balancing" {
  description = "Set to true to enable cross-zone load balancing"
  default     = true
}

variable "idle_timeout" {
  description = "The time, in seconds, that the connection is allowed to be idle."
  default     = 60
}

variable "connection_draining" {
  description = "Set to true to enable connection draining."
  default     = true
}

variable "connection_draining_timeout" {
  description = "The time, in seconds, to allow for connections to drain."
  default     = 300
}

variable "health_check_protocol" {
  description = "The protocol to use for health checks. Must be one of: HTTP, HTTPS, TCP, SSL."
  default     = "HTTPS"
}

variable "health_check_path" {
  description = "The path to use for health checks. Must return a 200 OK when the service is ready to receive requests from the ELB."
  default     = "/v1/sys/health?standbyok=true"
}

variable "health_check_port" {
  description = "The port to use for health checks if not vault_api_port."
  default     = 0
}

variable "health_check_interval" {
  description = "The amount of time, in seconds, between health checks."
  default     = 15
}

variable "health_check_healthy_threshold" {
  description = "The number of health checks that must pass before the instance is declared healthy."
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  description = "The number of health checks that must fail before the instance is declared unhealthy."
  default     = 2
}

variable "health_check_timeout" {
  description = "The amount of time, in seconds, before a health check times out."
  default     = 5
}

variable "load_balancer_tags" {
  description = "Tags to be applied to the ELB."
  default     = {}
}

variable "security_group_tags" {
  description = "Tags to be applied to the ELB security group."
  type        = map(string)
  default     = {}
}

variable "ssl_certificate_arn" {
  description = "The ARN of the SSL certificate to use for the ELB listener."
  type        = string
}

variable "allowed_outbound_cidr_blocks" {
  description = "A list of CIDR-formatted IP address ranges to which the ELB can send traffic."
  type        = list(string)
}

variable "enable_asg_health_check" {
  description = "Enable ELB health checks for the Auto Scaling Group."
  type        = bool
  default     = false
}