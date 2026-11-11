#---------------------------------------------------------------
# GP3 Encrypted Storage Class
#---------------------------------------------------------------
resource "kubernetes_annotations" "gp2_default" {
  annotations = {
    "storageclass.kubernetes.io/is-default-class" : "false"
  }
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  force = true

  depends_on = [module.eks]
}

resource "kubernetes_storage_class" "ebs_csi_encrypted_gp3_storage_class" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    fsType    = "xfs"
    encrypted = true
    type      = "gp3"
  }

  depends_on = [kubernetes_annotations.gp2_default, module.ebs_csi_driver_irsa]
}

#---------------------------------------------------------------
# Karpenter Node instance role Access Entry
#---------------------------------------------------------------
resource "aws_eks_access_entry" "karpenter_nodes" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.eks_blueprints_addons.karpenter.node_iam_role_arn
  type          = "EC2_LINUX"
}

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons
#---------------------------------------------------------------
module "eks_data_addons" {
  source  = "aws-ia/eks-data-addons/aws"
  version = "1.38.0"

  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_karpenter_resources = true

  karpenter_resources_helm_config = {
    spark-compute-optimized = {
      values = [
        <<-EOT
      name: spark-compute-optimized
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        amiFamily: AL2023
        amiSelectorTerms:
          - alias: al2023@latest
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          tags:
            Name: "${module.eks.cluster_name}-private-secondary*"
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        instanceStorePolicy: RAID0

      nodePool:
        labels:
          - type: karpenter
          - NodeGroupType: SparkComputeOptimized
          - multiArch: Spark
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot", "on-demand"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["amd64"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["c"]
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["c5d"]
          - key: "karpenter.k8s.aws/instance-size"
            operator: In
            values: ["4xlarge", "9xlarge", "12xlarge", "18xlarge", "24xlarge"]
          - key: "karpenter.k8s.aws/instance-hypervisor"
            operator: In
            values: ["nitro"]
          - key: "karpenter.k8s.aws/instance-generation"
            operator: Gt
            values: ["2"]
        limits:
          cpu: 1000
        disruption:
          consolidationPolicy: WhenEmptyOrUnderutilized
          consolidateAfter: 1m
        weight: 100
      EOT
      ]
    }
    spark-graviton-memory-optimized = {
      values = [
        <<-EOT
      name: spark-graviton-memory-optimized
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        amiFamily: AL2023
        amiSelectorTerms:
          - alias: al2023@latest
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          tags:
            Name: "${module.eks.cluster_name}-private-secondary*"
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        instanceStorePolicy: RAID0
        blockDeviceMappings:
          - deviceName: /dev/xvda
            ebs:
              volumeSize: 200Gi
              volumeType: gp3
              encrypted: true
              deleteOnTermination: true
      nodePool:
        labels:
          - type: karpenter
          - NodeGroupType: SparkGravitonMemoryOptimized
          - multiArch: Spark
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot", "on-demand"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["arm64"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["r"]
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["r6g", "r6gd", "r7g", "r7gd", "r8g"]
          - key: "karpenter.k8s.aws/instance-size"
            operator: In
            values: ["4xlarge", "8xlarge", "12xlarge", "16xlarge"]
          - key: "karpenter.k8s.aws/instance-hypervisor"
            operator: In
            values: ["nitro"]
          - key: "karpenter.k8s.aws/instance-generation"
            operator: Gt
            values: ["2"]
        limits:
          cpu: 1000
        disruption:
          consolidationPolicy: WhenEmptyOrUnderutilized
          consolidateAfter: 1m
        weight: 100
      EOT
      ]
    }
    spark-memory-optimized = {
      values = [
        <<-EOT
      name: spark-memory-optimized
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        amiFamily: AL2023
        amiSelectorTerms:
          - alias: al2023@latest
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          tags:
            Name: "${module.eks.cluster_name}-private-secondary*"
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        instanceStorePolicy: RAID0

      nodePool:
        labels:
          - type: karpenter
          - NodeGroupType: SparkMemoryOptimized
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot", "on-demand"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["amd64"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["r"]
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["r5d"]
          - key: "karpenter.k8s.aws/instance-cpu"
            operator: In
            values: ["4", "8", "16", "32"]
          - key: "karpenter.k8s.aws/instance-hypervisor"
            operator: In
            values: ["nitro"]
          - key: "karpenter.k8s.aws/instance-generation"
            operator: Gt
            values: ["2"]
        limits:
          cpu: 1000
        disruption:
          consolidationPolicy: WhenEmptyOrUnderutilized
          consolidateAfter: 1m
        weight: 50
      EOT
      ]
    }
    spark-vertical-ebs-scale = {
      values = [
        <<-EOT
      name: spark-vertical-ebs-scale
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        amiFamily: AL2023
        amiSelectorTerms:
          - alias: al2023@latest
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          tags:
            Name: "${module.eks.cluster_name}-private-secondary*"
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        userData: |
          MIME-Version: 1.0
          Content-Type: multipart/mixed; boundary="//"

          --//
          Content-Type: text/x-shellscript; charset="us-ascii"

          #!/bin/bash
          echo "Running a custom user data script"
          set -ex
          yum install mdadm -y

          IDX=1
          DEVICES=$(lsblk -o NAME,TYPE -dsn | awk '/disk/ {print $1}')

          DISK_ARRAY=()

          for DEV in $DEVICES
          do
            DISK_ARRAY+=("/dev/$${DEV}")
          done

          DISK_COUNT=$${#DISK_ARRAY[@]}

          if [ $${DISK_COUNT} -eq 0 ]; then
            echo "No SSD disks available. Creating new EBS volume according to number of cores available in the node."
            yum install -y jq awscli
            TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 3600")

            INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
            AVAILABILITY_ZONE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
            REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[a-z]$//')

            CORES=$(nproc --all)

            VOLUME_SIZE=$(expr $CORES \* 10)

            VOLUME_ID=$(aws ec2 create-volume --availability-zone $AVAILABILITY_ZONE --size $VOLUME_SIZE --volume-type gp3 --region $REGION --output text --query 'VolumeId')

            while [ "$(aws ec2 describe-volumes --volume-ids $VOLUME_ID --region $REGION --query "Volumes[*].State" --output text)" != "available" ]; do
              echo "Waiting for volume to become available"
              sleep 5
            done

            aws ec2 attach-volume --volume-id $VOLUME_ID --instance-id $INSTANCE_ID --device /dev/xvdb --region $REGION

            aws ec2 modify-instance-attribute --instance-id $INSTANCE_ID --block-device-mappings "[{\"DeviceName\": \"/dev/xvdb\",\"Ebs\":{\"DeleteOnTermination\":true}}]" --region $REGION

            while [ "$(aws ec2 describe-volumes --volume-ids $VOLUME_ID --region $REGION --query "Volumes[*].Attachments[*].State" --output text)" != "attached" ]; do
              echo "Waiting for volume to be attached"
              sleep 5
            done

            sudo mkfs -t ext4 /dev/xvdb
            sudo mkdir /mnt/k8s-disks
            sudo mount /dev/xvdb /mnt/k8s-disks
            echo "/dev/xvdb /mnt/k8s-disks ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab

            /usr/bin/chown -hR +999:+1000 /mnt/k8s-disks
          else
            if [ $${DISK_COUNT} -eq 1 ]; then
              TARGET_DEV=$${DISK_ARRAY[0]}
              mkfs.xfs $${TARGET_DEV}
            else
              mdadm --create --verbose /dev/md0 --level=0 --raid-devices=$${DISK_COUNT} $${DISK_ARRAY[@]}
              mkfs.xfs /dev/md0
              TARGET_DEV=/dev/md0
            fi

            mkdir -p /mnt/k8s-disks
            echo $${TARGET_DEV} /mnt/k8s-disks xfs defaults,noatime 1 2 >> /etc/fstab
            mount -a
            /usr/bin/chown -hR +999:+1000 /mnt/k8s-disks
          fi

          --//--

      nodePool:
        labels:
          - type: karpenter
          - provisioner: spark-vertical-ebs-scale
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot", "on-demand"]
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["r4", "r4", "r5", "r5d", "r5n", "r5dn", "r5b", "m4", "m5", "m5n", "m5zn", "m5dn", "m5d", "c4", "c5", "c5n", "c5d"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["amd64"]
          - key: "karpenter.k8s.aws/instance-generation"
            operator: Gt
            values: ["2"]
        limits:
          cpu: 1000
        disruption:
          consolidationPolicy: WhenEmptyOrUnderutilized
          consolidateAfter: 1m
        weight: 100
      EOT
      ]
    }
    spark-operator-benchmark = {
      values = [
        <<-EOT
      name: spark-operator-benchmark
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        amiFamily: AL2023
        amiSelectorTerms:
          - alias: al2023@latest
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          tags:
            Name: "${module.eks.cluster_name}-private-secondary*"
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
      nodePool:
        labels:
          - type: karpenter
          - NodeGroupType: spark-operator-benchmark
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["on-demand"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["c"]
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["c5"]
          - key: "karpenter.k8s.aws/instance-cpu"
            operator: In
            values: ["8", "36"]
          - key: "karpenter.k8s.aws/instance-hypervisor"
            operator: In
            values: ["nitro"]
          - key: "karpenter.k8s.aws/instance-generation"
            operator: Gt
            values: ["2"]
        limits:
          cpu: 1000
        disruption:
          consolidationPolicy: WhenEmptyOrUnderutilized
          consolidateAfter: 1m
        weight: 100
      EOT
      ]
    }
    spark-compute-ondemand = {
      values = [
        <<-EOT
      name: spark-compute-ondemand
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          tags:
            Name: "${module.eks.cluster_name}-private-secondary*"
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        instanceStorePolicy: RAID0

      nodePool:
        labels:
          - type: karpenter
          - NodeGroupType: SparkComputeOnDemand
          - multiArch: Spark
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["on-demand"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["amd64"]
        limits:
          cpu: 2000
        disruption:
          consolidationPolicy: WhenEmptyOrUnderutilized
          consolidateAfter: 1m
        weight: 100
      EOT
      ]
    }
    spark-compute-spot-cmr = {
      values = [
        <<-EOT
      name: spark-compute-spot-cmr
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          tags:
            Name: "${module.eks.cluster_name}-private-secondary*"
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        instanceStorePolicy: RAID0

      nodePool:
        labels:
          - type: karpenter
          - NodeGroupType: SparkComputeSpotCMR
          - multiArch: Spark
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["amd64"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["c","m","r"]
        limits:
          cpu: 2000
        disruption:
          consolidationPolicy: WhenEmptyOrUnderutilized
          consolidateAfter: 1m
        weight: 100
      EOT
      ]
    }
    spark-compute-spot-r = {
      values = [
        <<-EOT
      name: spark-compute-spot-r
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          tags:
            Name: "${module.eks.cluster_name}-private-secondary*"
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        instanceStorePolicy: RAID0

      nodePool:
        labels:
          - type: karpenter
          - NodeGroupType: SparkComputeSpotR
          - multiArch: Spark
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["amd64"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["r"]
          - key: karpenter.k8s.aws/instance-family
            operator: In
            values: ["r5","r5n", "r6i", "r6in", "r7i"]
        limits:
          cpu: 2000
        disruption:
          consolidationPolicy: WhenEmptyOrUnderutilized
          consolidateAfter: 1m
        weight: 100
      EOT
      ]
    }
    spark-compute-graviton-od-memory = {
      values = [
        <<-EOT
      name: spark-compute-graviton-od-memory
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          tags:
            Name: "${module.eks.cluster_name}-private-secondary*"
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        instanceStorePolicy: RAID0

      nodePool:
        labels:
          - type: karpenter
          - NodeGroupType: SparkComputeGravitonODMemory
          - multiArch: Spark
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["on-demand"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["arm64"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["r"]
          - key: "karpenter.k8s.aws/instance-cpu"
            operator: In
            values: ["4", "8", "16", "32"]
          - key: "karpenter.k8s.aws/instance-hypervisor"
            operator: In
            values: ["nitro"]
          - key: "karpenter.k8s.aws/instance-generation"
            operator: Gt
            values: ["2"]
        limits:
          cpu: 2000
        disruption:
          consolidationPolicy: WhenEmptyOrUnderutilized
          consolidateAfter: 1m
        weight: 100
      EOT
      ]
    }
    spark-compute-graviton = {
      values = [
        <<-EOT
      name: spark-compute-graviton
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          tags:
            Name: "${module.eks.cluster_name}-private-secondary*"
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        instanceStorePolicy: RAID0
      nodePool:
        labels:
          - type: karpenter
          - NodeGroupType: SparkGravitonMemoryOptimized
          - multiArch: Spark
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot", "on-demand"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["arm64"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["r"]
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["r6gd"]
          - key: "karpenter.k8s.aws/instance-cpu"
            operator: In
            values: ["4", "8", "16", "32"]
          - key: "karpenter.k8s.aws/instance-hypervisor"
            operator: In
            values: ["nitro"]
          - key: "karpenter.k8s.aws/instance-generation"
            operator: Gt
            values: ["2"]
        limits:
          cpu: 2000
        disruption:
          consolidationPolicy: WhenEmptyOrUnderutilized
          consolidateAfter: 1m
        weight: 100
      EOT
      ]
    }
    spark-compute-nitro-nvme = {
      values = [
        <<-EOT
      name: spark-compute-nitro-nvme
      clusterName: ${module.eks.cluster_name}
      ec2NodeClass:
        amiFamily: AL2023
        amiSelectorTerms:
          - alias: al2023@latest
        karpenterRole: ${split("/", module.eks_blueprints_addons.karpenter.node_iam_role_arn)[1]}
        subnetSelectorTerms:
          tags:
            Name: "${module.eks.cluster_name}-private-secondary*"
        securityGroupSelectorTerms:
          tags:
            Name: ${module.eks.cluster_name}-node
        instanceStorePolicy: RAID0

      nodePool:
        labels:
          - type: karpenter
          - NodeGroupType: SparkComputeNitroNvme
          - multiArch: Spark
        requirements:
          - key: "karpenter.sh/capacity-type"
            operator: In
            values: ["spot", "on-demand"]
          - key: "kubernetes.io/arch"
            operator: In
            values: ["amd64"]
          - key: "karpenter.k8s.aws/instance-category"
            operator: In
            values: ["c"]
          - key: "karpenter.k8s.aws/instance-family"
            operator: In
            values: ["c5d"]
          - key: "karpenter.k8s.aws/instance-size"
            operator: In
            values: ["4xlarge", "9xlarge", "12xlarge", "18xlarge", "24xlarge"]
          - key: "karpenter.k8s.aws/instance-hypervisor"
            operator: In
            values: ["nitro"]
          - key: "karpenter.k8s.aws/instance-generation"
            operator: Gt
            values: ["2"]
        limits:
          cpu: 1000
        disruption:
          consolidationPolicy: WhenEmptyOrUnderutilized
          consolidateAfter: 1m
        weight: 100
      EOT
      ]
    }
  }

  #---------------------------------------------------------------
  # Spark Operator Add-on
  #---------------------------------------------------------------
  enable_spark_operator = true
  spark_operator_helm_config = {
    version = "2.2.0"
    timeout = "120"
    values = [
      <<-EOT
        controller:
          replicas: 1
          workers: 20
          batchScheduler:
            enable: false
        spark:
          jobNamespaces:
            - default
            - spark-team-a
            - spark-team-b
            - spark-team-c
            - spark-s3-express
          serviceAccount:
            create: false
          rbac:
            create: false
        prometheus:
          metrics:
            enable: true
            port: 8080
            portName: metrics
            endpoint: /metrics
            prefix: ""
          podMonitor:
            create: true
            labels: {}
            jobLabel: spark-operator-podmonitor
            podMetricsEndpoint:
              scheme: http
              interval: 5s
      EOT
    ]
  }

  #---------------------------------------------------------------
  # Apache YuniKorn Add-on
  #---------------------------------------------------------------
  enable_yunikorn = var.enable_yunikorn
  yunikorn_helm_config = {
    version = "1.6.3"
    values  = [templatefile("${path.module}/helm-values/yunikorn-values.yaml", {})]
  }

  #---------------------------------------------------------------
  # Spark History Server Add-on
  #---------------------------------------------------------------
  enable_spark_history_server = var.enable_spark_history_server

  spark_history_server_helm_config = {
    version = "1.5.1"
    values = [templatefile("${path.module}/helm-values/shs-values.yaml",
      {
        s3_bucket_name   = module.s3_bucket.s3_bucket_id,
        event_log_prefix = aws_s3_object.this.key,
    })]
    timeout = 600
  }

  #---------------------------------------------------------------
  # Kubecost Add-on
  #---------------------------------------------------------------
  enable_kubecost = true
  kubecost_helm_config = {
    version             = "2.7.0"
    values              = [templatefile("${path.module}/helm-values/kubecost-values.yaml", {})]
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  #---------------------------------------------------------------
  # Kuberay Operator Add-on
  #---------------------------------------------------------------
  enable_kuberay_operator = var.enable_raydata
  kuberay_operator_helm_config = {
    version = "1.4.0"
    values = [
      <<-EOT
      batchScheduler:
        enabled: false
    EOT
    ]
  }

  #---------------------------------------------------------------
  # JupyterHub Add-on
  #---------------------------------------------------------------
  enable_jupyterhub = var.enable_jupyterhub

  jupyterhub_helm_config = {
    values = [templatefile("${path.module}/helm-values/jupyterhub-singleuser-values.yaml", {
      jupyter_single_user_sa_name = var.enable_jupyterhub ? kubernetes_service_account_v1.jupyterhub_single_user_sa[0].metadata[0].name : "not-used"
    })]
    version = "3.3.8"
  }
}

#---------------------------------------------------------------
# EKS Blueprints Addons
#---------------------------------------------------------------
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.20"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------
  # Karpenter Autoscaler for EKS Cluster
  #---------------------------------------
  enable_karpenter                  = true
  karpenter_enable_spot_termination = true
  karpenter_node = {
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      S3TableAccess                = aws_iam_policy.s3tables_policy.arn
    }
  }
  karpenter = {
    chart_version       = "1.2.1"
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
  }

  #---------------------------------------
  # AWS for FluentBit - DaemonSet
  #---------------------------------------
  enable_aws_for_fluentbit = true
  aws_for_fluentbit_cw_log_group = {
    use_name_prefix   = false
    name              = "/${local.name}/aws-fluentbit-logs"
    retention_in_days = 30
  }
  aws_for_fluentbit = {
    chart_version = "0.1.34"
    s3_bucket_arns = [
      module.s3_bucket.s3_bucket_arn,
      "${module.s3_bucket.s3_bucket_arn}/*"
    ]
    values = [templatefile("${path.module}/helm-values/aws-for-fluentbit-values.yaml", {
      region               = local.region,
      cloudwatch_log_group = "/${local.name}/aws-fluentbit-logs"
      s3_bucket_name       = module.s3_bucket.s3_bucket_id
      cluster_name         = module.eks.cluster_name
    })]
  }

  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    chart_version = "1.11.0"
    set = [{
      name  = "enableServiceMutatorWebhook"
      value = "false"
    }]
  }

  enable_ingress_nginx = true
  ingress_nginx = {
    version = "4.12.0"
    values  = [templatefile("${path.module}/helm-values/nginx-values.yaml", {})]
  }

  #---------------------------------------
  # Prommetheus and Grafana stack
  #---------------------------------------
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
    chart_version = "69.5.2"
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
# S3 bucket for Spark Event Logs and Example Data
#---------------------------------------------------------------
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.6"

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

resource "aws_s3_object" "this" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "spark-event-logs/"
  content_type = "application/x-directory"
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

resource "aws_kms_key" "grafana" {
  description             = "KMS key for Grafana secrets"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = local.tags
}

resource "aws_secretsmanager_secret" "grafana" {
  name_prefix             = "${local.name}-grafana-"
  recovery_window_in_days = 0
  kms_key_id              = aws_kms_key.grafana.arn
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = aws_secretsmanager_secret.grafana.id
  secret_string = random_password.grafana.result
}

resource "aws_secretsmanager_secret_rotation" "grafana" {
  secret_id           = aws_secretsmanager_secret.grafana.id
  rotation_lambda_arn = aws_lambda_function.grafana_rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }
}

resource "aws_lambda_function" "grafana_rotation" {
  filename      = "${path.module}/lambda/rotation.zip"
  function_name = "${local.name}-grafana-rotation"
  role          = aws_iam_role.grafana_rotation.arn
  handler       = "index.handler"
  runtime       = "python3.11"

  environment {
    variables = {
      SECRET_ARN = aws_secretsmanager_secret.grafana.arn
    }
  }

  tags = local.tags
}

resource "aws_iam_role" "grafana_rotation" {
  name_prefix = "${local.name}-grafana-rotation-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "grafana_rotation_basic" {
  role       = aws_iam_role.grafana_rotation.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "grafana_rotation_secrets" {
  name_prefix = "${local.name}-grafana-rotation-secrets-"
  role        = aws_iam_role.grafana_rotation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = aws_secretsmanager_secret.grafana.arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetRandomPassword"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_permission" "grafana_rotation" {
  statement_id  = "AllowExecutionFromSecretsManager"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.grafana_rotation.function_name
  principal     = "secretsmanager.amazonaws.com"
}

#---------------------------------------------------------------
# S3Table IAM policy for Karpenter nodes
#---------------------------------------------------------------
resource "aws_iam_policy" "s3tables_policy" {
  name_prefix = "${local.name}-s3tables"
  path        = "/"
  description = "S3Tables Metadata access for Nodes"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VisualEditor0"
        Effect = "Allow"
        Action = [
          "s3tables:UpdateTableMetadataLocation",
          "s3tables:GetNamespace",
          "s3tables:ListTableBuckets",
          "s3tables:ListNamespaces",
          "s3tables:GetTableBucket",
          "s3tables:GetTableBucketMaintenanceConfiguration",
          "s3tables:GetTableBucketPolicy",
          "s3tables:CreateNamespace",
          "s3tables:CreateTable"
        ]
        Resource = "arn:aws:s3tables:*:${data.aws_caller_identity.current.account_id}:bucket/*"
      },
      {
        Sid    = "VisualEditor1"
        Effect = "Allow"
        Action = [
          "s3tables:GetTableMaintenanceJobStatus",
          "s3tables:GetTablePolicy",
          "s3tables:GetTable",
          "s3tables:GetTableMetadataLocation",
          "s3tables:UpdateTableMetadataLocation",
          "s3tables:GetTableData",
          "s3tables:GetTableMaintenanceConfiguration"
        ]
        Resource = "arn:aws:s3tables:*:${data.aws_caller_identity.current.account_id}:bucket/*/table/*"
      }
    ]
  })
}

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
}

resource "aws_prometheus_workspace" "amp" {
  count = var.enable_amazon_prometheus ? 1 : 0

  alias = format("%s-%s", "amp-ws", local.name)
  tags  = local.tags
}

module "amp_ingest_irsa" {
  count = var.enable_amazon_prometheus ? 1 : 0

  source         = "aws-ia/eks-blueprints-addon/aws"
  version        = "~> 1.1"
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

#---------------------------------------------------------------
# EKS Cluster
#---------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.33"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  cluster_endpoint_public_access  = false
  cluster_endpoint_private_access = true

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true

  #---------------------------------------
  # Amazon EKS Managed Add-ons
  #---------------------------------------
  cluster_addons = {
    coredns                = {}
    eks-pod-identity-agent = {}
    vpc-cni = {
      before_compute = true
      preserve       = true
      most_recent    = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }

    kube-proxy = {}
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
      addon_version            = "v1.48.0-eksbuild.1"
      most_recent              = false
    }

    aws-mountpoint-s3-csi-driver = {
      service_account_role_arn = module.s3_csi_driver_irsa.iam_role_arn
      addon_version            = "v1.15.0-eksbuild.1"
      most_recent              = false
    }

    metrics-server = {}
    amazon-cloudwatch-observability = {
      preserve                 = true
      service_account_role_arn = aws_iam_role.cloudwatch_observability_role.arn
    }
  }

  vpc_id = module.vpc.vpc_id
  subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
    substr(cidr_block, 0, 4) == "100." ? subnet_id : null]
  )

