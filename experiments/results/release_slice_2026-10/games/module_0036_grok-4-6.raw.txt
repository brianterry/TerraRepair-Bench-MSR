# Required for public ECR where Karpenter artifacts are hosted
provider "aws" {
  region = "us-east-1"
  alias  = "ecr"
}

locals {
  environment = var.environment_name
  service     = var.service_name
  region      = var.aws_region

  env  = local.service
  name = "${local.environment}-${local.service}"

  # Mapping
  hosted_zone_name                            = var.hosted_zone_name
  ingress_type                                = var.ingress_type
  aws_secret_manager_git_private_ssh_key_name = var.aws_secret_manager_git_private_ssh_key_name
  cluster_version                             = var.cluster_version
  argocd_secret_manager_name                  = var.argocd_secret_manager_name_suffix
  eks_admin_role_name                         = var.eks_admin_role_name

  gitops_workloads_url      = "${var.gitops_workloads_org}/${var.gitops_workloads_repo}"
  gitops_workloads_path     = var.gitops_workloads_path
  gitops_workloads_revision = var.gitops_workloads_revision

  gitops_addons_url      = "${var.gitops_addons_org}/${var.gitops_addons_repo}"
  gitops_addons_basepath = var.gitops_addons_basepath
  gitops_addons_path     = var.gitops_addons_path
  gitops_addons_revision = var.gitops_addons_revision

  # Route 53 Ingress Weights
  argocd_route53_weight      = var.argocd_route53_weight
  route53_weight             = var.route53_weight
  ecsfrontend_route53_weight = var.ecsfrontend_route53_weight

  eks_cluster_domain = "${local.environment}.${local.hosted_zone_name}" # for external-dns

  tag_val_vpc            = local.environment
  tag_val_public_subnet  = "${local.environment}-public-"
  tag_val_private_subnet = "${local.environment}-private-"

  node_group_name = "managed-ondemand"

  #---------------------------------------------------------------
  # ARGOCD ADD-ON APPLICATION
  #---------------------------------------------------------------

  aws_addons = {
    enable_cert_manager          = true
    enable_aws_ebs_csi_resources = true # generate gp2 and gp3 storage classes for ebs-csi
    #enable_aws_efs_csi_driver                    = true
    #enable_aws_fsx_csi_driver                    = true
    enable_aws_cloudwatch_metrics = true
    #enable_aws_privateca_issuer                  = true
    #enable_cluster_autoscaler                    = true
    enable_external_dns                 = true
    enable_external_secrets             = true
    enable_aws_load_balancer_controller = true
    #enable_fargate_fluentbit                     = true
    enable_aws_for_fluentbit = true
    #enable_aws_node_termination_handler          = true
    enable_karpenter = true
    #enable_velero                                = true
    #enable_aws_gateway_api_controller            = true
    #enable_aws_secrets_store_csi_driver_provider = true
  }
  oss_addons = {
    #enable_argo_rollouts                         = true
    #enable_argo_workflows                        = true
    #enable_cluster_proportional_autoscaler       = true
    #enable_gatekeeper                            = true
    #enable_gpu_operator                          = true
    enable_ingress_nginx = true
    enable_kyverno       = true
    #enable_kube_prometheus_stack                 = true
    enable_metrics_server = true
    #enable_prometheus_adapter                    = true
    #enable_secrets_store_csi_driver              = true
    #enable_vpa                                   = true
    #enable_foo                                   = true # you can add any addon here, make sure to update the gitops repo with the corresponding application set
  }
  addons = merge(local.aws_addons, local.oss_addons, { kubernetes_version = local.cluster_version })

  #----------------------------------------------------------------
  # GitOps Bridge, define metadatas to pass from Terraform to ArgoCD
  #----------------------------------------------------------------

  addons_metadata = merge(
    try(module.eks_blueprints_addons.gitops_metadata, {}), # eks blueprints addons automatically expose metadatas
    {
      aws_cluster_name = module.eks.cluster_name
      aws_region       = local.region
      aws_account_id   = data.aws_caller_identity.current.account_id
      aws_vpc_id       = data.aws_vpc.vpc.id
      cluster_endpoint = try(module.eks.cluster_endpoint, {})
      env              = local.env
    },
    {
      argocd_password                             = bcrypt(data.aws_secretsmanager_secret_version.admin_password_version.secret_string)
      aws_secret_manager_git_private_ssh_key_name = local.aws_secret_manager_git_private_ssh_key_name

      gitops_workloads_url      = local.gitops_workloads_url
      gitops_workloads_path     = local.gitops_workloads_path
      gitops_workloads_revision = local.gitops_workloads_revision

      addons_repo_url      = local.gitops_addons_url
      addons_repo_basepath = local.gitops_addons_basepath
      addons_repo_path     = local.gitops_addons_path
      addons_repo_revision = local.gitops_addons_revision
    },
    {
      eks_cluster_domain         = local.eks_cluster_domain
      external_dns_policy        = "sync"
      ingress_type               = local.ingress_type
      argocd_route53_weight      = local.argocd_route53_weight
      route53_weight             = local.route53_weight
      ecsfrontend_route53_weight = local.ecsfrontend_route53_weight
      #target_group_arn = local.service == "blue" ? data.aws_lb_target_group.tg_blue.arn : data.aws_lb_target_group.tg_green.arn # <-- Add this line
      #      external_lb_dns = data.aws_lb.alb.dns_name
    }
  )

  #---------------------------------------------------------------
  # Manifests for bootstraping the cluster for addons & workloads
  #---------------------------------------------------------------

  argocd_apps = {
    addons    = file("${path.module}/../../bootstrap/addons.yaml")
    workloads = file("${path.module}/../../bootstrap/workloads.yaml")
  }


  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }

}

