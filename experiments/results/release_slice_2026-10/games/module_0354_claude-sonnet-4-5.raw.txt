terraform {
  required_version = ">= 0.10.7"
}

provider "archive" {
  version = "1.0.0"
}

provider "external" {
  version = "1.0.0"
}

provider "ignition" {
  version = "1.0.0"
}

provider "local" {
  version = "1.0.0"
}

provider "null" {
  version = "1.0.0"
}

provider "random" {
  version = "1.0.0"
}

provider "template" {
  version = "1.0.0"
}

provider "tls" {
  version = "1.0.1"
}

locals {
  // The total amount of public CA certificates present in Tectonic.
  // That is all custom CAs + kube CA + etcd CA + ingress CA
  // This is a local constant, which needs to be dependency injected because TF cannot handle length() on computed values,
  // see https://github.com/hashicorp/terraform/issues/10857#issuecomment-268289775.
  tectonic_ca_count = "${length(var.tectonic_custom_ca_pem_list) + 3}"

  tectonic_http_proxy_enabled = "${length(var.tectonic_http_proxy_address) > 0}"
}

variable "tectonic_config_version" {
  description = <<EOF
(internal) This declares the version of the global configuration variables.
It has no impact on generated assets but declares the version contract of the configuration.
EOF

  default = "1.0"
}

variable "tectonic_image_re" {
  description = <<EOF
(internal) Regular expression used to extract repo and tag components
EOF

  type    = "string"
  default = "/^([^/]+/[^/]+/[^/]+):(.*)$/"
}

variable "tectonic_container_images" {
  description = "(internal) Container images to use"
  type        = "map"

  default = {
    addon_resizer                = "gcr.io/google_containers/addon-resizer:2.1"
    awscli                       = "quay.io/coreos/awscli:025a357f05242fdad6a81e8a6b520098aa65a600"
    gcloudsdk                    = "google/cloud-sdk:178.0.0-alpine"
    bootkube                     = "quay.io/coreos/bootkube:v0.8.1"
    calico                       = "quay.io/calico/node:v2.6.1"
    calico_cni                   = "quay.io/calico/cni:v1.11.0"
    console                      = "quay.io/coreos/tectonic-console:v6.0.5"
    error_server                 = "quay.io/coreos/tectonic-error-server:1.1"
    etcd                         = "quay.io/coreos/etcd:v3.1.8"
    etcd_operator                = "quay.io/coreos/etcd-operator:v0.5.0"
    flannel                      = "quay.io/coreos/flannel:v0.8.0-amd64"
    flannel_cni                  = "quay.io/coreos/flannel-cni:v0.2.0"
    heapster                     = "gcr.io/google_containers/heapster:v1.4.1"
    hyperkube                    = "quay.io/coreos/hyperkube:v1.9.6_coreos.0"
    identity                     = "quay.io/coreos/dex:v2.8.1"
    ingress_controller           = "quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.9.0-beta.17"
    kenc                         = "quay.io/coreos/kenc:0.0.2"
    kubedns                      = "gcr.io/google_containers/k8s-dns-kube-dns-amd64:1.14.8"
    kubednsmasq                  = "gcr.io/google_containers/k8s-dns-dnsmasq-nanny-amd64:1.14.8"
    kubedns_sidecar              = "gcr.io/google_containers/k8s-dns-sidecar-amd64:1.14.8"
    kube_version                 = "quay.io/coreos/kube-version:0.1.0"
    kube_version_operator        = "quay.io/coreos/kube-version-operator:v1.9.6-kvo.4"
    node_agent                   = "quay.io/coreos/node-agent:cd69b4a0f65b0d3a3b30edfce3bb184fd2a22c26"
    pod_checkpointer             = "quay.io/coreos/pod-checkpointer:e22cc0e3714378de92f45326474874eb602ca0ac"
    stats_emitter                = "quay.io/coreos/tectonic-stats:6e882361357fe4b773adbf279cddf48cb50164c1"
    stats_extender               = "quay.io/coreos/tectonic-stats-extender:487b3da4e175da96dabfb44fba65cdb8b823db2e"
    tectonic_channel_operator    = "quay.io/coreos/tectonic-channel-operator:0.6.4"
    tectonic_etcd_operator       = "quay.io/coreos/tectonic-etcd-operator:v0.0.2"
    tectonic_prometheus_operator = "quay.io/coreos/tectonic-prometheus-operator:v1.9.5"
    tectonic_cluo_operator       = "quay.io/coreos/tectonic-cluo-operator:v0.3.2"
    tectonic_torcx               = "quay.io/coreos/tectonic-torcx:v0.2.0"
    tectonic_alm_operator        = "quay.io/coreos/tectonic-alm-operator:v0.4.0"
  }
}

variable "tectonic_container_base_images" {
  description = "(internal) Base images of the components to use"
  type        = "map"

  default = {
    tectonic_monitoring_auth = "quay.io/coreos/tectonic-monitoring-auth"
    config_reload            = "quay.io/coreos/configmap-reload"
    addon_resizer            = "quay.io/coreos/addon-resizer"
    kube_state_metrics       = "quay.io/coreos/kube-state-metrics"
    grafana                  = "quay.io/coreos/monitoring-grafana"
    grafana_watcher          = "quay.io/coreos/grafana-watcher"
    prometheus_operator      = "quay.io/coreos/prometheus-operator"
    prometheus_config_reload = "quay.io/coreos/prometheus-config-reloader"
    prometheus               = "quay.io/prometheus/prometheus"
    alertmanager             = "quay.io/prometheus/alertmanager"
    node_exporter            = "quay.io/prometheus/node-exporter"
    kube_rbac_proxy          = "quay.io/coreos/kube-rbac-proxy"
  }
}

variable "tectonic_versions" {
  description = "(internal) Versions of the components to use"
  type        = "map"

  default = {
    etcd          = "3.1.8"
    kubernetes    = "1.9.6+tectonic.1"
    monitoring    = "1.9.5"
    tectonic      = "1.9.6-tectonic.1"
    tectonic-etcd = "0.0.1"
    cluo          = "0.3.2"
    alm           = "0.4.0"
  }
}

variable "tectonic_service_cidr" {
  type    = "string"
  default = "10.3.0.0/16"

  description = <<EOF
(optional) This declares the IP range to assign Kubernetes service cluster IPs in CIDR notation.
The maximum size of this IP range is /12
EOF
}

variable "tectonic_cluster_cidr" {
  type    = "string"
  default = "10.2.0.0/16"

  description = "(optional) This declares the IP range to assign Kubernetes pod IPs in CIDR notation."
}

variable "tectonic_master_count" {
  type    = "string"
  default = "1"

  description = <<EOF
The number of master nodes to be created.
This applies only to cloud platforms.
EOF
}

variable "tectonic_worker_count" {
  type    = "string"
  default = "3"

  description = <<EOF
The number of worker nodes to be created.
This applies only to cloud platforms.
EOF
}

variable "tectonic_etcd_count" {
  type    = "string"
  default = "0"

  description = <<EOF
The number of etcd nodes to be created.
If set to zero, the count of etcd nodes will be determined automatically.

Note: This is not supported on bare metal.
EOF
}

variable "tectonic_etcd_servers" {
  description = <<EOF
(optional) List of external etcd v3 servers to connect with (hostnames/IPs only).
Needs to be set if using an external etcd cluster.
Note: If this variable is defined, the installer will not create self-signed certs.
To provide a CA certificate to trust the etcd servers, set "tectonic_etcd_ca_cert_path".

Example: `["etcd1", "etcd2", "etcd3"]`
EOF

  type    = "list"
  default = []
}

