module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws?ref=1.2.0"
  version = "~> 1.2"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  eks_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns = {
      preserve = true
    }
    vpc-cni = {
      preserve = true
    }
    kube-proxy = {
      preserve = true
    }
  }

  enable_aws_efs_csi_driver = true
  enable_aws_load_balancer_controller = true
  enable_metrics_server = true
  metrics_server = {
    values = [templatefile("${path.module}/helm-values/metrics-server-values.yaml", {})]
  }

  enable_cluster_autoscaler = true
  cluster_autoscaler = {
    values = [templatefile("${path.module}/helm-values/cluster-autoscaler-values.yaml", {
      aws_region     = var.region,
      eks_cluster_id = module.eks.cluster_name
    })]
  }

  enable_karpenter                  = true
  karpenter_enable_spot_termination = true
  karpenter_node = {
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }
  karpenter = {
    chart_version       = "v0.34.0"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  enable_aws_cloudwatch_metrics = true
  aws_cloudwatch_metrics = {
    values = [
      <<-EOT
        resources:
          limits:
            cpu: 500m
            memory: 2Gi
          requests:
            cpu: 200m
            memory: 1Gi
        tolerations:
          - operator: Exists
      EOT
    ]
  }

  enable_aws_for_fluentbit = true
  aws_for_fluentbit_cw_log_group = {
    create            = true
    use_name_prefix   = false
    name              = "/${local.name}/aws-fluentbit-logs"
    retention_in_days = 30
  }
  aws_for_fluentbit = {
    create_namespace = true
    namespace        = "aws-for-fluentbit"
    create_role      = true
    role_policies    = { "policy1" = aws_iam_policy.fluentbit.arn }
    values = [templatefile("${path.module}/helm-values/aws-for-fluentbit-values.yaml", {
      region               = local.region,
      cloudwatch_log_group = "/${local.name}/aws-fluentbit-logs"
      s3_bucket_name       = module.fluentbit_s3_bucket.s3_bucket_id
      cluster_name         = module.eks.cluster_name
    })]
  }

  enable_kube_prometheus_stack = true
  kube_prometheus_stack = {
    values = [
      var.enable_amazon_prometheus ? templatefile("${path.module}/helm-values/kube-prometheus-amp-enable.yaml", {
        region              = local.region
        amp_sa              = local.amp_ingest_service_account
        amp_irsa            = module.amp_ingest_irsa[0].iam_role_arn
        amp_remotewrite_url = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}/api/v1/remote_write"
        amp_url             = "https://aps-workspaces.${local.region}.amazonaws.com/workspaces/${aws_prometheus_workspace.amp[0].id}"
      }) : templatefile("${path.module}/helm-values/kube-prometheus.yaml", {})
    ]
    chart_version = "48.2.3"
    set_sensitive = [
      {
        name  = "grafana.adminPassword"
        value = data.aws_secretsmanager_secret_version.admin_password_version.secret_string
      }
    ],
  }

  tags = local.tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws?ref=19.15.0"
  version = "~> 19.15"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version
  cluster_endpoint_public_access = false
  cluster_endpoint_public_access_cidrs = ["10.0.0.0/16"]
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  vpc_id = module.vpc.vpc_id
  subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) : substr(cidr_block, 0, 4) == "100." ? subnet_id : null])

  manage_aws_auth_configmap = true
  aws_auth_roles = [
    {
      rolearn  = module.eks_blueprints_addons.karpenter.node_iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes",
      ]
    }
  ]

  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    },
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    },
    egress_restricted = {
      description      = "Restrict egress to VPC CIDR"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = [module.vpc.vpc_cidr_block, var.secondary_cidr_blocks[0]]
      ipv6_cidr_blocks = []
    }
  }

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }

  eks_managed_node_groups = {
    core_node_group = {
      name        = "core-node-group"
      description = "EKS Core node group for hosting critical add-ons"
      subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) : substr(cidr_block, 0, 4) == "100." ? subnet_id : null])

      min_size     = 4
      max_size     = 8
      desired_size = 4

      instance_types = ["m5.xlarge"]

      ebs_optimized = true
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 100
            volume_type = "gp3"
          }
        }
      }

      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core"
      }

      tags = merge(local.tags, {
        Name                     = "core-node-grp",
        "karpenter.sh/discovery" = local.name
      })
    }
  }
}