# Find the user currently in use by AWS
data "aws_caller_identity" "current" {}

data "aws_vpc" "vpc" {
  filter {
    name   = "tag:Name"
    values = [local.tag_val_vpc]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "tag:Name"
    values = ["${local.tag_val_private_subnet}*"]
  }
}

#Add Tags for the new cluster in the VPC Subnets
resource "aws_ec2_tag" "private_subnets" {
  for_each    = toset(data.aws_subnets.private.ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${local.environment}-${local.service}"
  value       = "shared"
}

data "aws_subnets" "public" {
  filter {
    name   = "tag:Name"
    values = ["${local.tag_val_public_subnet}*"]
  }
}

#Add Tags for the new cluster in the VPC Subnets
resource "aws_ec2_tag" "public_subnets" {
  for_each    = toset(data.aws_subnets.public.ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${local.environment}-${local.service}"
  value       = "shared"
}

# Get HostedZone four our deployment
data "aws_route53_zone" "sub" {
  name = "${local.environment}.${local.hosted_zone_name}"
}

################################################################################
# AWS Secret Manager for argocd password
################################################################################

data "aws_secretsmanager_secret" "argocd" {
  name = "${local.argocd_secret_manager_name}.${local.environment}"
}

data "aws_secretsmanager_secret_version" "admin_password_version" {
  secret_id = data.aws_secretsmanager_secret.argocd.id
}

################################################################################
# EKS Cluster
################################################################################
#tfsec:ignore:aws-eks-enable-control-plane-logging
module "eks" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git?ref=c347e86dc2c2e9c28a4bfd41020a6b407f5a59ba"

  cluster_name                         = local.name
  cluster_version                      = local.cluster_version
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access       = false
  cluster_endpoint_public_access_cidrs = ["10.0.0.0/8"]

  vpc_id     = data.aws_vpc.vpc.id
  subnet_ids = data.aws_subnets.private.ids

  #we uses only 1 security group to allow connection with Fargate, MNG, and Karpenter nodes
  create_node_security_group = false
  eks_managed_node_groups = {
    initial = {
      node_group_name = local.node_group_name
      instance_types  = ["m5.large"]

      min_size     = 1
      max_size     = 5
      desired_size = 3
      subnet_ids   = data.aws_subnets.private.ids
    }
  }

  manage_aws_auth_configmap = true
  aws_auth_roles = concat(
    [for team in module.eks_blueprints_dev_teams : team.aws_auth_configmap_role],
    [
      module.eks_blueprints_platform_teams.aws_auth_configmap_role,
      {
        rolearn  = module.eks_blueprints_addons.karpenter.node_iam_role_arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups = [
          "system:bootstrappers",
          "system:nodes",
        ]
      },
      {
        rolearn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.eks_admin_role_name}" # The ARN of the IAM role
        username = "ops-role"                                                                                      # The user name within Kubernetes to map to the IAM role
        groups   = ["system:masters"]                                                                              # A list of groups within Kubernetes to which the role is mapped; Checkout K8s Role and Rolebindings
      }
    ]
  )

  tags = merge(local.tags, {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = "${local.environment}-${local.service}"
  })
}