variable "tectonic_etcd_tls_enabled" {
  default = true

  description = <<EOF
(optional) If set to `true`, all etcd endpoints will be configured to use the "https" scheme.

Note: If `tectonic_experimental` is set to `true` this variable has no effect, because the experimental self-hosted etcd always uses TLS.
EOF
}

variable "tectonic_etcd_ca_cert_path" {
  type    = "string"
  default = "/dev/null"

  description = <<EOF
(optional) The path of the file containing the CA certificate for TLS communication with etcd.

Note: This works only when used in conjunction with an external etcd cluster.
If set, the variable `tectonic_etcd_servers` must also be set.
EOF
}

variable "tectonic_etcd_client_cert_path" {
  type    = "string"
  default = "/dev/null"

  description = <<EOF
(optional) The path of the file containing the client certificate for TLS communication with etcd.

Note: This works only when used in conjunction with an external etcd cluster.
If set, the variables `tectonic_etcd_servers`, `tectonic_etcd_ca_cert_path`, and `tectonic_etcd_client_key_path` must also be set.
EOF
}

variable "tectonic_etcd_client_key_path" {
  type    = "string"
  default = "/dev/null"

  description = <<EOF
(optional) The path of the file containing the client key for TLS communication with etcd.

Note: This works only when used in conjunction with an external etcd cluster.
If set, the variables `tectonic_etcd_servers`, `tectonic_etcd_ca_cert_path`, and `tectonic_etcd_client_cert_path` must also be set.
EOF
}

variable "tectonic_base_domain" {
  type = "string"

  description = <<EOF
The base DNS domain of the cluster. It must NOT contain a trailing period. Some
DNS providers will automatically add this if necessary.

Example: `openstack.dev.coreos.systems`.

Note: This field MUST be set manually prior to creating the cluster.
This applies only to cloud platforms.

[Azure-specific NOTE]
To use Azure-provided DNS, `tectonic_base_domain` should be set to `""`
If using DNS records, ensure that `tectonic_base_domain` is set to a properly configured external DNS zone.
Instructions for configuring delegated domains for Azure DNS can be found here: https://docs.microsoft.com/en-us/azure/dns/dns-delegate-domain-azure-dns
EOF
}

variable "tectonic_cluster_name" {
  type = "string"

  description = <<EOF
The name of the cluster.
If used in a cloud-environment, this will be prepended to `tectonic_base_domain` resulting in the URL to the Tectonic console.

Note: This field MUST be set manually prior to creating the cluster.
Warning: Special characters in the name like '.' may cause errors on OpenStack platforms due to resource name constraints.
EOF
}

variable "tectonic_pull_secret_path" {
  type    = "string"
  default = ""

  description = <<EOF
The path the pull secret file in JSON format.
This is known to be a "Docker pull secret" as produced by the docker login [1] command.
A sample JSON content is shown in [2].
You can download the pull secret from your Account overview page at [3].

[1] https://docs.docker.com/engine/reference/commandline/login/

[2] https://coreos.com/os/docs/latest/registry-authentication.html#manual-registry-auth-setup

[3] https://account.coreos.com/overview

Note: This field MUST be set manually prior to creating the cluster unless `tectonic_vanilla_k8s` is set to `true`.
EOF
}

variable "tectonic_license_path" {
  type    = "string"
  default = ""

  description = <<EOF
The path to the tectonic licence file.
You can download the Tectonic license file from your Account overview page at [1].

[1] https://account.coreos.com/overview

Note: This field MUST be set manually prior to creating the cluster unless `tectonic_vanilla_k8s` is set to `true`.
EOF
}

variable "tectonic_container_linux_channel" {
  type    = "string"
  default = "stable"

  description = <<EOF
(optional) The Container Linux update channel.

Examples: `stable`, `beta`, `alpha`
EOF
}

variable "tectonic_container_linux_version" {
  type    = "string"
  default = "latest"

  description = <<EOF
The Container Linux version to use. Set to `latest` to select the latest available version for the selected update channel.

Examples: `latest`, `1465.6.0`
EOF
}

variable "tectonic_update_server" {
  type        = "string"
  default     = "https://tectonic.update.core-os.net"
  description = "(internal) The URL of the Tectonic Omaha update server"
}

variable "tectonic_update_channel" {
  type        = "string"
  default     = "tectonic-1.8-production"
  description = "(internal) The Tectonic Omaha update channel"
}

variable "tectonic_update_app_id" {
  type        = "string"
  default     = "6bc7b986-4654-4a0f-94b3-84ce6feb1db4"
  description = "(internal) The Tectonic Omaha update App ID"
}

variable "tectonic_admin_email" {
  type = "string"

  description = <<EOF
(internal) The e-mail address used to:
1. login as the admin user to the Tectonic Console.
2. generate DNS zones for some providers.

Note: This field MUST be in all lower-case e-mail address format and set manually prior to creating the cluster.
EOF
}

variable "tectonic_admin_password" {
  type = "string"

  description = <<EOF
(internal) The admin user password to login to the Tectonic Console.

Note: This field MUST be set manually prior to creating the cluster. Backslashes and double quotes must
also be escaped.
EOF
}

variable "tectonic_ca_cert" {
  type    = "string"
  default = ""

  description = <<EOF
(optional) The content of the PEM-encoded CA certificate, used to generate Tectonic Console's server certificate.
If left blank, a CA certificate will be automatically generated.
EOF
}

variable "tectonic_ca_key" {
  type    = "string"
  default = ""

  description = <<EOF
(optional) The content of the PEM-encoded CA key, used to generate Tectonic Console's server certificate.
This field is mandatory if `tectonic_ca_cert` is set.
EOF
}

variable "tectonic_ca_key_alg" {
  type    = "string"
  default = "RSA"

  description = <<EOF
(optional) The algorithm used to generate tectonic_ca_key.
The default value is currently recommended.
This field is mandatory if `tectonic_ca_cert` is set.
EOF
}

variable "tectonic_tls_validity_period" {
  type    = "string"
  default = "26280"

  description = <<EOF
Validity period of the self-signed certificates (in hours).
Default is 3 years.
This setting is ignored if user provided certificates are used.
EOF
}

variable "tectonic_vanilla_k8s" {
  default = false

  description = <<EOF
If set to true, a vanilla Kubernetes cluster will be deployed, omitting any Tectonic assets.
EOF
}

variable "tectonic_stats_url" {
  type        = "string"
  default     = "https://stats-collector.tectonic.com"
  description = "(internal) The Tectonic statistics collection URL to which to report."
}

variable "tectonic_ddns_server" {
  type    = "string"
  default = ""

  description = <<EOF
(optional) This only applies if you use the modules/dns/ddns module.

Specifies the RFC2136 Dynamic DNS server IP/host to register IP addresses to.
EOF
}

variable "tectonic_ddns_key_name" {
  type    = "string"
  default = ""

  description = <<EOF
(optional) This only applies if you use the modules/dns/ddns module.

Specifies the RFC2136 Dynamic DNS server key name.
EOF
}

variable "tectonic_ddns_key_algorithm" {
  type    = "string"
  default = ""

  description = <<EOF
(optional) This only applies if you use the modules/dns/ddns module.

Specifies the RFC2136 Dynamic DNS server key algorithm.
EOF
}

variable "tectonic_ddns_key_secret" {
  type    = "string"
  default = ""

  description = <<EOF
(optional) This only applies if you use the modules/dns/ddns module.

Specifies the RFC2136 Dynamic DNS server key secret.
EOF
}

