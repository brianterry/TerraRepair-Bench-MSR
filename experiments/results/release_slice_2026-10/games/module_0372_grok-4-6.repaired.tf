#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "git::https://github.com/terraform-aws-modules/terraform-aws-iam.git//modules/iam-role-for-service-accounts-eks?ref=de32c1c3f62c3f5341763fb1e240a3d1a3a5891d"
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
#---------------------------------------------------------------
# EKS Blueprints Kubernetes Addons
#---------------------------------------------------------------
module "eks_blueprints_addons" {
  source = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-addons.git?ref=a99653d6b5c1909d469697a786e70cae2b3267b3"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
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
  #---------------------------------------
  # EFS CSI driver
  #---------------------------------------
  enable_aws_efs_csi_driver = true

  #---------------------------------------
  # CAUTION: This blueprint creates a PUBLIC facing load balancer to show the Airflow Web UI for demos.
  # Please change this to a private load balancer if you are using this in production.
  #---------------------------------------
  enable_aws_load_balancer_controller = true

  #---------------------------------------
  # Metrics Server
  #---------------------------------------
  enable_metrics_server = true
  metrics_server = {
    values = [templatefile("${path.module}/helm-values/metrics-server-values.yaml", {})]
  }

  #---------------------------------------
  # Cluster Autoscaler
  #---------------------------------------
  enable_cluster_autoscaler = true
  cluster_autoscaler = {
    values = [templatefile("${path.module}/helm-values/cluster-autoscaler-values.yaml", {
      aws_region     = var.region,
      eks_cluster_id = module.eks.cluster_name
    })]
  }

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
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
    role_policy_name    = "${local.name}-karpenter"
    policy_statements = [
      {
        sid       = "PassRoleFiltered"
        effect    = "Allow"
        actions   = ["iam:PassRole"]
        resources = [module.eks_blueprints_addons.karpenter.node_iam_role_arn]
        conditions = [
          {
            test     = "StringEquals"
            variable = "iam:PassedToService"
            values   = ["ec2.amazonaws.com"]
          }
        ]
      }
    ]
  }

  #---------------------------------------
  # CloudWatch metrics for EKS
  #---------------------------------------
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

        # This toleration allows Daemonset pod to be scheduled on any node, regardless of their Taints.
        tolerations:
          - operator: Exists
      EOT
    ]
  }

  #---------------------------------------
  # AWS for FluentBit - DaemonSet
  #---------------------------------------
  enable_aws_for_fluentbit = true
  aws_for_fluentbit_cw_log_group = {
    create            = true
    use_name_prefix   = false
    name              = "/${local.name}/aws-fluentbit-logs" # Add-on creates this log group
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

  #---------------------------------------
  # Prommetheus and Grafana stack
  #---------------------------------------
  #---------------------------------------------------------------
  # Install Kafka Monitoring Stack with Prometheus and Grafana
  # 1- Grafana port-forward `kubectl port-forward svc/kube-prometheus-stack-grafana 8080:80 -n kube-prometheus-stack`
  # 2- Grafana Admin user: admin
  # 3- Get admin user password: `aws secretsmanager get-secret-value --secret-id <output.grafana_secret_name> --region $AWS_REGION --query "SecretString" --output text`
  #---------------------------------------------------------------
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


#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "eks_data_addons" {
  source = "git::https://github.com/aws-ia/terraform-aws-eks-data-addons.git?ref=b3e43b34a0e4d61d80b0c476ca469a396c73864f"

  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------------------------------
  # Airflow Add-on
  #---------------------------------------------------------------
  enable_airflow = true
  airflow_helm_config = {
    namespace = try(kubernetes_namespace_v1.airflow[0].metadata[0].name, local.airflow_namespace)
    version   = "1.11.0"
    values = [templatefile("${path.module}/helm-values/airflow-values.yaml", {
      # Airflow Postgres RDS Config
      airflow_db_user = local.airflow_name
      airflow_db_pass = try(sensitive(aws_secretsmanager_secret_version.postgres[0].secret_string), "")
      airflow_db_name = try(module.db[0].db_instance_name, "")
      airflow_db_host = try(element(split(":", module.db[0].db_instance_endpoint), 0), "")
      #Service Accounts
      worker_service_account    = try(kubernetes_service_account_v1.airflow_worker[0].metadata[0].name, local.airflow_workers_service_account)
      scheduler_service_account = try(kubernetes_service_account_v1.airflow_scheduler[0].metadata[0].name, local.airflow_scheduler_service_account)
      webserver_service_account = try(kubernetes_service_account_v1.airflow_webserver[0].metadata[0].name, local.airflow_webserver_service_account)
      # S3 bucket config for Logs
      s3_bucket_name        = try(module.airflow_s3_bucket[0].s3_bucket_id, "")
      webserver_secret_name = local.airflow_webserver_secret_name
      efs_pvc               = local.efs_pvc
    })]
  }

  #---------------------------------------------------------------
  # Spark Operator Add-on
  #---------------------------------------------------------------
  enable_spark_operator = var.enable_airflow_spark_example
  spark_operator_helm_config = {
    values = [templatefile("${path.module}/helm-values/spark-operator-values.yaml", {})]
  }

  #---------------------------------------------------------------
  # Spark History Server Add-on
  #---------------------------------------------------------------
  enable_spark_history_server = var.enable_airflow_spark_example
  spark_history_server_helm_config = {
    values = [
      <<-EOT
      sparkHistoryOpts: "-Dspark.history.fs.logDirectory=s3a://${try(module.spark_logs_s3_bucket[0].s3_bucket_id, "")}/${try(aws_s3_object.this[0].key, "")}"
      EOT
    ]
  }

  #---------------------------------------------------------------
  # Enable Karpenter Resources for Spark team A
  #---------------------------------------------------------------

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
              values: ["c5d.large","c5d.xlarge","c5d.2xlarge","c5d.4xlarge","c5d.9xlarge"] # 1 NVMe disk
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

#---------------------------------------------------------------
# Grafana Admin credentials resources
#---------------------------------------------------------------
data "aws_secretsmanager_secret_version" "admin_password_version" {
  secret_id  = aws_secretsmanager_secret.grafana.id
  depends_on = [aws_secretsmanager_secret_version.grafana]
}

resource "random_password" "grafana" {
  length           = 16
  special          = true
  override_special = "@_"
}

resource "aws_kms_key" "this" {
  description             = "CMK for Secrets Manager and EFS"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = local.tags
}

resource "aws_secretsmanager_secret" "grafana" {
  name                    = "${local.name}-grafana"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
  kms_key_id              = aws_kms_key.this.arn
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = aws_secretsmanager_secret.grafana.id
  secret_string = random_password.grafana.result
}

resource "aws_secretsmanager_secret_rotation" "grafana" {
  secret_id = aws_secretsmanager_secret.grafana.id

  rotation_rules {
    automatically_after_days = 30
  }
}

#---------------------------------------------------------------
# IAM Policy for FluentBit Add-on
#---------------------------------------------------------------
resource "aws_iam_policy" "fluentbit" {
  description = "IAM policy policy for FluentBit"
  name        = "${local.name}-fluentbit-additional"
  policy      = data.aws_iam_policy_document.fluent_bit.json
}

#---------------------------------------------------------------
# S3 log bucket for FluentBit
#---------------------------------------------------------------
#tfsec:ignore:*
module "fluentbit_s3_bucket" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-s3-bucket.git?ref=8aa0bf5c2f6ba6761a3a72c746a8900b3895e041"

  bucket_prefix = "${local.name}-spark-logs-"
  # For example only - please evaluate for your environment
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

#---------------------------------------------------------------
# IAM policy for FluentBit
#---------------------------------------------------------------
data "aws_iam_policy_document" "fluent_bit" {
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${module.fluentbit_s3_bucket.s3_bucket_id}/*"]

    actions = [
      "s3:ListBucket",
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetObject",
      "s3:GetObjectAcl",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion"
    ]
  }
}


#---------------------------------------------------------------
# RDS Postgres Database for Apache Airflow Metadata
#---------------------------------------------------------------
module "db" {
  count  = var.enable_airflow ? 1 : 0
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-rds.git?ref=21bfd3d1c1b21762d0f67e5a97fbc035348414a8"

  identifier = local.airflow_name

  # All available versions: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html#PostgreSQL.Concepts
  engine               = "postgres"
  engine_version       = "14"
  family               = "postgres14" # DB parameter group
  major_engine_version = "14"         # DB option group
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

  backup_retention_period           = 7
  skip_final_snapshot               = true
  deletion_protection               = true
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

#---------------------------------------------------------------
# Apache Airflow Postgres Metastore DB Master password
#---------------------------------------------------------------
resource "random_password" "postgres" {
  count   = var.enable_airflow ? 1 : 0
  length  = 16
  special = false
}
resource "aws_secretsmanager_secret" "postgres" {
  count                   = var.enable_airflow ? 1 : 0
  name                    = "postgres-2"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
  kms_key_id              = aws_kms_key.this.arn
}

resource "aws_secretsmanager_secret_version" "postgres" {
  count         = var.enable_airflow ? 1 : 0
  secret_id     = aws_secretsmanager_secret.postgres[0].id
  secret_string = random_password.postgres[0].result
}

resource "aws_secretsmanager_secret_rotation" "postgres" {
  count     = var.enable_airflow ? 1 : 0
  secret_id = aws_secretsmanager_secret.postgres[0].id

  rotation_rules {
    automatically_after_days = 30
  }
}

#---------------------------------------------------------------
# PostgreSQL RDS security group
#---------------------------------------------------------------
module "security_group" {
  count  = var.enable_airflow ? 1 : 0
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git?ref=90a9b62e0a5e25a9d2345cde6d00e5c6c8694d3a"

  name        = local.name
  description = "Complete PostgreSQL example security group"
  vpc_id      = module.vpc.vpc_id

  # ingress
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

#---------------------------------------------------------------
# Airflow Namespace
#---------------------------------------------------------------
resource "kubernetes_namespace_v1" "airflow" {
  count = var.enable_airflow ? 1 : 0
  metadata {
    name = local.airflow_namespace
  }
  timeouts {
    delete = "15m"
  }
}

#---------------------------------------------------------------
# IRSA module for Airflow Scheduler
#---------------------------------------------------------------
resource "kubernetes_service_account_v1" "airflow_scheduler" {
  count = var.enable_airflow ? 1 : 0
  metadata {
    name        = local.airflow_scheduler_service_account
    namespace   = kubernetes_namespace_v1.airflow[0].metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.airflow_irsa_scheduler[0].iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "airflow_scheduler" {
  count = var.enable_airflow ? 1 : 0
  metadata {
    name      = "${kubernetes_service_account_v1.airflow_scheduler[0].metadata[0].name}-secret"
    namespace = kubernetes_namespace_v1.airflow[0].metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.airflow_scheduler[0].metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace_v1.airflow[0].metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

module "airflow_irsa_scheduler" {
  source = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-addon.git?ref=3e27617fa5c807b9b5b433346d9281a66d4c98c6"

  count = var.enable_airflow ? 1 : 0
  # IAM role for service account (IRSA)
  create_release = false
  create_policy  = false # Policy is created in the next resource

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

resource "aws_iam_policy" "airflow_scheduler" {
  count = var.enable_airflow ? 1 : 0

  description = "IAM policy for Airflow Scheduler Pod"
  name_prefix = local.airflow_scheduler_service_account
  path        = "/"
  policy      = data.aws_iam_policy_document.airflow_s3_logs[0].json
}

#---------------------------------------------------------------
# IRSA module for Airflow Webserver
#---------------------------------------------------------------
resource "kubernetes_service_account_v1" "airflow_webserver" {
  count = var.enable_airflow ? 1 : 0
  metadata {
    name        = local.airflow_webserver_service_account
    namespace   = kubernetes_namespace_v1.airflow[0].metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.airflow_irsa_webserver[0].iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "airflow_webserver" {
  count = var.enable_airflow ? 1 : 0
  metadata {
    name      = "${kubernetes_service_account_v1.airflow_webserver[0].metadata[0].name}-secret"
    namespace = kubernetes_namespace_v1.airflow[0].metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.airflow_webserver[0].metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace_v1.airflow[0].metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

module "airflow_irsa_webserver" {
  count = var.enable_airflow ? 1 : 0

  source = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-addon.git?ref=3e27617fa5c807b9b5b433346d9281a66d4c98c6"

  # Disable helm release
  create_release = false

  # IAM role for service account (IRSA)
  create_role   = var.enable_airflow
  create_policy = false # Policy is created in the next resource

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

resource "aws_iam_policy" "airflow_webserver" {
  count = var.enable_airflow ? 1 : 0

  description = "IAM policy for Airflow Webserver Pod"
  name_prefix = local.airflow_webserver_service_account
  path        = "/"
  policy      = data.aws_iam_policy_document.airflow_s3_logs[0].json
}

#---------------------------------------------------------------
# Apache Airflow Webserver Secret
#---------------------------------------------------------------
resource "random_id" "airflow_webserver" {
  count       = var.enable_airflow ? 1 : 0
  byte_length = 16
}

resource "aws_secretsmanager_secret" "airflow_webserver" {
  count                   = var.enable_airflow ? 1 : 0
  name                    = "airflow_webserver_secret_key_2"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
  kms_key_id              = aws_kms_key.this.arn
}

resource "aws_secretsmanager_secret_version" "airflow_webserver" {
  count         = var.enable_airflow ? 1 : 0
  secret_id     = aws_secretsmanager_secret.airflow_webserver[0].id
  secret_string = random_id.airflow_webserver[0].hex
}

resource "aws_secretsmanager_secret_rotation" "airflow_webserver" {
  count     = var.enable_airflow ? 1 : 0
  secret_id = aws_secretsmanager_secret.airflow_webserver[0].id

  rotation_rules {
    automatically_after_days = 30
  }
}

#---------------------------------------------------------------
# Webserver Secret Key
#---------------------------------------------------------------
resource "kubectl_manifest" "airflow_webserver" {
  count = var.enable_airflow ? 1 : 0
  sensitive_fields = [
    "data.webserver-secret-key"
  ]

  yaml_body = <<-YAML
apiVersion: v1
kind: Secret
metadata:
   name: ${local.airflow_webserver_secret_name}
   namespace: ${kubernetes_namespace_v1.airflow[0].metadata[0].name}
   labels:
    app.kubernetes.io/managed-by: "Helm"
   annotations:
    meta.helm.sh/release-name: "airflow"
    meta.helm.sh/release-namespace: "airflow"
type: Opaque
data:
  webserver-secret-key: ${base64encode(aws_secretsmanager_secret_version.airflow_webserver[0].secret_string)}
YAML
}

#---------------------------------------------------------------
# IRSA module for Airflow Workers
#---------------------------------------------------------------
resource "kubernetes_service_account_v1" "airflow_worker" {
  count = var.enable_airflow ? 1 : 0
  metadata {
    name        = local.airflow_workers_service_account
    namespace   = kubernetes_namespace_v1.airflow[0].metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.airflow_irsa_worker[0].iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "airflow_worker" {
  count = var.enable_airflow ? 1 : 0
  metadata {
    name      = "${local.airflow_workers_service_account}-secret"
    namespace = kubernetes_namespace_v1.airflow[0].metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.airflow_worker[0].metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace_v1.airflow[0].metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

# Create IAM Role for Service Account (IRSA) Only if Airflow is enabled
module "airflow_irsa_worker" {
  count = var.enable_airflow ? 1 : 0

  source = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-addon.git?ref=3e27617fa5c807b9b5b433346d9281a66d4c98c6"

  # Disable helm release
  create_release = false

  # IAM role for service account (IRSA)
  create_role   = true
  create_policy = false # Policy is created in the next resource

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

resource "aws_iam_policy" "airflow_worker" {
  count = var.enable_airflow ? 1 : 0

  description = "IAM policy for Airflow Workers Pod"
  name_prefix = local.airflow_workers_service_account
  path        = "/"
  policy      = data.aws_iam_policy_document.airflow_s3_logs[0].json
}

#---------------------------------------------------------------
# Managing DAG files with GitSync - EFS Storage Class
#---------------------------------------------------------------
resource "kubectl_manifest" "efs_sc" {
  count     = var.enable_airflow ? 1 : 0
  yaml_body = <<-YAML
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${local.efs_storage_class}
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: ${aws_efs_file_system.efs[0].id}
  directoryPerms: "700"
  gidRangeStart: "1000"
  gidRangeEnd: "2000"
YAML

  depends_on = [module.eks.cluster_name]
}

#---------------------------------------------------------------
# Persistent Volume Claim for EFS
#---------------------------------------------------------------
resource "kubectl_manifest" "efs_pvc" {
  count     = var.enable_airflow ? 1 : 0
  yaml_body = <<-YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${local.efs_pvc}
  namespace: ${kubernetes_namespace_v1.airflow[0].metadata[0].name}
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ${local.efs_storage_class}
  resources:
    requests:
      storage: 10Gi
YAML

  depends_on = [kubectl_manifest.efs_sc]
}
#---------------------------------------------------------------
# EFS Filesystem for Airflow DAGs
#---------------------------------------------------------------
resource "aws_efs_file_system" "efs" {
  count          = var.enable_airflow ? 1 : 0
  creation_token = "efs"
  encrypted      = true
  kms_key_id     = aws_kms_key.this.arn

  tags = local.tags
}

resource "aws_efs_mount_target" "efs_mt" {
  count = var.enable_airflow ? length(var.eks_data_plane_subnet_secondary_cidr) : 0

  file_system_id  = aws_efs_file_system.efs[0].id
  subnet_id       = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) : substr(cidr_block, 0, 4) == "100." ? subnet_id : null])[count.index]
  security_groups = [aws_security_group.efs[0].id]
}

resource "aws_security_group" "efs" {
  count       = var.enable_airflow ? 1 : 0
  name        = "${local.name}-efs"
  description = "Allow inbound NFS traffic from private subnets of the VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow NFS 2049/tcp"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
  }

  egress {
    description = "NFS response traffic to private subnets"
    cidr_blocks = module.vpc.private_subnets_cidr_blocks
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
  }

  tags = local.tags
}

#---------------------------------------------------------------
# S3 log bucket for Airflow Logs
#---------------------------------------------------------------

#tfsec:ignore:*
module "airflow_s3_bucket" {
  count  = var.enable_airflow ? 1 : 0
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-s3-bucket.git?ref=8aa0bf5c2f6ba6761a3a72c746a8900b3895e041"

  bucket_prefix = "${local.name}-logs-"

  # For example only - please evaluate for your environment
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

#---------------------------------------------------------------
# Example IAM policy for Aiflow S3 logging
#---------------------------------------------------------------
data "aws_iam_policy_document" "airflow_s3_logs" {
  count = var.enable_airflow ? 1 : 0
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${module.airflow_s3_bucket[0].s3_bucket_id}"]

    actions = [
      "s3:ListBucket"
    ]
  }
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${module.airflow_s3_bucket[0].s3_bucket_id}/*"]

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
  }
}


#IAM Policy for Amazon Prometheus & Grafana
resource "aws_iam_policy" "grafana" {
  count = var.enable_amazon_prometheus ? 1 : 0

  description = "IAM policy for Grafana Pod"
  name_prefix = format("%s-%s-", local.name, "grafana")
  path        = "/"
  policy      = data.aws_iam_policy_document.grafana[0].json
}

data "aws_iam_policy_document" "grafana" {
  count = var.enable_amazon_prometheus ? 1 : 0

  statement {
    sid       = "AllowReadingMetricsFromCloudWatch"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics"
    ]
  }

  statement {
    sid       = "AllowGetInsightsCloudWatch"
    effect    = "Allow"
    resources = ["arn:${local.partition}:cloudwatch:${local.region}:${local.account_id}:insight-rule/*"]

    actions = [
      "cloudwatch:GetInsightRuleReport",
    ]
  }

  statement {
    sid       = "AllowReadingAlarmHistoryFromCloudWatch"
    effect    = "Allow"
    resources = ["arn:${local.partition}:cloudwatch:${local.region}:${local.account_id}:alarm:*"]

    actions = [
      "cloudwatch:DescribeAlarmHistory",
      "cloudwatch:DescribeAlarms",
    ]
  }

  statement {
    sid       = "AllowReadingLogsFromCloudWatch"
    effect    = "Allow"
    resources = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:*:log-stream:*"]

    actions = [
      "logs:DescribeLogGroups",
      "logs:GetLogGroupFields",
      "logs:StartQuery",
      "logs:StopQuery",
      "logs:GetQueryResults",
      "logs:GetLogEvents",
    ]
  }

  statement {
    sid       = "AllowReadingTagsInstancesRegionsFromEC2"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "ec2:DescribeTags",
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
    ]
  }

  statement {
    sid       = "AllowReadingResourcesForTags"
    effect    = "Allow"
    resources = ["*"]
    actions   = ["tag:GetResources"]
  }

  statement {
    sid    = "AllowListApsWorkspaces"
    effect = "Allow"
    resources = [
      "arn:${local.partition}:aps:${local.region}:${local.account_id}:/*",
      "arn:${local.partition}:aps:${local.region}:${local.account_id}:workspace/*",
      "arn:${local.partition}:aps:${local.region}:${local.account_id}:workspace/*/*",
    ]
    actions = [
      "aps:ListWorkspaces",
      "aps:DescribeWorkspace",
      "aps:GetMetricMetadata",
      "aps:GetSeries",
      "aps:QueryMetrics",
      "aps:RemoteWrite",
      "aps:GetLabels"
    ]
  }
}