data "aws_iam_role" "eks_admin_role_name" {
  count = local.eks_admin_role_name != "" ? 1 : 0
  name  = local.eks_admin_role_name
}

################################################################################
# EKS Blueprints Teams
################################################################################
module "eks_blueprints_platform_teams" {
  source = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-teams.git?ref=a5261d0d548f6904733a72e0c9ae1c0d8cd2c5d8"

  name = "team-platform"

  # Enables elevated, admin privileges for this team
  enable_admin = true

  # Define who can impersonate the team-platform Role
  users = [
    data.aws_caller_identity.current.arn,
    try(data.aws_iam_role.eks_admin_role_name[0].arn, data.aws_caller_identity.current.arn),
  ]
  cluster_arn       = module.eks.cluster_arn
  oidc_provider_arn = module.eks.oidc_provider_arn

  labels = {
    "elbv2.k8s.aws/pod-readiness-gate-inject" = "enabled",
    "appName"                                 = "platform-team-app",
    "projectName"                             = "project-platform",
    #"pod-security.kubernetes.io/enforce"      = "restricted",
  }

  annotations = {
    team = "platform"
  }

  namespaces = {
    "team-platform" = {

      resource_quota = {
        hard = {
          "requests.cpu"    = "10000m",
          "requests.memory" = "20Gi",
          "limits.cpu"      = "20000m",
          "limits.memory"   = "50Gi",
          "pods"            = "20",
          "secrets"         = "20",
          "services"        = "20"
        }
      }

      limit_range = {
        limit = [
          {
            type = "Pod"
            max = {
              cpu    = "1000m"
              memory = "1Gi"
            },
            min = {
              cpu    = "10m"
              memory = "4Mi"
            }
          },
          {
            type = "PersistentVolumeClaim"
            min = {
              storage = "24M"
            }
          }
        ]
      }

    }

  }

  tags = local.tags
}

module "eks_blueprints_dev_teams" {
  source = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-teams.git?ref=a5261d0d548f6904733a72e0c9ae1c0d8cd2c5d8"

  for_each = {
    burnham = {
      labels = {
        "elbv2.k8s.aws/pod-readiness-gate-inject" = "enabled",
        "appName"                                 = "burnham-team-app",
        "projectName"                             = "project-burnham",
        #"pod-security.kubernetes.io/enforce"      = "restricted",
      }
    }
    riker = {
      labels = {
        "elbv2.k8s.aws/pod-readiness-gate-inject" = "enabled",
        "appName"                                 = "riker-team-app",
        "projectName"                             = "project-riker",
      }
    }
  }
  name = "team-${each.key}"

  users             = [data.aws_caller_identity.current.arn]
  cluster_arn       = module.eks.cluster_arn
  oidc_provider_arn = module.eks.oidc_provider_arn

  labels = merge(
    {
      team = each.key
    },
    try(each.value.labels, {})
  )

  annotations = {
    team = each.key
  }

  namespaces = {
    "team-${each.key}" = {
      labels = merge(
        {
          team = each.key
        },
        try(each.value.labels, {})
      )

      resource_quota = {
        hard = {
          "requests.cpu"    = "100",
          "requests.memory" = "20Gi",
          "limits.cpu"      = "200",
          "limits.memory"   = "50Gi",
          "pods"            = "100",
          "secrets"         = "10",
          "services"        = "20"
        }
      }

      limit_range = {
        limit = [
          {
            type = "Pod"
            max = {
              cpu    = "2"
              memory = "1Gi"
            }
            min = {
              cpu    = "10m"
              memory = "4Mi"
            }
          },
          {
            type = "PersistentVolumeClaim"
            min = {
              storage = "24M"
            }
          },
          {
            type = "Container"
            default = {
              cpu    = "50m"
              memory = "24Mi"
            }
          }
        ]
      }
    }
  }

  tags = local.tags

}

module "eks_blueprints_ecsdemo_teams" {
  source = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-teams.git?ref=a5261d0d548f6904733a72e0c9ae1c0d8cd2c5d8"

  for_each = {
    ecsdemo-frontend = {}
    ecsdemo-nodejs   = {}
    ecsdemo-crystal  = {}
  }
  name = "team-${each.key}"