  kms_key_administrators = distinct(concat([
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"],
    var.kms_key_admin_roles,
    [data.aws_iam_session_context.current.issuer_arn]

  ))

  #---------------------------------------
  # Note: This can further restricted to specific required for each Add-on and your application
  #---------------------------------------
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
    }
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
    egress_all = {
      description = "Node all egress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
    }
  }

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }

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
  }

  eks_managed_node_groups = {
    core_node_group = {
      name        = "core-node-group"
      description = "EKS managed node group example launch template"
      subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]
      )

      min_size     = 3
      max_size     = 3
      desired_size = 3

      instance_types = ["m5.xlarge"]

      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core"
      }

      tags = {
        Name                     = "core-node-grp",
        "karpenter.sh/discovery" = local.name
      }
    }

    spark_benchmark_ebs = {
      name        = "spark_benchmark_ebs"
      description = "Managed node group for Spark Benchmarks with EBS using x86 or ARM"
      subnet_ids = [element(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), 0)
      ]

      ami_type = "AL2023_ARM_64_STANDARD"

      min_size     = 0
      max_size     = 8
      desired_size = 0

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 300
            volume_type           = "gp3"
            iops                  = 3000
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      instance_types = ["r8g.12xlarge"]

      labels = {
        NodeGroupType = "spark_benchmark_ebs"
      }

      tags = {
        Name          = "spark_benchmark_ebs"
        NodeGroupType = "spark_benchmark_ebs"
      }
    }

    spark_benchmark_ssd = {
      name        = "spark_benchmark_ssd"
      description = "Managed node group for Spark Benchmarks with NVMEe SSD using x86 or ARM"
      subnet_ids = [element(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), 0)
      ]

      ami_type = "AL2023_x86_64_STANDARD"

      min_size     = var.spark_benchmark_ssd_min_size
      max_size     = 8
      desired_size = var.spark_benchmark_ssd_desired_size

      instance_types = ["c5d.12xlarge"]

      cloudinit_pre_nodeadm = [
        {
          content_type = "application/node.eks.aws"
          content      = <<-EOT
            ---
            apiVersion: node.eks.aws/v1alpha1
            kind: NodeConfig
            spec:
              instance:
                localStorage:
                  strategy: RAID0
          EOT
        }
      ]

      labels = {
        NodeGroupType = "spark_benchmark_ssd"
      }

      tags = {
        Name          = "spark_benchmark_ssd"
        NodeGroupType = "spark_benchmark_ssd"
      }
    }

    spark_operator_bench = {
      name        = "spark_operator_bench"
      description = "Managed node group for Spark Operator Benchmarks with EBS using x86 or ARM"
      subnet_ids = [element(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), 0)
      ]

      ami_type = "AL2023_x86_64_STANDARD"

      cloudinit_pre_nodeadm = [
        {
          content_type = "application/node.eks.aws"
          content      = <<-EOT
            ---
            apiVersion: node.eks.aws/v1alpha1
            kind: NodeConfig
            spec:
              kubelet:
                config:
                  maxPods: 220
          EOT
        }
      ]

      min_size     = 0
      max_size     = 200
      desired_size = 0

      instance_types = ["m6a.4xlarge"]

      labels = {
        NodeGroupType = "spark-operator-benchmark-ng"
      }

      taints = {
        benchmark = {
          key      = "spark-operator-benchmark-ng"
          effect   = "NO_SCHEDULE"
          operator = "EXISTS"
        }
      }

      tags = {
        Name          = "spark-operator-benchmark-ng"
        NodeGroupType = "spark-operator-benchmark-ng"
      }
    }
  }
}

