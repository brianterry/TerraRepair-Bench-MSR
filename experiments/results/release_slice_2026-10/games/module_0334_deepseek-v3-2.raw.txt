data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]


  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

}


resource "aws_backup_vault" "this" {
  name = var.name
  kms_key_arn = var.kms_key_id
}

resource "aws_backup_plan" "this" {
  name = var.name
  rule {
    rule_name         = var.name
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 1 * * ? *)"
    lifecycle {
      delete_after = 30
    }
  }
}

resource "aws_backup_selection" "efs" {
  iam_role_arn = module.backup_role.iam_role_arn
  name         = "${var.name}-efs"
  plan_id      = aws_backup_plan.this.id

  resources = [
    aws_efs_file_system.this.arn
  ]
}


#------------------------------------------------------------------------------
# Create EFS
#------------------------------------------------------------------------------
resource "aws_efs_file_system" "this" {
  creation_token = var.name
  encrypted      = var.encrypted
  kms_key_id     = var.kms_key_id

  tags = {
    "Name" = var.name
  }
  lifecycle {
    ignore_changes = [
      tags,
    ]
  }
}

resource "aws_efs_mount_target" "this" {
  count          = length(var.public_subnets)
  file_system_id = aws_efs_file_system.this.id
  subnet_id      = var.public_subnets[count.index]
  security_groups = [
    module.efs_sg.security_group_id
  ]
}


data "aws_iam_policy_document" "this" {
  statement {
    sid = "AllowMountEFS"
    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite"
    ]
    resources = [
      "arn:aws:elasticfilesystem:*:*:file-system/${aws_efs_file_system.this.id}"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"

      values = [var.encrypted]
    }
  }

  statement {
    sid     = "AllowAssociateEIP"
    actions = ["ec2:AssociateAddress"]
    resources = ["arn:aws:ec2:*:*:elastic-ip/${aws_eip.this.id}",
      "arn:aws:ec2:*:*:instance/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/Name"

      values = [var.name]
    }
  }

  statement {
    sid     = "AllowDisassociateAddressEIP"
    actions = ["ec2:DisassociateAddress"]
    resources = ["arn:aws:ec2:*:*:elastic-ip/${aws_eip.this.id}",
      "arn:aws:ec2:*:*:instance/*"
    ]
  }

  statement {
    sid       = "AllowModifyInstanceAttribute"
    actions   = ["ec2:ModifyInstanceAttribute"]
    resources = ["arn:aws:ec2:*:*:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/Name"

      values = [var.name]
    }
  }
}

module "iam_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "4.14.0"

  name        = var.name
  path        = "/"
  description = "${var.name} policy"

  policy = data.aws_iam_policy_document.this.json
}

module "this_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
  version = "4.14.0"

  trusted_role_services = [
    "ec2.amazonaws.com"
  ]

  create_role = true

  role_name         = var.name
  role_requires_mfa = false

  custom_role_policy_arns = [
    module.iam_policy.arn,
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
}

resource "aws_iam_instance_profile" "this_instance_profile" {
  name = var.name
  role = module.this_role.iam_role_name
}

module "backup_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
  version = "4.14.0"

  trusted_role_services = [
    "backup.amazonaws.com"
  ]

  create_role = true

  role_name         = "${var.name}-backup-role"
  role_requires_mfa = false

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  ]
}


data "aws_region" "current" {}
resource "aws_eip" "this" {
  domain = "vpc"
  tags = {
    Name        = var.name
    Environment = var.environment
  }
}

resource "aws_launch_template" "this" {
  name_prefix            = var.name
  image_id               = data.aws_ami.amazon_linux_2.id
  instance_type          = var.instance_type
  ebs_optimized          = false
  vpc_security_group_ids = [module.ec2_sg.security_group_id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.this_instance_profile.arn
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  user_data = base64encode(templatefile("${path.module}/templates/user-data.sh",
    {
      aws_region = data.aws_region.current.name
      eipalloc   = aws_eip.this.id
      efs_id     = aws_efs_file_system.this.id
    })
  )

  monitoring {
    enabled = false
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = var.name
    }
  }

  depends_on = [aws_efs_mount_target.this]

}

resource "aws_autoscaling_group" "this" {
  name                 = var.name
  desired_capacity     = 1
  max_size             = 1
  min_size             = 1
  default_cooldown     = 30
  force_delete         = true
  termination_policies = ["OldestLaunchTemplate", "OldestInstance"]

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  vpc_zone_identifier = var.public_subnets

  tag {
    key                 = "Name"
    value               = var.name
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}


output "pritunl_endpoint" {
  value = aws_eip.this.public_ip
}
output "pritunl_security_group" {
  value = module.ec2_sg.security_group_id
}


module "ec2_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "4.8.0"

  name        = var.name
  description = "${var.name} security group"
  vpc_id      = var.vpc_id

  ingress_with_source_security_group_id = var.ingress_with_source_security_group_id

  ingress_with_cidr_blocks = var.ingress_with_cidr_blocks

  egress_with_cidr_blocks = var.egress_with_cidr_blocks
}

module "efs_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "4.8.0"

  name        = "${var.name}-efs"
  description = "${var.name} efs security group"
  vpc_id      = var.vpc_id

  ingress_with_source_security_group_id = [
    {
      protocol                 = "6"
      from_port                = 2049
      to_port                  = 2049
      source_security_group_id = module.ec2_sg.security_group_id
    }
  ]
}


variable "vpc_id" {
  type        = string
  description = "ID of the VPC where to create security groups"
}

variable "public_subnets" {
  type        = list(any)
  description = "A list of public subnets where Pritunl server will be run"
}

variable "private_subnets" {
  type        = list(any)
  description = "A list of private subnets where EFS will be created"
}

variable "name" {
  default     = "pritunl"
  description = "Name used for all resources in this module"
}

variable "environment" {
  default     = "infra"
  description = "Environment name"
}

variable "instance_type" {
  default     = "t3.small"
  description = "Pritunl server instance type"
}

variable "encrypted" {
  default     = true
  description = "Encrypt or not EFS"
}

variable "kms_key_id" {
  default     = null
  description = "KMS key ID in case of using CMK"
}

variable "ingress_with_source_security_group_id" {
  type = list(object({
    protocol        = string
    from_port       = string
    to_port         = string
    security_groups = string
  }))

  default     = []
  description = "A list of Pritunl server security group rules where source is another security group"
}

variable "ingress_with_cidr_blocks" {
  type = list(object({
    protocol    = string
    from_port   = string
    to_port     = string
    cidr_blocks = string
  }))

  default     = []
  description = "A list of Pritunl server security group rules where source is CIDR"
}

variable "egress_with_cidr_blocks" {
  type = list(object({
    protocol    = string
    from_port   = string
    to_port     = string
    cidr_blocks = string
  }))

  default     = []
  description = "A list of Pritunl server security group rules for egress"
}