  users             = [data.aws_caller_identity.current.arn]
  cluster_arn       = module.eks.cluster_arn
  oidc_provider_arn = module.eks.oidc_provider_arn

  labels = {
    "elbv2.k8s.aws/pod-readiness-gate-inject" = "enabled",
    "appName"                                 = "${each.key}-app",
    "projectName"                             = each.key,
    "environment"                             = "dev",
  }

  annotations = {
    team = each.key
  }

  namespaces = {
    (each.key) = {
      labels = {
        "elbv2.k8s.aws/pod-readiness-gate-inject" = "enabled",
        "appName"                                 = "${each.key}-app",
        "projectName"                             = each.key,
        "environment"                             = "dev",
      }

      resource_quota = {
        hard = {
          "requests.cpu"    = "100",
          "requests.memory" = "20Gi",
          "limits.cpu"      = "200",
          "limits.memory"   = "50Gi",
          "pods"            = "100",
          "secrets"         = "10",
          "services"        = "20"
        }
      }

      limit_range = {
        limit = [
          {
            type = "Pod"
            max = {
              cpu    = "2"
              memory = "1Gi"
            }
            min = {
              cpu    = "10m"
              memory = "4Mi"
            }
          },
          {
            type = "PersistentVolumeClaim"
            min = {
              storage = "24M"
            }
          },
          {
            type = "Container"
            default = {
              cpu    = "50m"
              memory = "24Mi"
            }
          }
        ]
      }
    }
  }

  tags = local.tags
}

################################################################################
# GitOps Bridge: Private ssh keys for git
################################################################################
data "aws_secretsmanager_secret" "workload_repo_secret" {
  name = local.aws_secret_manager_git_private_ssh_key_name
}

data "aws_secretsmanager_secret_version" "workload_repo_secret" {
  secret_id = data.aws_secretsmanager_secret.workload_repo_secret.id
}

resource "kubernetes_namespace" "argocd" {
  depends_on = [module.eks_blueprints_addons]
  metadata {
    name = "argocd"
  }
}

resource "kubernetes_secret" "git_secrets" {

  for_each = {
    git-addons = {
      type = "git"
      url  = local.gitops_addons_url
      # comment if you want to uses public repo wigh syntax "https://github.com/xxx" syntax, uncomment when using syntax "git@github.com:xxx"
      sshPrivateKey = data.aws_secretsmanager_secret_version.workload_repo_secret.secret_string
    }
    git-workloads = {
      type = "git"
      url  = local.gitops_workloads_url
      # comment if you want to uses public repo wigh syntax "https://github.com/xxx" syntax, uncomment when using syntax "git@github.com:xxx"
      sshPrivateKey = data.aws_secretsmanager_secret_version.workload_repo_secret.secret_string
    }
  }
  metadata {
    name      = each.key
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repo-creds"
    }
  }
  data = each.value
}

################################################################################
# GitOps Bridge: Bootstrap
################################################################################
module "gitops_bridge_bootstrap" {
  source = "git::https://github.com/gitops-bridge-dev/gitops-bridge-argocd-bootstrap-terraform.git?ref=7c3e9f2a1b8d4c6e0f5a3b9d2e7c1f4a8b0d6e3c"

  cluster = {
    cluster_name = module.eks.cluster_name
    environment  = local.environment
    metadata     = local.addons_metadata
    addons       = local.addons
  }
  apps = local.argocd_apps

  argocd = {
    create_namespace = false
    set = [
      {
        name  = "server.service.type"
        value = "LoadBalancer"
      }
    ]
    set_sensitive = [
      {
        name  = "configs.secret.argocdServerAdminPassword"
        value = bcrypt(data.aws_secretsmanager_secret_version.admin_password_version.secret_string)
      }
    ]
  }

  depends_on = [kubernetes_secret.git_secrets]
}

################################################################################
# EKS Blueprints Addons
################################################################################
module "eks_blueprints_addons" {
  source = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-addons.git?ref=e8c0494c1d0b8c0e5cba3f3aeaeed17fb4a697df"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # Using GitOps Bridge
  create_kubernetes_resources = false