variable "tectonic_networking" {
  default = "flannel"

  description = <<EOF
(optional) Configures the network to be used in Tectonic. One of the following values can be used:

- "flannel": enables overlay networking only. This is implemented by flannel using VXLAN.

- "canal": [ALPHA] enables overlay networking including network policy. Overlay is implemented by flannel using VXLAN. Network policy is implemented by Calico.

- "calico": [ALPHA] enables BGP based networking. Routing and network policy is implemented by Calico. Note this has been tested on baremetal installations only.
EOF
}

variable "tectonic_self_hosted_etcd" {
  default = ""

  description = <<EOF
(internal) [ALPHA] If set to one of the following values, self-hosted etcd is deployed:

- "enabled": Deploys a self-hosted etcd cluster.

- "pv_backup": Deploys a self-hosted etcd cluster including backups to Persistence Volumes.
`tectonic_etcd_backup_size` and `tectonic_etcd_backup_storage_class` must be configured when using this setting.
EOF
}

variable "tectonic_etcd_backup_size" {
  type        = "string"
  description = "(optional) The size in MB of the PersistentVolume used for handling etcd backups."
  default     = "512"
}

variable "tectonic_etcd_backup_storage_class" {
  type        = "string"
  default     = ""
  description = "(optional) The name of an existing Kubernetes StorageClass that will be used for handling etcd backups."
}

variable "tectonic_bootstrap_upgrade_cl" {
  type        = "string"
  default     = "true"
  description = "(internal) Whether to trigger a ContainerLinux upgrade on node bootstrap."
}

variable "tectonic_kubelet_debug_config" {
  type    = "string"
  default = ""

  description = "(internal) debug flags for the kubelet (used in CI only)"
}

variable "tectonic_custom_ca_pem_list" {
  type    = "list"
  default = []

  description = <<EOF
(optional) A list of PEM encoded CA files that will be installed in /etc/ssl/certs on etcd, master, and worker nodes.
EOF
}

variable "tectonic_iscsi_enabled" {
  type        = "string"
  default     = "false"
  description = "(optional) Start iscsid.service to enable iscsi volume attachment."
}

variable "tectonic_http_proxy_address" {
  type    = "string"
  default = ""

  description = <<EOF
(optional) HTTP proxy address.

Example: `http://myproxy.example.com`
EOF
}

variable "tectonic_https_proxy_address" {
  type    = "string"
  default = ""

  description = <<EOF
(optional) HTTPS proxy address.

Example: `http://myproxy.example.com`
EOF
}

variable "tectonic_no_proxy" {
  type    = "list"
  default = []

  description = <<EOF
(optional) List of local endpoints that will not use HTTP proxy.

Example: `["127.0.0.1","localhost",".example.com","10.3.0.1"]`
EOF
}

variable "tectonic_ntp_servers" {
  type    = "list"
  default = []

  description = <<EOF
(optional) If left blank, the default Container Linux NTP servers will be used.
A list of NTP servers to be used for time synchronization on the cluster nodes.
EOF
}

variable "tectonic_nfs_config_file" {
  type    = "string"
  default = ""

  description = <<EOF
(optional) the path to an NFS configuration file to be placed in /etc/conf.d/nfs
file on the CL nodes.
EOF
}

locals {
  _tectonic_nfs_config_file = "${var.tectonic_nfs_config_file != "" ? var.tectonic_nfs_config_file : "/dev/null"}"
}

variable "tectonic_proxy_exclusive_units" {
  default = false

  description = <<EOF
(optional) When set to true, it restricts the application of proxy settings to processes started through systemd units.
Global proxy settings will not be affected in this case.
When set to false, the proxy settings will apply globally, including to all processes lauched by users.
EOF
}


provider "aws" {
  region  = "${var.tectonic_aws_region}"
  profile = "${var.tectonic_aws_profile}"
  version = "1.7.0"
}

data "aws_availability_zones" "azs" {
  state = "available"
}

module "container_linux" {
  source = "../../modules/container_linux"

  release_channel = "${var.tectonic_container_linux_channel}"
  release_version = "${var.tectonic_container_linux_version}"
}

module "vpc" {
  source = "../../modules/aws/vpc"

  base_domain              = "${var.tectonic_base_domain}"
  cidr_block               = "${var.tectonic_aws_vpc_cidr_block}"
  cluster_id               = "${module.tectonic.cluster_id}"
  cluster_name             = "${var.tectonic_cluster_name}"
  custom_dns_name          = "${var.tectonic_dns_name}"
  enable_etcd_sg           = "${var.tectonic_self_hosted_etcd == "" && length(compact(var.tectonic_etcd_servers)) == 0 ? 1 : 0}"
  external_master_subnets  = "${compact(var.tectonic_aws_external_master_subnet_ids)}"
  external_vpc_id          = "${var.tectonic_aws_external_vpc_id}"
  external_worker_subnets  = "${compact(var.tectonic_aws_external_worker_subnet_ids)}"
  extra_tags               = "${var.tectonic_aws_extra_tags}"
  private_master_endpoints = "${var.tectonic_aws_private_endpoints}"
  public_master_endpoints  = "${var.tectonic_aws_public_endpoints}"

  master_az_count = "${length(keys(var.tectonic_aws_master_custom_subnets)) > 0 ? "${length(keys(var.tectonic_aws_master_custom_subnets))}" : "${length(data.aws_availability_zones.azs.names)}"}"
  worker_az_count = "${length(keys(var.tectonic_aws_worker_custom_subnets)) > 0 ? "${length(keys(var.tectonic_aws_worker_custom_subnets))}" : "${length(data.aws_availability_zones.azs.names)}"}"
  master_subnets = "${concat(values(var.tectonic_aws_master_custom_subnets),list("padding"))}"
  worker_subnets = "${concat(values(var.tectonic_aws_worker_custom_subnets),list("padding"))}"
  master_azs = "${ split("|", "${length(keys(var.tectonic_aws_master_custom_subnets))}" > 0 ?
    join("|", keys(var.tectonic_aws_master_custom_subnets)) :
    join("|", data.aws_availability_zones.azs.names)
  )}"
  worker_azs = "${ split("|", "${length(keys(var.tectonic_aws_worker_custom_subnets))}" > 0 ?
    join("|", keys(var.tectonic_aws_worker_custom_subnets)) :
    join("|", data.aws_availability_zones.azs.names)
  )}"
}

module "etcd" {
  source = "../../modules/aws/etcd"

