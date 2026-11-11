```hcl
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
  version = "1.38.0" # ensure to update this to the latest/desired version

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
          - alias: al2023@latest # Amazon Linux 2023
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
          - alias: al2023@latest # Amazon Linux 2023
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
          - alias: al2023@latest # Amazon Linux 2023
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
          - alias: al2023@latest # Amazon Linux 2023
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

            # Get instance info
            INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
            AVAILABILITY_ZONE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
            REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[a-z]$//')

            # Get the number of cores available
            CORES=$(nproc --all)

            # Define volume size based on the number of cores and EBS volume size per core
            VOLUME_SIZE=$(expr $CORES \* 10) # 10GB per core. Change as desired

            # Create a volume
            VOLUME_ID=$(aws ec2 create-volume --availability-zone $AVAILABILITY_ZONE --size $VOLUME_SIZE --volume-type gp3 --region $REGION --output text --query 'VolumeId')

            # Check whether the volume is available
            while [ "$(aws ec2 describe-volumes --volume-ids $VOLUME_ID --region $REGION --query "Volumes[*].State" --output text)" != "available" ]; do
              echo "Waiting for volume to become available"
              sleep 5
            done

            # Attach the volume to the instance
            aws ec2 attach-volume --volume-id $VOLUME_ID --instance-id $INSTANCE_ID --device /dev/xvdb --region $REGION

            # Update the state to delete the volume when the node is terminated
            aws ec2 modify-instance-attribute --instance-id $INSTANCE_ID --block-device-mappings "[{\"DeviceName\": \"/dev/xvdb\",\"Ebs\":{\"DeleteOnTermination\":true}}]" --region $REGION

            # Wait for the volume to be attached
            while [ "$(aws ec2 describe-volumes --volume-ids $VOLUME_ID --region $REGION --query "Volumes[*].Attachments[*].State" --output text)" != "attached" ]; do
              echo "Waiting for volume to be attached"
              sleep 5
            done

            # Format the volume
            sudo mkfs -t ext4 /dev/xvdb # Improve this to get this value dynamically
            # Create a mount point
            sudo mkdir /mnt/k8s-disks # Change directory as you like
            # Mount the volume
            sudo mount /dev/xvdb /mnt/k8s-disks
            # To mount this EBS volume on every system reboot, you need to add an entry in /etc/fstab
            echo "/dev/xvdb /mnt/k8s-disks ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab

            # Adding permissions to the mount
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
          - alias: al2023@latest # Amazon Linux 2023
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
          - alias: al2023@latest # Amazon Linux 2023
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
          # -- Number of replicas of controller.
          replicas: 1
          # -- Reconcile concurrency, higher values might increase memory usage.
          # -- Increased from 10 to 20 to leverage more cores from the instance
          workers: 20
          # -- Change this to True when YuniKorn is deployed
          batchScheduler:
            enable: false
            # default: "yunikorn"
        #   -- Uncomment this for Spark Operator scale test
        #   -- Spark Operator is CPU bound so add more CPU or use compute optimized instance for handling large number of job submissions
        #   nodeSelector:
        #     NodeGroupType: spark-operator-benchmark
        #   resources:
        #     requests:
        #       cpu: 33000m
        #       memory: 50Gi
        # webhook:
        #   nodeSelector:
        #     NodeGroupType: spark-operator-benchmark
        #   resources:
        #     requests:
        #       cpu: 1000m
        #       memory: 10Gi
        spark:
          # -- List of namespaces where to run spark jobs.
          # If empty string is included, all namespaces will be allowed.
          # Make sure the namespaces have already existed.
          jobNamespaces:
            - default
            - spark-team-a
            - spark-team-b
            - spark-team-c
            - spark-s3-express
          serviceAccount:
            # -- Specifies whether to create a service account for the controller.
            create: false
          rbac:
            # -- Specifies whether to create RBAC resources for the controller.
            create: false
        prometheus:
          metrics:
            enable: true
            port: 8080
            portName: metrics
            endpoint: /metrics
            prefix: ""
          # Prometheus pod monitor for controller pods
          # Note: The kube-prometheus-stack addon must deploy before the PodMonitor CRD is available.
          #       This can cause the terraform apply to fail since the addons are deployed in parallel
          podMonitor:
            # -- Specifies whether to create pod monitor.
            create: true
            labels: {}
            # -- The label to use to retrieve the job name from
            jobLabel: spark-operator-podmonitor
            # -- Prometheus metrics endpoint properties. `metrics.portName` will be used as a port
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
  # Spark history server is required only when EMR Spark Operator is enabled
  enable_spark_history_server = var.enable_spark_history_server

  spark_history_server_helm_config = {
    version = "1.5.1"
    values = [templatefile("${path.module}/helm-values/shs-values.yaml",
      {
        s3_bucket_name   = module.s3_bucket.s3_bucket_id,
        event_log_prefix = aws_s3_object.this.key,
    })]
    timeout = 600 # add timeout(extra time) for EBS provisioning
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
    # Enabling Volcano as Batch scheduler for KubeRay Operator
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
  version = "1.20.0"

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
    name              = "/${local.name}/aws-fluentbit-logs" # Add-on creates this log group
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
#tfsec:ignore:*
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "4.6.0"

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

# Creating an s3 bucket prefix. Ensure you copy Spark History event logs under this path to visualize the dags
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

resource "aws_secretsmanager_secret" "grafana" {
  name_prefix             = "${local.name}-grafana-"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
  kms_key_id              = module.eks.kms_key_arn
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = aws_secretsmanager_secret.grafana.id
  secret_string = random_password.grafana.result
}

#---------------------------------------------------------------
# S3Table IAM policy for Karpenter nodes
# The S3 tables library does not fully support IRSA and Pod Identity as of this writing.
# We give the node role access to S3tables to work around this limitation.
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
  amp_namespace               = "kube-prometheus-stack"
}

resource "aws_prometheus_workspace" "amp" {
  count = var.enable_amazon_prometheus ? 1 : 0

  alias = format("%s-%s", "amp-ws", local.name)
  tags  = local.tags
}

module "amp_ingest_irsa" {
  count = var.enable_amazon_prometheus ? 1 : 0

  source         = "aws-ia/eks-blueprints-addon/aws"
  version        = "1.1.0"
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
  version = "20.33.0"

  cluster_name    = local.name
  cluster_version = var.eks_cluster_version

  cluster_endpoint_public_access  = false
  cluster_endpoint_private_access = true

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Add the IAM identity that terraform is using as a cluster admin
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
      most_recent    = true # To ensure access to the latest settings provided
      configuration_values = jsonencode({
        env = {
          # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
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
  # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the EKS Control Plane ENIs will be created
  subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
    substr(cidr_block, 0, 4) == "100." ? subnet_id : null]
  )

  # Combine root account, current user/role and additinoal roles to be able to access the cluster KMS key - required for terraform updates
  kms_key_administrators = distinct(concat([
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"],
    var.kms_key_admin_roles,
    [data.aws_iam_session_context.current.issuer_arn]

  ))

  #---------------------------------------
  # Note: This can further restricted to specific required for each Add-on and your application
  #---------------------------------------
  # Extend cluster security group rules
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

  # Extend node-to-node security group rules
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    # Allows Control Plane Nodes to talk to Worker nodes on all ports. Added this to simplify the example and further avoid issues with Add-ons communication with Control plane.
    # This can be restricted further to specific port based on the requirement for each Add-on e.g., metrics-server 4443, spark-operator 8080, karpenter 8443 etc.
    # Change this according to your security requirements if needed
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
    egress_all = {
      description = "Node all egress within VPC"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = [var.vpc_cidr, var.secondary_cidr_blocks[0]]
    }
    egress_https = {
      description = "Node egress HTTPS to internet"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  eks_managed_node_group_defaults = {
    iam_role_additional_policies = {
      # Not required, but used in the example to access the nodes to inspect mounted volumes
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }

    ebs_optimized = true
    # This block device is used only for root volume. Adjust volume according to your size.
    # NOTE: Don't use this volume for Spark workloads
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
    #  We recommend to have a MNG to place your critical workloads and add-ons
    #  Then rely on Karpenter to scale your workloads
    #  You can also make uses on nodeSelector and Taints/tolerations to spread workloads on MNG or Karpenter provisioners
    core_node_group = {
      name        = "core-node-group"
      description = "EKS managed node group example launch template"
      # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
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

    # The following Node groups are a placeholder to create Node groups for running Spark TPC-DS benchmarks
    spark_benchmark_ebs = {
      name        = "spark_benchmark_ebs"
      description = "Managed node group for Spark Benchmarks with EBS using x86 or ARM"
      # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
      subnet_ids = [element(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), 0)
      ]

      # Change ami_type= AL2023_x86_64_STANDARD for x86 instances
      ami_type = "AL2023_ARM_64_STANDARD" # arm64

      # Node group will be created with zero instances when you deploy the blueprint.
      # You can change the min_size and desired_size to 6 instances
      # desired_size might not be applied through terrafrom once the node group is created so this needs to be adjusted in AWS Console.
      min_size     = 0 # Change min and desired to 6 for running benchmarks
      max_size     = 8
      desired_size = 0 # Change min and desired to 6 for running benchmarks

      # This storage is used as a shuffle for non NVMe SSD instances. e.g., r8g instances
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

      # Change the instance type as you desire and match with ami_type
      instance_types = ["r8g.12xlarge"] # Change Instance type to run the benchmark with various instance types

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
      # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
      subnet_ids = [element(compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), 0)
      ]

      ami_type = "AL2023_x86_64_STANDARD" # x86

      # Node group will be created with zero instances when you deploy the blueprint.
      # You can change the min_size and desired_size to 6 instances
      # desired_size might not be applied through terrafrom once the node group is created so this needs to be adjusted in AWS Console.
      min_size     = var.spark_benchmark_ssd_min_size # Change min and desired to 6 for running benchmarks
      max_size     = 8
      desired_size = var.spark_benchmark_ssd_desired_size # Change min and desired to 6 for running benchmarks

      instance_types = ["c5d.12xlarge"] # c5d.12xlarge = 2 x 900 NVMe SSD

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
      # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
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
  version               = "5.55.0"
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
  version          = "5.55.0"
  role_name_prefix = format("%s-%s-", local.name, "s3-csi-driver")
  role_policy_arns = {
    # WARNING: Demo purpose only. Bring your own IAM policy with least privileges
    s3_access = aws_iam_policy.s3_irsa_access_policy.arn
    #kms_access = "arn:aws:iam::aws:policy/AWSKeyManagementServicePowerUser"
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

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  # checkov:skip=CKV_AWS_288: Demo purpose IAM policy
  # checkov:skip=CKV_AWS_290: Demo purpose IAM policy
  # checkov:skip=CKV_AWS_289: Demo purpose IAM policy
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:*",
          "s3express:*"
        ]
        Effect = "Allow"
        Resource = [
          "arn:${data.aws_partition.current.partition}:s3:::*",
          "arn:${data.aws_partition.current.partition}:s3express:*:*:bucket/*"
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
  version   = "5.52.0"
  role_name = "${module.eks.cluster_name}-jupyterhub-single-user-sa"

  role_policy_arns = {
    policy          = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" # Policy needs to be defined based in what you need to give access to your notebook instances.
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
# Please modify this policy according to your security requirements.
#---------------------------------------------------------------------
data "aws_iam_policy_document" "bedrock_jupyter" {
  statement {
    sid    = "BedrockModelAccess"
    effect = "Allow"
    resources = [
      "arn:${data.aws_partition.current.partition}:bedrock:*::foundation-model/*",
      "arn:aws:bedrock:*:*:inference-profile/us.anthropic.claude-3-7-sonnet-20250219-v1:0",
      "arn:aws:bedrock:*:*:inference-profile/us.anthropic.claude-sonnet-4-20250514-v1:0"
    ]
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]
  }

  statement {
    sid    = "BedrockModelDiscovery"
    effect = "Allow"
    resources = [
      "arn:${data.aws_partition.current.partition}:bedrock:*::foundation-model/*"
    ]
    actions = [
      "bedrock:ListFoundationModels",
      "bedrock:GetFoundationModel"
    ]
  }
}

#---------------------------------------------------------------------
# Important prerequisite: Amazon Bedrock models must be enabled in the AWS console first.
# The IAM policy alone doesn't enable model access - you need to request access to models in the Bedrock console.
#---------------------------------------------------------------------
resource "aws_iam_policy" "bedrock" {
  count       = var.enable_jupyterhub ? 1 : 0
  description = "IAM role policy for Bedrock model access from JupyterHub pods"
  name_prefix = "${local.name}-bedrock-irsa"
  policy      = data.aws_iam_policy_document.bedrock_jupyter.json
}


provider "aws" {
  region = local.region
}

# ECR always authenticates with `us-east-1` region
# Docs -> https://docs.aws.amazon.com/AmazonECR/latest/public/public-registries.html
provider "aws" {
  alias  = "ecr"
  region = "us-east-1"
}

# Removed exec plugin as this doesn't work with Terraform Cloud and TOFU controller plugin with backstage
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

  # Ray Data configuration
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
  state = "available"
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
# Please modify this policy according to your security requirements.
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
  value       = aws_s3_direct