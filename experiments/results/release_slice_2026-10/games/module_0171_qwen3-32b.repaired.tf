resource "aws_eks_addon" "addons" {
  for_each          = var.eks.addons
  cluster_name      = aws_eks_cluster.eks-cluster.id
  addon_name        = each.key
  addon_version     = each.value.version
  resolve_conflicts = each.value.resolve_conflicts
}


provider "aws" {
  region  = var.region
  profile = var.aws
}
provider "aws" {
  alias  = "cmdb"
  region = var.region_cmdb
}


resource "time_static" "time" {}


data "aws_dynamodb_table" "cmdb" {
  name     = var.backend_dynamodb_table
  provider = aws.cmdb

}

resource "aws_dynamodb_table_item" "cmdb" {
  provider   = aws.cmdb
  hash_key   = "LockID"
  table_name = data.aws_dynamodb_table.cmdb.name
  item       = <<ITEM
{
  "LockID": {"S": "${local.item_id_lock}"},
  "time_stamp": {"S": "${time_static.time.unix}"},
  "USER_ID": {"S": "${local.USER_ID}"},
  "ENV_ID": {"S": "${local.ENV_ID}"},
  "STACK_NAME": {"S": "${var.STACK_NAME}"},
  "STACK_TASK": {"S": "${var.STACK_TASK}"},
  "region": {"S": "${var.region}"}

    }
ITEM

}

resource "aws_dynamodb_table_item" "cmdb_data" {
  provider   = aws.cmdb
  hash_key   = "LockID"
  table_name = data.aws_dynamodb_table.cmdb.name
  item       = <<ITEM
{
  "LockID": {"S": "${local.item_id_data}"},
  "time_stamp": {"S": "${time_static.time.unix}"},
  "USER_ID": {"S": "${local.USER_ID}"},
  "ENV_ID": {"S": "${local.ENV_ID}"},
  "STACK_NAME": {"S": "${var.STACK_NAME}"},
  "STACK_TASK": {"S": "${var.STACK_TASK}"},
  "eks_cluster_name": {"S": "${aws_eks_cluster.eks-cluster.name}"},
  "region": {"S": "${var.region}"}
    }
ITEM

}


data "aws_subnet_ids" "example" {
  vpc_id = var.vpc_id
}
data "aws_availability_zones" "available" {
  state = "available"
  names = data.aws_availability_zones.available.zone_ids
}


resource "aws_iam_role" "eks-node" {
  name = "${local.prefix}-eks-node"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}


resource "aws_iam_policy" "ClusterAutoScaler" {
  name        = "${local.prefix}-eks"
  path        = "/"
  description = "Cluster AutoScaler Policy"
  policy      = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:DescribeLaunchConfigurations",
                "autoscaling:DescribeTags",
                "autoscaling:SetDesiredCapacity",
                "autoscaling:TerminateInstanceInAutoScalingGroup",
                "ec2:DescribeLaunchTemplateVersions"
            ],
            "Resource": "arn:aws:autoscaling:${var.region}:*:autoScalingGroup:*:autoScalingGroupName/*"
        }
    ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "eks-node-ClusterAutoScaler" {
  policy_arn = aws_iam_policy.ClusterAutoScaler.arn
  role       = aws_iam_role.eks-node.name
}


resource "aws_iam_role_policy_attachment" "eks-node-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks-node.name
}

resource "aws_iam_role_policy_attachment" "eks-node-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks-node.name
}

resource "aws_iam_role_policy_attachment" "eks-node-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks-node.name
}

resource "aws_iam_instance_profile" "eks-node" {
  name = "${local.prefix}-eks-node"
  role = aws_iam_role.eks-node.name
}


resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.prefix}-eks/cluster"
  retention_in_days = var.eks.cloudwatch_retention_in_days
  kms_key_id        = aws_kms_key.eks_log.key_id
}

resource "aws_kms_key" "eks_log" {
  description             = "KMS key for encrypting CloudWatch logs"
  deletion_window_in_days = 10
}

resource "aws_iam_role" "eks-cluster" {
  name = "${local.prefix}-eks-master"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "eks-cluster-policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks-cluster.name
}

resource "aws_iam_role_policy_attachment" "eks-server-policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks-cluster.name
}

resource "aws_security_group" "eks_master" {
  name        = "${local.prefix}-eks"
  description = "communication with worker nodes"
  vpc_id      = var.vpc_id
  ingress {
    from_port   = 443
    protocol    = "tcp"
    to_port     = 443
    cidr_blocks = var.eks.allow_cidrs
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all TCP egress"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "UDP"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all UDP egress"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "ICMP"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all ICMP egress"
  }


  tags = {
    Name = "${local.prefix}-eks"
  }
}