module "db" {
  count   = var.enable_airflow ? 1 : 0
  source  = "terraform-aws-modules/rds/aws?ref=5.0.0"
  version = "~> 5.0"

  identifier = local.airflow_name

  engine               = "postgres"
  engine_version       = "14"
  family               = "postgres14"
  major_engine_version = "14"
  instance_class       = "db.t4g.large"

  allocated_storage     = 20
  max_allocated_storage = 100

  db_name                = local.airflow_name
  username               = local.airflow_name
  create_random_password = false
  password               = sensitive(aws_secretsmanager_secret_version.postgres[0].secret_string)
  port                   = 5432

  multi_az               = true
  db_subnet_group_name   = module.vpc.database_subnet_group
  vpc_security_group_ids = [module.security_group[0].security_group_id]

  maintenance_window              = "Mon:00:00-Mon:03:00"
  backup_window                   = "03:00-06:00"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  create_cloudwatch_log_group     = true

  backup_retention_period      = 7
  skip_final_snapshot     = true
  deletion_protection     = true
  iam_database_authentication_enabled = true

  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  create_monitoring_role                = true
  monitoring_interval                   = 60
  monitoring_role_name                  = "airflow-metastore"
  monitoring_role_use_name_prefix       = true
  monitoring_role_description           = "Airflow Postgres Metastore for monitoring role"

  parameters = [
    {
      name  = "autovacuum"
      value = 1
    },
    {
      name  = "client_encoding"
      value = "utf8"
    }
  ]

  tags = local.tags
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws?ref=5.0.0"
  version = "~> 5.0"

  name = local.name
  cidr = var.vpc_cidr
  azs  = local.azs

  secondary_cidr_blocks = var.secondary_cidr_blocks
  private_subnets = concat(var.private_subnets, var.eks_data_plane_subnet_secondary_cidr)
  public_subnets = var.public_subnets
  database_subnets                   = var.db_private_subnets
  create_database_subnet_group       = true
  create_database_subnet_route_table = true

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  enable_flow_log = true
  flow_log_max_aggregation_interval = 60
  flow_log_traffic_type = "REJECT"

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery" = local.name
  }

  tags = local.tags
}

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "aws_secretsmanager_secret" "grafana" {
  name                    = "${local.name}-grafana"
  recovery_window_in_days = 0
  kms_key_id              = "alias/aws/secretsmanager"
  rotation_rules {
    automatically_after_days = 30
  }
}

resource "aws_secretsmanager_secret" "postgres" {
  count                   = var.enable_airflow ? 1 : 0
  name                    = "postgres-2"
  recovery_window_in_days = 0
  kms_key_id              = "alias/aws/secretsmanager"
  rotation_rules {
    automatically_after_days = 30
  }
}

resource "aws_secretsmanager_secret" "airflow_webserver" {
  count                   = var.enable_airflow ? 1 : 0
  name                    = "airflow_webserver_secret_key_2"
  recovery_window_in_days = 0
  kms_key_id              = "alias/aws/secretsmanager"
  rotation_rules {
    automatically_after_days = 30
  }
}

resource "aws_efs_file_system" "efs" {
  count          = var.enable_airflow ? 1 : 0
  creation_token = "efs"
  encrypted      = true
  kms_key_id     = "alias/aws/efs"
  tags = local.tags
}

module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks?ref=5.34.0"
  version = "~> 5.34"
  role_name_prefix      = format("%s-%s-", local.name, "ebs-csi-driver")
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = local.tags
}

module "eks_data_addons" {
  source  = "aws-ia/eks-data-addons/aws?ref=1.33.0"
  version = "1.33.0"

  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_airflow = true
  airflow_helm_config = {
    namespace = try(kubernetes_namespace_v1.airflow[0].metadata[0].name, local.airflow_namespace)
    version   = "1.11.0"
    values = [templatefile("${path.module}/helm-values/airflow-values.yaml", {
      airflow_db_user = local.airflow_name
      airflow_db_pass = try(sensitive(aws_secretsmanager_secret_version.postgres[0].secret_string), "")
      airflow_db_name = try(module.db[0].db_instance_name, "")
      airflow_db_host = try(element(split(":", module.db[0].db_instance_endpoint), 0), "")
      worker_service_account    = try(kubernetes_service_account_v1.airflow_worker[0].metadata[0].name, local.airflow_workers_service_account)
      scheduler_service_account = try(kubernetes_service_account_v1.airflow_scheduler[0].metadata[0].name, local.airflow_scheduler_service_account)
      webserver_service_account = try(kubernetes_service_account_v1.airflow_webserver[0].metadata[0].name, local.airflow_webserver_service_account)
      s3_bucket_name        = try(module.airflow_s3_bucket[0].s3_bucket_id, "")
      webserver_secret_name = local.airflow_webserver_secret_name
      efs_pvc               = local.efs_pvc
    })]
  }

