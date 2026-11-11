```hcl
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

resource "aws_eks_access_entry" "karpenter_nodes" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.eks_blueprints_addons.karpenter.node_iam_role_arn
  type          = "EC2_LINUX"
}

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
            while [ "$(aws ec2 describe-volumes --volume-ids $VOLUME_ID --region $REGION --query "Volumes[*].State" --output text)"!= "available" ]; do
              echo "Waiting for volume to become available"
              sleep 5
            done

            # Attach the volume to the instance
            aws ec2 attach-volume --volume-id $VOLUME_ID --instance-id $INSTANCE_ID --device /dev/xvdb --region $REGION

            # Update the state to delete the volume when the node is terminated
            aws ec2 modify-instance-attribute --instance-id $INSTANCE_ID --block-device-mappings "[{\"DeviceName\": \"/dev/xvdb\",\"Ebs\":{\"DeleteOnTermination\":true}}]" --region $REGION

            # Wait for the volume to be attached
            while [ "$(aws ec2 describe-volumes --volume-ids $VOLUME_ID --region $REGION --query "Volumes[*].Attachments[*].State" --output text)"!= "attached" ]; do
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

  enable_yunikorn = var.enable_yunikorn
  yunikorn_helm_config = {
    version = "1.6.3"
    values  = [templatefile("${path.module}/helm-values/yunikorn-values.yaml", {})]
  }

  enable_spark_history_server = var.enable_spark_history_server

  spark_history_server_helm_config = {
    version = "1.5.1"
    values = [templatefile("${path.module}/helm-values/sh " " " "aws-aws " aws "aws "aws "aws aws "aws "aws "1-1
 "awss " aws " 10-aws " aws "aws " aws aws "awssawss "aws "aws "s-awsmodule " " awss "awss " aws "awsaws "eks "awsawsaws "aws "aws "awsawssaws =awss "aws "s
 "aws "aws
 aws " aws " eks aws = "aws-aws aws aws "aws " aws "aws " "aws "s "aws " " eks "aws "-aws " "-aws "aws " "aws "aws "aws aws "aws "aws.aws "aws "seks-aws "-aws " aws "aws "aws-aws-aws
 "aws "s "aws "aws " = " "-aws "-aws "aws-aws-aws aws karkarkaraws2-aws "aws-awssaws
 "aws "aws aws
aws
 "aws "-cm-aws "aws "aws 1-aws " 1-aws "aws "aws-aws "aws "-aws "awscluster "aws eks " aws aws eks-aws "aws-aws-aws "aws-awssaws
-aws "aws " aws "-aws "aws "aws "eks-aws " eks-eks-aws "aws_aws-aws-aws-aws-aws-aws "aws-spark-module eksaws "aws "aws " aws -aws-aws " eks " " aws-aws " aws "s " -awsclusterscluster- "-cluster " aws "aws "aws-aws "cluster "aws "s
 " aws " aws "-aws "aws "-1-aws-eksaws-aws " eksaws "aws "cluster " "module "aws "aws "-kar-" "aws-aws " aws s
-aws "aws aws s " aws "aws aws "aws "aws-aws "aws "-aws-aws-aws s-aws "cluster "-aws "aws "aws "aws " aws "aws "aws "aws "aws-aws "kar-kars
karkarkar-aws "kar-aws "aws "aws "aws-kar-karaws "-aws "karkar-aws "- "-kar-aws "aws "-aws "s
 "aws " "module "eksaws "-aws "aws "-aws-kar-aws " aws "-karkar-kars ".s-eks-cluster = "-aws "s "-aws "karkarkar-aws "s
 "cluster- "-aws "-aws "aws-aws "-aws " "s "-module "aws "cluster "aws "cluster "aws " " "aws " " " "-aws "aws "-aws "aws "aws " " "cluster "cluster "cluster " " " "cluster "cluster "cluster " " " "aws "cluster-cluster-aws "- "-kar-kar-kar-kar-aws " "- "-aws = " " "-aws "aws " "aws "aws "aws " "- " = "aws "aws "aws "aws "-eks- " "-eks aws " " "aws " "eks "eks "aws "cluster "aws "eks "aws "cluster "aws " " " " " "aws " " " " " " eks "kar " " " "-spark "aws "s "spark-3-1- " "aws " " "-aws "-aws "-cluster " " " "aws "aws "aws "aws "cluster-cluster = " " "-cluster-aws "cluster "cluster "for "aws " "aws "aws "-aws " "aws "saws "s "aws " " "s "-aws "s
 "aws "aws "aws "aws " " " " "aws "s " " " " "s "-awssskar-aws " "aws " "aws "aws " " "aws "aws "aws "-aws "aws "aws "s
-aws-aws "
 " "aws-aws aws-aws-aws-aws-aws "s
 "-aws "-aws "-aws "aws "-aws-aws "-aws "s "aws "-aws-aws "-aws "-aws "aws "aws-aws-aws aws "- "-az-aws "-aws "s-aws "-aws "-aws-aws "-aws-aws-aws "s "-aws
 "
 " "s "aws-aws-aws-aws "-aws "-aws-aws-aws-aws "-aws-aws "-aws "aws-aws "s-aws "-aws-aws-aws-aws "-aws-aws-aws "-aws "aws "-aws "aws "-aws "-aws-aws "for "- "-ekss "-aws "aws "cluster "-spark "ec
0
 "s


 "kar "kar-aws " " " " "s "-0-aws-kars "s "-aws "10spark "-eks "s

karkar-kar "saws "oid

-kar-aws "namespaces
s
0seks-aws "-awss "s-aws-eks "s
 "eks "eks "oid "aws "-kar = "oid-ekss
0

-aws-0-0s
 "s
 "karkarkar-s