```hcl
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
    pod_checkpointer             = "quay.io/coreos/pod-checkpointer:e22cc03714378de92f45326474874eb602ca0ac"
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
  _tectonic_nfs_config_file = "${var.tectonic_nfs_config_file!= ""? var.tectonic_nfs_config_file : "/dev/null"}"
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
  enable_etcd_sg           = "${var.tectonic_self_hosted_etcd == "" && length(compact(var.tectonic_etcd_servers)) == 0? 1 : 0}"
  external_master_subnets  = "${compact(var.tectonic_aws_external_master_subnet_ids)}"
  external_vpc_id          = "${var.tectonic_aws_external_vpc_id}"
  external_worker_subnets  = "${compact(var.tectonic_aws_external_worker_subnet_ids)}"
  extra_tags               = "${var.tectonic_aws_extra_tags}"
  private_master_endpoints = "${var.tectonic_aws_private_endpoints}"
  public_master_endpoints  = "${var.tectonic_aws_public_endpoints}"

  master_az_count = "${length(keys(var.tectonic_aws_master_custom_subnets)) > 0? "${length(keys(var.tectonic_aws_master_custom_subnets))}" : "${length(data.aws_availability_zones.azs.names)}"}"
  worker_az_count = "${length(keys(var.tectonic_aws_worker_custom_subnets)) > 0? "${length(keys(var.tectonic_aws_worker_custom_subnets))}" : "${length(data.aws_availability_zones.azs.names)}"}"
  master_subnets = "${concat(values(var.tectonic_aws_master_custom_subnets),list("padding"))}"
  worker_subnets = "${concat(values(var.tectonic_aws_worker_custom_subnets),list("padding"))}"
  master_azs = "${ split("|", "${length(keys(var.tectonic_aws_master_custom_subnets))}" > 0?
    join("|", keys(var.tectonic_aws_master_custom_subnets)) :
    join("|", data.aws_availability_zones.azs.names)
  }"
  worker_azs = "${ split("|", "${length(keys(var.tectonic_aws_worker_custom_subnets))}" > 0?
    join("|", keys(var.tectonic_aws_worker_custom_subnets)) :
    join("|", data.aws_availability_zones.azs.names)
  }"
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
  ign_ntp_dropin_id          = "${length(var.tectonic_ntp_servers) > 0? module.ignition_masters.ntp_dropin_id : ""}"
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
  etcd_peer_key_pem          = "${module.etcd_certs.etcd_peer_key_pem}"
  etcd_server_crt_pem        = "${module.etcd_certs.etcd_server_crt_pem}"
  etcd_server_key_pem        = "${module.etcd_certs.etcd_server_key_pem}"
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
  kubelet_cni_bin_dir       = "${var.tectonic_networking == "calico" || var.tectonic_networking == "canal"? "/var/lib/cni/bin" : "" }"
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
  ign_nfs_config_id                    = "${var.tectonic_nfs_config_file!= ""? module.ignition_masters.nfs_config_id : ""}"
  ign_ntp_dropin_id                    = "${length(var.tectonic_ntp_servers) > 0? module.ignition_masters.ntp_dropin_id : ""}"
  ign_profile_env_id                   = "${module.ignition_masters.profile_env_id}"
  ign_rm_assets_path_unit_id           = "${module.ignition_masters.rm_assets_path_unit_id}"
  ign_rm_assets_service_id             = "${module.ignition_masters.rm_assets_service_id}"
  ign_s3_puller_id                     = "${module.ignition_masters.s3_puller_id}"
  ign_systemd_default_env_id           = "${module.ignition_masters.systemd_default_env_id}"
  ign_tectonic_path_unit_id            = "${var.tectonic_vanilla_k8s? "" : module.tectonic.systemd_path_unit_id}"
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
  kubelet_cni_bin_dir     = "${var.tectonic_networking == "calico" || var.tectonic_networking == "canal"? "/var/lib/cni/bin" : "" }"
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
  ign_nfs_config_id                    = "${var.tectonic_nfs_config_file!= ""? module.ignition_workers.nfs_config_id : ""}"
  ign_ntp_dropin_id                    = "${length(var.tectonic_ntp_servers) > 0? module.ignition_workers.ntp_dropin_id : ""}"
  ign_profile_env_id                   = "${module.ignition_workers.profile_env_id}"
  ign_s3_puller_id                     = "${module.ignition