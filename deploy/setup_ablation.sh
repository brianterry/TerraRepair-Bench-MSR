#!/usr/bin/env bash
# One-time (idempotent) setup for the RETRIEVAL ABLATION Fargate run in your
# AWS account (set ACCOUNT_ID). Mirrors deploy/setup.sh but:
#   - family terrarepair-ablation, entrypoint container_entrypoint_ablation.sh
#   - results prefix terrarepair/retrieval_ablation
#
# Builds/pushes the image (same image, ablation entrypoint baked in), ensures
# S3 bucket + IAM roles + log group + default ECS cluster, registers the ablation
# task def, and writes deploy/ablation.env for run_ablation.sh. Does NOT launch
# the run or call Bedrock. Prereq: awscli logged into the account, finch/docker.
set -uo pipefail

ACCOUNT_ID="${ACCOUNT_ID:?set ACCOUNT_ID to the 12-digit AWS account to deploy into}"
REGION="${REGION:-us-east-1}"
RESULTS_BUCKET="${RESULTS_BUCKET:-terrarepair-bench-results-${ACCOUNT_ID}}"
ECR_REPO="${ECR_REPO:-terrarepair-bench}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
TASK_ROLE_NAME="${TASK_ROLE_NAME:-terrarepair-ablation-task-role}"
EXEC_ROLE_NAME="${EXEC_ROLE_NAME:-terrarepair-ablation-exec-role}"
LOG_GROUP="${LOG_GROUP:-/ecs/terrarepair-ablation}"
CONTAINER_TOOL="${CONTAINER_TOOL:-finch}"
S3_PREFIX="${S3_PREFIX:-terrarepair/retrieval_ablation}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO}"

echo "== TerraRepair ABLATION Fargate setup =="
echo "  account=${ACCOUNT_ID} region=${REGION}"
echo "  bucket=${RESULTS_BUCKET} ecr=${ECR_URI}:${IMAGE_TAG}"

CALLER_ACCT="$(aws sts get-caller-identity --query Account --output text)"
if [[ "${CALLER_ACCT}" != "${ACCOUNT_ID}" ]]; then
  echo "ERROR: logged into ${CALLER_ACCT}, expected ${ACCOUNT_ID}." >&2
  exit 1
fi

# ---- 1. S3 bucket --------------------------------------------------------
if aws s3api head-bucket --bucket "${RESULTS_BUCKET}" 2>/dev/null; then
  echo "[s3] bucket ${RESULTS_BUCKET} exists"
else
  echo "[s3] creating bucket ${RESULTS_BUCKET}"
  aws s3api create-bucket --bucket "${RESULTS_BUCKET}" --region "${REGION}"
  aws s3api put-public-access-block --bucket "${RESULTS_BUCKET}" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
fi

# ---- 2. ECR repo + build/push -------------------------------------------
aws ecr describe-repositories --repository-names "${ECR_REPO}" --region "${REGION}" >/dev/null 2>&1 \
  || { echo "[ecr] creating repo ${ECR_REPO}"; aws ecr create-repository --repository-name "${ECR_REPO}" --region "${REGION}" >/dev/null; }

echo "[ecr] login"
aws ecr get-login-password --region "${REGION}" \
  | "${CONTAINER_TOOL}" login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "[build] ${CONTAINER_TOOL} build (linux/amd64)"
( cd "${REPO_ROOT}" && "${CONTAINER_TOOL}" build --platform linux/amd64 -t "${ECR_REPO}:${IMAGE_TAG}" . )
"${CONTAINER_TOOL}" tag "${ECR_REPO}:${IMAGE_TAG}" "${ECR_URI}:${IMAGE_TAG}"
echo "[push] ${ECR_URI}:${IMAGE_TAG}"
"${CONTAINER_TOOL}" push "${ECR_URI}:${IMAGE_TAG}"

