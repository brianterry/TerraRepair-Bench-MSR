```hcl
data "aws_secretsmanager_secret" "infra" {
  name = "/${local.name_wo_region}/infra/layer2-k8s"
}

data "aws_secretsmanager_secret_version" "infra" {
  secret_id = data.aws_secretsmanager_secret.infra.id
}

locals {
  aws_load_balancer_controller = {
    name          = local.helm_releases[index(local.helm_releases.*.id, "aws-load-balancer-controller")].id
    enabled       = local.helm_releases[index(local.helm_releases.*.id, "aws-load-balancer-controller")].enabled
    chart         = local.helm_releases[index(local.helm_releases.*.id, "aws-load-balancer-controller")].chart
    repository    = local.helm_releases[index(local.helm_releases.*.id, "aws-load-balancer-controller")].repository
    chart_version = local.helm_releases[index(local.helm_releases.*.id, "aws-load-balancer-controller")].chart_version
    namespace     = local.helm_releases[index(local.helm_releases.*.id, "aws-load-balancer-controller")].namespace
  }
  aws_load_balancer_controller_webhook_service_name = "${local.aws_load_balancer_controller.name}-webhook-service"

  aws_load_balancer_controller_values = <<VALUES
nameOverride: ${local.aws_load_balancer_controller.name}
clusterName: ${local.eks_cluster_id}
region: ${local.region}
vpcId: ${local.vpc_id}

serviceAccount:
  create: true
  annotations:
     "eks.amazonaws.com/role-arn": ${local.aws_load_balancer_controller.enabled? module.aws_iam_aws_loadbalancer_controller[0].role_arn : ""}
VALUES
}

module "aws_load_balancer_controller_namespace" {
  count = local.aws_load_balancer_controller.enabled? 1 : 0

  source = "../modules/eks-kubernetes-namespace"
  name   = local.aws_load_balancer_controller.namespace
  network_policies = [
    {
      name         = "default-deny"
      policy_types = ["Ingress", "Egress"]
      pod_selector = {}
    },
    {
      name         = "allow-this-namespace"
      policy_types = ["Ingress"]
      pod_selector = {}
      ingress = {
        from = [
          {
            namespace_selector = {
              match_labels = {
                name = local.aws_load_balancer_controller.namespace
              }
            }
          }
        ]
      }
    },
    {
      name         = "allow-control-plane"
      policy_types = ["Ingress"]
      pod_selector = {
        match_expressions = {
          key      = "app.kubernetes.io/name"
          operator = "In"
          values   = [local.aws_load_balancer_controller.name]
        }
      }
      ingress = {
        ports = [
          {
            port     = "9443"
            protocol = "TCP"
          }
        ]
        from = [
          {
            ip_block = {
              cidr = "0.0.0.0/0"
            }
          }
        ]
      }
    },
    {
      name         = "allow-egress"
      policy_types = ["Egress"]
      pod_selector = {}
      egress = {
        to = [
          {
            ip_block = {
              cidr = "0.0.0.0/0"
              except = [
                "169.254.169.254/32"
              ]
            }
          }
        ]
      }
    }
  ]
}

module "aws_iam_aws_loadbalancer_controller" {
  count = local.aws_load_balancer_controller.enabled? 1 : 0

  source            = "../modules/aws-iam-eks-trusted"
  name              = "${local.name}-aws-lb-controller"
  region            = local.region
  oidc_provider_arn = local.eks_oidc_provider_arn
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "iam:CreateServiceLinkedRole"
        ],
        "Resource" : "*",
        "Condition" : {
          "StringEquals" : {
            "iam:AWSServiceName" : "elasticloadbalancing.amazonaws.com"
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:GetCoipPoolUsage",
          "ec2:DescribeCoipPools",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "iam:ListServerCertificates",
          "iam:GetServerCertificate",
          "waf-regional:GetWebACL",
          "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "shield:GetSubscriptionState",
          "shield:DescribeProtection",
          "shield:CreateProtection",
          "shield:DeleteProtection"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateSecurityGroup"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateTags"
        ],
        "Resource" : "arn:aws:ec2:*:*:security-group/*",
        "Condition" : {
          "StringEquals" : {
            "ec2:CreateAction" : "CreateSecurityGroup"
          },
          "Null" : {
            "aws:RequestTag/elbv2.k8s.aws/cluster" : "false"
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ],
        "Resource" : "arn:aws:ec2:*:*:security-group/*",
        "Condition" : {
          "Null" : {
            "aws:RequestTag/elbv2.k8s.aws/cluster" : "true",
            "aws:ResourceTag/elbv2.k8s.aws/cluster" : "false"
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DeleteSecurityGroup"
        ],
        "Resource" : "*",
        "Condition" : {
          "Null" : {
            "aws:ResourceTag/elbv2.k8s.aws/cluster" : "false"
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup"
        ],
        "Resource" : "*",
        "Condition" : {
          "Null" : {
            "aws:RequestTag/elbv2.k8s.aws/cluster" : "false"
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ],
        "Resource" : [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
        ],
        "Condition" : {
          "Null" : {
            "aws:RequestTag/elbv2.k8s.aws/cluster" : "true",
            "aws:ResourceTag/elbv2.k8s.aws/cluster" : "false"
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ],
        "Resource" : [
          "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteTargetGroup"
        ],
        "Resource" : "*",
        "Condition" : {
          "Null" : {
            "aws:ResourceTag/elbv2.k8s.aws/cluster" : "false"
          }
        }
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets"
        ],
        "Resource" : "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "elasticloadbalancing:SetWebAcl",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:AddListenerCertificates",
          "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:ModifyRule"
        ],
        "Resource" : "*"
      }
    ]
  })
}

resource "tls_private_key" "aws_loadbalancer_controller_webhook_ca" {
  count = local.aws_load_balancer_controller.enabled? 1 : 0

  algorithm = "RSA"
}

resource "tls_self_signed_cert" "aws_loadbalancer_controller_webhook_ca" {
  count = local.aws_load_balancer_controller.enabled? 1 : 0

  private_key_pem       = tls_private_key.aws_loadbalancer_controller_webhook_ca[count.index].private_key_pem
  validity_period_hours = 87600 # 10 years
  early_renewal_hours   = 8760  # 1 year
  is_ca_certificate     = true
  allowed_uses = [
    "cert_signing",
    "key_encipherment",
    "digital_signature"
  ]
  subject {
    common_name  = local.aws_load_balancer_controller_webhook_service_name
    organization = local.name
  }
}

resource "tls_private_key" "aws_loadbalancer_controller_webhook" {
  count = local.aws_load_balancer_controller.enabled? 1 : 0

  algorithm = "RSA"
}

resource "tls_cert_request" "aws_loadbalancer_controller_webhook" {
  count = local.aws_load_balancer_controller.enabled? 1 : 0

  private_key_pem = tls_private_key.aws_loadbalancer_controller_webhook[count.index].private_key_pem
  dns_names       = ["${local.aws_load_balancer_controller_webhook_service_name}.${module.aws_load_balancer_controller_namespace[count.index].name}", "${local.aws_load_balancer_controller_webhook_service_name}.${module.aws_load_balancer_controller_namespace[count.index].name}.svc", "${local.aws_load_balancer_controller_webhook_service_name}.${module.aws_load_balancer_controller_namespace[count.index].name}.svc.cluster.local"]
  subject {
    common_name  = local.aws_load_balancer_controller_webhook_service_name
    organization = local.name
  }
}

resource "tls_locally_signed_cert" "aws_loadbalancer_controller_webhook" {
  count = local.aws_load_balancer_controller.enabled? 1 : 0

  cert_request_pem   = tls_cert_request.aws_loadbalancer_controller_webhook[count.index].cert_request_pem
  ca_private_key_pem = tls_private_key.aws_loadbalancer_controller_webhook_ca[count.index].private_key_pem
  ca_cert_pem        = tls_self_signed_cert.aws_loadbalancer_controller_webhook_ca[count.index].cert_pem

  validity_period_hours = 87600 # 10 years
  early_renewal_hours   = 8760  # 1 year
  allowed_uses = [
    "key_encipherment",
    "digital_signature"
  ]
}

resource "helm_release" "aws_loadbalancer_controller" {
  count = local.aws_load_balancer_controller.enabled? 1 : 0

  name        = local.aws_load_balancer_controller.name
  chart       = local.aws_load_balancer_controller.chart
  repository  = local.aws_load_balancer_controller.repository
  version     = local.aws_load_balancer_controller.chart_version
  namespace   = module.aws_load_balancer_controller_namespace[count.index].name
  max_history = var.helm_release_history_size

  values = [
    local.aws_load_balancer_controller_values
  ]
  set {
    name  = "webhookTLS.caCert"
    value = tls_self_signed_cert.aws_loadbalancer_controller_webhook_ca[0].cert_pem
  }
  set {
    name  = "webhookTLS.cert"
    value = tls_locally_signed_cert.aws_loadbalancer_controller_webhook[0].cert_pem
  }
  set {
    name  = "webhookTLS.key"
    value = tls_private_key.aws_loadbalancer_controller_webhook[0].private_key_pem
  }
}

resource "kubernetes_ingress_v1" "default" {
  count = local.aws_load_balancer_controller.enabled && local.ingress_nginx.enabled && var.nginx_ingress_ssl_terminator == "lb"? 1 : 0

  metadata {
    name = "${local.ingress_nginx.name}-controller"
    annotations = {
      "kubernetes.io/ingress.class"                        = "alb"
      "alb.ingress.kubernetes.io/scheme"                   = "internet-facing"
      "alb.ingress.kubernetes.io/tags"                     = "Environment=${local.env},Name=${local.name},Cluster=${local.eks_cluster_id}"
      "alb.ingress.kubernetes.io/certificate-arn"          = "${local.ssl_certificate_arn}"
      "alb.ingress.kubernetes.io/ssl-policy"               = "ELBSecurityPolicy-FS-1-2-Res-2019-08"
      "alb.ingress.kubernetes.io/listen-ports"             = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
      "alb.ingress.kubernetes.io/target-type"              = "ip"
      "alb.ingress.kubernetes.io/load-balancer-attributes" = "routing.http2.enabled=true"
      "alb.ingress.kubernetes.io/ssl-redirect"             = "443"
    }
    namespace = module.ingress_nginx_namespace[count.index].name
  }
  spec {
    rule {
      http {
        path {
          path = "/*"
          backend {
            service {
              name = "${local.ingress_nginx.name}-controller"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
  wait_for_load_balancer = true

  depends_on = [helm_release.aws_loadbalancer_controller, helm_release.ingress_nginx, module.aws_iam_aws_loadbalancer_controller, tls_locally_signed_cert.aws_loadbalancer_controller_webhook]
}

resource "aws_route53_record" "default_ingress" {
  count = local.aws_load_balancer_controller.enabled && local.ingress_nginx.enabled && var.nginx_ingress_ssl_terminator == "lb"? 1 : 0

  zone_id = local.zone_id
  name    = "*.${local.domain_name}"
  type    = "CNAME"
  ttl     = 360

  records = [kubernetes_ingress_v1.default[count.index].status.0.load_balancer.0.ingress.0.hostname]

  depends_on = [
    kubernetes_ingress_v1.default
  ]
}

locals {
  cert_manager = {
    name          = local.helm_releases[index(local.helm_releases.*.id, "cert-manager")].id
    enabled       = local.helm_releases[index(local.helm_releases.*.id, "cert-manager")].enabled
    chart         = local.helm_releases[index(local.helm_releases.*.id, "cert-manager")].chart
    repository    = local.helm_releases[index(local.helm_releases.*.id, "cert-manager")].repository
    chart_version = local.helm_releases[index(local.helm_releases.*.id, "cert-manager")].chart_version
    namespace     = local.helm_releases[index(local.helm_releases.*.id, "cert-manager")].namespace
  }
  cert_mananger_certificate = {
    name          = local.helm_releases[index(local.helm_releases.*.id, "cert-mananger-certificate")].id
    enabled       = local.helm_releases[index(local.helm_releases.*.id, "cert-mananger-certificate")].enabled
    chart         = local.helm_releases[index(local.helm_releases.*.id, "cert-mananger-certificate")].chart
    repository    = local.helm_releases[index(local.helm_releases.*.id, "cert-mananger-certificate")].repository
    chart_version = local.helm_releases[index(local.helm_releases.*.id, "cert-mananger-certificate")].chart_version
    namespace     = local.helm_releases[index(local.helm_releases.*.id, "cert-mananger-certificate")].namespace
  }
  cert_manager_cluster_issuer = {
    name          = local.helm_releases[index(local.helm_releases.*.id, "cert-manager-cluster-issuer")].id
    enabled       = local.helm_releases[index(local.helm_releases.*.id, "cert-manager-cluster-issuer")].enabled
    chart         = local.helm_releases[index(local.helm_releases.*.id, "cert-manager-cluster-issuer")].chart
    repository    = local.helm_releases[index(local.helm_releases.*.id, "cert-manager-cluster-issuer")].repository
    chart_version = local.helm_releases[index(local.helm_releases.*.id, "cert-manager-cluster-issuer")].chart_version
    namespace     = local.helm_releases[index(local.helm_releases.*.id, "cert-manager-cluster-issuer")].namespace
  }
  cert_manager_values                = <<VALUES
installCRDs: true
serviceAccount:
  annotations:
    "eks.amazonaws.com/role-arn": ${local.cert_manager.enabled? module.aws_iam_cert_manager[0].role_arn : ""}
securityContext:
  fsGroup: 1001

cainjector:
  enabled: true
  replicaCount: 1
  extraArgs:
    - --leader-elect=false
VALUES
  cert_manager_cluster_issuer_values = <<VALUES
dnsZone: ${local.domain_name}
dnsZoneId: ${local.zone_id}
region: ${local.region}
email: webmaster@${local.domain_name}
VALUES
  cert_mananger_certificate_values   = <<VALUES
domainName: "*.${local.domain_name}"
commonName: "${local.domain_name}"
VALUES
}

module "certmanager_namespace" {
  count = local.cert_manager.enabled? 1 : 0

  source = "../modules/eks-kubernetes-namespace"
  name   = local.cert_manager.namespace
  network_policies = [
    {
      name         = "default-deny"
      policy_types = ["Ingress", "Egress"]
      pod_selector = {}
    },
    {
      name         = "allow-this-namespace"
      policy_types = ["Ingress"]
      pod_selector = {}
      ingress = {
        from = [
          {
            namespace_selector = {
              match_labels = {
                name = local.cert_manager.namespace
              }
            }
          }
        ]
      }
    },
    {
      name         = "allow-control-plane"
      policy_types = ["Ingress"]
      pod_selector = {
        match_expressions = {
          key      = "app.kubernetes.io/name"
          operator = "In"
          values   = ["webhook"]
        }
      }
      ingress = {
        ports = [
          {
            port     = "10250"
            protocol = "TCP"
          }
        ]
        from = [
          {
            ip_block = {
              cidr = "0.0.0.0/0"
            }
          }
        ]
      }
    },
    {
      name         = "allow-egress"
      policy_types = ["Egress"]
      pod_selector = {}
      egress = {
        to = [
          {
            ip_block = {
              cidr = "0.0.0.0/0"
              except = [
                "169.254.169.254/32"
              ]
            }
          }
        ]
      }
    }
  ]
}

module "aws_iam_cert_manager" {
  count = local.cert_manager.enabled? 1 : 0

  source            = "../modules/aws-iam-eks-trusted"
  name              = "${local.name}-${local.cert_manager.name}"
  region            = local.region
  oidc_provider_arn = local.eks_oidc_provider_arn
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : "route53:GetChange",
        "Resource" : "arn:aws:route53:::change/*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ],
        "Resource" : [
          "arn:aws:route53:::hostedzone/*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "route53:ListHostedZones"
        ],
        "Resource" : ["*"]
      },
      {
        "Effect" : "Allow",
        "Action" : "route53:ListHostedZonesByName",
        "Resource" : "*"
      }
    ]
  })
}

resource "helm_release" "cert_manager" {
  count = local.cert_manager.enabled? 1 : 0

  name        = local.cert_manager.name
  chart       = local.cert_manager.chart
  repository  = local.cert_manager.repository
  version     = local.cert_manager.chart_version
  namespace   = module.certmanager_namespace[count.index].name
  max_history = var.helm_release_history_size

  values = [
    local.cert_manager_values
  ]

}

resource "helm_release" "cluster_issuer" {
  count = local.cert_manager_cluster_issuer.enabled? 1 : 0

  name        = local.cert_manager_cluster_issuer.name
  chart       = "${var.helm_charts_path}/${local.cert_manager_cluster_issuer.chart}"
  repository  = local.cert_manager_cluster_issuer.repository
  version     = local.cert_manager_cluster_issuer.chart_version
  namespace   = local.cert_manager_cluster_issuer.namespace
  max_history = var.helm_release_history_size

  values = [
    local.cert_manager_cluster_issuer_values
  ]

  depends_on = [helm_release.cert_manager]
}

resource "helm_release" "certificate" {
  count = local.cert_mananger_certificate.enabled? 1 : 0

  name        = local.cert_mananger_certificate.name
  chart       = "${var.helm_charts_path}/${local.cert_mananger_certificate.chart}"
  repository  = local.cert_mananger_certificate.repository
  version     = local.cert_mananger_certificate.chart_version
  namespace   = local.cert_mananger_certificate.namespace
  max_history = var.helm_release_history_size

  values = [
    local.cert_mananger_certificate_values
  ]

  depends_on = [helm_release.cert_manager, helm_release.cluster_issuer]
}

locals {
  elk = {
    name          = local.helm_releases[index(local.helm_releases.*.id, "elk")].id
    enabled       = local.helm_releases[index(local.helm_releases.*.id, "elk")].enabled
    chart         = local.helm_releases[index(local.helm_releases.*.id, "elk")].chart
    repository    = local.helm_releases[index(local.helm_releases.*.id, "elk")].repository
    chart_version = local.helm_releases[index(local.helm_releases.*.id, "elk")].chart_version
    namespace     = local.helm_releases[index(local.helm_releases.*.id, "elk")].namespace
  }
  kibana_domain_name          = "kibana-${local.domain_suffix}"
  apm_domain_name             = "apm-${local.domain_suffix}"
  elasticsearch_password      = local.elk.enabled? random_string.elasticsearch_password[0].result : "test123"
  elk_snapshot_retention_days = 90
  elk_index_retention_days    = 14
  kibana_user                 = "kibana-${local.env}"
  kibana_password             = local.elk.enabled? random_string.kibana_password[0].result : "test123"
  elk_snapshots_bucket_name   = local.elk.enabled? aws_s3_bucket.elastic_stack[0].id : "bucket_name"
  elk_elasticsearch_values    = <<VALUES
elasticsearch:
  enabled: true
  image: "public.ecr.aws/o7m5y2d9/elasticsearch" # Uses this dockerfile https://github.com/maddevsio/aws-eks-base/blob/main/docker/elasticsearch/Dockerfile
  imageTag: 7.16.2
  esMajorVersion: 7
  replicas: 1
  clusterHealthCheckParams: "wait_for_status=yellow&timeout=1s"
  clusterName: "elasticsearch"

  volumeClaimTemplate:
    accessModes: [ "ReadWriteOnce" ]
    storageClassName: advanced
    resources:
      requests:
        storage: 100Gi

  resources:
    limits:
      cpu: 1000m
      memory: 2Gi
    requests:
      cpu: 512m
      memory: 2Gi

  esJavaOpts: -Xmx1500m -Xms1500m
  protocol: https
  esConfig:
    elasticsearch.yml: |
      xpack.security.enabled: true
      xpack.monitoring.collection.enabled: true
      xpack.security.transport.ssl.enabled: true
      xpack.security.transport.ssl.verification_mode: certificate
      xpack.security.transport.ssl.key: /usr/share/elasticsearch/config/certs/tls.key
      xpack.security.transport.ssl.certificate: /usr/share/elasticsearch/config/certs/tls.crt
      xpack.security.http.ssl.enabled: true
      xpack.security.http.ssl.key: /usr/share/elasticsearch/config/certs/tls.key
      xpack.security.http.ssl.certificate: /usr/share/elasticsearch/config/certs/tls.crt

  extraEnvs:
    - name: ELASTIC_PASSWORD
      valueFrom:
        secretKeyRef:
          name: elastic-credentials
          key: password
    - name: ELASTIC_USERNAME
      valueFrom:
        secretKeyRef:
          name: elastic-credentials
          key: username

  secretMounts:
    - name: elastic-certificates
      secretName: elastic-certificates
      path: /usr/share/elasticsearch/config/certs

  keystore:
    - secretName: elasticsearch-s3-user-creds
      items:
      - key: aws_s3_user_access_key
        path: s3.client.default.access_key
      - key: aws_s3_user_secret_key
        path: s3.client.default.secret_key

  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: karpenter.sh/capacity-type
          operator: In
          values:
            - on-demand
VALUES
  elk_kibana_values           = <<VALUES
kibana:
  enabled: true
  resources:
    requests:
      cpu: "512m"
      memory: "1Gi"
    limits:
      cpu: "512m"
      memory: "1Gi"

  ingress:
    enabled: true
    className: nginx
    annotations:
      nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    path: /
    hosts:
      - ${local.kibana_domain_name}

  elasticsearchHosts: "https://elasticsearch-master:9200"

  extraEnvs:
    - name: "NODE_OPTIONS"
      value: "--max-old-space-size=800"
    - name: 'ELASTICSEARCH_USERNAME'
      valueFrom:
        secretKeyRef:
          name: elastic-credentials
          key: username
    - name: 'ELASTICSEARCH_PASSWORD'
      valueFrom:
        secretKeyRef:
          name: elastic-credentials
          key: password
    - name: 'KIBANA_ENCRYPTION_KEY'
      valueFrom:
        secretKeyRef:
          name: kibana-encryption-key
          key: encryptionkey

  kibanaConfig:
    kibana.yml: |
      server.ssl:
        enabled: true
        key: /usr/share/kibana/config/certs/tls.key
        certificate: /usr/share/kibana/config/certs/tls.crt
      xpack.security.encryptionKey: $${KIBANA_ENCRYPTION_KEY}
      elasticsearch.ssl:
        verificationMode: none
        certificateAuthorities: /usr/share/kibana/config/certs/tls.crt

  protocol: https

  secretMounts:
    - name: elastic-certificates
      secretName: elastic-certificates
      path: /usr/share/kibana/config/certs

  podAnnotations:
    co.elastic.logs/module: kibana

  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: karpenter.sh/capacity-type
            operator: In
            values:
              - spot

  extraInitContainers:
    - name: es-check
      image: "appropriate/curl:latest"
      imagePullPolicy: "IfNotPresent"
      command:
        - "/bin/sh"
        - "-c"
        - |
          is_down=true
          while "$is_down"; do
            if curl -k -sSf --fail-early --connect-timeout 5 -u $ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD https://elasticsearch-master:9200;
            then
              is_down=false
            else
              sleep 5
            fi
          done
      env:
        - name: 'ELASTICSEARCH_USERNAME'
          valueFrom:
            secretKeyRef:
              name: elastic-credentials
              key: username
        - name: 'ELASTICSEARCH_PASSWORD'
          valueFrom:
            secretKeyRef:
              name: elastic-credentials
              key: password
    - name: s3-repo
      image: "appropriate/curl:latest"
      imagePullPolicy: "IfNotPresent"
      command:
        - "/bin/sh"
        - "-c"
        - "curl -k -X PUT -u $ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD https://elasticsearch-master:9200/_snapshot/s3_repository -H 'Content-Type:application/json' -d '{ \"type\": \"s3\", \"settings\": {\"bucket\": \"${local.elk_snapshots_bucket_name}\", \"server_side_encryption\": \"true\"}}'"
      env:
        - name: 'ELASTICSEARCH_USERNAME'
          valueFrom:
            secretKeyRef:
              name: elastic-credentials
              key: username
        - name: 'ELASTICSEARCH_PASSWORD'
          valueFrom:
            secretKeyRef:
              name: elastic-credentials
              key: password
    - name: roles
      command:
        - /bin/sh
        - -c
        - 'curl -X POST -k -u $ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD https://elasticsearch-master:9200/_security/role/kibana_basic_user -H ''Content-Type: application/json''
          -d ''{"applications":[{"application":"kibana-.kibana","privileges":["feature_discover.all","feature_visualize.all","feature_dashboard.all","feature_dev_tools.all","feature_advancedSettings.all"],"resources":["space:default"]}]}''
          &&
          curl -X POST -k -u $ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD https://elasticsearch-master:9200/_security/role/all_indexes_read -H ''Content-Type: application/json''
          -d ''{"indices":[{"names":["*"],"privileges":["read"],"allow_restricted_indices":false}]}'''
      image: appropriate/curl:latest
      imagePullPolicy: IfNotPresent
      env:
        - name: 'ELASTICSEARCH_USERNAME'
          valueFrom:
            secretKeyRef:
              name: elastic-credentials
              key: username
        - name: 'ELASTICSEARCH_PASSWORD'
          valueFrom:
            secretKeyRef:
              name: elastic-credentials
              key: password
    - name: kibana-user
      command:
        - /bin/sh
        - -c
        - 'curl -X POST -k -u $ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD https://elasticsearch-master:9200/_security/user/${local.kibana_user} -H ''Content-Type: application/json''
          -d ''{"password" : "${local.kibana_password}","roles" : [ "superuser"],"full_name" : "Kibana User","email" : ""}'''
      image: appropriate/curl:latest
      imagePullPolicy: IfNotPresent
      env:
        - name: 'ELASTICSEARCH_USERNAME'
          valueFrom:
            secretKeyRef:
              name: elastic-credentials
              key: username
        - name: 'ELASTICSEARCH_PASSWORD'
          valueFrom:
            secretKeyRef:
              name: elastic-credentials
              key: password
    - name: snapshots
      command:
        - /bin/sh
        - -c
        - 'curl -X PUT -k -u $ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD https://elasticsearch-master:9200/_slm/policy/daily-snapshots?pretty -H ''Content-Type: application/json''
          -d ''{"schedule": "0 30 1 * *?","name": "<daily-snap-{now/d}>","repository": "s3_repository","config": {"ignore_unavailable": false,"include_global_state": false},"retention": {"expire_after": "${local.elk_snapshot_retention_days}d","min_count": 5,"max_count": 50}}'''
      image: appropriate/curl:latest
      imagePullPolicy: IfNotPresent
      env:
        - name: 'ELASTICSEARCH_USERNAME'
          valueFrom:
            secretKeyRef:
              name: elastic-credentials
              key: username
        - name: 'ELASTICSEARCH_PASSWORD'
          valueFrom:
            secretKeyRef:
              name: elastic-credentials
              key: password
    - name: delete-old-indicies
      command:
        - /bin/sh
        - -c
        - 'curl -X PUT -k -u $ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD https://elasticsearch-master:9200/_ilm/policy/delete_old_indicies -H ''Content-Type: application/json''
          -d ''{"policy": {"phases": {"hot": {"actions": {"set_priority": {"priority": 100 }}}, "delete": { "min_age": "${local.elk_index_retention_days}d", "actions": {"delete": {} }}}}}'''
      image: appropriate/curl:latest
      imagePullPolicy: IfNotPresent
      env:
        - name: 'ELASTICSEARCH_USERNAME'
          valueFrom:
            secretKeyRef:
              name: elastic-credentials
              key: username
        - name: 'ELASTICSEARCH_PASSWORD'
          valueFrom:
            secretKeyRef:
              name: elastic-credentials
              key: password
    - name: filebeat-template
      command:
        - /bin/sh
        - -c
        - 'curl -X PUT -k -u $ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD https://elasticsearch-master:9200/_template/filebeat?pretty -H ''Content-Type: application/json''
          -d ''{"index_patterns": ["filebeat-*"], "settings": {"number_of_shards": 1,"number_of_replicas": 1,"index.lifecycle.name": "delete_old_indicies" }}'''
      image: appropriate/curl:latest
      imagePullPolicy: IfNotPresent
      env:
        - name: 'ELASTICSEARCH_USERNAME'
          valueFrom:
            secretKeyRef:
              name: elastic-credentials
              key: username
        - name: 'ELASTICSEARCH_PASSWORD'
          valueFrom:
            secretKeyRef:
              name: elastic-credentials
              key: password
    - name: apm-template
      command:
        - /bin/sh
        - -c
        - 'curl -X PUT -k -u $ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD https://elasticsearch-master:9200/_template/apm?pretty -H ''Content-Type: application/json''
          -d ''{"index_patterns": ["apm-*"], "settings": {"number_of_shards": 1,"number_of_replicas": 1,"index.lifecycle.name": "delete_old_indicies" }}'''
      image: appropriate/curl:latest
      imagePullPolicy: IfNotPresent
      env:
        - name: 'ELASTICSEARCH_USERNAME'
          valueFrom:
            secretKeyRef:
              name: elastic-credentials
              key: username
        - name: 'ELASTICSEARCH_PASSWORD'
          valueFrom:
            secretKeyRef:
              name: elastic-credentials
              key: password
    - name: metricbeat-template
      command:
        - /bin/sh
        - -c
        - 'curl -X PUT -k -u $ELASTICSEARCH_USERNAME:$ELASTIC