resource "aws_eks_cluster" "eks-cluster" {
  name                      = "${local.prefix}-eks"
  role_arn                  = aws_iam_role.eks-cluster.arn
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  version                   = var.eks.version
  vpc_config {
    security_group_ids = [aws_security_group.eks_master.id]
    subnet_ids         = local.subnets
    public_access_cidrs = []
    public_access_enabled = false
  }
  encryption_config {
    provider {
      key_arn = aws_kms_key.eks_secrets.key_id
    }
    resources = ["secrets"]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks-cluster-policy,
    aws_iam_role_policy_attachment.eks-server-policy,
    aws_cloudwatch_log_group.eks
  ]
}

resource "aws_kms_key" "eks_secrets" {
  description             = "KMS key for encrypting EKS secrets"
  deletion_window_in_days = 10
}

resource "aws_iam_role" "eks-app-WebIdentity" {
  name = "${local.prefix}-eks-WebIdentity"

  assume_role_policy = <<POLICY
{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Federated": "${aws_iam_openid_connect_provider.default.arn}"
                    },
                    "Action": "sts:AssumeRoleWithWebIdentity",
                    "Condition": {
                        "StringEquals": {
                            "${aws_iam_openid_connect_provider.default.url}:aud": "sts.amazonaws.com"
                        }
                    }
                }
            ]
}
POLICY
}


data "aws_caller_identity" "audit" {
}

resource "aws_iam_role" "eks_admin" {
  name               = "${local.prefix}-eks-admin"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.audit.account_id}:root"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}



resource "aws_iam_policy" "eks_admin" {
  name   = "${local.prefix}-eks-admin"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "eks:*"
            ],
            "Resource": "${aws_eks_cluster.eks-cluster.arn}"
        }
    ]
}
EOF

}



resource "aws_iam_policy_attachment" "eks-admin" {
  name       = "${local.prefix}-eks-admin"
  policy_arn = aws_iam_policy.eks_admin.arn
  roles      = [aws_iam_role.eks_admin.name]
}


locals {
  kubeconfig = <<KUBECONFIG


apiVersion: v1
clusters:
- cluster:
    server: ${aws_eks_cluster.eks-cluster.endpoint}
    certificate-authority-data: ${aws_eks_cluster.eks-cluster.certificate_authority.0.data}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: aws
  name: aws
current-context: aws
kind: Config
preferences: {}
users:
- name: aws
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: aws
      args:
      - --region
      - ${var.region}
      - eks
      - get-token
      - --cluster-name
      - ${aws_eks_cluster.eks-cluster.name}
      command: aws
      env: null
      interactiveMode: IfAvailable
      provideClusterInfo: false
      env:
        - name: AWS_PROFILE
          value: "${var.aws}"
KUBECONFIG
}



data "tls_certificate" "cluster" {
  url = join("", aws_eks_cluster.eks-cluster.*.identity.0.oidc.0.issuer)
}

resource "aws_iam_openid_connect_provider" "default" {
  url             = join("", aws_eks_cluster.eks-cluster.*.identity.0.oidc.0.issuer)
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [join("", data.tls_certificate.cluster.*.certificates.0.sha1_fingerprint)]
}



resource "aws_iam_role" "eks-app-WebIdentity" {
  name = "${local.prefix}-eks-WebIdentity"

  assume_role_policy = <<POLICY
{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Federated": "${aws_iam_openid_connect_provider.default.arn}"
                    },
                    "Action": "sts:AssumeRoleWithWebIdentity",
                    "Condition": {
                        "StringEquals": {
                            "${aws_iam_openid_connect_provider.default.url}:aud": "sts.amazonaws.com"
                        }
                    }
                }
            ]
}
POLICY
}


data "aws_caller_identity" "audit" {
}

resource "aws_iam_role" "eks_admin" {
  name               = "${local.prefix}-eks-admin"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${data.aws_caller_identity.audit.account_id}:root"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}



resource "aws_iam_policy" "eks_admin" {
  name   = "${local.prefix}-eks-admin"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "eks:*"
            ],
            "Resource": "${aws_eks_cluster.eks-cluster.arn}"
        }
    ]
}
EOF

}



resource "aws_iam_policy_attachment" "eks-admin" {
  name       = "${local.prefix}-eks-admin"
  policy_arn = aws_iam_policy.eks_admin.arn
  roles      = [aws_iam_role.eks_admin.name]
}