  base_domain                = "${var.tectonic_base_domain}"
  cluster_id                 = "${module.tectonic.cluster_id}"
  cluster_name               = "${var.tectonic_cluster_name}"
  container_image            = "${var.tectonic_container_images["etcd"]}"
  container_linux_channel    = "${var.tectonic_container_linux_channel}"
  container_linux_version    = "${module.container_linux.version}"
  ec2_ami                    = "${var.tectonic_aws_ec2_ami_override}"
  ec2_type                   = "${var.tectonic_aws_etcd_ec2_type}"
  etcd_iam_role              = "${var.tectonic_aws_etcd_iam_role_name}"
  external_endpoints         = "${compact(var.tectonic_etcd_servers)}"
  extra_tags                 = "${var.tectonic_aws_extra_tags}"
  ign_etcd_crt_id_list       = "${module.ignition_masters.etcd_crt_id_list}"
  ign_etcd_dropin_id_list    = "${module.ignition_masters.etcd_dropin_id_list}"
  ign_ntp_dropin_id          = "${length(var.tectonic_ntp_servers) > 0 ? module.ignition_masters.ntp_dropin_id : ""}"
  ign_profile_env_id         = "${module.ignition_masters.profile_env_id}"
  ign_systemd_default_env_id = "${module.ignition_masters.systemd_default_env_id}"
  instance_count             = "${length(data.template_file.etcd_hostname_list.*.id)}"
  root_volume_iops           = "${var.tectonic_aws_etcd_root_volume_iops}"
  root_volume_size           = "${var.tectonic_aws_etcd_root_volume_size}"
  root_volume_type           = "${var.tectonic_aws_etcd_root_volume_type}"
  s3_bucket                  = "${aws_s3_bucket.tectonic.bucket}"
  sg_ids                     = "${concat(var.tectonic_aws_etcd_extra_sg_ids, list(module.vpc.etcd_sg_id))}"
  ssh_key                    = "${var.tectonic_aws_ssh_key}"
  subnets                    = "${module.vpc.worker_subnet_ids}"
  tls_enabled                = "${var.tectonic_etcd_tls_enabled}"
}

module "ignition_masters" {
  source = "../../modules/ignition"

  assets_location           = "${aws_s3_bucket_object.tectonic_assets.bucket}/${aws_s3_bucket_object.tectonic_assets.key}"
  base_domain               = "${var.tectonic_base_domain}"
  bootstrap_upgrade_cl      = "${var.tectonic_bootstrap_upgrade_cl}"
  cloud_provider            = "aws"
  cluster_name              = "${var.tectonic_cluster_name}"
  container_images          = "${var.tectonic_container_images}"
  custom_ca_cert_pem_list   = "${var.tectonic_custom_ca_pem_list}"
  etcd_advertise_name_list  = "${data.template_file.etcd_hostname_list.*.rendered}"
  etcd_ca_cert_pem          = "${module.etcd_certs.etcd_ca_crt_pem}"
  etcd_client_crt_pem       = "${module.etcd_certs.etcd_client_crt_pem}"
  etcd_client_key_pem       = "${module.etcd_certs.etcd_client_key_pem}"
  etcd_count                = "${length(data.template_file.etcd_hostname_list.*.id)}"
  etcd_initial_cluster_list = "${data.template_file.etcd_hostname_list.*.rendered}"
  etcd_peer_crt_pem         = "${module.etcd_certs.etcd_peer_crt_pem}"
  etcd_peer_key_pem         = "${module.etcd_certs.etcd_peer_key_pem}"
  etcd_server_crt_pem       = "${module.etcd_certs.etcd_server_crt_pem}"
  etcd_server_key_pem       = "${module.etcd_certs.etcd_server_key_pem}"
  etcd_tls_enabled          = "${var.tectonic_etcd_tls_enabled}"
  http_proxy                = "${var.tectonic_http_proxy_address}"
  http_proxy_enabled        = "${local.tectonic_http_proxy_enabled}"
  https_proxy               = "${var.tectonic_https_proxy_address}"
  image_re                  = "${var.tectonic_image_re}"
  ingress_ca_cert_pem       = "${module.ingress_certs.ca_cert_pem}"
  iscsi_enabled             = "${var.tectonic_iscsi_enabled}"
  kube_ca_cert_pem          = "${module.kube_certs.ca_cert_pem}"
  kube_dns_service_ip       = "${module.bootkube.kube_dns_service_ip}"
  kubeconfig_fetch_cmd      = "/opt/s3-puller.sh ${aws_s3_bucket_object.kubeconfig.bucket}/${aws_s3_bucket_object.kubeconfig.key} /etc/kubernetes/kubeconfig"
  kubelet_cni_bin_dir       = "${var.tectonic_networking == "calico" || var.tectonic_networking == "canal" ? "/var/lib/cni/bin" : "" }"
  kubelet_debug_config      = "${var.tectonic_kubelet_debug_config}"
  kubelet_node_label        = "node-role.kubernetes.io/master"
  kubelet_node_taints       = "node-role.kubernetes.io/master=:NoSchedule"
  nfs_config_file           = "${local._tectonic_nfs_config_file}"
  no_proxy                  = "${var.tectonic_no_proxy}"
  ntp_servers               = "${var.tectonic_ntp_servers}"
  proxy_exclusive_units     = "${var.tectonic_proxy_exclusive_units}"
  tectonic_vanilla_k8s      = "${var.tectonic_vanilla_k8s}"
}

module "masters" {
  source = "../../modules/aws/master-asg"

  assets_s3_location                   = "${aws_s3_bucket_object.tectonic_assets.bucket}/${aws_s3_bucket_object.tectonic_assets.key}"
  autoscaling_group_extra_tags         = "${var.tectonic_autoscaling_group_extra_tags}"
  aws_lbs                              = "${module.vpc.aws_lbs}"
  base_domain                          = "${var.tectonic_base_domain}"
  cluster_id                           = "${module.tectonic.cluster_id}"
  cluster_name                         = "${var.tectonic_cluster_name}"
  container_images                     = "${var.tectonic_container_images}"
  container_linux_channel              = "${var.tectonic_container_linux_channel}"
  container_linux_version              = "${module.container_linux.version}"
  ec2_ami                              = "${var.tectonic_aws_ec2_ami_override}"
  ec2_type                             = "${var.tectonic_aws_master_ec2_type}"
  extra_tags                           = "${var.tectonic_aws_extra_tags}"
  ign_bootkube_path_unit_id            = "${module.bootkube.systemd_path_unit_id}"
  ign_bootkube_service_id              = "${module.bootkube.systemd_service_id}"
  ign_ca_cert_id_list                  = "${module.ignition_masters.ca_cert_id_list}"
  ign_docker_dropin_id                 = "${module.ignition_masters.docker_dropin_id}"
  ign_init_assets_service_id           = "${module.ignition_masters.init_assets_service_id}"
  ign_installer_kubelet_env_id         = "${module.ignition_masters.installer_kubelet_env_id}"
  ign_installer_runtime_mappings_id    = "${module.ignition_masters.installer_runtime_mappings_id}"
  ign_iscsi_service_id                 = "${module.ignition_masters.iscsi_service_id}"
  ign_k8s_node_bootstrap_service_id    = "${module.ignition_masters.k8s_node_bootstrap_service_id}"
  ign_kubelet_service_id               = "${module.ignition_masters.kubelet_service_id}"
  ign_locksmithd_service_id            = "${module.ignition_masters.locksmithd_service_id}"
  ign_max_user_watches_id              = "${module.ignition_masters.max_user_watches_id}"
  ign_nfs_config_id                    = "${var.tectonic_nfs_config_file != "" ? module.ignition_masters.nfs_config_id : ""}"
  ign_ntp_dropin_id                    = "${length(var.tectonic_ntp_servers) > 0 ? module.ignition_masters.ntp_dropin_id : ""}"
  ign_profile_env_id                   = "${module.ignition_masters.profile_env_id}"
  ign_rm_assets_path_unit_id           = "${module.ignition_masters.rm_assets_path_unit_id}"
  ign_rm_assets_service_id             = "${module.ignition_masters.rm_assets_service_id}"
  ign_s3_puller_id                     = "${module.ignition_masters.s3_puller_id}"
  ign_systemd_default_env_id           = "${module.ignition_masters.systemd_default_env_id}"
  ign_tectonic_path_unit_id            = "${var.tectonic_vanilla_k8s ? "" : module.tectonic.systemd_path_unit_id}"
  ign_tectonic_service_id              = "${module.tectonic.systemd_service_id}"
  ign_update_ca_certificates_dropin_id = "${module.ignition_masters.update_ca_certificates_dropin_id}"
  instance_count                       = "${var.tectonic_master_count}"
  master_iam_role                      = "${var.tectonic_aws_master_iam_role_name}"
  master_sg_ids                        = "${concat(var.tectonic_aws_master_extra_sg_ids, list(module.vpc.master_sg_id))}"
  private_endpoints                    = "${var.tectonic_aws_private_endpoints}"
  public_endpoints                     = "${var.tectonic_aws_public_endpoints}"
  root_volume_iops                     = "${var.tectonic_aws_master_root_volume_iops}"
  root_volume_size                     = "${var.tectonic_aws_master_root_volume_size}"
  root_volume_type                     = "${var.tectonic_aws_master_root_volume_type}"
  s3_bucket                            = "${aws_s3_bucket.tectonic.bucket}"
  ssh_key                              = "${var.tectonic_aws_ssh_key}"
  subnet_ids                           = "${module.vpc.master_subnet_ids}"
}

