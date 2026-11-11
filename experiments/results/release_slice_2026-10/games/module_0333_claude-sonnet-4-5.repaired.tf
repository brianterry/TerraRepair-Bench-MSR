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
     "eks.amazonaws.com/role-arn": ${local.aws_load_balancer_controller.enabled ? module.aws_iam_aws_loadbalancer_controller[0].role_arn : ""}
VALUES
}

module "aws_load_balancer_controller_namespace" {
  count = local.aws_load_balancer_controller.enabled ? 1 : 0

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
  count = local.aws_load_balancer_controller.enabled ? 1 : 0

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
  count = local.aws_load_balancer_controller.enabled ? 1 : 0

  algorithm = "RSA"
}

resource "tls_self_signed_cert" "aws_loadbalancer_controller_webhook_ca" {
  count = local.aws_load_balancer_controller.enabled ? 1 : 0

  private_key_pem       = tls_private_key.aws_loadbalancer_controller_webhook_ca[count.index].private_key_pem
  validity_period_hours = 87600
  early_renewal_hours   = 8760
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
  count = local.aws_load_balancer_controller.enabled ? 1 : 0

  algorithm = "RSA"
}

resource "tls_cert_request" "aws_loadbalancer_controller_webhook" {
  count = local.aws_load_balancer_controller.enabled ? 1 : 0

  private_key_pem = tls_private_key.aws_loadbalancer_controller_webhook[count.index].private_key_pem
  dns_names       = ["${local.aws_load_balancer_controller_webhook_service_name}.${module.aws_load_balancer_controller_namespace[count.index].name}", "${local.aws_load_balancer_controller_webhook_service_name}.${module.aws_load_balancer_controller_namespace[count.index].name}.svc", "${local.aws_load_balancer_controller_webhook_service_name}.${module.aws_load_balancer_controller_namespace[count.index].name}.svc.cluster.local"]
  subject {
    common_name  = local.aws_load_balancer_controller_webhook_service_name
    organization = local.name
  }
}

resource "tls_locally_signed_cert" "aws_loadbalancer_controller_webhook" {
  count = local.aws_load_balancer_controller.enabled ? 1 : 0

  cert_request_pem   = tls_cert_request.aws_loadbalancer_controller_webhook[count.index].cert_request_pem
  ca_private_key_pem = tls_private_key.aws_loadbalancer_controller_webhook_ca[count.index].private_key_pem
  ca_cert_pem        = tls_self_signed_cert.aws_loadbalancer_controller_webhook_ca[count.index].cert_pem

  validity_period_hours = 87600
  early_renewal_hours   = 8760
  allowed_uses = [
    "key_encipherment",
    "digital_signature"
  ]
}