#---------------------------------------------------------------
# EKS Amazon CloudWatch Observability Role
#---------------------------------------------------------------
resource "aws_iam_role" "cloudwatch_observability_role" {
  name_prefix = "${local.name}-eks-cw-agent-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent",
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_observability_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.cloudwatch_observability_role.name
}

#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.55"
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
# IRSA for Mountpoint S3 CSI Driver
#---------------------------------------------------------------
module "s3_csi_driver_irsa" {
  source           = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version          = "~> 5.55"
  role_name_prefix = format("%s-%s-", local.name, "s3-csi-driver")
  role_policy_arns = {
    s3_access = aws_iam_policy.s3_irsa_access_policy.arn
  }
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:s3-csi-driver-sa"]
    }
  }
  tags = local.tags
}

resource "aws_iam_policy" "s3_irsa_access_policy" {
  name_prefix = "${local.name}-S3Access-"
  path        = "/"
  description = "S3 Access for Nodes"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3express:CreateSession"
        ]
        Effect = "Allow"
        Resource = [
          "${module.s3_bucket.s3_bucket_arn}",
          "${module.s3_bucket.s3_bucket_arn}/*"
        ]
      },
    ]
  })
}

#-----------------------------------------------------------------------------------------
# JupyterHub Single User IRSA Configuration
#-----------------------------------------------------------------------------------------
resource "kubernetes_namespace" "jupyterhub" {
  count = var.enable_jupyterhub ? 1 : 0
  metadata {
    name = "jupyterhub"
  }
}