module "ignition_workers" {
  source = "../../modules/ignition"

  bootstrap_upgrade_cl    = "${var.tectonic_bootstrap_upgrade_cl}"
  cloud_provider          = "aws"
  container_images        = "${var.tectonic_container_images}"
  custom_ca_cert_pem_list = "${var.tectonic_custom_ca_pem_list}"
  etcd_ca_cert_pem        = "${module.etcd_certs.etcd_ca_crt_pem}"
  http_proxy              = "${var.tectonic_http_proxy_address}"
  http_proxy_enabled      = "${local.tectonic_http_proxy_enabled}"
  https_proxy             = "${var.tectonic_https_proxy_address}"
  image_re                = "${var.tectonic_image_re}"
  ingress_ca_cert_pem     = "${module.ingress_certs.ca_cert_pem}"
  iscsi_enabled           = "${var.tectonic_iscsi_enabled}"
  kube_ca_cert_pem        = "${module.kube_certs.ca_cert_pem}"
  kube_dns_service_ip     = "${module.bootkube.kube_dns_service_ip}"
  kubeconfig_fetch_cmd    = "/opt/s3-puller.sh ${aws_s3_bucket_object.kubeconfig.bucket}/${aws_s3_bucket_object.kubeconfig.key} /etc/kubernetes/kubeconfig"
  kubelet_cni_bin_dir     = "${var.tectonic_networking == "calico" || var.tectonic_networking == "canal" ? "/var/lib/cni/bin" : "" }"
  kubelet_debug_config    = "${var.tectonic_kubelet_debug_config}"
  kubelet_node_label      = "node-role.kubernetes.io/node"
  kubelet_node_taints     = ""
  nfs_config_file         = "${local._tectonic_nfs_config_file}"
  no_proxy                = "${var.tectonic_no_proxy}"
  ntp_servers             = "${var.tectonic_ntp_servers}"
  proxy_exclusive_units   = "${var.tectonic_proxy_exclusive_units}"
  tectonic_vanilla_k8s    = "${var.tectonic_vanilla_k8s}"
}

module "workers" {
  source = "../../modules/aws/worker-asg"

  autoscaling_group_extra_tags         = "${var.tectonic_autoscaling_group_extra_tags}"
  cluster_id                           = "${module.tectonic.cluster_id}"
  cluster_name                         = "${var.tectonic_cluster_name}"
  container_linux_channel              = "${var.tectonic_container_linux_channel}"
  container_linux_version              = "${module.container_linux.version}"
  ec2_ami                              = "${var.tectonic_aws_ec2_ami_override}"
  ec2_type                             = "${var.tectonic_aws_worker_ec2_type}"
  extra_tags                           = "${var.tectonic_aws_extra_tags}"
  ign_ca_cert_id_list                  = "${module.ignition_masters.ca_cert_id_list}"
  ign_docker_dropin_id                 = "${module.ignition_workers.docker_dropin_id}"
  ign_installer_kubelet_env_id         = "${module.ignition_workers.installer_kubelet_env_id}"
  ign_installer_runtime_mappings_id    = "${module.ignition_workers.installer_runtime_mappings_id}"
  ign_iscsi_service_id                 = "${module.ignition_workers.iscsi_service_id}"
  ign_k8s_node_bootstrap_service_id    = "${module.ignition_workers.k8s_node_bootstrap_service_id}"
  ign_kubelet_service_id               = "${module.ignition_workers.kubelet_service_id}"
  ign_locksmithd_service_id            = "${module.ignition_workers.locksmithd_service_id}"
  ign_max_user_watches_id              = "${module.ignition_workers.max_user_watches_id}"
  ign_nfs_config_id                    = "${var.tectonic_nfs_config_file != "" ? module.ignition_workers.nfs_config_id : ""}"
  ign_ntp_dropin_id                    = "${length(var.tectonic_ntp_servers) > 0 ? module.ignition_workers.ntp_dropin_id : ""}"
  ign_profile_env_id                   = "${module.ignition_workers.profile_env_id}"
  ign_s3_puller_id                     = "${module.ignition_workers.s3_puller_id}"
  ign_systemd_default_env_id           = "${module.ignition_workers.systemd_default_env_id}"
  ign_update_ca_certificates_dropin_id = "${module.ignition_workers.update_ca_certificates_dropin_id}"
  instance_count                       = "${var.tectonic_worker_count}"
  load_balancers                       = "${var.tectonic_aws_worker_load_balancers}"
  root_volume_iops                     = "${var.tectonic_aws_worker_root_volume_iops}"
  root_volume_size                     = "${var.tectonic_aws_worker_root_volume_size}"
  root_volume_type                     = "${var.tectonic_aws_worker_root_volume_type}"
  s3_bucket                            = "${aws_s3_bucket.tectonic.bucket}"
  sg_ids                               = "${concat(var.tectonic_aws_worker_extra_sg_ids, list(module.vpc.worker_sg_id))}"
  ssh_key                              = "${var.tectonic_aws_ssh_key}"
  subnet_ids                           = "${module.vpc.worker_subnet_ids}"
  vpc_id                               = "${module.vpc.vpc_id}"
  worker_iam_role                      = "${var.tectonic_aws_worker_iam_role_name}"
}

module "dns" {
  source = "../../modules/dns/route53"

  api_external_elb_dns_name      = "${module.vpc.aws_api_external_dns_name}"
  api_external_elb_zone_id       = "${module.vpc.aws_elb_api_external_zone_id}"
  api_internal_elb_dns_name      = "${module.vpc.aws_api_internal_dns_name}"
  api_internal_elb_zone_id       = "${module.vpc.aws_elb_api_internal_zone_id}"
  api_ip_addresses               = "${module.vpc.aws_lbs}"
  base_domain                    = "${var.tectonic_base_domain}"
  cluster_id                     = "${module.tectonic.cluster_id}"
  cluster_name                   = "${var.tectonic_cluster_name}"
  console_elb_dns_name           = "${module.vpc.aws_console_dns_name}"
  console_elb_zone_id            = "${module.vpc.aws_elb_console_zone_id}"
  custom_dns_name                = "${var.tectonic_dns_name}"
  elb_alias_enabled              = true
  etcd_count                     = "${length(data.template_file.etcd_hostname_list.*.id)}"
  etcd_ip_addresses              = "${module.etcd.ip_addresses}"
  external_endpoints             = ["${compact(var.tectonic_etcd_servers)}"]
  master_count                   = "${var.tectonic_master_count}"
  tectonic_external_private_zone = "${var.tectonic_aws_external_private_zone}"
  tectonic_external_vpc_id       = "${module.vpc.vpc_id}"
  tectonic_extra_tags            = "${var.tectonic_aws_extra_tags}"
  tectonic_private_endpoints     = "${var.tectonic_aws_private_endpoints}"
  tectonic_public_endpoints      = "${var.tectonic_aws_public_endpoints}"
  tectonic_vanilla_k8s           = "${var.tectonic_vanilla_k8s}"
}