resource "helm_release" "aws_loadbalancer_controller" {
  count = local.aws_load_balancer_controller.enabled ? 1 : 0

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
  count = local.aws_load_balancer_controller.enabled && local.ingress_nginx.enabled && var.nginx_ingress_ssl_terminator == "lb" ? 1 : 0

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
  count = local.aws_load_balancer_controller.enabled && local.ingress_nginx.enabled && var.nginx_ingress_ssl_terminator == "lb" ? 1 : 0

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
    "eks.amazonaws.com/role-arn": ${local.cert_manager.enabled ? module.aws_iam_cert_manager[0].role_arn : ""}
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
  count = local.cert_manager.enabled ? 1 : 0

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
  count = local.cert_manager.enabled ? 1 : 0

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
  count = local.cert_manager.enabled ? 1 : 0

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
  count = local.cert_manager_cluster_issuer.enabled ? 1 : 0

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
  count = local.cert_mananger_certificate.enabled ? 1 : 0

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
  elasticsearch_password      = local.elk.enabled ? random_string.elasticsearch_password[0].result : "test123"
  elk_snapshot_retention_days = 90
  elk_index_retention_days    = 14
  kibana_user                 = "kibana-${local.env}"
  kibana_password             = local.elk.enabled ? random_string.kibana_password[0].result : "test123"
  elk_snapshots_bucket_name   = local.elk.enabled ? aws_s3_bucket.elastic_stack[0].id : "bucket_name"
  elk_elasticsearch_values    = <<VALUES
elasticsearch:
  enabled: true
  image: "public.ecr.aws/o7m5y2d9/elasticsearch"
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
          -d ''{"schedule": "0 30 1 * * ?","name": "<daily-snap-{now/d}>","repository": "s3_repository","config": {"ignore_unavailable": false,"include_global_state": false},"retention": {"expire_after": "${local.elk_snapshot_retention_days}d","min_count": 5,"max_count": 50}}'''
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
        - 'curl -X PUT -k -u $ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD https://elasticsearch-master:9200/_template/metricbeat?pretty -H ''Content-Type: application/json''
          -d ''{"index_patterns": ["metricbeat-*"], "settings": {"number_of_shards": 1,"number_of_replicas": 1,"index.lifecycle.name": "delete_old_indicies" }}'''
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
VALUES
  elk_filebeat_values         = <<VALUES
filebeat:
  enabled: true
  filebeatConfig:
    filebeat.yml: |
      filebeat.modules:
        - module: system
          syslog:
            enabled: true
      filebeat.autodiscover:
        providers:
          - type: kubernetes
            node: $${NODE_NAME}
            hints.enabled: true
            hints.default_config:
              type: container
              paths:
                - /var/log/containers/*$${data.kubernetes.container.id}.log

      processors:
        - drop_event:
            when:
              equals:
                kubernetes.container.name: "filebeat"

      output.elasticsearch:
        username: '$${ELASTICSEARCH_USERNAME}'
        password: '$${ELASTICSEARCH_PASSWORD}'
        protocol: https
        hosts: ["elasticsearch-master:9200"]
        ssl.verification_mode: none

  extraVolumeMounts:
    - name: elastic-certificates
      mountPath: /usr/share/filebeat/config/certs

  extraVolumes:
    - name: elastic-certificates
      secret:
        secretName: elastic-certificates

  extraEnvs:
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

  tolerations:
    - effect: NoSchedule
      operator: Exists
VALUES
  elk_apm_values              = <<VALUES
apm-server:
  enabled: false
  ingress:
    enabled: true
    annotations:
      kubernetes.io/ingress.class: nginx
    path: /
    hosts:
      - ${local.apm_domain_name}

  apmConfig:
    apm-server.yml: |
      apm-server:
        host: "0.0.0.0:8200"
      queue: {}
      output.elasticsearch:
        username: '$${ELASTICSEARCH_USERNAME}'
        password: '$${ELASTICSEARCH_PASSWORD}'
        protocol: https
        hosts: ["elasticsearch-master:9200"]
        ssl.verification_mode: none

  secretMounts:
    - name: elastic-certificates
      secretName: elastic-certificates
      path: /usr/share/apm-server/config/certs

  extraEnvs:
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

  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: karpenter.sh/capacity-type
            operator: In
            values:
              - on-demand
VALUES
  elk_metricbeat_values       = <<VALUES
metricbeat:
  enabled: false
  daemonset:
    extraEnvs:
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
    metricbeatConfig:
      metricbeat.yml: |
        metricbeat.autodiscover:
          providers:
            - type: kubernetes
              hints.enabled: true

        metricbeat.modules:
        - module: kubernetes
          metricsets:
            - container
            - node
            - pod
            - system
            - volume
          period: 10s
          host: "$${NODE_NAME}"
          hosts: ["https://$${NODE_NAME}:10250"]
          bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
          ssl.verification_mode: "none"
          processors:
          - add_kubernetes_metadata: ~
        - module: kubernetes
          enabled: true
          metricsets:
            - event
        - module: system
          period: 10s
          metricsets:
            - cpu
            - load
            - memory
            - network
            - process
            - process_summary
          processes: ['.*']
          process.include_top_n:
            by_cpu: 5
            by_memory: 5
        - module: system
          period: 1m
          metricsets:
            - filesystem
            - fsstat
          processors:
          - drop_event.when.regexp:
              system.filesystem.mount_point: '^/(sys|cgroup|proc|dev|etc|host|lib)($|/)'
        output.elasticsearch:
          username: '$${ELASTICSEARCH_USERNAME}'
          password: '$${ELASTICSEARCH_PASSWORD}'
          protocol: https
          hosts: ["elasticsearch-master:9200"]
          ssl.verification_mode: none

    secretMounts:
    - name: elastic-certificates
      secretName: elastic-certificates
      path: /usr/share/metricbeat/config/certs

  deployment:
    extraEnvs:
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
    metricbeatConfig:
      metricbeat.yml: |
        metricbeat.modules:
        - module: kubernetes
          enabled: true
          metricsets:
            - state_node
            - state_deployment
            - state_replicaset
            - state_pod
            - state_container
          period: 10s
          hosts: ["$${KUBE_STATE_METRICS_HOSTS}"]
        - module: prometheus
          metricsets: ["collector"]
          metrics_path: /metrics
          period: 10s
          hosts: ["nginx-ingress-controller-metrics.ing:9913"]
          namespace: ing
        output.elasticsearch:
          username: '$${ELASTICSEARCH_USERNAME}'
          password: '$${ELASTICSEARCH_PASSWORD}'
          protocol: https
          hosts: ["elasticsearch-master:9200"]
          ssl.verification_mode: none

    secretMounts:
    - name: elastic-certificates
      secretName: elastic-certificates
      path: /usr/share/metricbeat/config/certs
VALUES
}

module "elk_namespace" {
  count = local.elk.enabled ? 1 : 0

  source = "../modules/eks-kubernetes-namespace"
  name   = local.elk.namespace
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
                name = local.elk.namespace
              }
            }
          }
        ]
      }
    },
    {
      name         = "allow-ingress"
      policy_types = ["Ingress"]
      pod_selector = {}
      ingress = {

        from = [
          {
            namespace_selector = {
              match_labels = {
                name = local.ingress_nginx.namespace
              }
            }
          }
        ]
      }
    },
    {
      name         = "allow-apm"
      policy_types = ["Ingress"]
      pod_selector = {
        match_expressions = {
          key      = "app"
          operator = "In"
          values   = ["apm-server"]
        }
      }
      ingress = {
        ports = [
          {
            port     = "8200"
            protocol = "TCP"
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

module "elastic_tls" {
  count = local.elk.enabled ? 1 : 0

  source                = "../modules/self-signed-certificate"
  name                  = local.name
  common_name           = "elasticsearch-master"
  dns_names             = [local.domain_name, "*.${local.domain_name}", "elasticsearch-master", "elasticsearch-master.${module.elk_namespace[count.index].name}", "kibana", "kibana.${module.elk_namespace[count.index].name}", "kibana-kibana", "kibana-kibana.${module.elk_namespace[count.index].name}", "logstash", "logstash.${module.elk_namespace[count.index].name}"]
  validity_period_hours = 8760
  early_renewal_hours   = 336
}

resource "aws_kms_key" "elastic_stack" {
  count = local.elk.enabled ? 1 : 0

  description             = "KMS key for elastic stack S3 bucket encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_kms_alias" "elastic_stack" {
  count = local.elk.enabled ? 1 : 0

  name          = "alias/${local.name}-elastic-stack"
  target_key_id = aws_kms_key.elastic_stack[0].key_id
}

module "aws_iam_elastic_stack" {
  count = local.elk.enabled ? 1 : 0

  source = "../modules/aws-iam-user-with-policy"
  name   = "${local.name}-${local.elk.name}"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:ListBucketMultipartUploads",
          "s3:ListBucketVersions"
        ],
        "Resource" : [
          "arn:aws:s3:::${aws_s3_bucket.elastic_stack[count.index].id}"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ],
        "Resource" : [
          "arn:aws:s3:::${aws_s3_bucket.elastic_stack[count.index].id}/*"
        ]
      }
    ]
  })
}

resource "kubernetes_secret" "elasticsearch_credentials" {
  count = local.elk.enabled ? 1 : 0

  metadata {
    name      = "elastic-credentials"
    namespace = module.elk_namespace[count.index].name
  }

  data = {
    "username" = "elastic"
    "password" = random_string.elasticsearch_password[count.index].result
  }
}

resource "kubernetes_secret" "elasticsearch_certificates" {
  count = local.elk.enabled ? 1 : 0

  metadata {
    name      = "elastic-certificates"
    namespace = module.elk_namespace[count.index].name
  }

  data = {
    "tls.crt" = module.elastic_tls[count.index].cert_pem
    "tls.key" = module.elastic_tls[count.index].private_key_pem
    "tls.p8"  = module.elastic_tls[count.index].p8
  }
}

resource "kubernetes_secret" "elasticsearch_s3_user_creds" {
  count = local.elk.enabled ? 1 : 0

  metadata {
    name      = "elasticsearch-s3-user-creds"
    namespace = module.elk_namespace[count.index].name
  }

  data = {
    "aws_s3_user_access_key" = module.aws_iam_elastic_stack[count.index].access_key_id
    "aws_s3_user_secret_key" = module.aws_iam_elastic_stack[count.index].access_secret_key
  }
}

resource "random_string" "elasticsearch_password" {
  count = local.elk.enabled ? 1 : 0

  length  = 32
  special = false
  upper   = true
}

resource "kubernetes_secret" "kibana_enc_key" {
  count = local.elk.enabled ? 1 : 0

  metadata {
    name      = "kibana-encryption-key"
    namespace = module.elk_namespace[count.index].name
  }

  data = {
    "encryptionkey" = random_string.kibana_enc_key[count.index].result
  }
}

resource "random_string" "kibana_enc_key" {
  count = local.elk.enabled ? 1 : 0

  length  = 32
  special = false
  upper   = true
}

resource "random_string" "kibana_password" {
  count = local.elk.enabled ? 1 : 0

  length  = 32
  special = false
  upper   = true
}

resource "aws_s3_bucket" "elastic_stack" {
  count = local.elk.enabled ? 1 : 0

  bucket        = "${local.name}-elastic-stack"
  force_destroy = true
  tags = {
    Name        = "${local.name}-elastic-stack"
    Environment = local.env
  }
}

resource "aws_s3_bucket_acl" "elastic_stack_acl" {
  count = local.elk.enabled ? 1 : 0

  bucket = aws_s3_bucket.elastic_stack[0].id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "elastic_stack_versioning" {
  count = local.elk.enabled ? 1 : 0

  bucket = aws_s3_bucket.elastic_stack[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "elastic_stack_logging" {
  count = local.elk.enabled ? 1 : 0

  bucket        = aws_s3_bucket.elastic_stack[0].id
  target_bucket = aws_s3_bucket.elastic_stack[0].id
  target_prefix = "log/"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "elastic_stack_encryption" {
  count = local.elk.enabled ? 1 : 0

  bucket = aws_s3_bucket.elastic_stack[0].bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.elastic_stack[0].arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "elastic_stack_lifecycle" {
  count = local.elk.enabled ? 1 : 0

  bucket = aws_s3_bucket.elastic_stack[0].id

  rule {
    id     = "elastic-stack-lifecycle-rule"
    status = "Enabled"

    expiration {
      days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_replication_configuration" "elastic_stack_replication" {
  count = local.elk.enabled ? 1 : 0

  role   = aws_iam_role.elastic_stack_replication[0].arn
  bucket = aws_s3_bucket.elastic_stack[0].id

  rule {
    id     = "elastic-stack-replication-rule"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.elastic_stack_replica[0].arn
      storage_class = "STANDARD"
    }
  }

  depends_on = [aws_s3_bucket_versioning.elastic_stack_versioning]
}

resource "aws_s3_bucket" "elastic_stack_replica" {
  count = local.elk.enabled ? 1 : 0

  bucket   = "${local.name}-elastic-stack-replica"
  provider = aws
  tags = {
    Name        = "${local.name}-elastic-stack-replica"
    Environment = local.env
  }
}

resource "aws_s3_bucket_versioning" "elastic_stack_replica_versioning" {
  count = local.elk.enabled ? 1 : 0

  bucket = aws_s3_bucket.elastic_stack_replica[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "elastic_stack_replication" {
  count = local.elk.enabled ? 1 : 0

  name = "${local.name}-elastic-stack-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "elastic_stack_replication" {
  count = local.elk.enabled ? 1 : 0

  role = aws_iam_role.elastic_stack_replication[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.elastic_stack[0].arn
        ]
      },
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.elastic_stack[0].arn}/*"
        ]
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.elastic_stack_replica[0].arn}/*"
        ]
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "elastic_stack_notification" {
  count = local.elk.enabled ? 1 : 0

  bucket = aws_s3_bucket.elastic_stack[0].id
}

resource "aws_s3_bucket_public_access_block" "elastic_stack_public_access_block" {
  count = local.elk.enabled ? 1 : 0

  bucket                  = aws_s3_bucket.elastic_stack[count.index].id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "helm_release" "elk" {
  count = local.elk.enabled ? 1 : 0

  name        = local.elk.name
  chart       = "${var.helm_charts_path}/${local.elk.chart}"
  repository  = local.elk.repository
  version     = local.elk.chart_version
  namespace   = module.elk_namespace[count.index].name
  timeout     = "900"
  max_history = var.helm_release_history_size

  values = [
    local.elk_elasticsearch_values,
    local.elk_kibana_values,
    local.elk_filebeat_values,
    local.elk_apm_values,
    local.elk_metricbeat_values
  ]

}

output "kibana_domain_name" {
  value       = local.elk.enabled ? local.kibana_domain_name : null
  description = "Kibana dashboards address"
}

output "apm_domain_name" {
  value       = local.elk.enabled ? local.apm_domain_name : null
  description = "APM domain name"
}

output "elasticsearch_elastic_password" {
  value       = local.elk.enabled ? local.elasticsearch_password : null
  sensitive   = true
  description = "Password of the superuser 'elastic'"
}

output "elastic_stack_bucket_name" {
  value       = local.elk.enabled ? local.elk_snapshots_bucket_name : null
  description = "Name of the bucket for ELKS snapshots"
}


locals {
  external_dns = {
    name          = local.helm_releases[index(local.helm_releases.*.id, "external-dns")].id
    enabled       = local.helm_releases[index(local.helm_releases.*.id, "external-dns")].enabled
    chart         = local.helm_releases[index(local.helm_releases.*.id, "external-dns")].chart
    repository    = local.helm_releases[index(local.helm_releases.*.id, "external-dns")].repository
    chart_version = local.helm_releases[index(local.helm_releases.*.id, "external-dns")].chart_version
    namespace     = local.helm_releases[index(local.helm_releases.*.id, "external-dns")].namespace
  }
  external_dns_values = <<VALUES
rbac:
  create: true

serviceAccount:
  create: true
  name: "external-dns"
  annotations:
    "eks.amazonaws.com/role-arn": ${local.external_dns.enabled ? module.aws_iam_external_dns[0].role_arn : ""}

provider: aws
domainFilters: [${local.domain_name}]
extraArgs:
  - --aws-zone-type=public
  - --aws-batch-change-size=1000

serviceMonitor:
  enabled: false

sources:
  - service
  - ingress
VALUES
}

module "external_dns_namespace" {
  count = local.external_dns.enabled ? 1 : 0

  source = "../modules/eks-kubernetes-namespace"
  name   = local.external_dns.namespace
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
                name = local.external_dns.namespace
              }
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

module "aws_iam_external_dns" {
  count = local.external_dns.enabled ? 1 : 0

  source            = "../modules/aws-iam-eks-trusted"
  name              = "${local.name}-${local.external_dns.name}"
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

resource "helm_release" "external_dns" {
  count = local.external_dns.enabled ? 1 : 0

  name        = local.external_dns.name
  chart       = local.external_dns.chart
  repository  = local.external_dns.repository
  version     = local.external_dns.chart_version
  namespace   = module.external_dns_namespace[count.index].name
  max_history = var.helm_release_history_size

  values = [
    local.external_dns_values
  ]

}


locals {
  external_secrets = {
    name          = local.helm_releases[index(local.helm_releases.*.id, "external-secrets")].id
    enabled       = local.helm_releases[index(local.helm_releases.*.id, "external-secrets")].enabled
    chart         = local.helm_releases[index(local.helm_releases.*.id, "external-secrets")].chart
    repository    = local.helm_releases[index(local.helm_releases.*.id, "external-secrets")].repository
    chart_version = local.helm_releases[index(local.helm_releases.*.id, "external-secrets")].chart_version
    namespace     = local.helm_releases[index(local.helm_releases.*.id, "external-secrets")].namespace
  }
  external_secrets_values = <<VALUES
crds:
  createClusterExternalSecret: false
  createClusterSecretStore: true

processClusterExternalSecret: false
processClusterStore: false

securityContext:
  capabilities:
    drop:
    - ALL
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 1000

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 128Mi

webhook:
  securityContext:
    capabilities:
      drop:
      - ALL
    readOnlyRootFilesystem: true
    runAsNonRoot: true
    runAsUser: 1000

  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 64Mi

certController:
  securityContext:
    capabilities:
      drop:
      - ALL
    readOnlyRootFilesystem: true
    runAsNonRoot: true
    runAsUser: 1000

  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 64Mi
VALUES
}

module "external_secrets_namespace" {
  count = local.external_secrets.enabled ? 1 : 0

  source = "../modules/eks-kubernetes-namespace"
  name   = local.external_secrets.namespace
  network_policies = [
    {
      name         = "default-deny"
      policy_types = ["Ingress"]
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
                name = local.external_secrets.namespace
              }
            }
          }
        ]
      }
    },
    {
      name         = "allow-webhooks"
      policy_types = ["Ingress"]
      pod_selector = {
        match_expressions = {
          key      = "app.kubernetes.io/name"
          operator = "In"
          values   = ["${local.external_secrets.name}-webhook"]
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

resource "helm_release" "external_secrets" {
  count = local.external_secrets.enabled ? 1 : 0

  name        = local.external_secrets.name
  chart       = local.external_secrets.chart
  repository  = local.external_secrets.repository
  version     = local.external_secrets.chart_version
  namespace   = module.external_secrets_namespace[count.index].name
  max_history = var.helm_release_history_size

  values = [
    local.external_secrets_values
  ]

}


module "fargate_namespace" {
  source = "../modules/eks-kubernetes-namespace"
  name   = "fargate"
}


locals {
  gitlab_runner = {
    name          = local.helm_releases[index(local.helm_releases.*.id, "gitlab-runner")].id
    enabled       = local.helm_releases[index(local.helm_releases.*.id, "gitlab-runner")].enabled
    chart         = local.helm_releases[index(local.helm_releases.*.id, "gitlab-runner")].chart
    repository    = local.helm_releases[index(local.helm_releases.*.id, "gitlab-runner")].repository
    chart_version = local.helm_releases[index(local.helm_releases.*.id, "gitlab-runner")].chart_version
    namespace     = local.helm_releases[index(local.helm_releases.*.id, "gitlab-runner")].namespace
  }
  gitlab_runner_registration_token = lookup(jsondecode(data.aws_secretsmanager_secret_version.infra.secret_string), "gitlab_runner_registration_token", "")
  gitlab_runner_values             = <<VALUES
rbac:
  create: true
  clusterWideAccess: true
  serviceAccountAnnotations:
    eks.amazonaws.com/role-arn: ${local.gitlab_runner.enabled ? module.aws_iam_gitlab_runner[0].role_arn : ""}

runnerRegistrationToken: "${local.gitlab_runner_registration_token}"
gitlabUrl: "https://gitlab.com/"
concurrent: 4
checkInterval: 30

runners:
  tags: "eks-k8s"
  runUntagged: false

  config: |
    [[runners]]
      executor = "kubernetes"
      request_concurrency = 1
      [runners.kubernetes]
        namespace = "{{.Release.Namespace}}"
        image = "public.ecr.aws/ubuntu/ubuntu:20.04"
        privileged = true
        cpu_request = "250m"
        cpu_limit = "950m"
        memory_request = "512Mi"
        memory_limit = "2500Mi"
        helper_cpu_request = "250m"
        helper_cpu_limit = "950m"
        helper_memory_request = "256Mi"
        helper_memory_limit = "512Mi"
        service_cpu_request = "250m"
        service_cpu_limit = "950m"
        service_memory_request = "256Mi"
        service_memory_limit = "512Mi"
        [runners.kubernetes.node_selector]
          nodegroup = "ci"
        [runners.kubernetes.node_tolerations]
          "nodegroup=ci" = "NoSchedule"
        [runners.kubernetes.volumes]
          [[runners.kubernetes.volumes.empty_dir]]
            name = "docker-certs"
            mount_path = "/certs/client"
            medium = "Memory"
      [runners.cache]
        Type = "s3"
        Path = "gitlab_runner"
        Shared = false
        [runners.cache.s3]
          ServerAddress = "s3.amazonaws.com"
          BucketName = "${local.gitlab_runner.enabled ? aws_s3_bucket.gitlab_runner_cache[0].id : "bucket_name"}"
          BucketLocation = "${local.region}"
          Insecure = false
VALUES
}

module "gitlab_runner_namespace" {
  count = local.gitlab_runner.enabled ? 1 : 0

  source = "../modules/eks-kubernetes-namespace"
  name   = "gitlab-runner"
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
                name = "gitlab-runner"
              }
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

resource "aws_kms_key" "gitlab_runner_cache" {
  count = local.gitlab_runner.enabled ? 1 : 0

  description             = "KMS key for gitlab runner cache S3 bucket encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_kms_alias" "gitlab_runner_cache" {
  count = local.gitlab_runner.enabled ? 1 : 0

  name          = "alias/${local.name}-gitlab-runner-cache"
  target_key_id = aws_kms_key.gitlab_runner_cache[0].key_id
}

resource "aws_s3_bucket" "gitlab_runner_cache" {
  count = local.gitlab_runner.enabled ? 1 : 0

  bucket        = "${local.name}-gitlab-runner-cache"
  force_destroy = true
  tags = {
    Name        = "${local.name}-gitlab-runner-cache"
    Environment = local.env
  }

}

resource "aws_s3_bucket_acl" "gitlab_runner_acl" {
  count = local.gitlab_runner.enabled ? 1 : 0

  bucket = aws_s3_bucket.gitlab_runner_cache[0].id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "gitlab_runner_cache_versioning" {
  count = local.gitlab_runner.enabled ? 1 : 0

  bucket = aws_s3_bucket.gitlab_runner_cache[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_logging" "gitlab_runner_cache_logging" {
  count = local.gitlab_runner.enabled ? 1 : 0

  bucket        = aws_s3_bucket.gitlab_runner_cache[0].id
  target_bucket = aws_s3_bucket.gitlab_runner_cache[0].id
  target_prefix = "log/"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "gitlab_runner_encryption" {
  count = local.gitlab_runner.enabled ? 1 : 0

  bucket = aws_s3_bucket.gitlab_runner_cache[0].bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.gitlab_runner_cache[0].arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "gitlab_runner_lifecycle" {
  count = local.gitlab_runner.enabled ? 1 : 0

  bucket = aws_s3_bucket.gitlab_runner_cache[0].id

  rule {
    id = "gitlab-runner-cache-lifecycle-rule"
    expiration {
      days = 120
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    filter {
      and {
        tags = {
          rule = "gitlab-runner-cache-lifecycle-rule"
        }
      }
    }
    status = "Enabled"
  }
}

resource "aws_s3_bucket_replication_configuration" "gitlab_runner_cache_replication" {
  count = local.gitlab_runner.enabled ? 1 : 0

  role   = aws_iam_role.gitlab_runner_cache_replication[0].arn
  bucket = aws_s3_bucket.gitlab_runner_cache[0].id

  rule {
    id     = "gitlab-runner-cache-replication-rule"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.gitlab_runner_cache_replica[0].arn
      storage_class = "STANDARD"
    }
  }

  depends_on = [aws_s3_bucket_versioning.gitlab_runner_cache_versioning]
}

resource "aws_s3_bucket" "gitlab_runner_cache_replica" {
  count = local.gitlab_runner.enabled ? 1 : 0

  bucket   = "${local.name}-gitlab-runner-cache-replica"
  provider = aws
  tags = {
    Name        = "${local.name}-gitlab-runner-cache-replica"
    Environment = local.env
  }
}

resource "aws_s3_bucket_versioning" "gitlab_runner_cache_replica_versioning" {
  count = local.gitlab_runner.enabled ? 1 : 0

  bucket = aws_s3_bucket.gitlab_runner_cache_replica[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "gitlab_runner_cache_replication" {
  count = local.gitlab_runner.enabled ? 1 : 0

  name = "${local.name}-gitlab-runner-cache-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "gitlab_runner_cache_replication" {
  count = local.gitlab_runner.enabled ? 1 : 0

  role = aws_iam_role.gitlab_runner_cache_replication[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.gitlab_runner_cache[0].arn
        ]
      },
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.gitlab_runner_cache[0].arn}/*"
        ]
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.gitlab_runner_cache_replica[0].arn}/*"
        ]
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "gitlab_runner_cache_notification" {
  count = local.gitlab_runner.enabled ? 1 : 0

  bucket = aws_s3_bucket.gitlab_runner_cache[0].id
}

resource "aws_s3_bucket_public_access_block" "gitlab_runner_cache_public_access_block" {
  count = local.gitlab_runner.enabled ? 1 : 0

  bucket                  = aws_s3_bucket.gitlab_runner_cache[count.index].id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

module "aws_iam_gitlab_runner" {
  count = local.gitlab_runner.enabled ? 1 : 0

  source            = "../modules/aws-iam-eks-trusted"
  name              = "${local.name}-${local.gitlab_runner.name}"
  region            = local.region
  oidc_provider_arn = local.eks_oidc_provider_arn
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "ecr:GetAuthorizationToken",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:ListTagsForResource",
          "ecr:DescribeImageScanFindings",
          "ecr:DescribeImages"
        ],
        "Resource" : "*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:*"
        ],
        "Resource" : [
          "arn:aws:s3:::${aws_s3_bucket.gitlab_runner_cache[count.index].id}",
          "arn:aws:s3:::${aws_s3_bucket.gitlab_runner_cache[count.index].id}/*"
        ]
      }
    ]
  })
}

resource "helm_release" "gitlab_runner" {
  count = local.gitlab_runner.enabled ? 1 : 0

  name        = local.gitlab_runner.name
  chart       = local.gitlab_runner.chart
  repository  = local.gitlab_runner.repository
  version     = local.gitlab_runner.chart_version
  namespace   = module.gitlab_runner_namespace[count.index].name
  max_history = var.helm_release_history_size

  values = [
    local.gitlab_runner_values
  ]

}

output "gitlab_runner_cache_bucket_name" {
  value       = local.gitlab_runner.enabled ? aws_s3_bucket.gitlab_runner_cache[0].id : null
  description = "Name of the s3 bucket for gitlab-runner cache"
}


locals {
  ingress_nginx = {
    name          = local.helm_releases[index(local.helm_releases.*.id, "ingress-nginx")].id
    enabled       = local.helm_releases[index(local.helm_releases.*.id, "ingress-nginx")].enabled
    chart         = local.helm_releases[index(local.helm_releases.*.id, "ingress-nginx")].chart
    repository    = local.helm_releases[index(local.helm_releases.*.id, "ingress-nginx")].repository
    chart_version = local.helm_releases[index(local.helm_releases.*.id, "ingress-nginx")].chart_version
    namespace     = local.helm_releases[index(local.helm_releases.*.id, "ingress-nginx")].namespace
  }
  ingress_nginx_general_values                   = <<VALUES
rbac:
  create: true
controller:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true

  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: karpenter.sh/capacity-type
            operator: In
            values:
              - on-demand
VALUES
  ingress_nginx_and_aws_load_balancer_controller = <<VALUES
controller:
  service:
    type: ClusterIP
    targetPorts:
      http: http
      https: http
  publishService:
    enabled: true
  config:
    server-tokens: "false"
    use-forwarded-headers: "true"
VALUES
  ingress_pod_ssl_termination_values             = <<VALUES
controller:
  extraArgs:
    default-ssl-certificate: "${local.ingress_nginx.enabled ? module.ingress_nginx_namespace[0].name : "default"}/nginx-tls"
  containerPort:
    http: 80
    https: 443
  service:
    targetPorts:
      http: http
      https: https
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-backend-protocol: tcp
      service.beta.kubernetes.io/aws-load-balancer-proxy-protocol: "*"
      service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout: '60'
      service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "https"
      external-dns.alpha.kubernetes.io/hostname: ${local.domain_name}.
  publishService:
    enabled: true
  config:
    server-tokens: "false"
    use-forwarded-headers: "true"
    use-proxy-protocol: "true"
    set-real-ip-from: "${local.vpc_cidr}"
    real-ip-header: "proxy_protocol"
VALUES
}

module "ingress_nginx_namespace" {
  count = local.ingress_nginx.enabled ? 1 : 0

  source = "../modules/eks-kubernetes-namespace"
  name   = local.ingress_nginx.namespace
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
                name = local.ingress_nginx.namespace
              }
            }
          }
        ]
      }
    },
    {
      name         = "allow-ingress"
      policy_types = ["Ingress"]
      pod_selector = {
        match_expressions = {
          key      = "app.kubernetes.io/name"
          operator = "In"
          values   = [local.ingress_nginx.name]
        }
      }
      ingress = {
        ports = [
          {
            port     = "80"
            protocol = "TCP"
          },
          {
            port     = "443"
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
      name         = "allow-control-plane"
      policy_types = ["Ingress"]
      pod_selector = {
        match_expressions = {
          key      = "app.kubernetes.io/name"
          operator = "In"
          values   = [local.ingress_nginx.name]
        }
      }
      ingress = {
        ports = [
          {
            port     = "8443"
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
      name         = "allow-monitoring"
      policy_types = ["Ingress"]
      pod_selector = {
        match_expressions = {
          key      = "app.kubernetes.io/name"
          operator = "In"
          values   = [local.ingress_nginx.name]
        }
      }
      ingress = {
        ports = [
          {
            port     = "metrics"
            protocol = "TCP"
          }
        ]
        from = [
          {
            namespace_selector = {
              match_labels = {
                name = "monitoring"
              }
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

resource "helm_release" "ingress_nginx" {
  count = local.ingress_nginx.enabled ? 1 : 0

  name        = local.ingress_nginx.name
  chart       = local.ingress_nginx.chart
  repository  = local.ingress_nginx.repository
  version     = local.ingress_nginx.chart_version
  namespace   = module.ingress_nginx_namespace[count.index].name
  max_history = var.helm_release_history_size

  values = [
    local.ingress_nginx_general_values,
    var.nginx_ingress_ssl_terminator == "lb" ? local.ingress_nginx_and_aws_load_balancer_controller : local.ingress_pod_ssl_termination_values
  ]

  depends_on = [kubectl_manifest.kube_prometheus_stack_operator_crds]
}


locals {
  istio = {
    name          = local.helm_releases[index(local.helm_releases.*.id, "istio")].id
    enabled       = local.helm_releases[index(local.helm_releases.*.id, "istio")].enabled
    chart         = local.helm_releases[index(local.helm_releases.*.id, "istio")].chart
    repository    = local.helm_releases[index(local.helm_releases.*.id, "istio")].repository
    chart_version = local.helm_releases[index(local.helm_releases.*.id, "istio")].chart_version
    namespace     = local.helm_releases[index(local.helm_releases.*.id, "istio")].namespace
  }
  kiali_server = {
    name          = local.helm_releases[index(local.helm_releases.*.id, "kiali")].id
    enabled       = local.helm_releases[index(local.helm_releases.*.id, "kiali")].enabled
    chart         = local.helm_releases[index(local.helm_releases.*.id, "kiali")].chart
    repository    = local.helm_releases[index(local.helm_releases.*.id, "kiali")].repository
    chart_version = local.helm_releases[index(local.helm_releases.*.id, "kiali")].chart_version
    namespace     = local.helm_releases[index(local.helm_releases.*.id, "kiali")].namespace
  }
  istiod_values                                = <<VALUES
pilot:
  resources:
    requests:
      cpu: "500m"
      memory: "2Gi"
    limits:
      cpu: "500m"
      memory: "2Gi"
  nodeSelector:
    karpenter.sh/capacity-type: on-demand
global:
  imagePullPolicy: IfNotPresent
  proxy:
    autoInject: enabled
    excludeIPRanges: "169.254.169.254/32"
    holdApplicationUntilProxyStarts: true
VALUES
  kiali_server_prometheus_endpoint             = local.victoria_metrics_k8s_stack.enabled ? "http://vmsingle-${local.victoria_metrics_k8s_stack.name}.${local.victoria_metrics_k8s_stack.namespace}:8429" : "http://${local.kube_prometheus_stack.name}-prometheus.${local.kube_prometheus_stack.namespace}:9090"
  kiali_server_grafana_endpoint                = local.victoria_metrics_k8s_stack.enabled ? "http://${local.victoria_metrics_k8s_stack.name}-grafana.${local.victoria_metrics_k8s_stack.namespace}" : "http://${local.kube_prometheus_stack.name}-grafana.${local.kube_prometheus_stack.namespace}"
  kiali_server_values                          = <<VALUES
nameOverride: ${local.kiali_server.name}
fullnameOverride: ${local.kiali_server.name}
auth:
  strategy: "anonymous"
istio_namespace: ${local.istio.namespace}
external_services:
  custom_dashboards:
    enabled: true
  prometheus:
    url: ${local.kiali_server_prometheus_endpoint}
    custom_metrics_url: ${local.kiali_server_prometheus_endpoint}
  grafana:
    url: ${local.kiali_server_grafana_endpoint}
  namespace_label: kubernetes_namespace
server:
  port: 20001
  metrics_enabled: true
  metrics_port: 9090
  web_root: ""
VALUES
  istio_prometheus_service_monitor_cp_manifest = <<VALUES
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: istio-controlplane
  labels:
    release: kube-prometheus-stack
spec:
  jobLabel: istio
  selector:
    matchExpressions:
      - {key: istio, operator: In, values: [mixer,pilot,galley,citadel,sidecar-injector]}
  namespaceSelector:
    any: true
  endpoints:
  - port: http-monitoring
    interval: 15s
VALUES
  istio_prometheus_service_monitor_dp_manifest = <<VALUES
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: istio-dataplane
  labels:
    monitoring: istio-dataplane
    release: kube-prometheus-stack
spec:
  selector:
    matchExpressions:
      - {key: istio-prometheus-ignore, operator: DoesNotExist}
  namespaceSelector:
    any: true
  jobLabel: envoy-stats
  endpoints:
  - path: /stats/prometheus
    targetPort: http-envoy-prom
    interval: 15s
VALUES
}

module "istio_system_namespace" {
  count = local.istio.enabled ? 1 : 0

  source = "../modules/eks-kubernetes-namespace"
  name   = local.istio.namespace
  network_policies = concat([
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
                name = local.istio.namespace
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
          key      = "app"
          operator = "In"
          values   = ["istiod"]
        }
      }
      ingress = {
        ports = [
          {
            port     = "15017"
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
      name         = "allow-https-dns"
      policy_types = ["Ingress"]
      pod_selector = {
        match_expressions = {
          key      = "app"
          operator = "In"
          values   = ["istiod"]
        }
      }
      ingress = {
        ports = [
          {
            port     = "15012"
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
      name         = "allow-monitoring"
      policy_types = ["Ingress"]
      pod_selector = {
        match_expressions = {
          key      = "app"
          operator = "In"
          values   = ["istiod"]
        }
      }
      ingress = {
        ports = [
          {
            port     = "15014"
            protocol = "TCP"
          }
        ]
        from = [
          {
            namespace_selector = {
              match_labels = {
                name = "monitoring"
              }
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
    ], local.kiali_server.enabled ? [{
      name         = "allow-kiali-namespace"
      policy_types = ["Ingress"]
      pod_selector = {
        match_expressions = {
          key      = "app"
          operator = "In"
          values   = ["istiod"]
        }
      }
      ingress = {
        ports = [
          {
            port     = "15010"
            protocol = "TCP"
          }
        ]
        from = [
          {
            namespace_selector = {
              match_labels = {
                name = local.kiali_server.namespace
              }
            }
          }
        ]
      }
  }] : [])
}

module "kiali_namespace" {
  count = local.kiali_server.enabled ? 1 : 0

  source = "../modules/eks-kubernetes-namespace"
  name   = local.kiali_server.namespace
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
                name = local.kiali_server.namespace
              }
            }
          }
        ]
      }
    },
    {
      name         = "allow-monitoring"
      policy_types = ["Ingress"]
      pod_selector = {
        match_expressions = {
          key      = "app"
          operator = "In"
          values   = [local.kiali_server.name]
        }
      }
      ingress = {
        ports = [
          {
            port     = "9090"
            protocol = "TCP"
          }
        ]
        from = [
          {
            namespace_selector = {
              match_labels = {
                name = "monitoring"
              }
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

resource "helm_release" "istio_base" {
  count = local.istio.enabled ? 1 : 0

  name        = "istio-base"
  chart       = "base"
  repository  = local.istio.repository
  version     = local.istio.chart_version
  max_history = var.helm_release_history_size
}

resource "helm_release" "istiod" {
  count = local.istio.enabled ? 1 : 0

  name        = "istiod"
  chart       = "istiod"
  repository  = local.istio.repository
  version     = local.istio.chart_version
  namespace   = module.istio_system_namespace[count.index].name
  max_history = var.helm_release_history_size

  values = [
    local.istiod_values
  ]

  depends_on = [helm_release.istio_base, kubectl_manifest.kube_prometheus_stack_operator_crds]
}

resource "kubectl_manifest" "istio_prometheus_service_monitor_cp" {
  count              = local.istio.enabled ? 1 : 0
  yaml_body          = local.istio_prometheus_service_monitor_cp_manifest
  override_namespace = module.istio_system_namespace[count.index].name
  depends_on         = [helm_release.istiod]
}

resource "kubectl_manifest" "istio_prometheus_service_monitor_dp" {
  count              = local.istio.enabled ? 1 : 0
  yaml_body          = local.istio_prometheus_service_monitor_dp_manifest
  override_namespace = module.istio_system_namespace[count.index].name
  depends_on         = [helm_release.istiod]
}

resource "helm_release" "kiali" {
  count = local.kiali_server.enabled ? 1 : 0

  name        = local.kiali_server.name
  chart       = local.kiali_server.chart
  repository  = local.kiali_server.repository
  version     = local.kiali_server.chart_version
  namespace   = module.kiali_namespace[count.index].name
  max_history = var.helm_release_history_size

  values = [
    local.kiali_server_values
  ]

  depends_on = [helm_release.istiod, kubectl_manifest.kube_prometheus_stack_operator_crds]
}


locals {
  karpenter = {
    name          = local.helm_releases[index(local.helm_releases.*.id, "karpenter")].id
    enabled       = local.helm_releases[index(local.helm_releases.*.id, "karpenter")].enabled
    chart         = local.helm_releases[index(local.helm_releases.*.id, "karpenter")].chart
    repository    = local.helm_releases[index(local.helm_releases.*.id, "karpenter")].repository
    chart_version = local.helm_releases[index(local.helm_releases.*.id, "karpenter")].chart_version
    namespace     = local.helm_releases[index(local.helm_releases.*.id, "karpenter")].namespace
  }

  karpenter_values = <<VALUES
settings:
  clusterName: ${local.eks_cluster_id}
  clusterEndpoint: ${local.eks_cluster_endpoint}
  interruptionQueue: ${module.karpenter[0].queue_name}

serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: ${module.karpenter[0].irsa_arn}

controller:
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      memory: 512Mi

VALUES
}

data "aws_ecrpublic_authorization_token" "token" {}

module "karpenter" {
  count = local.karpenter.enabled ? 1 : 0

  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "19.21.0"

  cluster_name = local.eks_cluster_id

  policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  irsa_oidc_provider_arn          = local.eks_oidc_provider_arn
  irsa_namespace_service_accounts = ["karpenter:karpenter"]

  create_iam_role                            = false
  enable_karpenter_instance_profile_creation = true
  iam_role_arn                               = var.node_group_default_iam_role_arn
}

module "karpenter_namespace" {
  count = local.karpenter.enabled ? 1 : 0

  source = "../modules/eks-kubernetes-namespace"
  name   = local.karpenter.namespace
}

resource "kubectl_manifest" "karpenter_ec2nodeclass_private" {
  count = local.karpenter.enabled ? 1 : 0

  yaml_body = <<EOF
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: private
  namespace: karpenter
spec:
  amiFamily: AL2
  role: ${var.node_group_default_iam_role_name}
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "private"
        Name: "${local.name}-private"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${local.name}
  tags:
    karpenter.sh/discovery: ${local.name}
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 100Gi
        volumeType: gp3
EOF

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "karpenter_ec2nodeclass_public" {
  count = local.karpenter.enabled ? 1 : 0

  yaml_body = <<EOF
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: public
  namespace: karpenter
spec:
  amiFamily: AL2
  role: ${var.node_group_default_iam_role_name}
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "public"
        Name: "${local.name}-public"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${local.eks_cluster_id}
  tags:
    karpenter.sh/discovery: ${local.eks_cluster_id}
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 100Gi
        volumeType: gp3
EOF

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "karpenter_nodepool_default" {
  count = local.karpenter.enabled ? 1 : 0

  yaml_body = <<EOF
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
  namespace: karpenter
spec:
  template:
    metadata:
      labels:
        nodegroup: default

    spec:
      nodeClassRef:
        name: private

      requirements:
        - key: "karpenter.k8s.aws/instance-category"
          operator: In
          values: ["t", "m", "c"]
        - key: "karpenter.k8s.aws/instance-cpu"
          operator: In
          values: ["2", "4", "8"]
        - key: "karpenter.k8s.aws/instance-hypervisor"
          operator: In
          values: ["nitro"]
        - key: "karpenter.k8s.aws/instance-generation"
          operator: Gt
          values: ["3"]
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot", "on-demand"]

      kubelet:
        systemReserved:
          cpu: 100m
          memory: 100Mi
          ephemeral-storage: 1Gi
        kubeReserved:
          cpu: 200m
          memory: 100Mi
          ephemeral-storage: 3Gi
        evictionMaxPodGracePeriod: 60
        imageGCHighThresholdPercent: 85
        imageGCLowThresholdPercent: 80
        cpuCFSQuota: true

  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h

  limits:
    cpu: "1000"
    memory: 1000Gi

EOF

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "karpenter_nodepool_ci" {
  count = local.karpenter.enabled ? 1 : 0

  yaml_body = <<EOF
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: ci
  namespace: karpenter
spec:
  template:
    metadata:
      labels:
        nodegroup: ci

    spec:
      nodeClassRef:
        name: public

      taints:
        - key: nodegroup
          value: ci
          effect: NoSchedule

      requirements:
        - key: "karpenter.k8s.aws/instance-category"
          operator: In
          values: ["t", "m", "c"]
        - key: "karpenter.k8s.aws/instance-cpu"
          operator: In
          values: ["4", "8"]
        - key: "karpenter.k8s.aws/instance-hypervisor"
          operator: In
          values: ["nitro"]
        - key: "karpenter.k8s.aws/instance-generation"
          operator: Gt
          values: ["3"]
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot"]

      kubelet:
        systemReserved:
          cpu: 100m
          memory: 100Mi
          ephemeral-storage: 1Gi
        kubeReserved:
          cpu: 200m
          memory: 100Mi
          ephemeral-storage: 3Gi
        evictionMaxPodGracePeriod: 60
        imageGCHighThresholdPercent: 85
        imageGCLowThresholdPercent: 80
        cpuCFSQuota: true

  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h

  limits:
    cpu: "1000"
    memory: 1000Gi

EOF

  depends_on = [helm_release.karpenter]
}

resource "helm_release" "karpenter" {
  count = local.karpenter.enabled ? 1 : 0

  name                = local.karpenter.name
  chart               = local.karpenter.chart
  repository          = local.karpenter.repository
  version             = local.karpenter.chart_version
  namespace           = module.karpenter_namespace[count.index].name
  max_history         = 3
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password

  values = [
    local.karpenter_values
  ]
}


locals {
  keda = {
    name          = local.helm_releases[index(local.helm_releases.*.id, "keda")].id
    enabled       = local.helm_releases[index(local.helm_releases.*.id, "keda")].enabled
    chart         = local.helm_releases[index(local.helm_releases.*.id, "keda")].chart
    repository    = local.helm_releases[index(local.helm_releases.*.id, "keda")].repository
    chart_version = local.helm_releases[index(local.helm_releases.*.id, "keda")].chart_version
    namespace     = local.helm_releases[index(local.helm_releases.*.id, "keda")].namespace
  }
}

module "keda_namespace" {
  count = local.keda.enabled ? 1 : 0

  source = "../modules/eks-kubernetes-namespace"
  name   = local.keda.namespace
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
                name = local.keda.namespace
              }
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
    },
    {
      name         = "allow-control-plane"
      policy_types = ["Ingress"]
      pod_selector = {
        match_expressions = {
          key      = "app"
          operator = "In"
          values   = ["keda-operator-metrics-apiserver"]
        }
      }
      ingress = {
        ports = [
          {
            port     = "6443"
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
    }
  ]
}

resource "helm_release" "kedacore" {
  count = local.keda.enabled ? 1 : 0

  name        = local.keda.name
  chart       = local.keda.chart
  repository  = local.keda.repository
  version     = local.keda.chart_version
  namespace   = module.keda_namespace[count.index].name
  max_history = var.helm_release_history_size
}


locals {
  kube_prometheus_stack = {
    name          = local.helm_releases[index(local.helm_releases.*.id, "kube-prometheus-stack")].id
    enabled       = local.helm_releases[index(local.helm_releases.*.id, "kube-prometheus-stack")].enabled
    chart         = local.helm_releases[index(local.helm_releases.*.id, "kube-prometheus-stack")].chart
    repository    = local.helm_releases[index(local.helm_releases.*.id, "kube-prometheus-stack")].repository
    chart_version = local.helm_releases[index(local.helm_releases.*.id, "kube-prometheus-stack")].chart_version
    namespace     = local.helm_releases[index(local.helm_releases.*.id, "kube-prometheus-stack")].namespace
  }
  kube_prometheus_stack_grafana_oauth_type                   = ""
  kube_prometheus_stack_grafana_password                     = local.kube_prometheus_stack.enabled ? random_string.kube_prometheus_stack_grafana_password[0].result : ""
  kube_prometheus_stack_grafana_gitlab_client_id             = lookup(jsondecode(data.aws_secretsmanager_secret_version.infra.secret_string), "grafana_gitlab_client_id", "")
  kube_prometheus_stack_grafana_gitlab_client_secret         = lookup(jsondecode(data.aws_secretsmanager_secret_version.infra.secret_string), "grafana_gitlab_client_secret", "")
  kube_prometheus_stack_grafana_gitlab_group                 = lookup(jsondecode(data.aws_secretsmanager_secret_version.infra.secret_string), "grafana_gitlab_group", "")
  kube_prometheus_stack_grafana_github_client_id             = lookup(jsondecode(data.aws_secretsmanager_secret_version.infra.secret_string), "grafana_github_client_id", "")
  kube_prometheus_stack_grafana_github_client_secret         = lookup(jsondecode(data.aws_secretsmanager_secret_version.infra.secret_string), "grafana_github_client_secret", "")
  kube_prometheus_stack_grafana_github_team_ids              = lookup(jsondecode(data.aws_secretsmanager_secret_version.infra.secret_string), "grafana_github_team_ids", "")
  kube_prometheus_stack_grafana_github_allowed_organizations = lookup(jsondecode(data.aws_secretsmanager_secret_version.infra.secret_string), "grafana_github_allowed_organizations", "")
  kube_prometheus_stack_alertmanager_slack_webhook           = lookup(jsondecode(data.aws_secretsmanager_secret_version.infra.secret_string), "alertmanager_slack_webhook", "")
  kube_prometheus_stack_alertmanager_slack_channel           = lookup(jsondecode(data.aws_secretsmanager_secret_version.infra.secret_string), "alertmanager_slack_channel", "")
  kube_prometheus_stack_grafana_domain_name                  = "grafana-${local.domain_suffix}"
  kube_prometheus_stack_alertmanager_domain_name             = "alertmanager-${local.domain_suffix}"
  kube_prometheus_stack_prometheus_domain_name               = "prometheus-${local.domain_suffix}"
  kube_prometheus_stack_values                               = <<VALUES
defaultRules:
  disabled:
    KubeProxyDown: true

kubeControllerManager:
  enabled: false
kubeScheduler:
  enabled: false
kubeProxy:
  enabled: false

prometheus:
  ingress:
    enabled: true
    annotations:
      kubernetes.io/ingress.class: nginx
      nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
      nginx.ingress.kubernetes.io/whitelist-source-range: ${local.ip_whitelist}
    path: /
    hosts:
      - ${local.kube_prometheus_stack_prometheus_domain_name}
    tls:
    - hosts:
      - ${local.kube_prometheus_stack_prometheus_domain_name}
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: advanced
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 30Gi
    resources:
      requests:
        cpu: 200m
        memory: 1024Mi
      limits:
        cpu: 400m
        memory: 1024Mi
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: karpenter.sh/capacity-type
              operator: In
              values:
                - on-demand

prometheusOperator:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: karpenter.sh/capacity-type
            operator: In
            values:
              - on-demand
VALUES
  kube_prometheus_stack_grafana_values                       = <<VALUES
grafana:
  enabled: true
  adminPassword: "${local.kube_prometheus_stack_grafana_password}"
  serviceAccount:
    annotations:
      "eks.amazonaws.com/role-arn": ${local.kube_prometheus_stack.enabled ? module.aws_iam_kube_prometheus_stack_grafana[0].role_arn : ""}
  ingress:
    enabled: true
    annotations:
      kubernetes.io/ingress.class: nginx
      nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    path: /
    hosts:
      - ${local.kube_prometheus_stack_grafana_domain_name}
    tls:
    - hosts:
      - ${local.kube_prometheus_stack_grafana_domain_name}
  env:
    GF_SERVER_ROOT_URL: https://${local.kube_prometheus_stack_grafana_domain_name}
    GF_USERS_ALLOW_SIGN_UP: false

  persistence:
    enabled: false
  sidecar:
    datasources:
      enabled: true

  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: CloudWatch
          type: cloudwatch
          jsonData:
            defaultRegion: "${local.region}"
        - name: Loki
          type: loki
          url: http://loki-stack.loki:3100
          jsonData:
            maxLines: 1000

  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
      - name: 'logs'
        orgId: 1
        folder: 'logs'
        type: file
        disableDeletion: true
        editable: true
        options:
          path: /var/lib/grafana/dashboards/logs
      - name: 'k8s'
        orgId: 1
        folder: 'k8s'
        type: file
        disableDeletion: true
        editable: true
        options:
          path: /var/lib/grafana/dashboards/k8s
      - name: 'istio'
        orgId: 1
        folder: 'istio'
        type: file
        disableDeletion: true
        editable: true
        options:
          path: /var/lib/grafana/dashboards/istio
  dashboards:
    logs:
      logs:
        url: https://grafana-dashboards.maddevs.org/common/aws-eks-base/loki-dashboard-quick-search.json
    k8s:
      nginx-ingress:
        gnetId: 9614
        datasource: Prometheus
      loki-promtail:
        gnetId: 10880
        datasource: Prometheus
      cluster-autoscaler:
        gnetId: 3831
        datasource: Prometheus

  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: karpenter.sh/capacity-type
            operator: In
            values:
              - spot
VALUES
  kube_prometheus_stack_grafana_istio_values                 = <<VALUES
grafana:
  dashboards:
    istio:
      Istio-control-plane:
        gnetId: 7645
        revision: 101
        datasource: Prometheus
      Istio-galley:
        gnetId: 7648
        revision: 3
        datasource: Prometheus
      Istio-mesh:
        gnetId: 7639
        revision: 101
        datasource: Prometheus
      Istio-service:
        gnetId: 7636
        revision: 101
        datasource: Prometheus
      Istio-workload:
        gnetId: 7630
        revision: 101
        datasource: Prometheus
VALUES
  kube_prometheus_stack_grafana_gitlab_oauth_values          = <<VALUES
grafana:
  env:
    GF_AUTH_GITLAB_ENABLED: true
    GF_AUTH_GITLAB_ALLOW_SIGN_UP: true
    GF_AUTH_GITLAB_CLIENT_ID: ${local.kube_prometheus_stack_grafana_gitlab_client_id}
    GF_AUTH_GITLAB_CLIENT_SECRET: ${local.kube_prometheus_stack_grafana_gitlab_client_secret}
    GF_AUTH_GITLAB_SCOPES: read_api
    GF_AUTH_GITLAB_AUTH_URL: https://gitlab.com/oauth/authorize
    GF_AUTH_GITLAB_TOKEN_URL: https://gitlab.com/oauth/token
    GF_AUTH_GITLAB_API_URL: https://gitlab.com/api/v4
    GF_AUTH_GITLAB_ALLOWED_GROUPS: ${local.kube_prometheus_stack_grafana_gitlab_group}
VALUES
  kube_prometheus_stack_grafana_github_oauth_values          = <<VALUES
grafana:
  env:
    GF_AUTH_GITHUB_ENABLED: true
    GF_AUTH_GITHUB_ALLOW_SIGN_UP: true
    GF_AUTH_GITHUB_CLIENT_ID: ${local.kube_prometheus_stack_grafana_github_client_id}
    GF_AUTH_GITHUB_CLIENT_SECRET: ${local.kube_prometheus_stack_grafana_github_client_secret}
    GF_AUTH_GITHUB_SCOPES: user:email,read:org
    GF_AUTH_GITHUB_AUTH_URL: https://github.com/login/oauth/authorize
    GF_AUTH_GITHUB_TOKEN_URL: https://github.com/login/oauth/access_token
    GF_AUTH_GITHUB_API_URL: https://api.github.com/user
    GF_AUTH_GITHUB_TEAM_IDS: ${local.kube_prometheus_stack_grafana_github_team_ids}
    GF_AUTH_GITHUB_ALOWED_ORGANISATIONS: ${local.kube_prometheus_stack_grafana_github_allowed_organizations}
VALUES
  kube_prometheus_stack_alertmanager_values                  = <<VALUES
alertmanager:
  enabled: false
  ingress:
    enabled: true
    annotations:
      kubernetes.io/ingress.class: nginx
      nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
      nginx.ingress.kubernetes.io/whitelist-source-range: ${local.ip_whitelist}
    path: /
    hosts:
      - ${local.kube_prometheus_stack_alertmanager_domain_name}
    tls:
    - hosts:
      - ${local.kube_prometheus_stack_alertmanager_domain_name}
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: advanced
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
  config:
    global:
      resolve_timeout: 5m
    route:
      group_by: ['job']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 12h
      receiver: 'null'
      routes:
        - match:
            alertname: Watchdog
          receiver: 'null'
    receivers:
    - name: 'null'

  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: karpenter.sh/capacity-type
                operator: In
                values:
                  - on-demand
VALUES
  kube_prometheus_stack_alertmanager_slack_values            = <<VALUES
alertmanager:
  config:
    global:
      slack_api_url: ${local.kube_prometheus_stack_alertmanager_slack_webhook}
    route:
      routes:
        - match:
            alertname: Watchdog
          receiver: 'null'
        - match:
          receiver: "slack-notifications"
          continue: true
    receivers:
    - name: 'null'
    - name: 'slack-notifications'
      slack_configs:
        - channel: ${local.kube_prometheus_stack_alertmanager_slack_channel}
          send_resolved: true
          icon_url: https://avatars3.githubusercontent.com/u/3380462
          username: 'AlertManager'
          color: '{{ if eq .Status "firing" }}danger{{ else }}good{{ end }}'
          title: '[{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}] {{ .GroupLabels.SortedPairs.Values | join " " }} {{ if gt (len .CommonLabels) (len .GroupLabels) }}({{ with .CommonLabels.Remove .GroupLabels.Names }}{{ .Values | join " " }}{{ end }}){{ end }}'
          text: |-
            {{ range .Alerts }}
            {{ if .Annotations.summary }}*Alert:*  - {{ .Annotations.summary }} - `{{ .Labels.severity }}`{{ end }}
            *Description:* {{ .Annotations.message }}
            *Details:*
            {{ range .Labels.SortedPairs }} • *{{ .Name }}:* `{{ .Value }}`
            {{ end }}
            {{ end }}
          icon_emoji: '{{ template "slack.default.iconemoji" . }}'
VALUES
}

module "kube_prometheus_stack_namespace" {
  count = local.kube_prometheus_stack.enabled ? 1 : 0

  source = "../modules/eks-kubernetes-namespace"
  name   = local.kube_prometheus_stack.namespace
  network_policies = concat([
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
                name = local.kube_prometheus_stack.namespace
              }
            }
          }
        ]
      }
    },
    {
      name         = "allow-ingress"
      policy_types = ["Ingress"]
      pod_selector = {}
      ingress = {

        from = [
          {
            namespace_selector = {
              match_labels = {
                name = local.ingress_nginx.namespace
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
          key      = "app"
          operator = "In"
          values   = ["${local.kube_prometheus_stack.name}-operator"]
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
    ], local.kiali_server.enabled ? [{
      name         = "allow-kiali-namespace"
      policy_types = ["Ingress"]
      pod_selector = {
        match_expressions = {
          key      = "app.kubernetes.io/name"
          operator = "In"
          values   = ["prometheus", "grafana"]
        }
      }
      ingress = {
        ports = [
          {
            port     = "9090"
            protocol = "TCP"
          },
          {
            port     = "3000"
            protocol = "TCP"
          }
        ]
        from = [
          {
            namespace_selector = {
              match_labels = {
                name = local.kiali_server.namespace
              }
            }
          }
        ]
      }
  }] : [])
}

module "aws_iam_kube_prometheus_stack_grafana" {
  count = local.kube_prometheus_stack.enabled ? 1 : 0

  source            = "../modules/aws-iam-eks-trusted"
  name              = "${local.name}-grafana"
  region            = local.region
  oidc_provider_arn = local.eks_oidc_provider_arn
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowReadingMetricsFromCloudWatch",
        "Effect" : "Allow",
        "Action" : [
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "AllowReadingTagsInstancesRegionsFromEC2",
        "Effect" : "Allow",
        "Action" : [
          "ec2:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "AllowReadingResourcesForTags",
        "Effect" : "Allow",
        "Action" : "tag:GetResources",
        "Resource" : "*"
      }
    ]
  })
}

resource "random_string" "kube_prometheus_stack_grafana_password" {
  count   = local.kube_prometheus_stack.enabled ? 1 : 0
  length  = 20
  special = true
}

resource "helm_release" "prometheus_operator" {
  count = local.kube_prometheus_stack.enabled ? 1 : 0

  name        = local.kube_prometheus_stack.name
  chart       = local.kube_prometheus_stack.chart
  repository  = local.kube_prometheus_stack.repository
  version     = local.kube_prometheus_stack.chart_version
  namespace   = module.kube_prometheus_stack_namespace[count.index].name
  skip_crds   = true
  max_history = var.helm_release_history_size

  values = compact([
    local.kube_prometheus_stack_values,
    local.kube_prometheus_stack_grafana_values,
    local.istio.enabled ? local.kube_prometheus_stack_grafana_istio_values : null,
    local.kube_prometheus_stack_grafana_oauth_type == "gitlab" ? local.kube_prometheus_stack_grafana_gitlab_oauth_values : null,
    local.kube_prometheus_stack_grafana_oauth_type == "github" ? local.kube_prometheus_stack_grafana_github_oauth_values : null,
    local.kube_prometheus_stack_alertmanager_values,
    local.kube_prometheus_stack_alertmanager_slack_webhook != "" ? local.kube_prometheus_stack_alertmanager_slack_values : null
  ])

  depends_on = [
    kubectl_manifest.kube_prometheus_stack_operator_crds
  ]

}

output "kube_prometheus_stack_grafana_domain_name" {
  value       = local.kube_prometheus_stack.enabled ? local.kube_prometheus_stack_grafana_domain_name : null
  description = "Grafana dashboards address"
}

output "kube_prometheus_stack_alertmanager_domain_name" {
  value       = local.kube_prometheus_stack.enabled ? local.kube_prometheus_stack_alertmanager_domain_name : null
  description = "Alertmanager ui address"
}

output "kube_prometheus_stack_prometheus_domain_name" {
  value       = local.kube_prometheus_stack.enabled ? local.kube_prometheus_stack_prometheus_domain_name : null
  description = "Prometheus ui address"
}

output "kube_prometheus_stack_grafana_admin_password" {
  value       = local.kube_prometheus_stack.enabled ? local.kube_prometheus_stack_grafana_password : null
  sensitive   = true
  description = "Grafana admin password"
}

output "kube_prometheus_stack_get_grafana_admin_password" {
  value       = local.kube_prometheus_stack.enabled ? "kubectl get secret --namespace ${local.kube_prometheus_stack.namespace} kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 --decode ; echo" : null
  description = "Command which gets admin password from kubernetes secret"
}


locals {
  loki_stack = {
    name          = local.helm_releases[index(local.helm_releases.*.id, "loki-stack")].id
    enabled       = local.helm_releases[index(local.helm_releases.*.id, "loki-stack")].enabled
    chart         = local.helm_releases[index(local.helm_releases.*.id, "loki-stack")].chart
    repository    = local.helm_releases[index(local.helm_releases.*.id, "loki-stack")].repository
    chart_version = local.helm_releases[index(local.helm_releases.*.id, "loki-stack")].chart_version
    namespace     = local.helm_releases[index(local.helm_releases.*.id, "loki-stack")].namespace
  }
  loki_stack_values = <<VALUES
loki:
  enabled: true
  rbac:
    create: true
    pspEnabled: false
  resources:
    limits:
      cpu: 1
      memory: 1Gi
    requests:
      cpu: 500m
      memory: 1Gi
  config:
    limits_config:
      enforce_metric_name: false
      reject_old_samples: true
      reject_old_samples_max_age: 168h
  persistence:
    enabled: true
    accessModes:
      - ReadWriteOnce
    size: 10Gi
    storageClassName: advanced
  serviceMonitor:
    enabled: true
    scrapeTimeout: 10s
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: karpenter.sh/capacity-type
            operator: In
            values:
              - on-demand

promtail:
  enabled: true
  serviceMonitor:
    enabled: true
  tolerations:
    - effect: NoSchedule
      operator: Exists

fluent-bit:
  enabled: false
grafana:
  enabled: false
VALUES
}

module "loki_namespace" {
  count = local.loki_stack.enabled ? 1 : 0

  source = "../modules/eks-kubernetes-namespace"
  name   = local.loki_stack.namespace
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
                name = local.loki_stack.namespace
              }
            }
          }
        ]
      }
    },
    {
      name         = "allow-monitoring-loki"
      policy_types = ["Ingress"]
      pod_selector = {
        match_expressions = {
          key      = "release"
          operator = "In"
          values   = [local.loki_stack.name]
        }
      }
      ingress = {
        ports = [
          {
            port     = "http-metrics"
            protocol = "TCP"
          },
          {
            port     = "3100"
            protocol = "TCP"
          }
        ]
        from = [
          {
            namespace_selector = {
              match_labels = {
                name = "monitoring"
              }
            }
          }
        ]
      }
    },
    {
      name         = "allow-monitoring-promtail"
      policy_types = ["Ingress"]
      pod_selector = {
        match_expressions = {
          key      = "app.kubernetes.io/instance"
          operator = "In"
          values   = [local.loki_stack.name]
        }
      }
      ingress = {
        ports = [
          {
            port     = "3101"
            protocol = "TCP"
          }
        ]
        from = [
          {
            namespace_selector = {
              match_labels = {
                name = "monitoring"
              }
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

resource "helm_release" "loki_stack" {
  count = local.loki_stack.enabled ? 1 : 0

  name        = local.loki_stack.name
  chart       = local.loki_stack.chart
  repository  = local.loki_stack.repository
  version     = local.loki_stack.chart_version
  namespace   = module.loki_namespace[count.index].name
  max_history = var.helm_release_history_size

  values = [
    local.loki_stack_values
  ]

  depends_on = [kubectl_manifest.kube_prometheus_stack_operator_crds]
}


locals {
  kube_prometheus_stack_operator_crds = [
    "https://raw.githubusercontent.com/prometheus-community/helm-charts/kube-prometheus-stack-${local.kube_prometheus_stack.chart_version}/charts/kube-prometheus-stack/crds/crd-alertmanagerconfigs.yaml",
    "https://raw.githubusercontent.com/prometheus-community/helm-charts/kube-prometheus-stack-${local.kube_prometheus_stack.chart_version}/charts/kube-prometheus-stack/crds/crd-alertmanagers.yaml",
    "https://raw.githubusercontent.com/prometheus-community/helm-charts/kube-prometheus-stack-${local.kube_prometheus_stack.chart_version}/charts/kube-prometheus-stack/crds/crd-podmonitors.yaml",
    "https://raw.githubusercontent.com/prometheus-community/helm-charts/kube-prometheus-stack-${local.kube_prometheus_stack.chart_version}/charts/kube-prometheus-stack/crds/crd-probes.yaml",
    "https://raw.githubusercontent.com/prometheus-community/helm-charts/kube-prometheus-stack-${local.kube_prometheus_stack.chart_version}/charts/kube-prometheus-stack/crds/crd-prometheuses.yaml",
    "https://raw.githubusercontent.com/prometheus-community/helm-charts/kube-prometheus-stack-${local.kube_prometheus_stack.chart_version}/charts/kube-prometheus-stack/crds/crd-prometheusrules.yaml",
    "https://raw.githubusercontent.com/prometheus-community/helm-charts/kube-prometheus-stack-${local.kube_prometheus_stack.chart_version}/charts/kube-prometheus-stack/crds/crd-servicemonitors.yaml",
    "https://raw.githubusercontent.com/prometheus-community/helm-charts/kube-prometheus-stack-${local.kube_prometheus_stack.chart_version}/charts/kube-prometheus-stack/crds/crd-thanosrulers.yaml"
  ]
}

data "http" "kube_prometheus_stack_operator_crds" {
  for_each = (local.victoria_metrics_k8s_stack.enabled || local.kube_prometheus_stack.enabled) ? toset(local.kube_prometheus_stack_operator_crds) : []
  url      = each.key
}

resource "kubectl_manifest" "kube_prometheus_stack_operator_crds" {
  for_each          = (local.victoria_metrics_k8s_stack.enabled || local.kube_prometheus_stack.enabled) ? { for k, v in data.http.kube_prometheus_stack_operator_crds : yamldecode(v.body).metadata.name => v.body } : {}
  yaml_body         = each.value
  server_side_apply = true
}


locals {
  reloader = {
    name          = local.helm_releases[index(local.helm_releases.*.id, "reloader")].id
    enabled       = local.helm_releases[index(local.helm_releases.*.id, "reloader")].enabled
    chart         = local.helm_releases[index(local.helm_releases.*.id, "reloader")].chart
    repository    = local.helm_releases[index(local.helm_releases.*.id, "reloader")].repository
    chart_version = local.helm_releases[index(local.helm_releases.*.id, "reloader")].chart_version
    namespace     = local.helm_releases[index(local.helm_releases.*.id, "reloader")].namespace
  }
}

module "reloader_namespace" {
  count = local.reloader.enabled ? 1 : 0

  source = "../modules/eks-kubernetes-namespace"
  name   = local.reloader.namespace
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
                name = local.reloader.namespace
              }
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

resource "helm_release" "reloader" {
  count = local.reloader.enabled ? 1 : 0

  name        = local.reloader.name
  chart       = local.reloader.chart
  repository  = local.reloader.repository
  version     = local.reloader.chart_version
  namespace   = module.reloader_namespace[count.index].name
  max_history = var.helm_release_history_size
}


resource "kubernetes_storage_class" "advanced" {
  metadata {
    name = "advanced"
  }
  storage_provisioner    = "kubernetes.io/aws-ebs"
  reclaim_policy         = "Retain"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    type      = "gp2"
    fsType    = "ext4"
    encrypted = "true"
  }
}


locals {
  victoria_metrics_k8s_stack = {
    name          = local.helm_releases[index(local.helm_releases.*.id, "victoria-metrics-k8s-stack")].id
    enabled       = local.helm_releases[index(local.helm_releases.*.id, "victoria-metrics-k8s-stack")].enabled
    chart         = local.helm_releases[index(local.helm_releases.*.id, "victoria-metrics-k8s-stack")].chart
    repository    = local.helm_releases[index(local.helm_releases.*.id, "victoria-metrics-k8s-stack")].repository
    chart_version = local.helm_releases[index(local.helm_releases.*.id, "victoria-metrics-k8s-stack")].chart_version
    namespace     = local.helm_releases[index(local.helm_releases.*.id, "victoria-metrics-k8s-stack")].namespace
  }
  victoria_metrics_k8s_stack_grafana_oauth_type                   = ""
  victoria_metrics_k8s_stack_grafana_password                     = local.victoria_metrics_k8s_stack.enabled ? random_string.victoria_metrics_k8s_stack_grafana_password[0].result : ""
  victoria_metrics_k8s_stack_grafana_gitlab_client_id             = lookup(jsondecode(data.aws_secretsmanager_secret_version.infra.secret_string), "grafana_gitlab_client_id", "")
  victoria_metrics_k8s_stack_grafana_gitlab_client_secret         = lookup(jsondecode(data.aws_secretsmanager_secret_version.infra.secret_string), "grafana_gitlab_client_secret", "")
  victoria_metrics_k8s_stack_grafana_gitlab_group                 = lookup(jsondecode(data.aws_secretsmanager_secret_version.infra.secret_string), "grafana_gitlab_group", "")
  victoria_metrics_k8s_stack_grafana_github_client_id             = lookup(jsondecode(data.aws_secretsmanager_secret_version.infra.secret_string), "grafana_github_client_id", "")
  victoria_metrics_k8s_stack_grafana_github_client_secret         = lookup(jsondecode(data.aws_secretsmanager_secret_version.infra.secret_string), "grafana_github_client_secret", "")
  victoria_metrics_k8s_stack_grafana_github_team_ids              = lookup(jsondecode(data.aws_secretsmanager_secret_version.infra.secret_string), "grafana_github_team_ids", "")
  victoria_metrics_k8s_stack_grafana_github_allowed_organizations = lookup(jsondecode(data.aws_secretsmanager_secret_version.infra.secret_string), "grafana_github_allowed_organizations", "")
  victoria_metrics_k8s_stack_alertmanager_slack_webhook           = lookup(jsondecode(data.aws_secretsmanager_secret_version.infra.secret_string), "alertmanager_slack_webhook", "")
  victoria_metrics_k8s_stack_alertmanager_slack_channel           = lookup(jsondecode(data.aws_secretsmanager_secret_version.infra.secret_string), "alertmanager_slack_channel", "")
  victoria_metrics_k8s_stack_grafana_domain_name                  = "grafana-${local.domain_suffix}"
  victoria_metrics_k8s_stack_alertmanager_domain_name             = "alertmanager-${local.domain_suffix}"
  victoria_metrics_k8s_stack_values                               = <<VALUES
defaultRules:
  create: true
  rules:
    general: false
    kubernetesSystem: false
victoria-metrics-operator:
  createCRD: false
  operator:
    disable_prometheus_converter: false
    enable_converter_ownership: true
    useCustomConfigReloader: true
vmsingle:
  enabled: true
  spec:
    retentionPeriod: "14d"
    replicaCount: 1
    storage:
      storageClassName: advanced
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 30Gi
    resources:
      limits:
        cpu: "400m"
        memory: "1024Mi"
      requests:
        cpu: "200m"
        memory: "1024Mi"
    extraArgs:
      maxLabelsPerTimeseries: "50"
      search.maxConcurrentRequests: "8"
      search.maxQueryDuration: "10s"
      memory.allowedPercent: "80"
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: karpenter.sh/capacity-type
              operator: In
              values:
                - on-demand
vmagent:
  spec:
    extraArgs:
      promscrape.streamParse: "true"
      promscrape.maxScrapeSize: "335544320"
    resources:
      limits:
        cpu: "200m"