  enable_spark_operator = var.enable_airflow_spark_example
  spark_operator_helm_config = {
    values = [templatefile("${path.module}/helm-values/spark-operator-values.yaml", {})]
  }

  enable_spark_history_server = var.enable_airflow_spark_example
  spark_history_server_helm_config = {
    values = [
      <<-EOT
      sparkHistoryOpts: "-Dspark.history.fs.logDirectory=s3a://${try(module.spark_logs_s3_bucket[0].s3_bucket_id, "")}/${try(aws_s3_object.this[0].key, "")}"
      EOT
    ]
  }

  enable_karpenter_resources = true
  karpenter_resources_helm_config = {
    spark-compute-optimized = {
      values = [
        <<-EOT
        name: spark-compute-optimized
        clusterName: ${module.eks.cluster_name}
        ec2NodeClass:
          karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
          subnetSelectorTerms:
            tags:
              Name: "${module.eks.cluster_name}-private*"
          securityGroupSelectorTerms:
            tags:
              Name: ${module.eks.cluster_name}-node
          userData: |
            MIME-Version: 1.0
            Content-Type: multipart/mixed; boundary="BOUNDARY"

            --BOUNDARY
            Content-Type: text/x-shellscript; charset="us-ascii"

            #!/bin/bash
            echo "Running a custom user data script"
            set -ex
            yum install mdadm -y

            DEVICES=$(lsblk -o NAME,TYPE -dsn | awk '/disk/ {print $1}')

            DISK_ARRAY=()

            for DEV in $DEVICES
            do
              DISK_ARRAY+=("/dev/$${DEV}")
            done

            DISK_COUNT=$${#DISK_ARRAY[@]}

            if [ $${DISK_COUNT} -eq 0 ]; then
              echo "No SSD disks available. No further action needed."
            else
              if [ $${DISK_COUNT} -eq 1 ]; then
                TARGET_DEV=$${DISK_ARRAY[0]}
                mkfs.xfs $${TARGET_DEV}
              else
                mdadm --create --verbose /dev/md0 --level=0 --raid-devices=$${DISK_COUNT} $${DISK_ARRAY[@]}
                mkfs.xfs /dev/md0
                TARGET_DEV=/dev/md0
              fi

              mkdir -p /local1
              echo $${TARGET_DEV} /local1 xfs defaults,noatime 1 2 >> /etc/fstab
              mount -a
              /usr/bin/chown -hR +999:+1000 /local1
            fi

            --BOUNDARY--
        nodePool:
          labels:
            - provisioner: spark-compute-optimized
            - NodeGroupType: SparkComputeOptimized
            - type: karpenter
          taints:
            - key: spark-compute-optimized
              value: 'true'
              effect: NoSchedule
          requirements:
            - key: "topology.kubernetes.io/zone"
              operator: In
              values: [${local.region}a]
            - key: "node.kubernetes.io/instance-type"
              operator: In
              values: ["c5d.large","c5d.xlarge","c5d.2xlarge","c5d.4xlarge","c5d.9xlarge"]
            - key: "kubernetes.io/arch"
              operator: In
              values: ["amd64"]
            - key: "karpenter.sh/capacity-type"
              operator: In
              values: ["spot", "on-demand"]
      EOT
      ]
    }
  }
}

module "fluentbit_s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws?ref=3.0.0"
  version = "~> 3.0"

  bucket_prefix = "${local.name}-spark-logs-"
  force_destroy = true
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}

module "security_group" {
  count   = var.enable_airflow ? 1 : 0
  source  = "terraform-aws-modules/security-group/aws?ref=5.0.0"
  version = "~> 5.0"