data "aws_region" "current" {
  current = true
}

resource "aws_kms_key" "tectonic" {
  description             = "Tectonic S3 bucket encryption key for ${var.tectonic_cluster_name}"
  deletion_window_in_days = 7

  tags = "${merge(map(
      "Name", "${var.tectonic_cluster_name}-tectonic-kms",
      "KubernetesCluster", "${var.tectonic_cluster_name}",
      "tectonicClusterID", "${module.tectonic.cluster_id}"
    ), var.tectonic_aws_extra_tags)}"
}

resource "aws_s3_bucket" "tectonic" {
  bucket = "${var.tectonic_aws_assets_s3_bucket_name == "" ? format("%s%s-%s", "a", var.tectonic_cluster_name, md5(format("%s-%s", data.aws_region.current.name , var.tectonic_base_domain))) : var.tectonic_aws_assets_s3_bucket_name }"

  acl = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = "${aws_kms_key.tectonic.arn}"
      }
    }
  }

  logging {
    target_bucket = "${aws_s3_bucket.tectonic_logs.id}"
    target_prefix = "log/"
  }

  lifecycle_rule {
    enabled = true

    noncurrent_version_expiration {
      days = 90
    }
  }

  tags = "${merge(map(
      "Name", "${var.tectonic_cluster_name}-tectonic",
      "KubernetesCluster", "${var.tectonic_cluster_name}",
      "tectonicClusterID", "${module.tectonic.cluster_id}"
    ), var.tectonic_aws_extra_tags)}"

  lifecycle {
    ignore_changes = ["*"]
  }
}

resource "aws_s3_bucket_public_access_block" "tectonic" {
  bucket = "${aws_s3_bucket.tectonic.id}"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "tectonic_logs" {
  bucket = "${var.tectonic_aws_assets_s3_bucket_name == "" ? format("%s%s-%s-logs", "a", var.tectonic_cluster_name, md5(format("%s-%s", data.aws_region.current.name , var.tectonic_base_domain))) : format("%s-logs", var.tectonic_aws_assets_s3_bucket_name) }"

  acl = "log-delivery-write"

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm     = "aws:kms"
        kms_master_key_id = "${aws_kms_key.tectonic.arn}"
      }
    }
  }

  lifecycle_rule {
    enabled = true

    expiration {
      days = 90
    }
  }

  tags = "${merge(map(
      "Name", "${var.tectonic_cluster_name}-tectonic-logs",
      "KubernetesCluster", "${var.tectonic_cluster_name}",
      "tectonicClusterID", "${module.tectonic.cluster_id}"
    ), var.tectonic_aws_extra_tags)}"

  lifecycle {
    ignore_changes = ["*"]
  }
}

resource "aws_s3_bucket_public_access_block" "tectonic_logs" {
  bucket = "${aws_s3_bucket.tectonic_logs.id}"

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_object" "tectonic_assets" {
  bucket = "${aws_s3_bucket.tectonic.bucket}"
  key    = "assets.zip"
  source = "${data.archive_file.assets.output_path}"
  acl    = "private"

  server_side_encryption = "aws:kms"
  kms_key_id             = "${aws_kms_key.tectonic.arn}"

  tags = "${merge(map(
      "Name", "${var.tectonic_cluster_name}-tectonic-assets",
      "KubernetesCluster", "${var.tectonic_cluster_name}",
      "tectonicClusterID", "${module.tectonic.cluster_id}"
    ), var.tectonic_aws_extra_tags)}"

  lifecycle {
    ignore_changes = ["*"]
  }
}

resource "aws_s3_bucket_object" "kubeconfig" {
  bucket  = "${aws_s3_bucket.tectonic.bucket}"
  key     = "kubeconfig"
  content = "${module.bootkube.kubeconfig}"
  acl     = "private"

  server_side_encryption = "aws:kms"
  kms_key_id             = "${aws_kms_key.tectonic.arn}"

  tags = "${merge(map(
      "Name", "${var.tectonic_cluster_name}-kubeconfig",
      "KubernetesCluster", "${var.tectonic_cluster_name}",
      "tectonicClusterID", "${module.tectonic.cluster_id}"
    ), var.tectonic_aws_extra_tags)}"
}


data "template_file" "etcd_hostname_list" {
  count    = "${var.tectonic_self_hosted_etcd != "" ? 0 : var.tectonic_etcd_count > 0 ? var.tectonic_etcd_count : length(data.aws_availability_zones.azs.names) == 5 ? 5 : 3}"
  template = "${var.tectonic_cluster_name}-etcd-${count.index}.${var.tectonic_base_domain}"
}

module "bootkube" {
  source         = "../../modules/bootkube"
  cloud_provider = "aws"

  cluster_name = "${var.tectonic_cluster_name}"

  kube_apiserver_url = "https://${var.tectonic_aws_private_endpoints ? module.dns.api_internal_fqdn : module.dns.api_external_fqdn}:443"
  oidc_issuer_url    = "https://${var.tectonic_aws_private_endpoints ? module.dns.ingress_internal_fqdn : module.dns.ingress_external_fqdn}/identity"

  container_images = "${var.tectonic_container_images}"
  versions         = "${var.tectonic_versions}"
  self_hosted_etcd = "${var.tectonic_self_hosted_etcd}"

  service_cidr = "${var.tectonic_service_cidr}"
  cluster_cidr = "${var.tectonic_cluster_cidr}"

  advertise_address = "0.0.0.0"
  anonymous_auth    = "false"

  oidc_username_claim = "email"
  oidc_groups_claim   = "groups"
  oidc_client_id      = "tectonic-kubectl"
  oidc_ca_cert        = "${module.ingress_certs.ca_cert_pem}"

  apiserver_cert_pem   = "${module.kube_certs.apiserver_cert_pem}"
  apiserver_key_pem    = "${module.kube_certs.apiserver_key_pem}"
  etcd_ca_cert_pem     = "${module.etcd_certs.etcd_ca_crt_pem}"
  etcd_client_cert_pem = "${module.etcd_certs.etcd_client_crt_pem}"
  etcd_client_key_pem  = "${module.etcd_certs.etcd_client_key_pem}"
  etcd_peer_cert_pem   = "${module.etcd_certs.etcd_peer_crt_pem}"
  etcd_peer_key_pem    = "${module.etcd_certs.etcd_peer_key_pem}"
  etcd_server_cert_pem = "${module.etcd_certs.etcd_server_crt_pem}"
  etcd_server_key_pem  = "${module.etcd_certs.etcd_server_key_pem}"
  kube_ca_cert_pem     = "${module.kube_certs.ca_cert_pem}"
  kubelet_cert_pem     = "${module.kube_certs.kubelet_cert_pem}"
  kubelet_key_pem      = "${module.kube_certs.kubelet_key_pem}"

  etcd_backup_size          = "${var.tectonic_etcd_backup_size}"
  etcd_backup_storage_class = "${var.tectonic_etcd_backup_storage_class}"
  etcd_endpoints            = "${module.dns.etcd_endpoints}"
  master_count              = "${var.tectonic_master_count}"