module "jupyterhub_single_user_irsa" {
  count     = var.enable_jupyterhub ? 1 : 0
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "~> 5.52.0"
  role_name = "${module.eks.cluster_name}-jupyterhub-single-user-sa"

  role_policy_arns = {
    policy          = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
    s3tables_policy = aws_iam_policy.s3tables.arn
    bedrock_policy  = aws_iam_policy.bedrock[0].arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${kubernetes_namespace.jupyterhub[0].metadata[0].name}:${module.eks.cluster_name}-jupyterhub-single-user"]
    }
  }
}

resource "kubernetes_service_account_v1" "jupyterhub_single_user_sa" {
  count = var.enable_jupyterhub ? 1 : 0
  metadata {
    name        = "${module.eks.cluster_name}-jupyterhub-single-user"
    namespace   = kubernetes_namespace.jupyterhub[0].metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.jupyterhub_single_user_irsa[0].iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "jupyterhub_single_user" {
  count = var.enable_jupyterhub ? 1 : 0
  metadata {
    name      = "${module.eks.cluster_name}-jupyterhub-single-user-secret"
    namespace = kubernetes_namespace.jupyterhub[0].metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.jupyterhub_single_user_sa[0].metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace.jupyterhub[0].metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

#---------------------------------------------------------------------
# Example IAM policy for accessing Bedrock Models from Spark Jobs
#---------------------------------------------------------------------
data "aws_iam_policy_document" "bedrock_jupyter" {
  statement {
    sid    = "BedrockModelAccess"
    effect = "Allow"
    resources = [
      "arn:${data.aws_partition.current.partition}:bedrock:${local.region}::foundation-model/anthropic.claude-3-7-sonnet-20250219-v1:0",
      "arn:${data.aws_partition.current.partition}:bedrock:${local.region}::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0",
      "arn:aws:bedrock:${local.region}:${data.aws_caller_identity.current.account_id}:inference-profile/us.anthropic.claude-3-7-sonnet-20250219-v1:0",
      "arn:aws:bedrock:${local.region}:${data.aws_caller_identity.current.account_id}:inference-profile/us.anthropic.claude-sonnet-4-20250514-v1:0"
    ]
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]
  }

  statement {
    sid       = "BedrockModelDiscovery"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "bedrock:ListFoundationModels",
      "bedrock:GetFoundationModel"
    ]
  }
}

resource "aws_iam_policy" "bedrock" {
  count       = var.enable_jupyterhub ? 1 : 0
  description = "IAM role policy for Bedrock model access from JupyterHub pods"
  name_prefix = "${local.name}-bedrock-irsa"
  policy      = data.aws_iam_policy_document.bedrock_jupyter.json
}

provider "aws" {
  region = local.region
}

provider "aws" {
  alias  = "ecr"
  region = "us-east-1"
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubectl" {
  apply_retry_count      = 10
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false
  token                  = data.aws_eks_cluster_auth.this.token
}

locals {
  name   = var.name
  region = var.region
  azs    = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  s3_prefix        = "${local.name}/spark-application-logs/spark-team-a"
  iceberg_database = "raydata_spark_logs"

  s3_express_supported_az_ids = [
    "use1-az4", "use1-az5", "use1-az6", "usw2-az1", "usw2-az3", "usw2-az4", "apne1-az1", "apne1-az4", "eun1-az1", "eun1-az2", "eun1-az3"
  ]

  s3_express_az_ids = [
    for az_id in data.aws_availability_zones.available.zone_ids :
    az_id if contains(local.s3_express_supported_az_ids, az_id)
  ]

  s3_express_azs = [for zone_id in local.s3_express_az_ids : [
    for az in data.aws_availability_zones.available.zone_ids :
    data.aws_availability_zones.available.names[index(data.aws_availability_zones.available.zone_ids, az)] if az == zone_id
  ][0]]

  s3_express_zone_id   = local.s3_express_az_ids[0]
  s3_express_zone_name = local.s3_express_azs[0]

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

#---------------------------------------------------------------
# Example IAM policy for Spark job execution
#---------------------------------------------------------------
data "aws_iam_policy_document" "spark_operator" {
  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::*"]

    actions = [
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
    ]
  }

  statement {
    sid       = ""
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:*"]

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
  }
}

#---------------------------------------------------------------------
# Example IAM policy for s3 Tables access from Spark Jobs.
#---------------------------------------------------------------------
data "aws_iam_policy_document" "s3tables_policy" {
  version = "2012-10-17"

  statement {
    sid    = "VisualEditor0"
    effect = "Allow"

    actions = [
      "s3tables:CreateTableBucket",
      "s3tables:ListTables",
      "s3tables:CreateTable",
      "s3tables:GetNamespace",
      "s3tables:DeleteTableBucket",
      "s3tables:CreateNamespace",
      "s3tables:ListNamespaces",
      "s3tables:ListTableBuckets",
      "s3tables:GetTableBucket",
      "s3tables:DeleteNamespace",
      "s3tables:GetTableBucketMaintenanceConfiguration",
      "s3tables:PutTableBucketMaintenanceConfiguration",
      "s3tables:GetTableBucketPolicy"
    ]

    resources = ["arn:aws:s3tables:*:${data.aws_caller_identity.current.account_id}:bucket/*"]
  }

  statement {
    sid    = "VisualEditor1"
    effect = "Allow"

    actions = [
      "s3tables:GetTableMaintenanceJobStatus",
      "s3tables:GetTablePolicy",
      "s3tables:GetTable",
      "s3tables:GetTableMetadataLocation",
      "s3tables:UpdateTableMetadataLocation",
      "s3tables:DeleteTable",
      "s3tables:PutTableData",
      "s3tables:RenameTable",
      "s3tables:PutTableMaintenanceConfiguration",
      "s3tables:GetTableData",
      "s3tables:GetTableMaintenanceConfiguration"
    ]

    resources = ["arn:aws:s3tables:*:${data.aws_caller_identity.current.account_id}:bucket/*/table/*"]
  }

  statement {
    sid    = "VisualEditor2"
    effect = "Allow"

    actions = ["s3tables:ListTableBuckets"]

    resources = ["*"]
  }
}

################################################################################
# Cluster
################################################################################

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = module.eks.cluster_arn
}

output "cluster_name" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = module.eks.cluster_name
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

################################################################################
# Private Subnets
################################################################################

output "subnet_ids_starting_with_100" {
  description = "Secondary CIDR Private Subnet IDs for EKS Data Plane"
  value       = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) : substr(cidr_block, 0, 4) == "100." ? subnet_id : null])
}

