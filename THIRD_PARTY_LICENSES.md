# Third-Party Licenses

TerraRepair-Bench redistributes Terraform modules written by third parties. This file lists, for each of the 262 corpus modules used in the `release_slice_2026-10` run, the repository it came from and that repository's license, grouped by license.

## Modified files

The modules in `data/terrads_sample/` are copies of the `.tf` files in each repository's module directory, cloned from the repository's default branch by `scripts/sample_terrads.py` between March and September 2026 (the sampler was written in March 2026 and the modules were committed to this repository in September 2026; the exact commit cloned was not recorded). Their contents were not edited (exceptions: 4 modules had CRLF line endings converted to LF on extraction, and 6 modules contain a file that is a symlink in the repository and was copied as the file it points to).

**The files in the benchmark results are modified versions of these modules.** Each `experiments/results/*/games/<module>_<model>.repaired.tf` (and the code inside the matching `.raw.txt`) was produced by a large language model asked to repair security misconfigurations in the original module. These modified files were generated automatically, have not been reviewed by the original authors, and are not endorsed by them. They carry the license of the repository the module came from.

## Source and how this list was built

- Modules were selected from **TerraDS v1** (Bühler et al., MSR 2025; Zenodo record [14217386](https://zenodo.org/records/14217386), DOI 10.5281/zenodo.14217386, `TerraDS.sqlite` md5 `92e2fffd8208b2a290204555ec500977`). TerraDS itself is licensed CC BY 4.0.
- Licenses are **as stored in TerraDS** (`Repositories.License`, SPDX identifiers). TerraDS recorded them in its 2024 snapshot; they were not re-checked against the repositories' current state.
- Every module was verified by cloning its repository and confirming that the module directory's `.tf` file names and contents are identical to the copy in `data/terrads_sample/` at a specific commit. All 262 modules matched. For each, `data/terrads_provenance.csv` gives a `verified_commit`: the first commit, checking the TerraDS-recorded commit, then current HEAD, then the rest of the default branch's history, at which the module's files are identical to the corpus copy. It is a commit with identical content, not necessarily the one that was cloned. Full details are in `data/terrads_provenance_verification.json`.

## Copyleft licenses

TerraDS stores copyleft licenses for 21 corpus modules: **MPL-2.0** (9 modules, 2 repositories), **GPL-3.0** (7 modules, 1 repository), and **AGPL-3.0** (5 modules, 1 repository). Earlier project documentation described all TerraDS repositories as permissively licensed. That was incorrect for these modules.

Each copyleft module, and every LLM repair of it, is distributed under its source repository's license and not under the dataset's CC BY 4.0 license. The repaired files are modified versions of the originals. They were generated automatically, the original authors have not reviewed them, and the change is described above. The full text of each copyleft license is in `LICENSES/`. The source of every original module is the repository and commit listed in `data/terrads_provenance.csv`.

## Summary

| License | Repositories | Modules |
|---|---:|---:|
| [Apache-2.0](https://spdx.org/licenses/Apache-2.0.html) | 18 | 129 |
| [MIT](https://spdx.org/licenses/MIT.html) | 13 | 112 |
| [MPL-2.0](https://spdx.org/licenses/MPL-2.0.html) | 2 | 9 |
| [GPL-3.0](https://spdx.org/licenses/GPL-3.0.html) | 1 | 7 |
| [AGPL-3.0](https://spdx.org/licenses/AGPL-3.0.html) | 1 | 5 |
| **Total** | **35** | **262** |

## Apache-2.0

License text: https://spdx.org/licenses/Apache-2.0.html

### aws-ia/terraform-aws-control_tower_account_factory

- Repository: https://github.com/aws-ia/terraform-aws-control_tower_account_factory
- Commit recorded by TerraDS: `380c67bee4437eb7a132870665e18de534251217`
- Modules (7): `module_0336` (`modules/aft-account-provisioning-framework`), `module_0337` (`modules/aft-account-request-framework`), `module_0338` (`modules/aft-backend`), `module_0339` (`modules/aft-code-repositories`), `module_0340` (`modules/aft-customizations`), `module_0341` (`modules/aft-feature-options`), `module_0343` (`modules/aft-lambda-layer`)

### aws-ia/terraform-aws-eks-blueprints

- Repository: https://github.com/aws-ia/terraform-aws-eks-blueprints
- Commit recorded by TerraDS: `1f09f5c9f4746a64c4acd15b871cca0cb5f7531b`
- Modules (13): `module_0035` (`patterns/blue-green-upgrade/environment`), `module_0036` (`patterns/blue-green-upgrade/modules/eks_cluster`), `module_0037` (`patterns/bottlerocket`), `module_0038` (`patterns/external-secrets`), `module_0039` (`patterns/gitops/multi-cluster-hub-spoke-argocd/hub`), `module_0040` (`patterns/gitops/multi-cluster-hub-spoke-argocd/spokes`), `module_0041` (`patterns/kubecost`), `module_0042` (`patterns/privatelink-access`), `module_0043` (`patterns/sso-iam-identity-center`), `module_0044` (`patterns/tls-with-aws-pca-issuer`), `module_0045` (`patterns/vpc-lattice/client-server-communication`), `module_0046` (`patterns/vpc-lattice/cross-cluster-pod-communication/cluster`), `module_0047` (`patterns/vpc-lattice/cross-cluster-pod-communication/environment`)

### awslabs/data-on-eks

- Repository: https://github.com/awslabs/data-on-eks
- Commit recorded by TerraDS: `2be29e5da652d3a5581eeaca8d872a3480700138`
- Modules (9): `module_0365` (`analytics/terraform/emr-eks-karpenter`), `module_0366` (`analytics/terraform/spark-k8s-operator`), `module_0367` (`distributed-databases/cloudnative-postgres`), `module_0370` (`schedulers/terraform/argo-workflow`), `module_0371` (`schedulers/terraform/managed-airflow-mwaa`), `module_0372` (`schedulers/terraform/self-managed-airflow`), `module_0373` (`streaming/emr-eks-flink`), `module_0375` (`streaming/kafka`), `module_0376` (`streaming/nifi`)

### chadgeary/cloudblock

- Repository: https://github.com/chadgeary/cloudblock
- Commit recorded by TerraDS: `585d09b2c699f2ffe5b0f384f1fb26eee37b3213`
- Modules (3): `module_0176` (`aws`), `module_0177` (`etc/aws-two-instances`), `module_0178` (`lightsail`)

### cloudposse/terraform-aws-components

- Repository: https://github.com/cloudposse/terraform-aws-components
- Commit recorded by TerraDS: `e3c4ffd7559b1db9c06cae0131ac7c332fca06f0`
- Modules (37): `module_0403` (`deprecated/aws/aws-metrics-role`), `module_0404` (`deprecated/aws/backing-services`), `module_0405` (`deprecated/aws/bootstrap`), `module_0406` (`deprecated/aws/ecs`), `module_0407` (`deprecated/aws/kops-aws-platform`), `module_0408` (`deprecated/aws/sentry`), `module_0410` (`deprecated/aws/teleport`), `module_0411` (`deprecated/eks/karpenter`), `module_0412` (`deprecated/github-actions-runner`), `module_0413` (`deprecated/iam-delegated-roles`), `module_0414` (`deprecated/iam-primary-roles`), `module_0415` (`deprecated/securityhub/securityhub/common`), `module_0417` (`deprecated/spacelift-worker-pool`), `module_0418` (`deprecated/sso/modules/okta-user`), `module_0419` (`modules/api-gateway-rest-api`), `module_0420` (`modules/aurora-mysql`), `module_0421` (`modules/aurora-postgres`), `module_0423` (`modules/aws-saml/modules/okta-user`), `module_0425` (`modules/aws-sso`), `module_0426` (`modules/aws-ssosync`), `module_0427` (`modules/aws-team-roles`), `module_0428` (`modules/aws-teams`), `module_0429` (`modules/bastion`), `module_0430` (`modules/cloudtrail`), `module_0432` (`modules/datadog-logs-archive`), `module_0433` (`modules/dns-delegated`), `module_0435` (`modules/ecs`), `module_0436` (`modules/ecs-service`), `module_0437` (`modules/eks/cluster`), `module_0438` (`modules/eks/karpenter`), `module_0439` (`modules/github-runners`), `module_0440` (`modules/github-runners/modules/graceful_scale_in`), `module_0441` (`modules/guardduty`), `module_0443` (`modules/security-hub`), `module_0444` (`modules/spa-s3-cloudfront`), `module_0445` (`modules/spacelift/worker-pool`), `module_0446` (`modules/tfstate-backend`)

### cloudposse/terraform-aws-eks-cluster

- Repository: https://github.com/cloudposse/terraform-aws-eks-cluster
- Commit recorded by TerraDS: `89688f6783f5b4edd6612f61fa1647141e10ca28`
- Modules (2): `module_0400` (`.`), `module_0401` (`examples/complete`)

### coreos/tectonic-installer

- Repository: https://github.com/coreos/tectonic-installer
- Commit recorded by TerraDS: `d8309a9ed214f754f62da0dc5ac427c7c1faa9ca`
- Modules (10): `module_0345` (`contrib/govcloud`), `module_0346` (`contrib/internal-cluster`), `module_0347` (`modules/aws/etcd`), `module_0348` (`modules/aws/master-asg`), `module_0350` (`modules/aws/worker-asg`), `module_0351` (`modules/govcloud/etcd`), `module_0352` (`modules/govcloud/master-asg`), `module_0353` (`modules/govcloud/worker-asg`), `module_0354` (`platforms/aws`), `module_0355` (`platforms/govcloud`)

### hashicorp/terraform-aws-vault

- Repository: https://github.com/hashicorp/terraform-aws-vault
- Commit recorded by TerraDS: `96afcb4ad7166182ef33398d54db5eaa9d1f79c3`
- Modules (7): `module_0315` (`examples/vault-agent`), `module_0316` (`examples/vault-auto-unseal`), `module_0317` (`examples/vault-ec2-auth`), `module_0318` (`examples/vault-iam-auth`), `module_0319` (`.`), `module_0320` (`modules/vault-cluster`), `module_0321` (`modules/vault-elb`)

### HXSecurity/TerraformGoat

- Repository: https://github.com/HXSecurity/TerraformGoat
- Commit recorded by TerraDS: `0d436fa553e56c548bfc51fd973660ece82d5b61`
- Modules (6): `module_0390` (`aws/ec2/console_takeover`), `module_0391` (`aws/s3/bucket_acl_writable`), `module_0392` (`aws/s3/bucket_object_traversal`), `module_0393` (`aws/s3/object_acl_writable`), `module_0394` (`aws/s3/special_bucket_policy`), `module_0395` (`aws/s3/unrestricted_file_upload`)

### kubernetes/k8s.io

- Repository: https://github.com/kubernetes/k8s.io
- Commit recorded by TerraDS: `f1e44e2e2ecc4c2df9be8638cefd22a8c3bf590f`
- Modules (10): `module_0207` (`infra/aws/terraform/artifacts.k8s.io/s3`), `module_0209` (`infra/aws/terraform/cdn.packages.k8s.io`), `module_0211` (`infra/aws/terraform/management-account`), `module_0212` (`infra/aws/terraform/modules/eks-prow-iam`), `module_0214` (`infra/aws/terraform/policy-staging-account-1`), `module_0215` (`infra/aws/terraform/prow-build-cluster`), `module_0216` (`infra/aws/terraform/registry-k8s-io-prod`), `module_0217` (`infra/aws/terraform/registry-sandbox-k8s-io-image-layers`), `module_0218` (`infra/aws/terraform/registry.k8s.io/s3`), `module_0219` (`infra/aws/terraform/test-artifacts.k8s.io/s3`)

### maddevsio/aws-eks-base

- Repository: https://github.com/maddevsio/aws-eks-base
- Commit recorded by TerraDS: `15ad5fa2827e0915048b75d06e7f3c8d4650df62`
- Modules (3): `module_0332` (`terraform/layer1-aws`), `module_0333` (`terraform/layer2-k8s`), `module_0334` (`terraform/modules/aws-pritunl`)

### terraform-aws-modules/terraform-aws-ec2-instance

- Repository: https://github.com/terraform-aws-modules/terraform-aws-ec2-instance
- Commit recorded by TerraDS: `29230f956912d751a01a5694510f684754a93196`
- Modules (2): `module_0195` (`examples/complete`), `module_0197` (`.`)

### terraform-aws-modules/terraform-aws-ecs

- Repository: https://github.com/terraform-aws-modules/terraform-aws-ecs
- Commit recorded by TerraDS: `3b70e1e46e1b96a2da7fbfe6e2c11d44009607f1`
- Modules (2): `module_0388` (`modules/cluster`), `module_0389` (`modules/service`)

### terraform-aws-modules/terraform-aws-eks

- Repository: https://github.com/terraform-aws-modules/terraform-aws-eks
- Commit recorded by TerraDS: `c60b70fbc80606eb4ed8cf47063ac6ed0d8dd435`
- Modules (3): `module_0002` (`.`), `module_0007` (`tests/eks-managed-node-group`), `module_0008` (`tests/self-managed-node-group`)

### terraform-aws-modules/terraform-aws-lambda

- Repository: https://github.com/terraform-aws-modules/terraform-aws-lambda
- Commit recorded by TerraDS: `1d122404c2a3834ce39a7c5a319a3e754d5b0c29`
- Modules (3): `module_0154` (`examples/complete`), `module_0155` (`examples/event-source-mapping`), `module_0156` (`.`)

### terraform-aws-modules/terraform-aws-rds

- Repository: https://github.com/terraform-aws-modules/terraform-aws-rds
- Commit recorded by TerraDS: `a76a3cd92220b91eaa467a5328db6f2c21e1fdee`
- Modules (4): `module_0160` (`examples/complete-mssql`), `module_0161` (`examples/enhanced-monitoring`), `module_0162` (`examples/s3-import-mysql`), `module_0163` (`modules/db_instance`)

### terraform-aws-modules/terraform-aws-s3-bucket

- Repository: https://github.com/terraform-aws-modules/terraform-aws-s3-bucket
- Commit recorded by TerraDS: `8a0b697adfbc673e6135c70246cff7f8052ad95a`
- Modules (3): `module_0396` (`examples/complete`), `module_0397` (`examples/s3-replication`), `module_0398` (`.`)

### ViktorUJ/cks

- Repository: https://github.com/ViktorUJ/cks
- Commit recorded by TerraDS: `4a559d410c026c9156c61ffbe3e5d1a5b59f0763`
- Modules (5): `module_0171` (`terraform/modules/eks`), `module_0172` (`terraform/modules/k8s_self_managment`), `module_0173` (`terraform/modules/vpc`), `module_0174` (`terraform/modules/work_pc`), `module_0175` (`terraform/modules/worker_lfcs`)

## MIT

License text: https://spdx.org/licenses/MIT.html

### antonputra/tutorials

- Repository: https://github.com/antonputra/tutorials
- Commit recorded by TerraDS: `e9e9390e86e40dd5946849abd0596e948fe642de`
- Modules (55): `module_0048` (`lessons/020`), `module_0049` (`lessons/038/terraform`), `module_0050` (`lessons/063`), `module_0051` (`lessons/089/terraform`), `module_0052` (`lessons/090/terraform`), `module_0053` (`lessons/091/terraform`), `module_0054` (`lessons/099/terraform`), `module_0055` (`lessons/102/terraform`), `module_0056` (`lessons/104/terraform`), `module_0057` (`lessons/105/aws-terraform`), `module_0058` (`lessons/112/terraform`), `module_0059` (`lessons/113/terraform`), `module_0060` (`lessons/114/terraform`), `module_0061` (`lessons/115/terraform`), `module_0062` (`lessons/116/terraform`), `module_0063` (`lessons/117/terraform`), `module_0065` (`lessons/119/terraform`), `module_0066` (`lessons/121/terraform`), `module_0067` (`lessons/122/terraform`), `module_0069` (`lessons/126/terraform`), `module_0073` (`lessons/130/terraform`), `module_0075` (`lessons/133/terraform`), `module_0076` (`lessons/134/terraform`), `module_0077` (`lessons/135/terraform`), `module_0078` (`lessons/136/terraform`), `module_0079` (`lessons/138/terraform`), `module_0080` (`lessons/139/0-terraform`), `module_0081` (`lessons/140/terraform`), `module_0082` (`lessons/142/terraform`), `module_0083` (`lessons/143/terraform`), `module_0084` (`lessons/144/terraform`), `module_0085` (`lessons/145/terraform`), `module_0087` (`lessons/147/terraform`), `module_0088` (`lessons/149/terraform`), `module_0089` (`lessons/150/terraform`), `module_0091` (`lessons/152/terraform`), `module_0093` (`lessons/154/terraform`), `module_0094` (`lessons/155/eks-terraform`), `module_0095` (`lessons/156/terraform`), `module_0096` (`lessons/160/git-infrastructure-modules/eks`), `module_0098` (`lessons/160/git-infrastructure-modules/vpc`), `module_0099` (`lessons/160/infrastructure-live-v1/dev/vpc`), `module_0100` (`lessons/160/infrastructure-live-v1/staging/vpc`), `module_0101` (`lessons/160/infrastructure-modules/eks`), `module_0103` (`lessons/160/infrastructure-modules/vpc`), `module_0104` (`lessons/164`), `module_0105` (`lessons/165/1-example`), `module_0106` (`lessons/165/global/s3`), `module_0107` (`lessons/166/terraform`), `module_0108` (`lessons/167/terraform`), `module_0109` (`lessons/175/terraform`), `module_0110` (`lessons/194/terraform`), `module_0111` (`lessons/195/terraform`), `module_0112` (`lessons/196/terraform`), `module_0113` (`lessons/200/terraform`)

### arminc/terraform-ecs

- Repository: https://github.com/arminc/terraform-ecs
- Commit recorded by TerraDS: `38f562cee06f95048565c557a7b698ab5e31da94`
- Modules (3): `module_0179` (`modules/alb`), `module_0180` (`modules/ecs`), `module_0182` (`modules/ecs_instances`)

### brikis98/terraform-up-and-running-code

- Repository: https://github.com/brikis98/terraform-up-and-running-code
- Commit recorded by TerraDS: `27a3beaf842dbe2a582e29f64373dfb793374ba8`
- Modules (19): `module_0013` (`code/terraform/02-intro-to-terraform-syntax/webserver-cluster`), `module_0014` (`code/terraform/03-terraform-state/file-layout-example/global/s3`), `module_0015` (`code/terraform/03-terraform-state/file-layout-example/stage/services/webserver-cluster`), `module_0016` (`code/terraform/04-terraform-module/module-example/modules/services/webserver-cluster`), `module_0017` (`code/terraform/05-tips-and-tricks/loops-and-if-statements/live/global/three-iam-users-unique-names`), `module_0018` (`code/terraform/05-tips-and-tricks/loops-and-if-statements/modules/services/webserver-cluster`), `module_0019` (`code/terraform/05-tips-and-tricks/zero-downtime-deployment/modules/services/webserver-cluster`), `module_0020` (`code/terraform/05-tips-and-tricks/zero-downtime-deployment/modules/services/webserver-cluster-instance-refresh`), `module_0021` (`code/terraform/06-managing-secrets-with-terraform/ec2-iam-role`), `module_0022` (`code/terraform/06-managing-secrets-with-terraform/github-actions-oidc`), `module_0023` (`code/terraform/06-managing-secrets-with-terraform/kms-cmk`), `module_0024` (`code/terraform/07-working-with-multiple-providers/modules/services/eks-cluster`), `module_0025` (`code/terraform/08-production-grade-infrastructure/more-than-terraform/remote-exec-provisioner`), `module_0026` (`code/terraform/08-production-grade-infrastructure/small-modules/modules/cluster/asg-rolling-deploy`), `module_0027` (`code/terraform/08-production-grade-infrastructure/small-modules/modules/networking/alb`), `module_0029` (`code/terraform/09-testing-terraform-code/modules/cluster/asg-rolling-deploy`), `module_0030` (`code/terraform/09-testing-terraform-code/modules/networking/alb`), `module_0032` (`code/terraform/10-terraform-team/modules/cluster/asg-rolling-deploy`), `module_0033` (`code/terraform/10-terraform-team/modules/networking/alb`)

### cattle-ops/terraform-aws-gitlab-runner

- Repository: https://github.com/cattle-ops/terraform-aws-gitlab-runner
- Commit recorded by TerraDS: `745fc46508b27ea382a321da7f7530192fbc91fb`
- Modules (1): `module_0385` (`.`)

### chime/terraform-aws-alternat

- Repository: https://github.com/chime/terraform-aws-alternat
- Commit recorded by TerraDS: `0d7aa377fe5ccdf9d3ef213f2ae40e134553670e`
- Modules (1): `module_0152` (`.`)

### futurice/terraform-examples

- Repository: https://github.com/futurice/terraform-examples
- Commit recorded by TerraDS: `c191f7bcb0fa786b68c7b3904b6f3bbb90881fc6`
- Modules (7): `module_0198` (`aws/aws_ec2_ebs_docker_host`), `module_0199` (`aws/aws_lambda_api`), `module_0200` (`aws/aws_lambda_cronjob`), `module_0201` (`aws/aws_reverse_proxy`), `module_0202` (`aws/aws_static_site`), `module_0203` (`aws/aws_vpc_msk`), `module_0204` (`aws/static_website_ssl_cloudfront_private_s3`)

### kz8s/tack

- Repository: https://github.com/kz8s/tack
- Commit recorded by TerraDS: `10bc69869881f20335051430ba45b553caabe5b4`
- Modules (1): `module_0206` (`modules/vpc`)

### ministryofjustice/modernisation-platform

- Repository: https://github.com/ministryofjustice/modernisation-platform
- Commit recorded by TerraDS: `e703c2084bcbb072cb879d4fb59f32ec49c06deb`
- Modules (6): `module_0224` (`terraform/environments/bootstrap/member-bootstrap`), `module_0226` (`terraform/environments/bootstrap/single-sign-on`), `module_0236` (`terraform/environments/core-logging`), `module_0237` (`terraform/environments/core-network-services`), `module_0240` (`terraform/environments/core-shared-services`), `module_0299` (`terraform/modernisation-platform-account`)

### ned1313/Getting-Started-Terraform

- Repository: https://github.com/ned1313/Getting-Started-Terraform
- Commit recorded by TerraDS: `8e90313f09c1393a4f781c8610b4b9b810da1e59`
- Modules (4): `module_0378` (`base_web_app`), `module_0379` (`m4_solution`), `module_0380` (`m5_solution`), `module_0381` (`m6_solution`)

### nozaq/terraform-aws-secure-baseline

- Repository: https://github.com/nozaq/terraform-aws-secure-baseline
- Commit recorded by TerraDS: `6b2d679cf480093ec279450d7d0a90affe3ddc43`
- Modules (4): `module_0143` (`examples/external-bucket`), `module_0145` (`modules/cloudtrail-baseline`), `module_0148` (`modules/secure-bucket`), `module_0150` (`modules/vpc-baseline`)

### philips-labs/terraform-aws-github-runner

- Repository: https://github.com/philips-labs/terraform-aws-github-runner
- Commit recorded by TerraDS: `61108a9bb5f1e4ee2cfa233e7df0f8c1fe7faaec`
- Modules (6): `module_0114` (`modules/ami-housekeeper`), `module_0115` (`modules/lambda`), `module_0116` (`modules/runner-binaries-syncer`), `module_0118` (`modules/runners`), `module_0119` (`modules/runners/pool`), `module_0122` (`modules/webhook`)

### poseidon/typhoon

- Repository: https://github.com/poseidon/typhoon
- Commit recorded by TerraDS: `c72e99834cfee6dcdb55332a868b8bc03fcc3375`
- Modules (2): `module_0127` (`aws/fedora-coreos/kubernetes/workers`), `module_0129` (`aws/flatcar-linux/kubernetes/workers`)

### segmentio/stack

- Repository: https://github.com/segmentio/stack
- Commit recorded by TerraDS: `76da16f2e0fdcfaf62f5b4d3ecca2d77c1a09ee8`
- Modules (3): `module_0123` (`ecs-cluster`), `module_0124` (`rds-cluster`), `module_0125` (`vpc`)

## MPL-2.0

License text: https://spdx.org/licenses/MPL-2.0.html

### hashicorp/best-practices

- Repository: https://github.com/hashicorp/best-practices
- Commit recorded by TerraDS: `1589fedc72c4486affa0c28ed5a67ca424c2f367`
- Modules (3): `module_0130` (`terraform/modules/aws/compute/nodejs`), `module_0131` (`terraform/modules/aws/data/vault`), `module_0134` (`terraform/modules/aws/util/website`)

### hashicorp/terraform-guides

- Repository: https://github.com/hashicorp/terraform-guides
- Commit recorded by TerraDS: `38d077a6da77fffe5f8469e992fe79a852339871`
- Modules (6): `module_0136` (`infrastructure-as-code/dynamic-aws-creds-from-vault`), `module_0137` (`infrastructure-as-code/k8s-cluster-openshift-aws/modules/openshift`), `module_0138` (`infrastructure-as-code/s3-buckets-and-policies`), `module_0139` (`infrastructure-as-code/sagemaker-notebook`), `module_0140` (`infrastructure-as-code/terraform-0.12-examples/first-class-expressions`), `module_0141` (`infrastructure-as-code/terraform-0.12-examples/for-expressions`)

## GPL-3.0

License text: https://spdx.org/licenses/GPL-3.0.html

### Coalfire-Research/Red-Baron

- Repository: https://github.com/Coalfire-Research/Red-Baron
- Commit recorded by TerraDS: `d62c7a52586870636e4fdc1aa2b9e68d20878736`
- Modules (7): `module_0164` (`modules/aws/create-vpc`), `module_0165` (`modules/aws/dns-c2`), `module_0166` (`modules/aws/dns-rdir`), `module_0167` (`modules/aws/http-c2`), `module_0168` (`modules/aws/http-rdir`), `module_0169` (`modules/aws/phishing-server`), `module_0170` (`modules/aws/smtp`)

## AGPL-3.0

License text: https://spdx.org/licenses/AGPL-3.0.html

### nccgroup/sadcloud

- Repository: https://github.com/nccgroup/sadcloud
- Commit recorded by TerraDS: `f538652921a7f3e8e25c0afaecad2d4382f8b21e`
- Modules (5): `module_0326` (`modules/aws/cloudtrail`), `module_0327` (`modules/aws/elasticsearch`), `module_0328` (`modules/aws/elbv2`), `module_0329` (`modules/aws/iam`), `module_0330` (`modules/aws/network`)