# ---- 3. IAM roles --------------------------------------------------------
TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
ensure_role() {
  aws iam get-role --role-name "$1" >/dev/null 2>&1 \
    && echo "[iam] role $1 exists" \
    || { echo "[iam] creating role $1"; aws iam create-role --role-name "$1" --assume-role-policy-document "${TRUST}" >/dev/null; }
}
ensure_role "${EXEC_ROLE_NAME}"
aws iam attach-role-policy --role-name "${EXEC_ROLE_NAME}" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

ensure_role "${TASK_ROLE_NAME}"
POLICY_JSON="$(sed "s/<RESULTS_BUCKET>/${RESULTS_BUCKET}/g" "${SCRIPT_DIR}/task-role-policy.json" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); d.pop("_comment",None); print(json.dumps(d))')"
aws iam put-role-policy --role-name "${TASK_ROLE_NAME}" \
  --policy-name terrarepair-ablation-task-policy --policy-document "${POLICY_JSON}"

# ---- 4. Log group + default cluster -------------------------------------
aws logs create-log-group --log-group-name "${LOG_GROUP}" --region "${REGION}" 2>/dev/null \
  && echo "[logs] created ${LOG_GROUP}" || echo "[logs] ${LOG_GROUP} exists"
aws ecs describe-clusters --clusters default --region "${REGION}" \
  --query 'clusters[0].status' --output text 2>/dev/null | grep -q ACTIVE \
  || { echo "[ecs] creating default cluster"; aws ecs create-cluster --cluster-name default --region "${REGION}" >/dev/null; }

# ---- 5. Networking (default VPC public subnet + default SG) --------------
if [[ -z "${SUBNET_ID:-}" ]]; then
  VPC_ID="$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text --region "${REGION}")"
  SUBNET_ID="$(aws ec2 describe-subnets --filters Name=vpc-id,Values=${VPC_ID} Name=map-public-ip-on-launch,Values=true --query 'Subnets[0].SubnetId' --output text --region "${REGION}")"
  echo "[vpc] ${VPC_ID} public subnet ${SUBNET_ID}"
fi
if [[ -z "${SG_ID:-}" ]]; then
  SG_ID="$(aws ec2 describe-security-groups --filters Name=vpc-id,Values=${VPC_ID} Name=group-name,Values=default --query 'SecurityGroups[0].GroupId' --output text --region "${REGION}")"
  echo "[vpc] default sg ${SG_ID} (must allow outbound 443)"
fi

# ---- 6. Render + register the ablation task def -------------------------
RENDERED="${SCRIPT_DIR}/fargate-task-def-ablation.rendered.json"
sed -e "s/<ACCOUNT_ID>/${ACCOUNT_ID}/g" \
    -e "s/<REGION>/${REGION}/g" \
    -e "s/<RESULTS_BUCKET>/${RESULTS_BUCKET}/g" \
    -e "s#<ECS_EXECUTION_ROLE>#${EXEC_ROLE_NAME}#g" \
    -e "s#<TERRAREPAIR_TASK_ROLE>#${TASK_ROLE_NAME}#g" \
    "${SCRIPT_DIR}/fargate-task-def-ablation.json" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); d.pop("_comment",None); print(json.dumps(d,indent=2))' \
  > "${RENDERED}"
echo "[ecs] registering task def from ${RENDERED}"
aws ecs register-task-definition --cli-input-json "file://${RENDERED}" --region "${REGION}" >/dev/null

# ---- 7. Persist run params ----------------------------------------------
cat > "${SCRIPT_DIR}/ablation.env" <<EOF
# Generated by setup_ablation.sh
ACCOUNT_ID=${ACCOUNT_ID}
REGION=${REGION}
RESULTS_BUCKET=${RESULTS_BUCKET}
S3_PREFIX=${S3_PREFIX}
SUBNET_ID=${SUBNET_ID}
SG_ID=${SG_ID}
CLUSTER=default
TASK_FAMILY=terrarepair-ablation
EOF

echo
echo "== ablation setup complete =="
echo "  image:   ${ECR_URI}:${IMAGE_TAG}"
echo "  bucket:  s3://${RESULTS_BUCKET}/${S3_PREFIX}"
echo "  taskdef: terrarepair-ablation"
echo "  wrote:   ${SCRIPT_DIR}/ablation.env"