  node_monitor_grace_period = "2m"

  pod_eviction_timeout = "220s"

  cloud_config_path = ""
}

module "tectonic" {
  source   = "../../modules/tectonic"
  platform = "aws"

  cluster_name = "${var.tectonic_cluster_name}"

  base_address       = "${var.tectonic_aws_private_endpoints ? module.dns.ingress_internal_fqdn : module.dns.ingress_external_fqdn}"
  kube_apiserver_url = "https://${var.tectonic_aws_private_endpoints ? module.dns.api_internal_fqdn : module.dns.api_external_fqdn}:443"
  service_cidr       = "${var.tectonic_service_cidr}"

  container_images      = "${var.tectonic_container_images}"
  container_base_images = "${var.tectonic_container_base_images}"
  versions              = "${var.tectonic_versions}"

  license_path     = "${var.tectonic_vanilla_k8s ? "/dev/null" : pathexpand(var.tectonic_license_path)}"
  pull_secret_path = "${var.tectonic_vanilla_k8s ? "/dev/null" : pathexpand(var.tectonic_pull_secret_path)}"

  admin_email    = "${var.tectonic_admin_email}"
  admin_password = "${var.tectonic_admin_password}"

  update_channel = "${var.tectonic_update_channel}"
  update_app_id  = "${var.tectonic_update_app_id}"
  update_server  = "${var.tectonic_update_server}"

  ca_generated = "${var.tectonic_ca_cert == "" ? false : true}"
  ca_cert      = "${module.kube_certs.ca_cert_pem}"

  ingress_ca_cert_pem = "${module.ingress_certs.ca_cert_pem}"
  ingress_cert_pem    = "${module.ingress_certs.cert_pem}"
  ingress_key_pem     = "${module.ingress_certs.key_pem}"

  identity_client_cert_pem = "${module.identity_certs.client_cert_pem}"
  identity_client_key_pem  = "${module.identity_certs.client_key_pem}"
  identity_server_cert_pem = "${module.identity_certs.server_cert_pem}"
  identity_server_key_pem  = "${module.identity_certs.server_key_pem}"

  console_client_id = "tectonic-console"
  kubectl_client_id = "tectonic-kubectl"
  ingress_kind      = "NodePort"
  self_hosted_etcd  = "${var.tectonic_self_hosted_etcd}"
  master_count      = "${var.tectonic_master_count}"
  stats_url         = "${var.tectonic_stats_url}"

  image_re = "${var.tectonic_image_re}"
}

module "flannel_vxlan" {
  source = "../../modules/net/flannel_vxlan"

  cluster_cidr     = "${var.tectonic_cluster_cidr}"
  enabled          = "${var.tectonic_networking == "flannel"}"
  container_images = "${var.tectonic_container_images}"
}

module "calico" {
  source = "../../modules/net/calico"

  container_images = "${var.tectonic_container_images}"
  cluster_cidr     = "${var.tectonic_cluster_cidr}"
  enabled          = "${var.tectonic_networking == "calico"}"
}

module "canal" {
  source = "../../modules/net/canal"

  container_images = "${var.tectonic_container_images}"
  cluster_cidr     = "${var.tectonic_cluster_cidr}"
  enabled          = "${var.tectonic_networking == "canal"}"
}

data "archive_file" "assets" {
  type       = "zip"
  source_dir = "./generated/"

  output_path = "./.terraform/generated_${sha1("${module.etcd_certs.id} ${module.tectonic.id} ${module.bootkube.id} ${module.flannel_vxlan.id} ${module.calico.id} ${module.canal.id}")}.zip"
}


module "kube_certs" {
  source = "../../modules/tls/kube/self-signed"

  ca_cert_pem        = "${var.tectonic_ca_cert}"
  ca_key_alg         = "${var.tectonic_ca_key_alg}"
  ca_key_pem         = "${var.tectonic_ca_key}"
  kube_apiserver_url = "https://${var.tectonic_aws_private_endpoints ? module.dns.api_internal_fqdn : module.dns.api_external_fqdn}:443"
  service_cidr       = "${var.tectonic_service_cidr}"
  validity_period    = "${var.tectonic_tls_validity_period}"
}

module "etcd_certs" {
  source = "../../modules/tls/etcd/signed"

  etcd_ca_cert_path     = "${var.tectonic_etcd_ca_cert_path}"
  etcd_cert_dns_names   = "${data.template_file.etcd_hostname_list.*.rendered}"
  etcd_client_cert_path = "${var.tectonic_etcd_client_cert_path}"
  etcd_client_key_path  = "${var.tectonic_etcd_client_key_path}"
  self_signed           = "${var.tectonic_self_hosted_etcd != "" ? "true" : length(compact(var.tectonic_etcd_servers)) == 0 ? "true" : "false"}"
  service_cidr          = "${var.tectonic_service_cidr}"
}

module "ingress_certs" {
  source = "../../modules/tls/ingress/self-signed"

  base_address    = "${var.tectonic_aws_private_endpoints ? module.dns.ingress_internal_fqdn : module.dns.ingress_external_fqdn}"
  ca_cert_pem     = "${module.kube_certs.ca_cert_pem}"
  ca_key_alg      = "${module.kube_certs.ca_key_alg}"
  ca_key_pem      = "${module.kube_certs.ca_key_pem}"
  validity_period = "${var.tectonic_tls_validity_period}"
}

module "identity_certs" {
  source = "../../modules/tls/identity/self-signed"

  ca_cert_pem     = "${module.kube_certs.ca_cert_pem}"
  ca_key_alg      = "${module.kube_certs.ca_key_alg}"
  ca_key_pem      = "${module.kube_certs.ca_key_pem}"
  validity_period = "${var.tectonic_tls_validity_period}"
}


variable "tectonic_aws_config_version" {
  description = <<EOF
(internal) This declares the version of the AWS configuration variables.
It has no impact on generated assets but declares the version contract of the configuration.
EOF

  default = "1.0"
}

variable "tectonic_aws_profile" {
  description = <<EOF
(optional) This declares the AWS credentials profile to use.
EOF

  type    = "string"
  default = "default"
}

variable "tectonic_aws_ssh_key" {
  type        = "string"
  description = "Name of an SSH key located within the AWS region. Example: coreos-user."
}

variable "tectonic_aws_master_ec2_type" {
  type        = "string"
  description = "Instance size for the master node(s). Example: `t2.medium`."
  default     = "t2.medium"
}

variable "tectonic_aws_worker_ec2_type" {
  type        = "string"
  description = "Instance size for the worker node(s). Example: `t2.medium`."
  default     = "t2.medium"
}