output "s3_bucket_id_spark_history_server" {
  description = "Spark History server logs S3 bucket ID"
  value       = module.s3_bucket.s3_bucket_id
}

output "s3_bucket_region_spark_history_server" {
  description = "Spark History server logs S3 bucket ID"
  value       = module.s3_bucket.s3_bucket_region
}

output "grafana_secret_name" {
  description = "Grafana password secret name"
  value       = aws_secretsmanager_secret.grafana.name
}

################################################################################
# S3 Directory Bucket
################################################################################

output "s3directory_bucket_name" {
  description = "s3 directory bucket name"
  value       = aws_s3_directory_bucket.spark_data_bucket_express.bucket
}

output "s3directory_bucket_region" {
  description = "s3 directory bucket region"
  value       = local.region
}

output "s3directory_bucket_zone" {
  description = "s3 directory bucket availability zone"
  value       = local.s3_express_zone_name
}

################################################################################
# Ray Data Configuration
################################################################################

output "raydata_config" {
  description = "Configuration for Ray Data processing"
  value = var.enable_raydata ? {
    namespace         = "raydata"
    service_account   = "raydata"
    s3_prefix         = local.s3_prefix
    iceberg_database  = local.iceberg_database
    iceberg_warehouse = "s3://${module.s3_bucket.s3_bucket_id}/iceberg-warehouse/"
    iam_role_arn      = module.spark_team_irsa["raydata"].iam_role_arn
  } : null
}