  eks_addons = {

    # Remove for workshop as ebs-csi is long to provision (15mn)
    # aws-ebs-csi-driver = {
    #   most_recent              = true
    #   service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    # }
    coredns = {
      most_recent = true
    }
    vpc-cni = {
      # Specify the VPC CNI addon should be deployed before compute to ensure
      # the addon is configured before data plane compute resources are created
      # See README for further details
      service_account_role_arn = module.vpc_cni_irsa.iam_role_arn
      before_compute           = true
      #addon_version  = "v1.12.2-eksbuild.1"
      most_recent = true # To ensure access to the latest settings provided
      configuration_values = jsonencode({
        env = {
          # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    kube-proxy = {
      most_recent = true
    }
  }

  # EKS Blueprints Addons
  enable_cert_manager = try(local.aws_addons.enable_cert_manager, false)
  #enable_aws_ebs_csi_resources  = try(local.aws_addons.enable_aws_ebs_csi_resources, false)
  enable_aws_efs_csi_driver           = try(local.aws_addons.enable_aws_efs_csi_driver, false)
  enable_aws_fsx_csi_driver           = try(local.aws_addons.enable_aws_fsx_csi_driver, false)
  enable_aws_cloudwatch_metrics       = try(local.aws_addons.enable_aws_cloudwatch_metrics, false)
  enable_aws_privateca_issuer         = try(local.aws_addons.enable_aws_privateca_issuer, false)
  enable_cluster_autoscaler           = try(local.aws_addons.enable_cluster_autoscaler, false)
  enable_external_dns                 = try(local.aws_addons.enable_external_dns, false)
  external_dns_route53_zone_arns      = [data.aws_route53_zone.sub.arn]
  enable_external_secrets             = try(local.aws_addons.enable_external_secrets, false)
  enable_aws_load_balancer_controller = try(local.aws_addons.enable_aws_load_balancer_controller, false)
  aws_load_balancer_controller = {
    service_account_name = "aws-lb-sa"
  }

  enable_fargate_fluentbit              = try(local.aws_addons.enable_fargate_fluentbit, false)
  enable_aws_for_fluentbit              = try(local.aws_addons.enable_aws_for_fluentbit, false)
  enable_aws_node_termination_handler   = try(local.aws_addons.enable_aws_node_termination_handler, false)
  aws_node_termination_handler_asg_arns = [for asg in module.eks.self_managed_node_groups : asg.autoscaling_group_arn]
  enable_karpenter                      = try(local.aws_addons.enable_karpenter, false)
  karpenter = {
    policy_statements = [
      {
        sid       = "AllowPassingInstanceRole"
        effect    = "Allow"
        resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.name}-karpenter-*"]
        actions   = ["iam:PassRole"]
        condition = [
          {
            test     = "StringEquals"
            variable = "iam:PassedToService"
            values   = ["ec2.amazonaws.com"]
          }
        ]
      }
    ]
  }
  enable_velero = try(local.aws_addons.enable_velero, false)
  #velero = {
  #  s3_backup_location = "${module.velero_backup_s3_bucket.s3_bucket_arn}/backups"
  #}
  enable_aws_gateway_api_controller = try(local.aws_addons.enable_aws_gateway_api_controller, false)
  #enable_aws_secrets_store_csi_driver_provider = try(local.enable_aws_secrets_store_csi_driver_provider, false)

  tags = local.tags
}

module "ebs_csi_driver_irsa" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-iam.git//modules/iam-role-for-service-accounts-eks?ref=f572f45f69f3b8f2497da0c278e7c9a60a91b243"

  role_name_prefix = "${module.eks.cluster_name}-ebs-csi-"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

module "vpc_cni_irsa" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-iam.git//modules/iam-role-for-service-accounts-eks?ref=f572f45f69f3b8f2497da0c278e7c9a60a91b243"

  role_name_prefix = "${module.eks.cluster_name}-vpc-cni-"

  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }

  tags = local.tags
}


output "eks_cluster_id" {
  description = "The name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${var.aws_region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "eks_blueprints_platform_teams_configure_kubectl" {
  description = "Configure kubectl Platform Team: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${var.aws_region} update-kubeconfig --name ${module.eks.cluster_name}  --role-arn ${module.eks_blueprints_platform_teams.iam_role_arn}"
}

output "eks_blueprints_dev_teams_configure_kubectl" {
  description = "Configure kubectl for each Dev Application Teams: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = [for team in module.eks_blueprints_dev_teams : "aws eks --region ${var.aws_region} update-kubeconfig --name ${module.eks.cluster_name}  --role-arn ${team.iam_role_arn}"]
}