  name        = local.name
  description = "Complete PostgreSQL example security group"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "PostgreSQL access from within VPC"
      cidr_blocks = "${module.vpc.vpc_cidr_block},${module.vpc.vpc_secondary_cidr_blocks[0]}"
    },
  ]

  tags = local.tags
}

module "airflow_irsa_scheduler" {
  source  = "aws-ia/eks-blueprints-addon/aws?ref=1.0.0"
  version = "~> 1.0"

  count = var.enable_airflow ? 1 : 0
  create_release = false
  create_policy  = false

  create_role = var.enable_airflow
  role_name   = local.airflow_scheduler_service_account

  role_policies = { AirflowScheduler = aws_iam_policy.airflow_scheduler[0].arn }

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = kubernetes_namespace_v1.airflow[0].metadata[0].name
      service_account = local.airflow_scheduler_service_account
    }
  }
}

module "airflow_irsa_webserver" {
  count = var.enable_airflow ? 1 : 0

  source  = "aws-ia/eks-blueprints-addon/aws?ref=1.0.0"
  version = "~> 1.0"

  create_release = false
  create_role   = true
  create_policy = false

  role_name     = local.airflow_webserver_service_account
  role_policies = merge({ AirflowWebserver = aws_iam_policy.airflow_webserver[0].arn })

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = kubernetes_namespace_v1.airflow[0].metadata[0].name
      service_account = local.airflow_webserver_service_account
    }
  }

  tags = local.tags
}

module "airflow_irsa_worker" {
  count = var.enable_airflow ? 1 : 0

  source  = "aws-ia/eks-blueprints-addon/aws?ref=1.0.0"
  version = "~> 1.0"

  create_release = false
  create_role   = true
  create_policy = false

  role_name     = local.airflow_workers_service_account
  role_policies = merge({ AirflowWorker = aws_iam_policy.airflow_worker[0].arn })

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = kubernetes_namespace_v1.airflow[0].metadata[0].name
      service_account = local.airflow_workers_service_account
    }
  }

  tags = local.tags
}

module "airflow_s3_bucket" {
  count   = var.enable_airflow ? 1 : 0
  source  = "terraform-aws-modules/s3-bucket/aws?ref=3.0.0"
  version = "~> 3.0"

  bucket_prefix = "${local.name}-logs-"
  force_destroy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}

module "spark_team_a_irsa" {
  count = var.enable_airflow_spark_example ? 1 : 0

  source  = "aws-ia/eks-blueprints-addon/aws?ref=1.0.0"
  version = "~> 1.0"

  create_release = false
  create_role   = true
  role_name     = "${local.name}-${local.spark_team}"
  create_policy = false
  role_policies = {
    spark_team_a_policy = aws_iam_policy.spark[0].arn
  }

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = local.spark_team
      service_account = local.spark_team
    }
  }
}

module "spark_logs_s3_bucket" {
  count   = var.enable_airflow_spark_example ? 1 : 0
  source  = "terraform-aws-modules/s3-bucket/aws?ref=3.0.0"
  version = "~> 3.0"

  bucket_prefix = "${local.name}-spark-logs-"
  force_destroy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}

module "amp_ingest_irsa" {
  count = var.enable_amazon_prometheus ? 1 : 0

  source         = "aws-ia/eks-blueprints-addon/aws?ref=1.0.0"
  version        = "~> 1.0"
  create_release = false
  create_role    = true
  create_policy  = false
  role_name      = format("%s-%s", local.name, "amp-ingest")
  role_policies  = { amp_policy = aws_iam_policy.grafana[0].arn }

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = local.amp_namespace
      service_account = local.amp_ingest_service_account
    }
  }

  tags = local.tags
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws?ref=5.0.0"
  version = "~> 5.0"

  name = local.name
  cidr = var.vpc_cidr
  azs  = local.azs

  secondary_cidr_blocks = var.secondary_cidr_blocks
  private_subnets = concat(var.private_subnets, var.eks_data_plane_subnet_secondary_cidr)
  public_subnets = var.public_subnets
  database_subnets                   = var.db_private_subnets
  create_database_subnet_group       = true
  create_database_subnet_route_table = true

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  enable_flow_log = true
  flow_log_max_aggregation_interval = 60
  flow_log_traffic_type = "REJECT"

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery" = local.name
  }

  tags = local.tags
}