resource "aws_iam_policy" "raydata_iceberg" {
  count = var.enable_raydata ? 1 : 0

  name        = "${local.name}-raydata-iceberg-policy"
  description = "IAM policy for Ray Data to access S3 and Glue for Iceberg operations"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = [
          "${module.s3_bucket.s3_bucket_arn}/${local.s3_prefix}*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload"
        ]
        Resource = [
          "${module.s3_bucket.s3_bucket_arn}/iceberg-warehouse/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          module.s3_bucket.s3_bucket_arn
        ]
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "${local.s3_prefix}*",
              "iceberg-warehouse/*",
              trimsuffix(local.s3_prefix, "/")
            ]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          module.s3_bucket.s3_bucket_arn
        ]
        Condition = {
          StringEquals = {
            "s3:prefix" = [
              trimsuffix(local.s3_prefix, "/")
            ]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:CreateDatabase",
          "glue:GetTable",
          "glue:GetTables",
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:DeleteTable",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:CreatePartition",
          "glue:UpdatePartition",
          "glue:DeletePartition",
          "glue:BatchCreatePartition",
          "glue:BatchDeletePartition",
          "glue:BatchUpdatePartition"
        ]
        Resource = [
          "arn:aws:glue:${local.region}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${local.region}:${data.aws_caller_identity.current.account_id}:database/*",
          "arn:aws:glue:${local.region}:${data.aws_caller_identity.current.account_id}:table/*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "lakeformation:GetDataAccess"
        ]
        Resource = ["*"]
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "raydata_iceberg" {
  count = var.enable_raydata ? 1 : 0

  role       = module.spark_team_irsa["raydata"].iam_role_name
  policy_arn = aws_iam_policy.raydata_iceberg[0].arn

  depends_on = [module.spark_team_irsa]
}

resource "aws_glue_catalog_database" "raydata_iceberg" {
  count = var.enable_raydata ? 1 : 0

  name        = local.iceberg_database
  description = "Database for storing processed Spark logs using Iceberg format"

  catalog_id = data.aws_caller_identity.current.account_id

  tags = local.tags
}

resource "aws_s3_directory_bucket" "spark_data_bucket_express" {
  bucket        = "${local.name}-${local.account_id}--${local.s3_express_zone_id}--x-s3"
  force_destroy = true

  location {
    name = local.s3_express_zone_id
  }
}

locals {
  teams = ["spark-team-a", "spark-team-b", "spark-team-c", "spark-s3-express", "raydata"]
}

resource "kubernetes_namespace_v1" "spark_team" {
  for_each = toset(local.teams)

  metadata {
    name = each.value
  }
  timeouts {
    delete = "15m"
  }
}

resource "kubernetes_service_account_v1" "spark_team" {
  for_each = toset(local.teams)

  metadata {
    name        = each.value
    namespace   = kubernetes_namespace_v1.spark_team[each.key].metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.spark_team_irsa[each.key].iam_role_arn }
  }

  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "spark_team" {
  for_each = toset(local.teams)

  metadata {
    name      = "${each.value}-secret"
    namespace = kubernetes_namespace_v1.spark_team[each.key].metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.spark_team[each.key].metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace_v1.spark_team[each.key].metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

module "spark_team_irsa" {
  for_each = toset(local.teams)

  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.1"

  create_release = false
  create_role    = true
  role_name      = "${local.name}-${each.value}"
  create_policy  = false
  role_policies = {
    spark_team_policy = aws_iam_policy.spark.arn
    s3tables_policy   = aws_iam_policy.s3tables.arn
  }

  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = each.value
      service_account = each.value
    }
  }
}

resource "aws_iam_policy" "spark" {
  description = "IAM role policy for Spark Job execution"
  name_prefix = "${local.name}-spark-irsa"
  policy      = data.aws_iam_policy_document.spark_operator.json
}

resource "aws_iam_policy" "s3tables" {
  description = "IAM role policy for S3 Tables Access from Spark Job execution"
  name_prefix = "${local.name}-s3tables-irsa"
  policy      = data.aws_iam_policy_document.s3tables_policy.json
}

resource "kubernetes_cluster_role" "spark_role" {
  metadata {
    name = "spark-cluster-role"
  }

  rule {
    verbs      = ["get", "list", "watch"]
    api_groups = [""]
    resources  = ["namespaces", "nodes", "persistentvolumes"]
  }

  rule {
    verbs      = ["list", "watch"]
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses"]
  }

  rule {
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "deletecollection", "annotate", "patch", "label"]
    api_groups = [""]
    resources  = ["serviceaccounts", "services", "configmaps", "events", "pods", "pods/log", "persistentvolumeclaims"]
  }

  rule {
    verbs      = ["create", "patch", "delete", "watch"]
    api_groups = [""]
    resources  = ["secrets"]
  }

  rule {
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "annotate", "patch", "label"]
    api_groups = ["apps"]
    resources  = ["statefulsets", "deployments"]
  }

  rule {
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "annotate", "patch", "label"]
    api_groups = ["batch", "extensions"]
    resources  = ["jobs"]
  }

  rule {
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "annotate", "patch", "label"]
    api_groups = ["extensions"]
    resources  = ["ingresses"]
  }

  rule {
    verbs      = ["get", "list", "watch", "describe", "create", "edit", "delete", "deletecollection", "annotate", "patch", "label"]
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["roles", "rolebindings"]
  }

  depends_on = [module.spark_team_irsa]
}