output "eks_blueprints_ecsdemo_teams_configure_kubectl" {
  description = "Configure kubectl for each ECSDEMO Application Teams: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = [for team in module.eks_blueprints_ecsdemo_teams : "aws eks --region ${var.aws_region} update-kubeconfig --name ${module.eks.cluster_name}  --role-arn ${team.iam_role_arn}"]
}

output "eks_cluster_endpoint" {
  description = "The endpoint of the EKS cluster."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "cluster_certificate_authority_data"
  value       = module.eks.cluster_certificate_authority_data
}

output "access_argocd" {
  description = "ArgoCD Access"
  value       = <<-EOT
    export KUBECONFIG="/tmp/${module.eks.cluster_name}"
    aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}
    echo "ArgoCD URL: https://$(kubectl get svc -n argocd argo-cd-argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
    echo "ArgoCD Username: admin"
    echo "ArgoCD Password: $(aws secretsmanager get-secret-value --secret-id argocd-admin-secret.${local.environment} --query SecretString --output text --region ${local.region})"
  EOT
}

output "gitops_metadata" {
  description = "export gitops_metadata"
  value       = local.addons_metadata
  sensitive   = true
}


variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-west-2"
}

variable "environment_name" {
  description = "The name of Environment Infrastructure stack, feel free to rename it. Used for cluster and VPC names."
  type        = string
  default     = "eks-blueprint"
}

variable "ingress_type" {
  type        = string
  description = "Type of ingress to uses (alb | nginx | ...). this parameter will be sent to argocd via gitops bridge"
  default     = "alb"
}

variable "hosted_zone_name" {
  type        = string
  description = "Route53 domain for the cluster."
  default     = ""
}

variable "eks_admin_role_name" {
  type        = string
  description = "Additional IAM role to be admin in the cluster"
  default     = ""
}

variable "aws_secret_manager_git_private_ssh_key_name" {
  type        = string
  description = "Secret Manager secret name for hosting Github SSH-Key to Access private repository"
  default     = "github-blueprint-ssh-key"
}

variable "argocd_secret_manager_name_suffix" {
  type        = string
  description = "Name of secret manager secret for ArgoCD Admin UI Password"
  default     = "argocd-admin-secret"
}

variable "gitops_addons_org" {
  type        = string
  description = "Git repository org/user contains for addons"
  default     = "git@github.com:aws-samples"
}
variable "gitops_addons_repo" {
  type        = string
  description = "Git repository contains for addons"
  default     = "eks-blueprints-add-ons"
}
variable "gitops_addons_basepath" {
  type        = string
  description = "Git repository base path for addons"
  default     = "argocd/"
}
variable "gitops_addons_path" {
  type        = string
  description = "Git repository path for addons"
  default     = "argocd/bootstrap/control-plane/addons"
}
variable "gitops_addons_revision" {
  type        = string
  description = "Git repository revision/branch/ref for addons"
  default     = "HEAD"
}

variable "gitops_workloads_org" {
  type        = string
  description = "Git repository org/user contains for workloads"
  default     = "git@github.com:aws-samples"
}

variable "gitops_workloads_repo" {
  type        = string
  description = "Git repository contains for workloads"
  default     = "eks-blueprints-workloads"
}

variable "gitops_workloads_path" {
  type        = string
  description = "Git repo path in workload_repo_url for the ArgoCD workload deployment"
  default     = "envs/dev"
}

variable "gitops_workloads_revision" {
  type        = string
  description = "Git repo revision in gitops_workloads_url  for the ArgoCD workload deployment"
  default     = "main"
}

variable "service_name" {
  description = "The name of the Suffix for the stack name"
  type        = string
  default     = "blue"
}

variable "cluster_version" {
  description = "The Version of Kubernetes to deploy"
  type        = string
  default     = "1.25"
}

variable "argocd_route53_weight" {
  description = "The Route53 weighted records weight for argocd application"
  type        = string
  default     = "100"
}

variable "ecsfrontend_route53_weight" {
  description = "The Route53 weighted records weight for ecsdemo-frontend application"
  type        = string
  default     = "100"
}

variable "route53_weight" {
  description = "The Route53 weighted records weight for others application"
  type        = string
  default     = "100"
}


terraform {
  required_version = ">= 1.4.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.34, < 6.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.22.0"
    }
  }
}