locals {
  ami_id  = var.arch == "arm64" ? data.aws_ami.flatcar-arm64[0].image_id : data.aws_ami.flatcar.image_id
  channel = split("-", var.os_image)[1]
}

data "aws_ami" "flatcar" {
  most_recent = true
  owners      = ["075585003325"]

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "name"
    values = ["Flatcar-${local.channel}-*"]
  }
}

data "aws_ami" "flatcar-arm64" {
  count = var.arch == "arm64" ? 1 : 0

  most_recent = true
  owners      = ["075585003325"]

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "name"
    values = ["Flatcar-${local.channel}-*"]
  }
}

resource "aws_lb_target_group" "workers-http" {
  name        = "${var.name}-workers-http"
  vpc_id      = var.vpc_id
  target_type = "instance"

  protocol = "TCP"
  port     = 80

  health_check {
    protocol = "HTTP"
    port     = 10254
    path     = "/healthz"

    healthy_threshold   = 3
    unhealthy_threshold = 3

    interval = 10
  }
}

resource "aws_lb_target_group" "workers-https" {
  name        = "${var.name}-workers-https"
  vpc_id      = var.vpc_id
  target_type = "instance"

  protocol = "TCP"
  port     = 443

  health_check {
    protocol = "HTTP"
    port     = 10254
    path     = "/healthz"

    healthy_threshold   = 3
    unhealthy_threshold = 3

    interval = 10
  }
}

output "target_group_http" {
  description = "ARN of a target group of workers for HTTP traffic"
  value       = aws_lb_target_group.workers-http.arn
}

output "target_group_https" {
  description = "ARN of a target group of workers for HTTPS traffic"
  value       = aws_lb_target_group.workers-https.arn
}

variable "name" {
  type        = string
  description = "Unique name for the worker pool"
}

variable "vpc_id" {
  type        = string
  description = "Must be set to `vpc_id` output by cluster"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Must be set to `subnet_ids` output by cluster"
}

variable "security_groups" {
  type        = list(string)
  description = "Must be set to `worker_security_groups` output by cluster"
}

variable "worker_count" {
  type        = number
  description = "Number of instances"
  default     = 1
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t3.small"
}

variable "associate_public_ipv4_address" {
  type        = bool
  description = "Associate a public IPv4 address to instances (otherwise, no IPv4 access to instances from the internet and no outbound IPv4 access to the internet)"
  default     = true
}

variable "os_image" {
  type        = string
  description = "AMI channel for a Container Linux derivative (flatcar-stable, flatcar-beta, flatcar-alpha)"
  default     = "flatcar-stable"

  validation {
    condition     = contains(["flatcar-stable", "flatcar-beta", "flatcar-alpha"], var.os_image)
    error_message = "The os_image must be flatcar-stable, flatcar-beta, or flatcar-alpha."
  }
}

variable "disk_size" {
  type        = number
  description = "Size of the EBS volume in GB"
  default     = 30
}

variable "disk_type" {
  type        = string
  description = "Type of the EBS volume (e.g. standard, gp2, gp3, io1)"
  default     = "gp3"
}

variable "disk_iops" {
  type        = number
  description = "IOPS of the EBS volume (required for io1)"
  default     = 0
}

variable "spot_price" {
  type        = number
  description = "Spot price in USD for worker instances or 0 to use on-demand instances"
  default     = 0
}

variable "cpu_credits" {
  type        = string
  description = "CPU burst credits mode (if applicable)"
  default     = null
}

variable "target_groups" {
  type        = list(string)
  description = "Additional target group ARNs to which instances should be added"
  default     = []
}

variable "snippets" {
  type        = list(string)
  description = "Container Linux Config snippets"
  default     = []
}

variable "kubeconfig" {
  type        = string
  description = "Must be set to `kubeconfig` output by cluster"
}

variable "ssh_authorized_key" {
  type        = string
  description = "SSH public key for user 'core'"
}

variable "service_cidr" {
  type        = string
  description = <<EOD
CIDR IPv4 range to assign Kubernetes services.
The 1st IP will be reserved for kube_apiserver, the 10th IP will be reserved for coredns.
EOD
  default     = "10.3.0.0/16"
}

variable "node_labels" {
  type        = list(string)
  description = "List of initial node labels"
  default     = []
}

variable "node_taints" {
  type        = list(string)
  description = "List of initial node taints"
  default     = []
}

variable "arch" {
  type        = string
  description = "Container architecture (amd64 or arm64)"
  default     = "amd64"

  validation {
    condition     = contains(["amd64", "arm64"], var.arch)
    error_message = "The arch must be amd64 or arm64."
  }
}

terraform {
  required_version = ">= 0.13.0, < 2.0.0"
  required_providers {
    aws = ">= 2.23"
    ct = {
      source  = "poseidon/ct"
      version = "~> 0.14"
    }
  }
}

resource "aws_autoscaling_group" "workers" {
  name = "${var.name}-worker"

  desired_capacity = var.worker_count
  min_size         = var.worker_count
  max_size         = var.worker_count + 2

  vpc_zone_identifier = var.subnet_ids

  launch_template {
    id      = aws_launch_template.worker.id
    version = aws_launch_template.worker.latest_version
  }

  target_group_arns = flatten([
    aws_lb_target_group.workers-http.id,
    aws_lb_target_group.workers-https.id,
    var.target_groups,
  ])

  instance_refresh {
    strategy = "Rolling"
    preferences {
      instance_warmup        = 120
      min_healthy_percentage = 90
    }
  }
  health_check_grace_period = 30
  default_cooldown = 30

  lifecycle {
    create_before_destroy = true
  }

  wait_for_capacity_timeout = "0"

  tag {
    key                 = "Name"
    value               = "${var.name}-worker"
    propagate_at_launch = true
  }
}

resource "aws_launch_template" "worker" {
  name_prefix   = "${var.name}-worker"
  image_id      = local.ami_id
  instance_type = var.instance_type

  ebs_optimized = true
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = var.disk_type
      volume_size           = var.disk_size
      iops                  = var.disk_iops
      encrypted             = true
      delete_on_termination = true
    }
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = var.security_groups
  }

  user_data = sensitive(base64encode(data.ct_config.worker.rendered))

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }
  monitoring {
    enabled = false
  }

  credit_specification {
    cpu_credits = var.cpu_credits
  }
  dynamic "instance_market_options" {
    for_each = var.spot_price > 0 ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        max_price = var.spot_price
      }
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [image_id]
  }
}

data "ct_config" "worker" {
  content = templatefile("${path.module}/butane/worker.yaml", {
    kubeconfig             = indent(10, var.kubeconfig)
    ssh_authorized_key     = var.ssh_authorized_key
    cluster_dns_service_ip = cidrhost(var.service_cidr, 10)
    node_labels            = join(",", var.node_labels)
    node_taints            = join(",", var.node_taints)
  })
  strict   = true
  snippets = var.snippets
}