resource "kubernetes_cluster_role_binding" "spark_role_binding" {
  for_each = toset(local.teams)

  metadata {
    name = "spark-cluster-role-bind-${each.value}"
  }

  subject {
    kind      = "ServiceAccount"
    name      = each.value
    namespace = each.value
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.spark_role.id
  }

  depends_on = [module.spark_team_irsa]
}

variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "spark-operator-doeks"
  type        = string
}

variable "region" {
  description = "Region"
  type        = string
  default     = "us-west-2"
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.33"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR. This should be a valid private (RFC 1918) CIDR range"
  default     = "10.1.0.0/16"
  type        = string
}

variable "secondary_cidr_blocks" {
  description = "Secondary CIDR blocks to be attached to VPC"
  default     = ["100.64.0.0/16"]
  type        = list(string)
}

variable "az_count" {
  description = "Number of Availability Zones (2-4)"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "AZ count must be between 2 and 4"
  }
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC Endpoints"
  default     = false
  type        = bool
}

variable "enable_amazon_prometheus" {
  description = "Enable AWS Managed Prometheus service"
  type        = bool
  default     = true
}

variable "enable_yunikorn" {
  default     = false
  description = "Enable Apache YuniKorn Scheduler"
  type        = bool
}

variable "enable_jupyterhub" {
  default     = false
  description = "Enable Jupyter Hub"
  type        = bool
}