#------------------------------------------
# Amazon Prometheus
#------------------------------------------
locals {
  amp_ingest_service_account = "amp-iamproxy-ingest-service-account"
  amp_namespace              = "kube-prometheus-stack"
  account_id                 = data.aws_caller_identity.current.account_id
  partition                  = data.aws_partition.current.partition
}

resource "aws_prometheus_workspace" "amp" {
  count = var.enable_amazon_prometheus ? 1 : 0

  alias = format("%s-%s", "amp-ws", local.name)
  tags  = local.tags
}

module "amp_ingest_irsa" {
  count = var.enable_amazon_prometheus ? 1 : 0

  source         = "git::https://github.com/aws-ia/terraform-aws-eks-blueprints-addon.git?ref=3e27617fa5c807b9b5b433346d9281a66d4c98c6"
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


# Creates a Data team with all the required resources for Airflow and Spark

locals {
  spark_team = "spark-team-a"
}

# Create a namespace for spark-team-a
resource "kubernetes_namespace_v1" "spark_team_a" {
  count = var.enable_airflow_spark_example ? 1 : 0
  metadata {
    name = local.spark_team
  }
  timeouts {
    delete = "15m"
  }
}

# Create a service account for spark-team-a
resource "kubernetes_service_account_v1" "spark_team_a" {
  count = var.enable_airflow_spark_example ? 1 : 0
  metadata {
    name        = local.spark_team
    namespace   = kubernetes_namespace_v1.spark_team_a[0].metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.spark_team_a_irsa[0].iam_role_arn }
  }

  automount_service_account_token = true
}

# Create a secret for spark-team-a
resource "kubernetes_secret_v1" "spark_team_a" {
  count = var.enable_airflow_spark_example ? 1 : 0
  metadata {
    name      = "${local.spark_team}-secret"
    namespace = kubernetes_namespace_v1.spark_team_a[0].metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.spark_team_a[0].metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace_v1.spark_team_a[0].metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

#---------------------------------------------------------------
# IRSA for Spark driver/executor pods for "spark-team-a"
#---------------------------------------------------------------
module "spark_team_a_irsa" {
  count = var.enable_airflow_spark_example ? 1 : 0

  source