variable "tectonic_aws_etcd_ec2_type" {
  type = "string"

  description = <<EOF
  Instance size for the etcd node(s). Example: `t2.medium`. Read the [etcd recommended hardware](https://coreos.com/etcd/docs/latest/op-guide/hardware.html) guide for best performance
  EOF

  default = "t2.medium"
}

variable "tectonic_aws_ec2_ami_override" {
  type        = "string"
  description = "(optional) AMI override for all nodes. Example: `ami-foobar123`."
  default     = ""
}

variable "tectonic_aws_etcd_extra_sg_ids" {
  description = <<EOF
(optional) List of additional security group IDs for etcd nodes.

Example: `["sg-51530134", "sg-b253d7cc"]`
EOF

  type    = "list"
  default = []
}

variable "tectonic_aws_assets_s3_bucket_name" {
  type    = "string"
  default = ""

  description = <<EOF
(optional) Unique name under which the Amazon S3 bucket will be created. Bucket name must start with a lower case name and is limited to 63 characters.
The Tectonic Installer uses the bucket to store tectonic assets and kubeconfig.
If name is not provided the installer will construct the name using "tectonic_cluster_name", current AWS region and "tectonic_base_domain"
EOF
}

variable "tectonic_aws_master_extra_sg_ids" {
  description = <<EOF
(optional) List of additional security group IDs for master nodes.

Example: `["sg-51530134", "sg-b253d7cc"]`
EOF

  type    = "list"
  default = []
}

variable "tectonic_aws_worker_extra_sg_ids" {
  description = <<EOF
(optional) List of additional security group IDs for worker nodes.

Example: `["sg-51530134", "sg-b253d7cc"]`
EOF

  type    = "list"
  default = []
}

variable "tectonic_aws_vpc_cidr_block" {
  type    = "string"
  default = "10.0.0.0/16"

  description = <<EOF
Block of IP addresses used by the VPC.
This should not overlap with any other networks, such as a private datacenter connected via Direct Connect.
EOF
}

variable "tectonic_aws_external_vpc_id" {
  type = "string"

  description = <<EOF
(optional) ID of an existing VPC to launch nodes into.
If unset a new VPC is created.

Example: `vpc-123456`
EOF

  default = ""
}

variable "tectonic_aws_private_endpoints" {
  default = true

  description = <<EOF
(optional) If set to true, create private-facing ingress resources (ELB, A-records).
If set to false, no private-facing ingress resources will be provisioned and all DNS records will be created in the public Route53 zone.
EOF
}

variable "tectonic_aws_public_endpoints" {
  default = true

  description = <<EOF
(optional) If set to true, create public-facing ingress resources (ELB, A-records).
If set to false, no public-facing ingress resources will be created.
EOF
}

variable "tectonic_aws_external_private_zone" {
  default = ""

  description = <<EOF
(optional) If set, the given Route53 zone ID will be used as the internal (private) zone.
This zone will be used to create etcd DNS records as well as internal API and internal Ingress records.
If set, no additional private zone will be created.

Example: `"Z1ILINNUJGTAO1"`
EOF
}

variable "tectonic_aws_external_master_subnet_ids" {
  type = "list"

  description = <<EOF
(optional) List of subnet IDs within an existing VPC to deploy master nodes into.
Required to use an existing VPC and the list must match the AZ count.

Example: `["subnet-111111", "subnet-222222", "subnet-333333"]`
EOF

  default = []
}

variable "tectonic_aws_external_worker_subnet_ids" {
  type = "list"

  description = <<EOF
(optional) List of subnet IDs within an existing VPC to deploy worker nodes into.
Required to use an existing VPC and the list must match the AZ count.

Example: `["subnet-111111", "subnet-222222", "subnet-333333"]`
EOF

  default = []
}

variable "tectonic_aws_extra_tags" {
  type        = "map"
  description = "(optional) Extra AWS tags to be applied to created resources."
  default     = {}
}

variable "tectonic_autoscaling_group_extra_tags" {
  type    = "list"
  default = []

  description = <<EOF
(optional) Extra AWS tags to be applied to created autoscaling group resources.
This is a list of maps having the keys `key`, `value` and `propagate_at_launch`.

Example: `[ { key = "foo", value = "bar", propagate_at_launch = true } ]`
EOF
}

variable "tectonic_dns_name" {
  type        = "string"
  default     = ""
  description = "(optional) DNS prefix used to construct the console and API server endpoints."
}

variable "tectonic_aws_etcd_root_volume_type" {
  type        = "string"
  default     = "gp2"
  description = "The type of volume for the root block device of etcd nodes."
}

variable "tectonic_aws_etcd_root_volume_size" {
  type        = "string"
  default     = "30"
  description = "The size of the volume in gigabytes for the root block device of etcd nodes."
}

variable "tectonic_aws_etcd_root_volume_iops" {
  type    = "string"
  default = "100"

  description = <<EOF
The amount of provisioned IOPS for the root block device of etcd nodes.
Ignored if the volume type is not io1.
EOF
}

variable "tectonic_aws_master_root_volume_type" {
  type        = "string"
  default     = "gp2"
  description = "The type of volume for the root block device of master nodes."
}

variable "tectonic_aws_master_root_volume_size" {
  type        = "string"
  default     = "30"
  description = "The size of the volume in gigabytes for the root block device of master nodes."
}

variable "tectonic_aws_master_root_volume_iops" {
  type    = "string"
  default = "100"

  description = <<EOF
The amount of provisioned IOPS for the root block device of master nodes.
Ignored if the volume type is not io1.
EOF
}

variable "tectonic_aws_worker_root_volume_type" {
  type        = "string"
  default     = "gp2"
  description = "The type of volume for the root block device of worker nodes."
}

variable "tectonic_aws_worker_root_volume_size" {
  type        = "string"
  default     = "30"
  description = "The size of the volume in gigabytes for the root block device of worker nodes."
}

variable "tectonic_aws_worker_root_volume_iops" {
  type    = "string"
  default = "100"

  description = <<EOF
The amount of provisioned IOPS for the root block device of worker nodes.
Ignored if the volume type is not io1.
EOF
}

variable "tectonic_aws_master_custom_subnets" {
  type    = "map"
  default = {}

  description = <<EOF
(optional) This configures master availability zones and their corresponding subnet CIDRs directly.

Example:
`{ eu-west-1a = "10.0.0.0/20", eu-west-1b = "10.0.16.0/20" }`
EOF
}

variable "tectonic_aws_worker_custom_subnets" {
  type    = "map"
  default = {}

  description = <<EOF
(optional) This configures worker availability zones and their corresponding subnet CIDRs directly.

Example: `{ eu-west-1a = "10.0.64.0/20", eu-west-1b = "10.0.80.0/20" }`
EOF
}

variable "tectonic_aws_region" {
  type        = "string"
  default     = "eu-west-1"
  description = "The target AWS region for the cluster."
}

variable "tectonic_aws_master_iam_role_name" {
  type    = "string"
  default = ""

  description = <<EOF
(optional) Name of IAM role to use for the instance profiles of master nodes.
The name is also the last part of a role's ARN.

Example:
 * Role ARN  = arn:aws:iam::123456789012:role/tectonic-installer
 * Role Name = tectonic-installer
EOF
}

variable "tectonic_aws_worker_iam_role_name" {
  type    = "string"
  default = ""

  description = <<EOF
(optional) Name of IAM role to use for the instance profiles of worker nodes.
The name is also the last part of a role's ARN.

Example:
 * Role ARN  = arn:aws:iam::123456789012:role/tectonic-installer
 * Role Name = tectonic-installer
EOF
}

variable "tectonic_aws_etcd_iam_role_name" {
  type    = "string"
  default = ""

  description = <<EOF
(optional) Name of IAM role to use for the instance profiles of etcd nodes.
The name is also the last part of a role's ARN.

Example:
 * Role ARN  = arn:aws:iam::123456789012:role/tectonic-installer
 * Role Name = tectonic-installer
EOF
}

variable "tectonic_aws_worker_load_balancers" {
  type    = "list"
  default = []

  description = <<EOF
(optional) List of ELBs to attach all worker instances to.
This is useful for exposing NodePort services via load-balancers managed separately from the cluster.

Example:
 * `["ingress-nginx"]`
EOF
}