variable "kms_key_admin_roles" {
  description = "list of role ARNs to add to the KMS policy"
  type        = list(string)
  default     = []
}

variable "spark_benchmark_ssd_min_size" {
  description = "Minimum size for nodegroup of c5d 12xlarge instances to run data generation for Spark benchmark"
  type        = number
  default     = 0
}

variable "spark_benchmark_ssd_desired_size" {
  description = "Desired size for nodegroup of c5d 12xlarge instances to run data generation for Spark benchmark"
  type        = number
  default     = 0
}

variable "enable_raydata" {
  description = "Enable Ray Data Spark logs processing with Iceberg"
  type        = bool
  default     = false
}

variable "enable_spark_history_server" {
  description = "Enable Spark History Server"
  type        = bool
  default     = true
}

terraform {
  required_version = ">= 1.3.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.95"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
  }
}

#---------------------------------------------------------------
# Supporting Network Resources
#---------------------------------------------------------------

locals {

  private_primary_subnets = [
    for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i)
  ]

  private_secondary_subnets = [
    for i, az in local.azs : cidrsubnet(var.secondary_cidr_blocks[0], 2, i)
  ]

  public_subnets = [
    for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, 128 + i)
  ]

  all_private_subnets = concat(local.private_primary_subnets, local.private_secondary_subnets)

  private_subnet_names = concat(
    [for az in local.azs : "${var.name}-private-${az}"],
    [for az in local.azs : "${var.name}-private-secondary-${az}"]
  )

  public_subnet_names = [for az in local.azs : "${var.name}-public-${az}"]

}

#---------------------------------------------------------------
# VPC
#---------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.19"

  name = local.name
  cidr = var.vpc_cidr

  azs = local.azs

  secondary_cidr_blocks = var.secondary_cidr_blocks

  private_subnets      = local.all_private_subnets
  private_subnet_names = local.private_subnet_names
  public_subnets       = local.public_subnets
  public_subnet_names  = local.public_subnet_names

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true
  flow_log_retention_in_days           = 7
  flow_log_traffic_type                = "REJECT"

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = local.name
  }

  tags = local.tags
}

module "vpc_endpoints_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.3"

  create = var.enable_vpc_endpoints

  name        = "${local.name}-vpc-endpoints"
  description = "Security group for VPC endpoint access"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      rule        = "https-443-tcp"
      description = "VPC CIDR HTTPS"
      cidr_blocks = join(",", [module.vpc.vpc_cidr_block], module.vpc.vpc_secondary_cidr_blocks)
    },
  ]

  egress_with_cidr_blocks = [
    {
      rule        = "https-443-tcp"
      description = "All egress HTTPS"
      cidr_blocks = "0.0.0.0/0"
    },
  ]

  tags = local.tags
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 5.21"

  create = var.enable_vpc_endpoints

  vpc_id             = module.vpc.vpc_id
  security_group_ids = [module.vpc_endpoints_sg.security_group_id]

  endpoints = merge({
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = concat(module.vpc.public_route_table_ids, module.vpc.private_route_table_ids)
      tags = {
        Name = "${local.name}-s3"
      }
    }
    },
    { for service in toset(["autoscaling", "ecr.api", "ecr.dkr", "ec2", "ec2messages", "eks", "eks-auth", "elasticloadbalancing", "sts", "kms", "logs", "ssm", "ssmmessages"]) :
      replace(service, ".", "_") =>
      {
        service = service
        subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
          substr(cidr_block, 0, 3) == "10." ? subnet_id : null]
        )
        private_dns_enabled = true
        tags                = { Name = "${local.name}-${service}" }
      }
  })

  tags = local.tags
}