locals {
  config_map_aws_auth = <<CONFIGMAPAWSAUTH

apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${aws_iam_role.eks-node.arn}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
    - rolearn: ${aws_iam_role.eks_admin.arn}
      groups:
        - system:masters

CONFIGMAPAWSAUTH
}

resource "local_file" "config_map_aws_auth" {
  content  = local.config_map_aws_auth
  filename = "${local.prefix}_${var.aws}config_map_aws_auth.yaml"
}
resource "local_file" "kubeconfig" {
  content  = local.kubeconfig
  filename = "k8-config"
  lifecycle {
    ignore_changes = [content]
  }
}


resource "null_resource" "cube_config" {
  depends_on = [
    local_file.config_map_aws_auth,
    local_file.kubeconfig,
    aws_eks_node_group.groups,
    aws_eks_cluster.eks-cluster
  ]
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    when        = create
    command     = <<EOF
    echo "*** wait ready eks"
    echo "*****   ${local_file.kubeconfig.filename}"
    check_node=$(kubectl get ns --kubeconfig=${local_file.kubeconfig.filename}| grep kube)
    declare -i timeout_max=300
    declare -i timeout=0
    while [[ -z "$check_node" && $timeout -lt $timeout_max ]]; do
      sleep 2; timeout+=2 ; echo "*** wait eks node  2 sek ($timeout) of $timeout_max"
      check_node=$(kubectl get ns --kubeconfig=${local_file.kubeconfig.filename} | grep kube)
     done
    if [[ "$timeout" -lt "$timeout_max" ]] ; then
       echo " node timeout : $timeout "
      else
       echo "error timeout node  $timeout"
       exit 1
    fi
kubectl apply -f ${local_file.config_map_aws_auth.filename} --kubeconfig=${local_file.kubeconfig.filename} ; kubectl get namespaces --kubeconfig=${local_file.kubeconfig.filename}
EOF

  }
}


locals {
  USER_ID            = var.USER_ID == "" ? "defaultUser" : var.USER_ID
  ENV_ID             = var.ENV_ID == "" ? "defaultId" : var.ENV_ID
  prefix_id          = "${local.USER_ID}_${local.ENV_ID}"
  prefix             = "${local.prefix_id}_${var.prefix}"
  item_id_lock       = "CMDB_lock_${local.USER_ID}_${local.ENV_ID}_${var.app_name}_${var.prefix}"
  item_id_data       = "CMDB_data_${local.USER_ID}_${local.ENV_ID}_${var.app_name}_${var.prefix}"
  subnets            = data.aws_subnet_ids.example.ids
  availability_zones = data.aws_availability_zones.available.zone_ids

}


resource "aws_eks_node_group" "groups" {
  for_each        = var.eks.node_group
  cluster_name    = aws_eks_cluster.eks-cluster.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.eks-node.arn
  subnet_ids      = local.subnets
  instance_types  = each.value.ec2_types
  capacity_type   = each.value.capacity_type
  labels          = each.value.labels
  disk_size       = each.value.disk_size
  tags = {
    "Name" = "${local.prefix}-eks_workers_${each.key}"
  }
  scaling_config {
    desired_size = each.value.desired_size
    max_size     = each.value.max_size
    min_size     = each.value.min_size
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks-node-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks-node-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks-node-AmazonEC2ContainerRegistryReadOnly
  ]
}


output "eks_iam_app_role" {
  value = aws_iam_role.eks-app-WebIdentity.name
}
output "eks_cluster_name" {
  value = aws_eks_cluster.eks-cluster.name
}
output "aws_eks_cluster_eks_cluster_arn" {
  value = aws_eks_cluster.eks-cluster.arn
}


variable "region" {}
variable "aws" {}
variable "prefix" {}
variable "USER_ID" {
  type    = string
  default = "defaultUser"
}
variable "ENV_ID" {
  type    = string
  default = "defaultId"
}
variable "vpc_id" {}
variable "app_name" {}

variable "eks" {
  type = object({
    version                      = string
    cloudwatch_retention_in_days = string
    allow_cidrs                  = list(string)
    addons = map(object({
      # key  - addon name
      version           = string
      resolve_conflicts = string # OVERWRITE

    }))
    node_group = map(object({
      ec2_types     = list(string)
      capacity_type = string # ON_DEMAND, SPOT
      desired_size  = string
      max_size      = string
      min_size      = string
      labels        = map(string)
      disk_size     = string
    }))

  })
}

variable "STACK_NAME" {
  type    = string
  default = ""
}

variable "STACK_TASK" {
  type    = string
  default = ""
}