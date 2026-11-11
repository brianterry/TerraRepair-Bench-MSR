data "aws_partition" "current" {
  count = local.create ? 1 : 0
}
data "aws_caller_identity" "current" {
  count = local.create ? 1 : 0
}

data "aws_iam_session_context" "current" {
  count = local.create ? 1 : 0

  # This data source provides information on the IAM source role of an STS assumed role
  # For non-role ARNs, this data source simply passes the ARN through issuer ARN
  # Ref https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2327#issuecomment-1355581682
  # Ref https://github.com/hashicorp/terraform-provider-aws/issues/28381
  arn = try(data.aws_caller_identity.current[0].arn, "")
}

locals {
  create = var.create && var.putin_khuylo

  account_id = try(data.aws_caller_identity.current[0].account_id, "")
  partition  = try(data.aws_partition.current[0].partition, "")

  role_arn = try(aws_iam_role.this[0].arn, var.iam_role_arn)

  create_outposts_local_cluster = var.outpost_config != null
  enable_encryption_config      = var.encryption_config != null && !local.create_outposts_local_cluster

  create_auto_mode_iam_resources = try(var.compute_config.enabled, false) == true || var.create_auto_mode_iam_resources
}

################################################################################
# Cluster
################################################################################

resource "aws_eks_cluster" "this" {
  count = local.create ? 1 : 0

  region = var.region

  name                          = var.name
  role_arn                      = local.role_arn
  version                       = var.kubernetes_version
  enabled_cluster_log_types     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  deletion_protection           = var.deletion_protection
  bootstrap_self_managed_addons = false
  force_update_version          = var.force_update_version

  access_config {
    authentication_mode = var.authentication_mode

    # See access entries below - this is a one time operation from the EKS API.
    # Instead, we are hardcoding this to false and if users wish to achieve this
    # same functionality, we will do that through an access entry which can be
    # enabled or disabled at any time of their choosing using the variable
    # var.enable_cluster_creator_admin_permissions
    bootstrap_cluster_creator_admin_permissions = false
  }

  dynamic "control_plane_scaling_config" {
    for_each = var.control_plane_scaling_config != null ? [var.control_plane_scaling_config] : []

    content {
      tier = control_plane_scaling_config.value.tier
    }
  }

  dynamic "compute_config" {
    for_each = var.compute_config != null ? [var.compute_config] : []

    content {
      enabled       = compute_config.value.enabled
      node_pools    = compute_config.value.node_pools
      node_role_arn = compute_config.value.node_pools != null ? try(aws_iam_role.eks_auto[0].arn, compute_config.value.node_role_arn) : null
    }
  }

  vpc_config {
    security_group_ids      = compact(distinct(concat(var.additional_security_group_ids, [local.security_group_id], local.create_security_group ? [aws_security_group.cluster[0].id] : [], local.create_node_sg ? [aws_security_group.node[0].id] : [])))
    subnet_ids              = coalescelist(var.control_plane_subnet_ids, var.subnet_ids)
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access_cidrs
  }

  dynamic "kubernetes_network_config" {
    # Not valid on Outposts
    for_each = local.create_outposts_local_cluster ? [] : [1]

    content {
      dynamic "elastic_load_balancing" {
        for_each = var.compute_config != null ? [var.compute_config] : []

        content {
          enabled = elastic_load_balancing.value.enabled
        }
      }

      ip_family         = var.ip_family
      service_ipv4_cidr = var.service_ipv4_cidr
      service_ipv6_cidr = var.service_ipv6_cidr
    }
  }

  dynamic "outpost_config" {
    for_each = local.create_outposts_local_cluster ? [var.outpost_config] : []

    content {
      control_plane_instance_type = outpost_config.value.control_plane_instance_type

      dynamic "control_plane_placement" {
        for_each = outpost_config.value.control_plane_placement != null ? [outpost_config.value.control_plane_placement] : []

        content {
          group_name = control_plane_placement.value.group_name
        }
      }

      outpost_arns = outpost_config.value.outpost_arns
    }
  }

  encryption_config {
    provider {
      key_arn = var.create_kms_key ? module.kms.key_arn : try(var.encryption_config.provider_key_arn, null)
    }
    resources = ["secrets"]
  }

  dynamic "remote_network_config" {
    # Not valid on Outposts
    for_each = var.remote_network_config != null && !local.create_outposts_local_cluster ? [var.remote_network_config] : []

    content {
      dynamic "remote_node_networks" {
        for_each = [remote_network_config.value.remote_node_networks]

        content {
          cidrs = remote_node_networks.value.cidrs
        }
      }

      dynamic "remote_pod_networks" {
        for_each = remote_network_config.value.remote_pod_networks != null ? [remote_network_config.value.remote_pod_networks] : []

        content {
          cidrs = remote_pod_networks.value.cidrs
        }
      }
    }
  }

  dynamic "storage_config" {
    for_each = var.compute_config != null ? [var.compute_config] : []

    content {
      block_storage {
        enabled = storage_config.value.enabled
      }
    }
  }

  dynamic "upgrade_policy" {
    for_each = var.upgrade_policy != null ? [var.upgrade_policy] : []

    content {
      support_type = upgrade_policy.value.support_type
    }
  }

  dynamic "zonal_shift_config" {
    for_each = var.zonal_shift_config != null ? [var.zonal_shift_config] : []

    content {
      enabled = zonal_shift_config.value.enabled
    }
  }

  tags = merge(
    var.tags,
    var.cluster_tags,
  )

  dynamic "timeouts" {
    for_each = var.timeouts != null ? [var.timeouts] : []

    content {
      create = var.timeouts.create
      update = var.timeouts.update
      delete = var.timeouts.delete
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.this,
    aws_security_group_rule.cluster,
    aws_security_group_rule.node,
    aws_cloudwatch_log_group.this,
    aws_iam_policy.cni_ipv6_policy,
  ]

  lifecycle {
    ignore_changes = [
      access_config[0].bootstrap_cluster_creator_admin_permissions,
      bootstrap_self_managed_addons,
    ]
  }
}

resource "aws_ec2_tag" "cluster_primary_security_group" {
  # This should not affect the name of the cluster primary security group
  # Ref: https://github.com/terraform-aws-modules/terraform-aws-eks/pull/2006
  # Ref: https://github.com/terraform-aws-modules/terraform-aws-eks/pull/2008
  for_each = { for k, v in merge(var.tags, var.cluster_tags) :
    k => v if local.create && k != "Name" && var.create_primary_security_group_tags
  }

  region = var.region

  resource_id = aws_eks_cluster.this[0].vpc_config[0].cluster_security_group_id
  key         = each.key
  value       = each.value
}

resource "aws_cloudwatch_log_group" "this" {
  count = local.create && var.create_cloudwatch_log_group ? 1 : 0

  region = var.region

  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = 365
  kms_key_id        = var.cloudwatch_log_group_kms_key_id
  log_group_class   = var.cloudwatch_log_group_class

  tags = merge(
    var.tags,
    var.cloudwatch_log_group_tags,
    { Name = "/aws/eks/${var.name}/cluster" }
  )
}

################################################################################
# Access Entry
################################################################################

locals {
  # This replaces the one time logic from the EKS API with something that can be
  # better controlled by users through Terraform
  bootstrap_cluster_creator_admin_permissions = { for k, v in {
    cluster_creator = {
      principal_arn = try(data.aws_iam_session_context.current[0].issuer_arn, "")
      type          = "STANDARD"

      policy_associations = {
        admin = {
          policy_arn = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  } : k => v if var.enable_cluster_creator_admin_permissions }

  # Merge the bootstrap behavior with the entries that users provide
  merged_access_entries = merge(
    local.bootstrap_cluster_creator_admin_permissions,
    var.access_entries,
  )

  # Flatten out entries and policy associations so users can specify the policy
  # associations within a single entry
  flattened_access_entries = flatten([
    for entry_key, entry_val in local.merged_access_entries : [
      for pol_key, pol_val in entry_val.policy_associations :
      merge(
        {
          principal_arn = entry_val.principal_arn
          entry_key     = entry_key
          pol_key       = pol_key
        },
        { for k, v in {
          association_policy_arn              = pol_val.policy_arn
          association_access_scope_type       = pol_val.access_scope.type
          association_access_scope_namespaces = try(pol_val.access_scope.namespaces, null)
        } : k => v if !contains(["EC2_LINUX", "EC2_WINDOWS", "FARGATE_LINUX", "HYBRID_LINUX"], lookup(entry_val, "type", "STANDARD")) },
      )
    ]
  ])
}

resource "aws_eks_access_entry" "this" {
  for_each = { for k, v in local.merged_access_entries : k => v if local.create }

  region = var.region

  cluster_name      = aws_eks_cluster.this[0].id
  kubernetes_groups = try(each.value.kubernetes_groups, null)
  principal_arn     = each.value.principal_arn
  type              = try(each.value.type, null)
  user_name         = try(each.value.user_name, null)

  tags = merge(
    var.tags,
    try(each.value.tags, {}),
  )
}

resource "aws_eks_access_policy_association" "this" {
  for_each = { for k, v in local.flattened_access_entries : "${v.entry_key}_${v.pol_key}" => v if local.create }

  region = var.region

  access_scope {
    namespaces = each.value.association_access_scope_namespaces
    type       = each.value.association_access_scope_type
  }

  cluster_name = aws_eks_cluster.this[0].id

  policy_arn    = each.value.association_policy_arn
  principal_arn = each.value.principal_arn

  depends_on = [
    aws_eks_access_entry.this,
  ]
}

################################################################################
# KMS Key
################################################################################

module "kms" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-kms.git?ref=fe1df92ed7444f5e93c4b9d12f0184a6fb3d9d27"

  create = local.create && var.create_kms_key && local.enable_encryption_config # not valid on Outposts

  region = var.region

  description             = coalesce(var.kms_key_description, "${var.name} cluster encryption key")
  key_usage               = "ENCRYPT_DECRYPT"
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  enable_key_rotation     = var.enable_kms_key_rotation
  rotation_period_in_days = var.kms_key_rotation_period_in_days

  # Policy
  enable_default_policy     = var.kms_key_enable_default_policy
  key_owners                = var.kms_key_owners
  key_administrators        = coalescelist(var.kms_key_administrators, [try(data.aws_iam_session_context.current[0].issuer_arn, "")])
  key_users                 = concat([local.role_arn], var.kms_key_users)
  key_service_users         = var.kms_key_service_users
  source_policy_documents   = var.kms_key_source_policy_documents
  override_policy_documents = var.kms_key_override_policy_documents

  # Aliases
  aliases = var.kms_key_aliases
  computed_aliases = {
    # Computed since users can pass in computed values for cluster name such as random provider resources
    cluster = { name = "eks/${var.name}" }
  }

  tags = merge(
    var.tags,
  )
}

################################################################################
# Cluster Security Group
# Defaults follow https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html
################################################################################

locals {
  security_group_name   = coalesce(var.security_group_name, "${var.name}-cluster")
  create_security_group = local.create && var.create_security_group

  security_group_id = local.create_security_group ? aws_security_group.cluster[0].id : var.security_group_id

  # Do not add rules to node security group if the module is not creating it
  cluster_security_group_rules = { for k, v in {
    ingress_nodes_443 = {
      description                = "Node groups to cluster API"
      protocol                   = "tcp"
      from_port                  = 443
      to_port                    = 443
      type                       = "ingress"
      source_node_security_group = true
    }
  } : k => v if local.create_node_sg }
}

resource "aws_security_group" "cluster" {
  count = local.create_security_group ? 1 : 0

  region = var.region

  name        = var.security_group_use_name_prefix ? null : local.security_group_name
  name_prefix = var.security_group_use_name_prefix ? "${local.security_group_name}${var.prefix_separator}" : null
  description = var.security_group_description
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    { "Name" = local.security_group_name },
    var.security_group_tags
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "cluster" {
  for_each = { for k, v in merge(
    local.cluster_security_group_rules,
    var.security_group_additional_rules
  ) : k => v if local.create_security_group }

  region = var.region

  security_group_id        = aws_security_group.cluster[0].id
  protocol                 = each.value.protocol
  from_port                = each.value.from_port
  to_port                  = each.value.to_port
  type                     = each.value.type
  description              = try(each.value.description, null)
  cidr_blocks              = try(each.value.cidr_blocks, null)
  ipv6_cidr_blocks         = try(each.value.ipv6_cidr_blocks, null)
  prefix_list_ids          = try(each.value.prefix_list_ids, null)
  self                     = try(each.value.self, null)
  source_security_group_id = try(each.value.source_node_security_group, false) ? local.node_security_group_id : try(each.value.source_security_group_id, null)
}

################################################################################
# IRSA
# Note - this is different from EKS identity provider
################################################################################

locals {
  # Not available on outposts
  create_oidc_provider = local.create && var.enable_irsa && !local.create_outposts_local_cluster

  oidc_root_ca_thumbprint = local.create_oidc_provider && var.include_oidc_root_ca_thumbprint ? [data.tls_certificate.this[0].certificates[0].sha1_fingerprint] : []
}

data "tls_certificate" "this" {
  # Not available on outposts
  count = local.create_oidc_provider && var.include_oidc_root_ca_thumbprint ? 1 : 0

  url = aws_eks_cluster.this[0].identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "oidc_provider" {
  # Not available on outposts
  count = local.create_oidc_provider ? 1 : 0

  client_id_list  = distinct(compact(concat(["sts.amazonaws.com"], var.openid_connect_audiences)))
  thumbprint_list = concat(local.oidc_root_ca_thumbprint, var.custom_oidc_thumbprints)
  url             = aws_eks_cluster.this[0].identity[0].oidc[0].issuer

  tags = merge(
    { Name = "${var.name}-eks-irsa" },
    var.tags
  )
}

################################################################################
# IAM Role
################################################################################

locals {
  create_iam_role        = local.create && var.create_iam_role
  iam_role_name          = coalesce(var.iam_role_name, "${var.name}-cluster")
  iam_role_policy_prefix = "arn:${local.partition}:iam::aws:policy"

  cluster_encryption_policy_name = coalesce(var.encryption_policy_name, "${local.iam_role_name}-ClusterEncryption")

  # Standard EKS cluster
  eks_standard_iam_role_policies = { for k, v in {
    AmazonEKSClusterPolicy = "${local.iam_role_policy_prefix}/AmazonEKSClusterPolicy",
  } : k => v if !local.create_outposts_local_cluster && !local.create_auto_mode_iam_resources }

  # EKS cluster with EKS auto mode enabled
  eks_auto_mode_iam_role_policies = { for k, v in {
    AmazonEKSClusterPolicy       = "${local.iam_role_policy_prefix}/AmazonEKSClusterPolicy"
    AmazonEKSComputePolicy       = "${local.iam_role_policy_prefix}/AmazonEKSComputePolicy"
    AmazonEKSBlockStoragePolicy  = "${local.iam_role_policy_prefix}/AmazonEKSBlockStoragePolicy"
    AmazonEKSLoadBalancingPolicy = "${local.iam_role_policy_prefix}/AmazonEKSLoadBalancingPolicy"
    AmazonEKSNetworkingPolicy    = "${local.iam_role_policy_prefix}/AmazonEKSNetworkingPolicy"
  } : k => v if !local.create_outposts_local_cluster && local.create_auto_mode_iam_resources }

  # EKS local cluster on Outposts
  eks_outpost_iam_role_policies = { for k, v in {
    AmazonEKSClusterPolicy = "${local.iam_role_policy_prefix}/AmazonEKSLocalOutpostClusterPolicy"
  } : k => v if local.create_outposts_local_cluster && !local.create_auto_mode_iam_resources }
}

data "aws_iam_policy_document" "assume_role_policy" {
  count = local.create && var.create_iam_role ? 1 : 0

  statement {
    sid = "EKSClusterAssumeRole"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
    ]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    dynamic "principals" {
      for_each = local.create_outposts_local_cluster ? [1] : []

      content {
        type        = "Service"
        identifiers = ["ec2.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role" "this" {
  count = local.create_iam_role ? 1 : 0

  name        = var.iam_role_use_name_prefix ? null : local.iam_role_name
  name_prefix = var.iam_role_use_name_prefix ? "${local.iam_role_name}${var.prefix_separator}" : null
  path        = var.iam_role_path
  description = var.iam_role_description

  assume_role_policy    = data.aws_iam_policy_document.assume_role_policy[0].json
  permissions_boundary  = var.iam_role_permissions_boundary
  force_detach_policies = true

  tags = merge(var.tags, var.iam_role_tags)
}

# Policies attached ref https://docs.aws.amazon.com/eks/latest/userguide/service_IAM_role.html
resource "aws_iam_role_policy_attachment" "this" {
  for_each = { for k, v in merge(
    local.eks_standard_iam_role_policies,
    local.eks_auto_mode_iam_role_policies,
    local.eks_outpost_iam_role_policies,
  ) : k => v if local.create_iam_role }

  policy_arn = each.value
  role       = aws_iam_role.this[0].name
}

resource "aws_iam_role_policy_attachment" "additional" {
  for_each = { for k, v in var.iam_role_additional_policies : k => v if local.create_iam_role }

  policy_arn = each.value
  role       = aws_iam_role.this[0].name
}

# Using separate attachment due to `The "for_each" value depends on resource attributes that cannot be determined until apply`
resource "aws_iam_role_policy_attachment" "cluster_encryption" {
  # Encryption config not available on Outposts
  count = local.create_iam_role && var.attach_encryption_policy && local.enable_encryption_config ? 1 : 0

  policy_arn = aws_iam_policy.cluster_encryption[0].arn
  role       = aws_iam_role.this[0].name
}

resource "aws_iam_policy" "cluster_encryption" {
  # Encryption config not available on Outposts
  count = local.create_iam_role && var.attach_encryption_policy && local.enable_encryption_config ? 1 : 0

  name        = var.encryption_policy_use_name_prefix ? null : local.cluster_encryption_policy_name
  name_prefix = var.encryption_policy_use_name_prefix ? local.cluster_encryption_policy_name : null
  description = var.encryption_policy_description
  path        = var.encryption_policy_path

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ListGrants",
          "kms:DescribeKey",
        ]
        Effect   = "Allow"
        Resource = var.create_kms_key ? module.kms.key_arn : var.encryption_config.provider_key_arn
      },
    ]
  })

  tags = merge(var.tags, var.encryption_policy_tags)
}

data "aws_iam_policy_document" "custom" {
  count = local.create_iam_role && local.create_auto_mode_iam_resources && var.enable_auto_mode_custom_tags ? 1 : 0

  dynamic "statement" {
    for_each = var.enable_auto_mode_custom_tags ? [1] : []

    content {
      sid = "Compute"
      actions = [
        "ec2:CreateFleet",
        "ec2:RunInstances",
        "ec2:CreateLaunchTemplate",
      ]
      resources = ["*"]

      condition {
        test     = "StringEquals"
        variable = "aws:RequestTag/eks:eks-cluster-name"
        values   = ["$${aws:PrincipalTag/eks:eks-cluster-name}"]
      }

      condition {
        test     = "StringLike"
        variable = "aws:RequestTag/eks:kubernetes-node-class-name"
        values   = ["*"]
      }

      condition {
        test     = "StringLike"
        variable = "aws:RequestTag/eks:kubernetes-node-pool-name"
        values   = ["*"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.enable_auto_mode_custom_tags ? [1] : []

    content {
      sid = "Storage"
      actions = [
        "ec2:CreateVolume",
        "ec2:CreateSnapshot",
      ]
      resources = [
        "arn:${local.partition}:ec2:*:*:volume/*",
        "arn:${local.partition}:ec2:*:*:snapshot/*",
      ]

      condition {
        test     = "StringEquals"
        variable = "aws:RequestTag/eks:eks-cluster-name"
        values   = ["$${aws:PrincipalTag/eks:eks-cluster-name}"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.enable_auto_mode_custom_tags ? [1] : []

    content {
      sid       = "Networking"
      actions   = ["ec2:CreateNetworkInterface"]
      resources = ["*"]

      condition {
        test     = "StringEquals"
        variable = "aws:RequestTag/eks:eks-cluster-name"
        values   = ["$${aws:PrincipalTag/eks:eks-cluster-name}"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:RequestTag/eks:kubernetes-cni-node-name"
        values   = ["*"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.enable_auto_mode_custom_tags ? [1] : []

    content {
      sid = "LoadBalancer"
      actions = [
        "elasticloadbalancing:CreateLoadBalancer",
        "elasticloadbalancing:CreateTargetGroup",
        "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:CreateRule",
        "ec2:CreateSecurityGroup",
      ]
      resources = ["*"]

      condition {
        test     = "StringEquals"
        variable = "aws:RequestTag/eks:eks-cluster-name"
        values   = ["$${aws:PrincipalTag/eks:eks-cluster-name}"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.enable_auto_mode_custom_tags ? [1] : []

    content {
      sid       = "ShieldProtection"
      actions   = ["shield:CreateProtection"]
      resources = ["*"]

      condition {
        test     = "StringEquals"
        variable = "aws:RequestTag/eks:eks-cluster-name"
        values   = ["$${aws:PrincipalTag/eks:eks-cluster-name}"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.enable_auto_mode_custom_tags ? [1] : []

    content {
      sid       = "ShieldTagResource"
      actions   = ["shield:TagResource"]
      resources = ["arn:${local.partition}:shield::*:protection/*"]

      condition {
        test     = "StringEquals"
        variable = "aws:RequestTag/eks:eks-cluster-name"
        values   = ["$${aws:PrincipalTag/eks:eks-cluster-name}"]
      }
    }
  }
}

resource "aws_iam_policy" "custom" {
  count = local.create_iam_role && local.create_auto_mode_iam_resources && var.enable_auto_mode_custom_tags ? 1 : 0

  name        = var.iam_role_use_name_prefix ? null : local.iam_role_name
  name_prefix = var.iam_role_use_name_prefix ? "${local.iam_role_name}-" : null
  path        = var.iam_role_path
  description = var.iam_role_description

  policy = data.aws_iam_policy_document.custom[0].json

  tags = merge(var.tags, var.iam_role_tags)
}

resource "aws_iam_role_policy_attachment" "custom" {
  count = local.create_iam_role && local.create_auto_mode_iam_resources && var.enable_auto_mode_custom_tags ? 1 : 0

  policy_arn = aws_iam_policy.custom[0].arn
  role       = aws_iam_role.this[0].name
}

################################################################################
# EKS Addons
################################################################################

data "aws_eks_addon_version" "this" {
  for_each = var.addons != null && local.create && !local.create_outposts_local_cluster ? var.addons : {}

  region = var.region

  addon_name         = coalesce(each.value.name, each.key)
  kubernetes_version = coalesce(var.kubernetes_version, aws_eks_cluster.this[0].version)
  most_recent        = each.value.most_recent
}

resource "aws_eks_addon" "this" {
  # Not supported on outposts
  for_each = var.addons != null && local.create && !local.create_outposts_local_cluster ? { for k, v in var.addons : k => v if !v.before_compute } : {}

  region = var.region

  cluster_name = aws_eks_cluster.this[0].id
  addon_name   = coalesce(each.value.name, each.key)

  addon_version        = coalesce(each.value.addon_version, data.aws_eks_addon_version.this[each.key].version)
  configuration_values = each.value.configuration_values

  dynamic "pod_identity_association" {
    for_each = each.value.pod_identity_association != null ? each.value.pod_identity_association : []

    content {
      role_arn        = pod_identity_association.value.role_arn
      service_account = pod_identity_association.value.service_account
    }
  }

  preserve                    = each.value.preserve
  resolve_conflicts_on_create = each.value.resolve_conflicts_on_create
  resolve_conflicts_on_update = each.value.resolve_conflicts_on_update
  service_account_role_arn    = each.value.service_account_role_arn

  timeouts {
    create = each.value.timeouts.create != null ? each.value.timeouts.create : var.addons_timeouts.create
    update = each.value.timeouts.update != null ? each.value.timeouts.update : var.addons_timeouts.update
    delete = each.value.timeouts.delete != null ? each.value.timeouts.delete : var.addons_timeouts.delete
  }

  tags = merge(
    var.tags,
    each.value.tags,
  )

  # before_compute = false
  depends_on = [
    module.fargate_profile,
    module.eks_managed_node_group,
    module.self_managed_node_group,
  ]
}

resource "aws_eks_addon" "before_compute" {
  # Not supported on outposts
  for_each = var.addons != null && local.create && !local.create_outposts_local_cluster ? { for k, v in var.addons : k => v if v.before_compute } : {}

  region = var.region

  cluster_name = aws_eks_cluster.this[0].id
  addon_name   = coalesce(each.value.name, each.key)

  addon_version        = coalesce(each.value.addon_version, data.aws_eks_addon_version.this[each.key].version)
  configuration_values = each.value.configuration_values

  dynamic "pod_identity_association" {
    for_each = each.value.pod_identity_association != null ? each.value.pod_identity_association : []

    content {
      role_arn        = pod_identity_association.value.role_arn
      service_account = pod_identity_association.value.service_account
    }
  }

  preserve                    = each.value.preserve
  resolve_conflicts_on_create = each.value.resolve_conflicts_on_create
  resolve_conflicts_on_update = each.value.resolve_conflicts_on_update
  service_account_role_arn    = each.value.service_account_role_arn

  timeouts {
    create = each.value.timeouts.create != null ? each.value.timeouts.create : var.addons_timeouts.create
    update = each.value.timeouts.update != null ? each.value.timeouts.update : var.addons_timeouts.update
    delete = each.value.timeouts.delete != null ? each.value.timeouts.delete : var.addons_timeouts.delete
  }

  tags = merge(
    var.tags,
    each.value.tags,
  )
}

################################################################################
# EKS Identity Provider
# Note - this is different from IRSA
################################################################################

resource "aws_eks_identity_provider_config" "this" {
  for_each = var.identity_providers != null && local.create && !local.create_outposts_local_cluster ? var.identity_providers : {}

  region = var.region

  cluster_name = aws_eks_cluster.this[0].id

  oidc {
    client_id                     = each.value.client_id
    groups_claim                  = each.value.groups_claim
    groups_prefix                 = each.value.groups_prefix
    identity_provider_config_name = coalesce(each.value.identity_provider_config_name, each.key)
    issuer_url                    = each.value.issuer_url
    required_claims               = each.value.required_claims
    username_claim                = each.value.username_claim
    username_prefix               = each.value.username_prefix
  }

  tags = merge(
    var.tags,
    each.value.tags,
  )
}

################################################################################
# EKS Auto Node IAM Role
################################################################################

locals {
  create_node_iam_role = local.create && var.create_node_iam_role && local.create_auto_mode_iam_resources
  node_iam_role_name   = coalesce(var.node_iam_role_name, "${var.name}-eks-auto")
}

data "aws_iam_policy_document" "node_assume_role_policy" {
  count = local.create_node_iam_role ? 1 : 0

  statement {
    sid = "EKSAutoNodeAssumeRole"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
    ]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_auto" {
  count = local.create_node_iam_role ? 1 : 0

  name        = var.node_iam_role_use_name_prefix ? null : local.node_iam_role_name
  name_prefix = var.node_iam_role_use_name_prefix ? "${local.node_iam_role_name}-" : null
  path        = var.node_iam_role_path
  description = var.node_iam_role_description

  assume_role_policy    = data.aws_iam_policy_document.node_assume_role_policy[0].json
  permissions_boundary  = var.node_iam_role_permissions_boundary
  force_detach_policies = true

  tags = merge(var.tags, var.node_iam_role_tags)
}

# Policies attached ref https://docs.aws.amazon.com/eks/latest/userguide/service_IAM_role.html
resource "aws_iam_role_policy_attachment" "eks_auto" {
  for_each = { for k, v in {
    AmazonEKSWorkerNodeMinimalPolicy   = "${local.iam_role_policy_prefix}/AmazonEKSWorkerNodeMinimalPolicy",
    AmazonEC2ContainerRegistryPullOnly = "${local.iam_role_policy_prefix}/AmazonEC2ContainerRegistryPullOnly",
  } : k => v if local.create_node_iam_role }

  policy_arn = each.value
  role       = aws_iam_role.eks_auto[0].name
}

resource "aws_iam_role_policy_attachment" "eks_auto_additional" {
  for_each = { for k, v in var.node_iam_role_additional_policies : k => v if local.create_node_iam_role }

  policy_arn = each.value
  role       = aws_iam_role.eks_auto[0].name
}


locals {
  kubernetes_network_config = try(aws_eks_cluster.this[0].kubernetes_network_config[0], {})
}

# This sleep resource is used to provide a timed gap between the cluster creation and the downstream dependencies
# that consume the outputs from here. Any of the values that are used as triggers can be used in dependencies
# to ensure that the downstream resources are created after both the cluster is ready and the sleep time has passed.
# This was primarily added to give addons that need to be configured BEFORE data plane compute resources
# enough time to create and configure themselves before the data plane compute resources are created.
resource "time_sleep" "this" {
  count = var.create ? 1 : 0

  create_duration = var.dataplane_wait_duration

  triggers = {
    name               = aws_eks_cluster.this[0].id
    endpoint           = aws_eks_cluster.this[0].endpoint
    kubernetes_version = aws_eks_cluster.this[0].version
    service_cidr       = var.ip_family == "ipv6" ? try(local.kubernetes_network_config.service_ipv6_cidr, "") : try(local.kubernetes_network_config.service_ipv4_cidr, "")

    certificate_authority_data = aws_eks_cluster.this[0].certificate_authority[0].data
  }
}

################################################################################
# EKS IPV6 CNI Policy
# https://docs.aws.amazon.com/eks/latest/userguide/cni-iam-role.html#cni-iam-role-create-ipv6-policy
################################################################################

data "aws_iam_policy_document" "cni_ipv6_policy" {
  count = var.create && var.create_cni_ipv6_iam_policy ? 1 : 0

  statement {
    sid = "Describe"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeInstanceTypes"
    ]
    resources = ["*"]
  }

  statement {
    sid = "AssignIpv6Addresses"
    actions = [
      "ec2:AssignIpv6Addresses"
    ]
    resources = ["arn:${local.partition}:ec2:*:${local.account_id}:network-interface/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "CreateTags"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:${local.partition}:ec2:*:${local.account_id}:network-interface/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values   = [local.account_id]
    }
  }
}

# Note - we are keeping this to a minimum in hopes that its soon replaced with an AWS managed policy like `AmazonEKS_CNI_Policy`
resource "aws_iam_policy" "cni_ipv6_policy" {
  count = var.create && var.create_cni_ipv6_iam_policy ? 1 : 0

  # Will cause conflicts if trying to create on multiple clusters but necessary to reference by exact name in sub-modules
  name        = "AmazonEKS_CNI_IPv6_Policy"
  description = "IAM policy for EKS CNI to assign IPV6 addresses"
  policy      = data.aws_iam_policy_document.cni_ipv6_policy[0].json

  tags = var.tags
}

################################################################################
# Node Security Group
# Defaults follow https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html
# Plus NTP/HTTPS (otherwise nodes fail to launch)
################################################################################

locals {
  node_sg_name   = coalesce(var.node_security_group_name, "${var.name}-node")
  create_node_sg = var.create && var.create_node_security_group

  node_security_group_id = local.create_node_sg ? aws_security_group.node[0].id : var.node_security_group_id

  node_security_group_rules = {
    ingress_cluster_443 = {
      description                   = "Cluster API to node groups"
      protocol                      = "tcp"
      from_port                     = 443
      to_port                       = 443
      type                          = "ingress"
      source_cluster_security_group = true
    }
    ingress_cluster_kubelet = {
      description                   = "Cluster API to node kubelets"
      protocol                      = "tcp"
      from_port                     = 10250
      to_port                       = 10250
      type                          = "ingress"
      source_cluster_security_group = true
    }
    ingress_self_coredns_tcp = {
      description = "Node to node CoreDNS"
      protocol    = "tcp"
      from_port   = 53
      to_port     = 53
      type        = "ingress"
      self        = true
    }
    ingress_self_coredns_udp = {
      description = "Node to node CoreDNS UDP"
      protocol    = "udp"
      from_port   = 53
      to_port     = 53
      type        = "ingress"
      self        = true
    }
  }

  node_security_group_recommended_rules = { for k, v in {
    ingress_nodes_ephemeral = {
      description = "Node to node ingress on ephemeral ports"
      protocol    = "tcp"
      from_port   = 1025
      to_port     = 65535
      type        = "ingress"
      self        = true
    }
    # metrics-server, legacy port - TODO: remove this on the next breaking change at v22
    ingress_cluster_4443_webhook = {
      description                   = "Cluster API to node 4443/tcp webhook"
      protocol                      = "tcp"
      from_port                     = 4443
      to_port                       = 4443
      type                          = "ingress"
      source_cluster_security_group = true
    }
    # metrics-server, current EKS default port
    ingress_cluster_10251_webhook = {
      description                   = "Cluster API to node 10251/tcp webhook"
      protocol                      = "tcp"
      from_port                     = 10251
      to_port                       = 10251
      type                          = "ingress"
      source_cluster_security_group = true
    }
    # prometheus-adapter
    ingress_cluster_6443_webhook = {
      description                   = "Cluster API to node 6443/tcp webhook"
      protocol                      = "tcp"
      from_port                     = 6443
      to_port                       = 6443
      type                          = "ingress"
      source_cluster_security_group = true
    }
    # Karpenter
    ingress_cluster_8443_webhook = {
      description                   = "Cluster API to node 8443/tcp webhook"
      protocol                      = "tcp"
      from_port                     = 8443
      to_port                       = 8443
      type                          = "ingress"
      source_cluster_security_group = true
    }
    # ALB controller, NGINX
    ingress_cluster_9443_webhook = {
      description                   = "Cluster API to node 9443/tcp webhook"
      protocol                      = "tcp"
      from_port                     = 9443
      to_port                       = 9443
      type                          = "ingress"
      source_cluster_security_group = true
    }
  } : k => v if var.node_security_group_enable_recommended_rules }
}

resource "aws_security_group" "node" {
  count = local.create_node_sg ? 1 : 0

  region = var.region

  name        = var.node_security_group_use_name_prefix ? null : local.node_sg_name
  name_prefix = var.node_security_group_use_name_prefix ? "${local.node_sg_name}${var.prefix_separator}" : null
  description = var.node_security_group_description
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      "Name"                              = local.node_sg_name
      "kubernetes.io/cluster/${var.name}" = "owned"
    },
    var.node_security_group_tags
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "node" {
  for_each = { for k, v in merge(
    local.node_security_group_rules,
    local.node_security_group_recommended_rules,
    var.node_security_group_additional_rules,
  ) : k => v if local.create_node_sg }

  region = var.region

  security_group_id        = aws_security_group.node[0].id
  protocol                 = each.value.protocol
  from_port                = each.value.from_port
  to_port                  = each.value.to_port
  type                     = each.value.type
  description              = try(each.value.description, null)
  cidr_blocks              = try(each.value.cidr_blocks, null)
  ipv6_cidr_blocks         = try(each.value.ipv6_cidr_blocks, null)
  prefix_list_ids          = try(each.value.prefix_list_ids, null)
  self                     = try(each.value.self, null)
  source_security_group_id = try(each.value.source_cluster_security_group, false) ? local.security_group_id : try(each.value.source_security_group_id, null)
}

################################################################################
# Fargate Profile
################################################################################

module "fargate_profile" {
  source = "./modules/fargate-profile"

  for_each = var.create && !local.create_outposts_local_cluster && var.fargate_profiles != null ? var.fargate_profiles : {}

  create = each.value.create

  region = var.region

  # Pass through values to reduce GET requests from data sources
  partition  = local.partition
  account_id = local.account_id

  # Fargate Profile
  cluster_name      = time_sleep.this[0].triggers["name"]
  cluster_ip_family = var.ip_family
  name              = coalesce(each.value.name, each.key)
  subnet_ids        = coalesce(each.value.subnet_ids, var.subnet_ids)
  selectors         = each.value.selectors
  timeouts          = each.value.timeouts

  # IAM role
  create_iam_role               = each.value.create_iam_role
  iam_role_arn                  = each.value.iam_role_arn
  iam_role_name                 = each.value.iam_role_name
  iam_role_use_name_prefix      = each.value.iam_role_use_name_prefix
  iam_role_path                 = each.value.iam_role_path
  iam_role_description          = each.value.iam_role_description
  iam_role_permissions_boundary = each.value.iam_role_permissions_boundary
  iam_role_tags                 = each.value.iam_role_tags
  iam_role_attach_cni_policy    = each.value.iam_role_attach_cni_policy
  iam_role_additional_policies  = lookup(each.value, "iam_role_additional_policies", null)
  create_iam_role_policy        = each.value.create_iam_role_policy
  iam_role_policy_statements    = each.value.iam_role_policy_statements

  tags = merge(
    var.tags,
    each.value.tags,
  )
}

################################################################################
# EKS Managed Node Group
################################################################################

module "eks_managed_node_group" {
  source = "./modules/eks-managed-node-group"

  for_each = var.create && !local.create_outposts_local_cluster && var.eks_managed_node_groups != null ? var.eks_managed_node_groups : {}

  create = each.value.create

  region = var.region

  # Pass through values to reduce GET requests from data sources
  partition  = local.partition
  account_id = local.account_id

  cluster_name       = time_sleep.this[0].triggers["name"]
  kubernetes_version = each.value.kubernetes_version != null ? each.value.kubernetes_version : time_sleep.this[0].triggers["kubernetes_version"]


  # EKS Managed Node Group
  name            = coalesce(each.value.name, each.key)
  use_name_prefix = each.value.use_name_prefix

  subnet_ids = coalesce(each.value.subnet_ids, var.subnet_ids)

  min_size     = each.value.min_size
  max_size     = each.value.max_size
  desired_size = each.value.desired_size

  ami_id                         = each.value.ami_id
  ami_type                       = each.value.ami_type
  ami_release_version            = each.value.ami_release_version
  use_latest_ami_release_version = each.value.use_latest_ami_release_version

  capacity_type        = each.value.capacity_type
  disk_size            = each.value.disk_size
  force_update_version = each.value.force_update_version
  instance_types       = each.value.instance_types
  labels               = each.value.labels
  node_repair_config   = each.value.node_repair_config
  remote_access        = each.value.remote_access
  taints               = each.value.taints
  update_config        = each.value.update_config
  timeouts             = each.value.timeouts

  # User data
  cluster_endpoint           = try(time_sleep.this[0].triggers["endpoint"], "")
  cluster_auth_base64        = try(time_sleep.this[0].triggers["certificate_authority_data"], "")
  cluster_ip_family          = var.ip_family
  cluster_service_cidr       = try(time_sleep.this[0].triggers["service_cidr"], "")
  enable_bootstrap_user_data = each.value.enable_bootstrap_user_data
  pre_bootstrap_user_data    = each.value.pre_bootstrap_user_data
  post_bootstrap_user_data   = each.value.post_bootstrap_user_data
  bootstrap_extra_args       = each.value.bootstrap_extra_args
  user_data_template_path    = each.value.user_data_template_path
  cloudinit_pre_nodeadm      = each.value.cloudinit_pre_nodeadm
  cloudinit_post_nodeadm     = each.value.cloudinit_post_nodeadm

  # Launch Template
  create_launch_template                 = each.value.create_launch_template
  use_custom_launch_template             = each.value.use_custom_launch_template
  launch_template_id                     = each.value.launch_template_id
  launch_template_name                   = coalesce(each.value.launch_template_name, each.key)
  launch_template_use_name_prefix        = each.value.launch_template_use_name_prefix
  launch_template_version                = each.value.launch_template_version
  launch_template_default_version        = each.value.launch_template_default_version
  update_launch_template_default_version = each.value.update_launch_template_default_version
  launch_template_description            = coalesce(each.value.launch_template_description, "Custom launch template for ${coalesce(each.value.name, each.key)} EKS managed node group")
  launch_template_tags                   = each.value.launch_template_tags
  tag_specifications                     = each.value.tag_specifications

  ebs_optimized           = each.value.ebs_optimized
  key_name                = each.value.key_name
  disable_api_termination = each.value.disable_api_termination
  kernel_id               = each.value.kernel_id
  ram_disk_id             = each.value.ram_disk_id

  block_device_mappings              = each.value.block_device_mappings
  capacity_reservation_specification = each.value.capacity_reservation_specification
  cpu_options                        = each.value.cpu_options
  credit_specification               = each.value.credit_specification
  enclave_options                    = each.value.enclave_options
  instance_market_options            = each.value.instance_market_options
  license_specifications             = each.value.license_specifications
  metadata_options                   = each.value.metadata_options
  enable_monitoring                  = each.value.enable_monitoring
  enable_efa_support                 = each.value.enable_efa_support
  enable_efa_only                    = each.value.enable_efa_only
  efa_indices                        = each.value.efa_indices
  create_placement_group             = each.value.create_placement_group
  placement                          = each.value.placement
  network_interfaces                 = each.value.network_interfaces
  maintenance_options                = each.value.maintenance_options
  private_dns_name_options           = each.value.private_dns_name_options

  # IAM role
  create_iam_role               = each.value.create_iam_role
  iam_role_arn                  = each.value.iam_role_arn
  iam_role_name                 = each.value.iam_role_name
  iam_role_use_name_prefix      = each.value.iam_role_use_name_prefix
  iam_role_path                 = each.value.iam_role_path
  iam_role_description          = each.value.iam_role_description
  iam_role_permissions_boundary = each.value.iam_role_permissions_boundary
  iam_role_tags                 = each.value.iam_role_tags
  iam_role_attach_cni_policy    = each.value.iam_role_attach_cni_policy
  iam_role_additional_policies  = lookup(each.value, "iam_role_additional_policies", null)
  create_iam_role_policy        = each.value.create_iam_role_policy
  iam_role_policy_statements    = each.value.iam_role_policy_statements

  # Security group
  vpc_security_group_ids            = compact(concat([try(aws_security_group.node[0].id, local.node_security_group_id)], each.value.vpc_security_group_ids))
  cluster_primary_security_group_id = each.value.attach_cluster_primary_security_group ? aws_eks_cluster.this[0].vpc_config[0].cluster_security_group_id : null
  create_security_group             = each.value.create_security_group
  security_group_name               = each.value.security_group_name
  security_group_use_name_prefix    = each.value.security_group_use_name_prefix
  security_group_description        = each.value.security_group_description
  security_group_ingress_rules      = each.value.security_group_ingress_rules
  security_group_egress_rules       = each.value.security_group_egress_rules
  security_group_tags               = each.value.security_group_tags

  tags = merge(
    var.tags,
    each.value.tags,
  )
}

################################################################################
# Self Managed Node Group
################################################################################

module "self_managed_node_group" {
  source = "./modules/self-managed-node-group"

  for_each = var.create && var.self_managed_node_groups != null ? var.self_managed_node_groups : {}

  create = each.value.create

  region = var.region

  # Pass through values to reduce GET requests from data sources
  partition  = local.partition
  account_id = local.account_id

  cluster_name = time_sleep.this[0].triggers["name"]

  # Autoscaling Group
  create_autoscaling_group = each.value.create_autoscaling_group

  name            = coalesce(each.value.name, each.key)
  use_name_prefix = each.value.use_name_prefix

  availability_zones = each.value.availability_zones
  subnet_ids         = coalesce(each.value.subnet_ids, var.subnet_ids)

  min_size                = each.value.min_size
  max_size                = each.value.max_size
  desired_size            = each.value.desired_size
  desired_size_type       = each.value.desired_size_type
  capacity_rebalance      = each.value.capacity_rebalance
  default_instance_warmup = each.value.default_instance_warmup
  protect_from_scale_in   = each.value.protect_from_scale_in
  context                 = each.value.context

  create_placement_group    = each.value.create_placement_group
  placement_group           = each.value.placement_group
  health_check_type         = each.value.health_check_type
  health_check_grace_period = each.value.health_check_grace_period

  ignore_failed_scaling_activities = each.value.ignore_failed_scaling_activities

  force_delete          = each.value.force_delete
  termination_policies  = each.value.termination_policies
  suspended_processes   = each.value.suspended_processes
  max_instance_lifetime = each.value.max_instance_lifetime

  enabled_metrics     = each.value.enabled_metrics
  metrics_granularity = each.value.metrics_granularity

  initial_lifecycle_hooks     = each.value.initial_lifecycle_hooks
  instance_maintenance_policy = each.value.instance_maintenance_policy
  instance_refresh            = each.value.instance_refresh
  use_mixed_instances_policy  = each.value.use_mixed_instances_policy
  mixed_instances_policy      = each.value.mixed_instances_policy

  timeouts               = each.value.timeouts
  autoscaling_group_tags = each.value.autoscaling_group_tags

  # User data
  ami_type                   = each.value.ami_type
  cluster_endpoint           = try(time_sleep.this[0].triggers["endpoint"], "")
  cluster_auth_base64        = try(time_sleep.this[0].triggers["certificate_authority_data"], "")
  cluster_service_cidr       = try(time_sleep.this[0].triggers["service_cidr"], "")
  additional_cluster_dns_ips = each.value.additional_cluster_dns_ips
  cluster_ip_family          = var.ip_family
  pre_bootstrap_user_data    = each.value.pre_bootstrap_user_data
  post_bootstrap_user_data   = each.value.post_bootstrap_user_data
  bootstrap_extra_args       = each.value.bootstrap_extra_args
  user_data_template_path    = each.value.user_data_template_path
  cloudinit_pre_nodeadm      = each.value.cloudinit_pre_nodeadm
  cloudinit_post_nodeadm     = each.value.cloudinit_post_nodeadm

  # Launch Template
  create_launch_template                 = each.value.create_launch_template
  launch_template_id                     = each.value.launch_template_id
  launch_template_name                   = coalesce(each.value.launch_template_name, each.key)
  launch_template_use_name_prefix        = each.value.launch_template_use_name_prefix
  launch_template_version                = each.value.launch_template_version
  launch_template_default_version        = each.value.launch_template_default_version
  update_launch_template_default_version = each.value.update_launch_template_default_version
  launch_template_description            = coalesce(each.value.launch_template_description, "Custom launch template for ${coalesce(each.value.name, each.key)} self managed node group")
  launch_template_tags                   = each.value.launch_template_tags
  tag_specifications                     = each.value.tag_specifications

  ebs_optimized      = each.value.ebs_optimized
  ami_id             = each.value.ami_id
  kubernetes_version = each.value.kubernetes_version != null ? each.value.kubernetes_version : time_sleep.this[0].triggers["kubernetes_version"]
  instance_type      = each.value.instance_type
  key_name           = each.value.key_name

  disable_api_termination              = each.value.disable_api_termination
  instance_initiated_shutdown_behavior = each.value.instance_initiated_shutdown_behavior
  kernel_id                            = each.value.kernel_id
  ram_disk_id                          = each.value.ram_disk_id

  block_device_mappings              = each.value.block_device_mappings
  capacity_reservation_specification = each.value.capacity_reservation_specification
  cpu_options                        = each.value.cpu_options
  credit_specification               = each.value.credit_specification
  enclave_options                    = each.value.enclave_options
  instance_requirements              = each.value.instance_requirements
  instance_market_options            = each.value.instance_market_options
  license_specifications             = each.value.license_specifications
  metadata_options                   = each.value.metadata_options
  enable_monitoring                  = each.value.enable_monitoring
  enable_efa_support                 = each.value.enable_efa_support
  enable_efa_only                    = each.value.enable_efa_only
  efa_indices                        = each.value.efa_indices
  network_interfaces                 = each.value.network_interfaces
  placement                          = each.value.placement
  maintenance_options                = each.value.maintenance_options
  private_dns_name_options           = each.value.private_dns_name_options

  # IAM role
  create_iam_instance_profile   = each.value.create_iam_instance_profile
  iam_instance_profile_arn      = each.value.iam_instance_profile_arn
  iam_role_name                 = each.value.iam_role_name
  iam_role_use_name_prefix      = each.value.iam_role_use_name_prefix
  iam_role_path                 = each.value.iam_role_path
  iam_role_description          = each.value.iam_role_description
  iam_role_permissions_boundary = each.value.iam_role_permissions_boundary
  iam_role_tags                 = each.value.iam_role_tags
  iam_role_attach_cni_policy    = each.value.iam_role_attach_cni_policy
  iam_role_additional_policies  = lookup(each.value, "iam_role_additional_policies", null)
  create_iam_role_policy        = each.value.create_iam_role_policy
  iam_role_policy_statements    = each.value.iam_role_policy_statements

  # Access entry
  create_access_entry = each.value.create_access_entry
  iam_role_arn        = each.value.iam_role_arn

  # Security group
  vpc_security_group_ids            = compact(concat([try(aws_security_group.node[0].id, local.node_security_group_id)], each.value.vpc_security_group_ids))
  cluster_primary_security_group_id = each.value.attach_cluster_primary_security_group ? aws_eks_cluster.this[0].vpc_config[0].cluster_security_group_id : null
  create_security_group             = each.value.create_security_group
  security_group_name               = each.value.security_group_name
  security_group_use_name_prefix    = each.value.security_group_use_name_prefix
  security_group_description        = each.value.security_group_description
  security_group_ingress_rules      = each.value.security_group_ingress_rules
  security_group_egress_rules       = each.value.security_group_egress_rules
  security_group_tags               = each.value.security_group_tags

  tags = merge(
    var.tags,
    each.value.tags,
  )
}


################################################################################
# Cluster
################################################################################

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = try(aws_eks_cluster.this[0].arn, null)

  depends_on = [
    aws_eks_access_entry.this,
    aws_eks_access_policy_association.this,
  ]
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = try(aws_eks_cluster.this[0].certificate_authority[0].data, null)

  depends_on = [
    aws_eks_access_entry.this,
    aws_eks_access_policy_association.this,
  ]
}

output "cluster_endpoint" {
  description = "Endpoint for your Kubernetes API server"
  value       = try(aws_eks_cluster.this[0].endpoint, null)

  depends_on = [
    aws_eks_access_entry.this,
    aws_eks_access_policy_association.this,
  ]
}

output "cluster_id" {
  description = "The ID of the EKS cluster. Note: currently a value is returned only for local EKS clusters created on Outposts"
  value       = try(aws_eks_cluster.this[0].cluster_id, "")
}

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = try(aws_eks_cluster.this[0].name, "")

  depends_on = [
    aws_eks_access_entry.this,
    aws_eks_access_policy_association.this,
  ]
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = try(aws_eks_cluster.this[0].identity[0].oidc[0].issuer, null)
}

output "cluster_dualstack_oidc_issuer_url" {
  description = "Dual-stack compatible URL on the EKS cluster for the OpenID Connect identity provider"
  # https://github.com/aws/containers-roadmap/issues/2038#issuecomment-2278450601
  value = try(replace(replace(aws_eks_cluster.this[0].identity[0].oidc[0].issuer, "https://oidc.eks.", "https://oidc-eks."), ".amazonaws.com/", ".api.aws/"), null)
}

output "cluster_version" {
  description = "The Kubernetes version for the cluster"
  value       = try(aws_eks_cluster.this[0].version, null)
}

output "cluster_platform_version" {
  description = "Platform version for the cluster"
  value       = try(aws_eks_cluster.this[0].platform_version, null)
}

output "cluster_status" {
  description = "Status of the EKS cluster. One of `CREATING`, `ACTIVE`, `DELETING`, `FAILED`"
  value       = try(aws_eks_cluster.this[0].status, null)
}

output "cluster_primary_security_group_id" {
  description = "Cluster security group that was created by Amazon EKS for the cluster. Managed node groups use this security group for control-plane-to-data-plane communication. Referred to as 'Cluster security group' in the EKS console"
  value       = try(aws_eks_cluster.this[0].vpc_config[0].cluster_security_group_id, null)
}

output "cluster_service_cidr" {
  description = "The CIDR block where Kubernetes pod and service IP addresses are assigned from"
  value       = var.ip_family == "ipv6" ? try(aws_eks_cluster.this[0].kubernetes_network_config[0].service_ipv6_cidr, null) : try(aws_eks_cluster.this[0].kubernetes_network_config[0].service_ipv4_cidr, null)
}

output "cluster_ip_family" {
  description = "The IP family used by the cluster (e.g. `ipv4` or `ipv6`)"
  value       = try(aws_eks_cluster.this[0].kubernetes_network_config[0].ip_family, null)
}

output "cluster_control_plane_scaling_tier" {
  description = "The EKS Provisioned Control Plane scaling tier for the cluster"
  value       = try(aws_eks_cluster.this[0].control_plane_scaling_config[0].tier, null)
}

################################################################################
# Access Entry
################################################################################

output "access_entries" {
  description = "Map of access entries created and their attributes"
  value       = aws_eks_access_entry.this
}

output "access_policy_associations" {
  description = "Map of eks cluster access policy associations created and their attributes"
  value       = aws_eks_access_policy_association.this
}

################################################################################
# KMS Key
################################################################################

output "kms_key_arn" {
  description = "The Amazon Resource Name (ARN) of the key"
  value       = module.kms.key_arn
}

output "kms_key_id" {
  description = "The globally unique identifier for the key"
  value       = module.kms.key_id
}

output "kms_key_policy" {
  description = "The IAM resource policy set on the key"
  value       = module.kms.key_policy
}

################################################################################
# Cluster Security Group
################################################################################

output "cluster_security_group_arn" {
  description = "Amazon Resource Name (ARN) of the cluster security group"
  value       = try(aws_security_group.cluster[0].arn, null)
}

output "cluster_security_group_id" {
  description = "ID of the cluster security group"
  value       = try(aws_security_group.cluster[0].id, null)
}

################################################################################
# Node Security Group
################################################################################

output "node_security_group_arn" {
  description = "Amazon Resource Name (ARN) of the node shared security group"
  value       = try(aws_security_group.node[0].arn, null)
}

output "node_security_group_id" {
  description = "ID of the node shared security group"
  value       = try(aws_security_group.node[0].id, null)
}

################################################################################
# IRSA
################################################################################

output "oidc_provider" {
  description = "The OpenID Connect identity provider (issuer URL without leading `https://`)"
  value       = try(replace(aws_eks_cluster.this[0].identity[0].oidc[0].issuer, "https://", ""), null)
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider if `enable_irsa = true`"
  value       = try(aws_iam_openid_connect_provider.oidc_provider[0].arn, null)
}

output "cluster_tls_certificate_sha1_fingerprint" {
  description = "The SHA1 fingerprint of the public key of the cluster's certificate"
  value       = try(data.tls_certificate.this[0].certificates[0].sha1_fingerprint, null)
}

################################################################################
# IAM Role
################################################################################

output "cluster_iam_role_name" {
  description = "Cluster IAM role name"
  value       = try(aws_iam_role.this[0].name, null)
}

output "cluster_iam_role_arn" {
  description = "Cluster IAM role ARN"
  value       = try(aws_iam_role.this[0].arn, null)
}

output "cluster_iam_role_unique_id" {
  description = "Stable and unique string identifying the IAM role"
  value       = try(aws_iam_role.this[0].unique_id, null)
}

################################################################################
# EKS Auto Node IAM Role
################################################################################

output "node_iam_role_name" {
  description = "EKS Auto node IAM role name"
  value       = try(aws_iam_role.eks_auto[0].name, null)
}

output "node_iam_role_arn" {
  description = "EKS Auto node IAM role ARN"
  value       = try(aws_iam_role.eks_auto[0].arn, null)
}

output "node_iam_role_unique_id" {
  description = "Stable and unique string identifying the IAM role"
  value       = try(aws_iam_role.eks_auto[0].unique_id, null)
}

################################################################################
# EKS Addons
################################################################################

output "cluster_addons" {
  description = "Map of attribute maps for all EKS cluster addons enabled"
  value       = merge(aws_eks_addon.this, aws_eks_addon.before_compute)
}

################################################################################
# EKS Identity Provider
################################################################################

output "cluster_identity_providers" {
  description = "Map of attribute maps for all EKS identity providers enabled"
  value       = aws_eks_identity_provider_config.this
}

################################################################################
# CloudWatch Log Group
################################################################################

output "cloudwatch_log_group_name" {
  description = "Name of cloudwatch log group created"
  value       = try(aws_cloudwatch_log_group.this[0].name, null)
}

output "cloudwatch_log_group_arn" {
  description = "Arn of cloudwatch log group created"
  value       = try(aws_cloudwatch_log_group.this[0].arn, null)
}

################################################################################
# Fargate Profile
################################################################################

output "fargate_profiles" {
  description = "Map of attribute maps for all EKS Fargate Profiles created"
  value       = module.fargate_profile
}

################################################################################
# EKS Managed Node Group
################################################################################

output "eks_managed_node_groups" {
  description = "Map of attribute maps for all EKS managed node groups created"
  value       = module.eks_managed_node_group
}

output "eks_managed_node_groups_autoscaling_group_names" {
  description = "List of the autoscaling group names created by EKS managed node groups"
  value       = compact(flatten([for group in module.eks_managed_node_group : group.node_group_autoscaling_group_names]))
}

################################################################################
# Self Managed Node Group
################################################################################

output "self_managed_node_groups" {
  description = "Map of attribute maps for all self managed node groups created"
  value       = module.self_managed_node_group
}

output "self_managed_node_groups_autoscaling_group_names" {
  description = "List of the autoscaling group names created by self-managed node groups"
  value       = compact([for group in module.self_managed_node_group : group.autoscaling_group_name])
}


variable "create" {
  description = "Controls if resources should be created (affects nearly all resources)"
  type        = bool
  default     = true
}

variable "prefix_separator" {
  description = "The separator to use between the prefix and the generated timestamp for resource names"
  type        = string
  default     = "-"
}

variable "region" {
  description = "Region where the resource(s) will be managed. Defaults to the Region set in the provider configuration"
  type        = string
  default     = null
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

################################################################################
# Cluster
################################################################################

variable "name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = ""
}

variable "kubernetes_version" {
  description = "Kubernetes `<major>.<minor>` version to use for the EKS cluster (i.e.: `1.33`)"
  type        = string
  default     = null
}

variable "enabled_log_types" {
  description = "A list of the desired control plane logs to enable. For more information, see Amazon EKS Control Plane Logging documentation (https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html)"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection for the cluster. When enabled, the cluster cannot be deleted unless deletion protection is first disabled"
  type        = bool
  default     = null
}

variable "force_update_version" {
  description = "Force version update by overriding upgrade-blocking readiness checks when updating a cluster"
  type        = bool
  default     = null
}

variable "authentication_mode" {
  description = "The authentication mode for the cluster. Valid values are `CONFIG_MAP`, `API` or `API_AND_CONFIG_MAP`"
  type        = string
  default     = "API_AND_CONFIG_MAP"
}

variable "compute_config" {
  description = "Configuration block for the cluster compute configuration"
  type = object({
    enabled       = optional(bool, false)
    node_pools    = optional(list(string))
    node_role_arn = optional(string)
  })
  default = null
}

variable "control_plane_scaling_config" {
  description = "Configuration block for the EKS Provisioned Control Plane scaling tier. Valid values for tier are `standard`, `tier-xl`, `tier-2xl`, and `tier-4xl`"
  type = object({
    tier = string
  })
  default = null
}

variable "upgrade_policy" {
  description = "Configuration block for the cluster upgrade policy"
  type = object({
    support_type = optional(string)
  })
  default = null
}

variable "remote_network_config" {
  description = "Configuration block for the cluster remote network configuration"
  type = object({
    remote_node_networks = object({
      cidrs = optional(list(string))
    })
    remote_pod_networks = optional(object({
      cidrs = optional(list(string))
    }))
  })
  default = null
}

variable "zonal_shift_config" {
  description = "Configuration block for the cluster zonal shift"
  type = object({
    enabled = optional(bool)
  })
  default = null
}

variable "additional_security_group_ids" {
  description = "List of additional, externally created security group IDs to attach to the cluster control plane"
  type        = list(string)
  default     = []
}

variable "control_plane_subnet_ids" {
  description = "A list of subnet IDs where the EKS cluster control plane (ENIs) will be provisioned. Used for expanding the pool of subnets used by nodes/node groups without replacing the EKS control plane"
  type        = list(string)
  default     = []
}

variable "subnet_ids" {
  description = "A list of subnet IDs where the nodes/node groups will be provisioned. If `control_plane_subnet_ids` is not provided, the EKS cluster control plane (ENIs) will be provisioned in these subnets"
  type        = list(string)
  default     = []
}

variable "endpoint_private_access" {
  description = "Indicates whether or not the Amazon EKS private API server endpoint is enabled"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Indicates whether or not the Amazon EKS public API server endpoint is enabled"
  type        = bool
  default     = false
}

variable "endpoint_public_access_cidrs" {
  description = "List of CIDR blocks which can access the Amazon EKS public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ip_family" {
  description = "The IP family used to assign Kubernetes pod and service addresses. Valid values are `ipv4` (default) and `ipv6`. You can only specify an IP family when you create a cluster, changing this value will force a new cluster to be created"
  type        = string
  default     = "ipv4"
}

variable "service_ipv4_cidr" {
  description = "The CIDR block to assign Kubernetes service IP addresses from. If you don't specify a block, Kubernetes assigns addresses from either the 10.100.0.0/16 or 172.20.0.0/16 CIDR blocks"
  type        = string
  default     = null
}

variable "service_ipv6_cidr" {
  description = "The CIDR block to assign Kubernetes pod and service IP addresses from if `ipv6` was specified when the cluster was created. Kubernetes assigns service addresses from the unique local address range (fc00::/7) because you can't specify a custom IPv6 CIDR block when you create the cluster"
  type        = string
  default     = null
}

variable "outpost_config" {
  description = "Configuration for the AWS Outpost to provision the cluster on"
  type = object({
    control_plane_instance_type = optional(string)
    control_plane_placement = optional(object({
      group_name = string
    }))
    outpost_arns = list(string)
  })
  default = null
}

variable "encryption_config" {
  description = "Configuration block with encryption configuration for the cluster"
  type = object({
    provider_key_arn = optional(string)
    resources        = optional(list(string), ["secrets"])
  })
  default = {}
}

variable "attach_encryption_policy" {
  description = "Indicates whether or not to attach an additional policy for the cluster IAM role to utilize the encryption key provided"
  type        = bool
  default     = true
}

variable "cluster_tags" {
  description = "A map of additional tags to add to the cluster"
  type        = map(string)
  default     = {}
}

variable "create_primary_security_group_tags" {
  description = "Indicates whether or not to tag the cluster's primary security group. This security group is created by the EKS service, not the module, and therefore tagging is handled after cluster creation"
  type        = bool
  default     = true
}

variable "timeouts" {
  description = "Create, update, and delete timeout configurations for the cluster"
  type = object({
    create = optional(string)
    update = optional(string)
    delete = optional(string)
  })
  default = null
}

################################################################################
# Access Entry
################################################################################

variable "access_entries" {
  description = "Map of access entries to add to the cluster"
  type = map(object({
    # Access entry
    kubernetes_groups = optional(list(string))
    principal_arn     = string
    type              = optional(string, "STANDARD")
    user_name         = optional(string)
    tags              = optional(map(string), {})
    # Access policy association
    policy_associations = optional(map(object({
      policy_arn = string
      access_scope = object({
        namespaces = optional(list(string))
        type       = string
      })
    })), {})
  }))
  default = {}
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Indicates whether or not to add the cluster creator (the identity used by Terraform) as an administrator via access entry"
  type        = bool
  default     = false
}

################################################################################
# KMS Key
################################################################################

variable "create_kms_key" {
  description = "Controls if a KMS key for cluster encryption should be created"
  type        = bool
  default     = true
}

variable "kms_key_description" {
  description = "The description of the key as viewed in AWS console"
  type        = string
  default     = null
}

variable "kms_key_deletion_window_in_days" {
  description = "The waiting period, specified in number of days. After the waiting period ends, AWS KMS deletes the KMS key. If you specify a value, it must be between `7` and `30`, inclusive. If you do not specify a value, it defaults to `30`"
  type        = number
  default     = null
}

variable "enable_kms_key_rotation" {
  description = "Specifies whether key rotation is enabled"
  type        = bool
  default     = true
}

variable "kms_key_rotation_period_in_days" {
  description = "Custom period of time between each key rotation date. If you specify a value, it must be between `90` and `2560`, inclusive. If you do not specify a value, it defaults to `365`"
  type        = number
  default     = null
}

variable "kms_key_enable_default_policy" {
  description = "Specifies whether to enable the default key policy"
  type        = bool
  default     = true
}

variable "kms_key_owners" {
  description = "A list of IAM ARNs for those who will have full key permissions (`kms:*`)"
  type        = list(string)
  default     = []
}

variable "kms_key_administrators" {
  description = "A list of IAM ARNs for [key administrators](https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-default.html#key-policy-default-allow-administrators). If no value is provided, the current caller identity is used to ensure at least one key admin is available"
  type        = list(string)
  default     = []
}

variable "kms_key_users" {
  description = "A list of IAM ARNs for [key users](https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-default.html#key-policy-default-allow-users)"
  type        = list(string)
  default     = []
}

variable "kms_key_service_users" {
  description = "A list of IAM ARNs for [key service users](https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-default.html#key-policy-service-integration)"
  type        = list(string)
  default     = []
}

variable "kms_key_source_policy_documents" {
  description = "List of IAM policy documents that are merged together into the exported document. Statements must have unique `sid`s"
  type        = list(string)
  default     = []
}

variable "kms_key_override_policy_documents" {
  description = "List of IAM policy documents that are merged together into the exported document. In merging, statements with non-blank `sid`s will override statements with the same `sid`"
  type        = list(string)
  default     = []
}

variable "kms_key_aliases" {
  description = "A list of aliases to create. Note - due to the use of `toset()`, values must be static strings and not computed values"
  type        = list(string)
  default     = []
}

################################################################################
# CloudWatch Log Group
################################################################################

variable "create_cloudwatch_log_group" {
  description = "Determines whether a log group is created by this module for the cluster logs. If not, AWS will automatically create one if logging is enabled"
  type        = bool
  default     = true
}

variable "cloudwatch_log_group_retention_in_days" {
  description = "Number of days to retain log events. Default retention - 365 days"
  type        = number
  default     = 365
}

variable "cloudwatch_log_group_kms_key_id" {
  description = "If a KMS Key ARN is set, this key will be used to encrypt the corresponding log group. Please be sure that the KMS Key has an appropriate key policy (https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html)"
  type        = string
  default     = null
}

variable "cloudwatch_log_group_class" {
  description = "Specified the log class of the log group. Possible values are: `STANDARD` or `INFREQUENT_ACCESS`"
  type        = string
  default     = null
}

variable "cloudwatch_log_group_tags" {
  description = "A map of additional tags to add to the cloudwatch log group created"
  type        = map(string)
  default     = {}
}

################################################################################
# Cluster Security Group
################################################################################

variable "create_security_group" {
  description = "Determines if a security group is created for the cluster. Note: the EKS service creates a primary security group for the cluster by default"
  type        = bool
  default     = true
}

variable "security_group_id" {
  description = "Existing security group ID to be attached to the cluster"
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "ID of the VPC where the cluster security group will be provisioned"
  type        = string
  default     = null
}

variable "security_group_name" {
  description = "Name to use on cluster security group created"
  type        = string
  default     = null
}

variable "security_group_use_name_prefix" {
  description = "Determines whether cluster security group name (`cluster_security_group_name`) is used as a prefix"
  type        = bool
  default     = true
}

variable "security_group_description" {
  description = "Description of the cluster security group created"
  type        = string
  default     = "EKS cluster security group"
}

variable "security_group_additional_rules" {
  description = "List of additional security group rules to add to the cluster security group created. Set `source_node_security_group = true` inside rules to set the `node_security_group` as source"
  type = map(object({
    protocol                   = optional(string, "tcp")
    from_port                  = number
    to_port                    = number
    type                       = optional(string, "ingress")
    description                = optional(string)
    cidr_blocks                = optional(list(string))
    ipv6_cidr_blocks           = optional(list(string))
    prefix_list_ids            = optional(list(string))
    self                       = optional(bool)
    source_node_security_group = optional(bool, false)
    source_security_group_id   = optional(string)
  }))
  default = {}
}

variable "security_group_tags" {
  description = "A map of additional tags to add to the cluster security group created"
  type        = map(string)
  default     = {}
}

################################################################################
# EKS IPV6 CNI Policy
################################################################################

variable "create_cni_ipv6_iam_policy" {
  description = "Determines whether to create an [`AmazonEKS_CNI_IPv6_Policy`](https://docs.aws.amazon.com/eks/latest/userguide/cni-iam-role.html#cni-iam-role-create-ipv6-policy)"
  type        = bool
  default     = false
}

################################################################################
# Node Security Group
################################################################################

variable "create_node_security_group" {
  description = "Determines whether to create a security group for the node groups or use the existing `node_security_group_id`"
  type        = bool
  default     = true
}

variable "node_security_group_id" {
  description = "ID of an existing security group to attach to the node groups created"
  type        = string
  default     = ""
}

variable "node_security_group_name" {
  description = "Name to use on node security group created"
  type        = string
  default     = null
}

variable "node_security_group_use_name_prefix" {
  description = "Determines whether node security group name (`node_security_group_name`) is used as a prefix"
  type        = bool
  default     = true
}

variable "node_security_group_description" {
  description = "Description of the node security group created"
  type        = string
  default     = "EKS node shared security group"
}

variable "node_security_group_additional_rules" {
  description = "List of additional security group rules to add to the node security group created. Set `source_cluster_security_group = true` inside rules to set the `cluster_security_group` as source"
  type = map(object({
    protocol                      = optional(string, "tcp")
    from_port                     = number
    to_port                       = number
    type                          = optional(string, "ingress")
    description                   = optional(string)
    cidr_blocks                   = optional(list(string))
    ipv6_cidr_blocks              = optional(list(string))
    prefix_list_ids               = optional(list(string))
    self                          = optional(bool)
    source_cluster_security_group = optional(bool, false)
    source_security_group_id      = optional(string)
  }))
  default = {}
}

variable "node_security_group_enable_recommended_rules" {
  description = "Determines whether to enable recommended security group rules for the node security group created. This includes node-to-node TCP ingress on ephemeral ports"
  type        = bool
  default     = true
}

variable "node_security_group_tags" {
  description = "A map of additional tags to add to the node security group created"
  type        = map(string)
  default     = {}
}

################################################################################
# IRSA
################################################################################

variable "enable_irsa" {
  description = "Determines whether to create an OpenID Connect Provider for EKS to enable IRSA"
  type        = bool
  default     = true
}

variable "openid_connect_audiences" {
  description = "List of OpenID Connect audience client IDs to add to the IRSA provider"
  type        = list(string)
  default     = []
}

variable "include_oidc_root_ca_thumbprint" {
  description = "Determines whether to include the root CA thumbprint in the OpenID Connect (OIDC) identity provider's server certificate(s)"
  type        = bool
  default     = true
}

variable "custom_oidc_thumbprints" {
  description = "Additional list of server certificate thumbprints for the OpenID Connect (OIDC) identity provider's server certificate(s)"
  type        = list(string)
  default     = []
}

################################################################################
# Cluster IAM Role
################################################################################

variable "create_iam_role" {
  description = "Determines whether an IAM role is created for the cluster"
  type        = bool
  default     = true
}

variable "iam_role_arn" {
  description = "Existing IAM role ARN for the cluster. Required if `create_iam_role` is set to `false`"
  type        = string
  default     = null
}

variable "iam_role_name" {
  description = "Name to use on IAM role created"
  type        = string
  default     = null
}

variable "iam_role_use_name_prefix" {
  description = "Determines whether the IAM role name (`iam_role_name`) is used as a prefix"
  type        = bool
  default     = true
}

variable "iam_role_path" {
  description = "The IAM role path"
  type        = string
  default     = null
}

variable "iam_role_description" {
  description = "Description of the role"
  type        = string
  default     = null
}

variable "iam_role_permissions_boundary" {
  description = "ARN of the policy that is used to set the permissions boundary for the IAM role"
  type        = string
  default     = null
}

variable "iam_role_additional_policies" {
  description = "Additional policies to be added to the IAM role"
  type        = map(string)
  default     = {}
}

variable "iam_role_tags" {
  description = "A map of additional tags to add to the IAM role created"
  type        = map(string)
  default     = {}
}

variable "encryption_policy_use_name_prefix" {
  description = "Determines whether cluster encryption policy name (`cluster_encryption_policy_name`) is used as a prefix"
  type        = bool
  default     = true
}

variable "encryption_policy_name" {
  description = "Name to use on cluster encryption policy created"
  type        = string
  default     = null
}

variable "encryption_policy_description" {
  description = "Description of the cluster encryption policy created"
  type        = string
  default     = "Cluster encryption policy to allow cluster role to utilize CMK provided"
}

variable "encryption_policy_path" {
  description = "Cluster encryption policy path"
  type        = string
  default     = null
}

variable "encryption_policy_tags" {
  description = "A map of additional tags to add to the cluster encryption policy created"
  type        = map(string)
  default     = {}
}

variable "dataplane_wait_duration" {
  description = "Duration to wait after the EKS cluster has become active before creating the dataplane components (EKS managed node group(s), self-managed node group(s), Fargate profile(s))"
  type        = string
  default     = "30s"
}

variable "enable_auto_mode_custom_tags" {
  description = "Determines whether to enable permissions for custom tags resources created by EKS Auto Mode"
  type        = bool
  default     = true
}

variable "create_auto_mode_iam_resources" {
  description = "Determines whether to create/attach IAM resources for EKS Auto Mode. Useful for when using only custom node pools and not built-in EKS Auto Mode node pools"
  type        = bool
  default     = false
}

################################################################################
# EKS Addons
################################################################################

variable "addons" {
  description = "Map of cluster addon configurations to enable for the cluster. Addon name can be the map keys or set with `name`"
  type = map(object({
    name                 = optional(string) # will fall back to map key
    before_compute       = optional(bool, false)
    most_recent          = optional(bool, true)
    addon_version        = optional(string)
    configuration_values = optional(string)
    pod_identity_association = optional(list(object({
      role_arn        = string
      service_account = string
    })))
    preserve                    = optional(bool, true)
    resolve_conflicts_on_create = optional(string, "NONE")
    resolve_conflicts_on_update = optional(string, "OVERWRITE")
    service_account_role_arn    = optional(string)
    timeouts = optional(object({
      create = optional(string)
      update = optional(string)
      delete = optional(string)
    }), {})
    tags = optional(map(string), {})
  }))
  default = null
}

variable "addons_timeouts" {
  description = "Create, update, and delete timeout configurations for the cluster addons"
  type = object({
    create = optional(string)
    update = optional(string)
    delete = optional(string)
  })
  default = {}
}

################################################################################
# EKS Identity Provider
################################################################################

variable "identity_providers" {
  description = "Map of cluster identity provider configurations to enable for the cluster. Note - this is different/separate from IRSA"
  type = map(object({
    client_id                     = string
    groups_claim                  = optional(string)
    groups_prefix                 = optional(string)
    identity_provider_config_name = optional(string) # will fall back to map key
    issuer_url                    = string
    required_claims               = optional(map(string))
    username_claim                = optional(string)
    username_prefix               = optional(string)
    tags                          = optional(map(string), {})
  }))
  default = null
}

################################################################################
# EKS Auto Node IAM Role
################################################################################

variable "create_node_iam_role" {
  description = "Determines whether an EKS Auto node IAM role is created"
  type        = bool
  default     = true
}

variable "node_iam_role_name" {
  description = "Name to use on the EKS Auto node IAM role created"
  type        = string
  default     = null
}

variable "node_iam_role_use_name_prefix" {
  description = "Determines whether the EKS Auto node IAM role name (`node_iam_role_name`) is used as a prefix"
  type        = bool
  default     = true
}

variable "node_iam_role_path" {
  description = "The EKS Auto node IAM role path"
  type        = string
  default     = null
}

variable "node_iam_role_description" {
  description = "Description of the EKS Auto node IAM role"
  type        = string
  default     = null
}

variable "node_iam_role_permissions_boundary" {
  description = "ARN of the policy that is used to set the permissions boundary for the EKS Auto node IAM role"
  type        = string
  default     = null
}

variable "node_iam_role_additional_policies" {
  description = "Additional policies to be added to the EKS Auto node IAM role"
  type        = map(string)
  default     = {}
}

variable "node_iam_role_tags" {
  description = "A map of additional tags to add to the EKS Auto node IAM role created"
  type        = map(string)
  default     = {}
}

################################################################################
# Fargate
################################################################################

variable "fargate_profiles" {
  description = "Map of Fargate Profile definitions to create"
  type = map(object({
    create = optional(bool)

    # Fargate profile
    name       = optional(string) # Will fall back to map key
    subnet_ids = optional(list(string))
    selectors = optional(list(object({
      labels    = optional(map(string))
      namespace = string
    })))
    timeouts = optional(object({
      create = optional(string)
      delete = optional(string)
    }))

    # IAM role
    create_iam_role               = optional(bool)
    iam_role_arn                  = optional(string)
    iam_role_name                 = optional(string)
    iam_role_use_name_prefix      = optional(bool)
    iam_role_path                 = optional(string)
    iam_role_description          = optional(string)
    iam_role_permissions_boundary = optional(string)
    iam_role_tags                 = optional(map(string))
    iam_role_attach_cni_policy    = optional(bool)
    iam_role_additional_policies  = optional(map(string))
    create_iam_role_policy        = optional(bool)