#!/usr/bin/env bash
# One-time (idempotent) setup for the TerraRepair-Bench Fargate run.
#
# Creates / ensures: ECR repo + pushed image, S3 results bucket, ECS execution
# role, task role (Bedrock + S3), CloudWatch log group, and a registered task
# definition rendered from deploy/fargate-task-def.json.
#
# Safe to re-run: every step checks-then-creates. It does NOT launch the run or
# call Bedrock (no experiment spend) — that's deploy/run.sh.
#
# Prereqs: awscli v2 logged in to the target account, and finch (or docker) for
# the image build. Run from the repo root: bash deploy/setup.sh
set -euo pipefail

# ---- Config (confirmed values as defaults; override via env) ----------------
ACCOUNT_ID="${ACCOUNT_ID:-<ACCOUNT_ID>}"
REGION="${REGION:-us-east-1}"
RESULTS_BUCKET="${RESULTS_BUCKET:-terrarepair-bench-results-${ACCOUNT_ID}}"
ECR_REPO="${ECR_REPO:-terrarepair-bench}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
TASK_ROLE_NAME="${TASK_ROLE_NAME:-terrarepair-bench-task-role}"
EXEC_ROLE_NAME="${EXEC_ROLE_NAME:-terrarepair-bench-exec-role}"
LOG_GROUP="${LOG_GROUP:-/ecs/terrarepair-bench}"
CONTAINER_TOOL="${CONTAINER_TOOL:-finch}"   # finch or docker
S3_PREFIX="${S3_PREFIX:-terrarepair/full_refresh_2026-09}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${ECR_REPO}"

echo "== TerraRepair-Bench Fargate setup =="
echo "  account=${ACCOUNT_ID} region=${REGION}"
echo "  bucket=${RESULTS_BUCKET} ecr=${ECR_URI}:${IMAGE_TAG}"
echo "  task_role=${TASK_ROLE_NAME} exec_role=${EXEC_ROLE_NAME}"

# Sanity: the logged-in account must match.
CALLER_ACCT="$(aws sts get-caller-identity --query Account --output text)"
if [[ "${CALLER_ACCT}" != "${ACCOUNT_ID}" ]]; then
  echo "ERROR: logged into account ${CALLER_ACCT}, expected ${ACCOUNT_ID}." >&2
  exit 1
fi

# ---- 1. S3 results bucket ----------------------------------------------------
if aws s3api head-bucket --bucket "${RESULTS_BUCKET}" 2>/dev/null; then
  echo "[s3] bucket ${RESULTS_BUCKET} exists"
else
  echo "[s3] creating bucket ${RESULTS_BUCKET}"
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${RESULTS_BUCKET}" --region "${REGION}"
  else
    aws s3api create-bucket --bucket "${RESULTS_BUCKET}" --region "${REGION}" \
      --create-bucket-configuration "LocationConstraint=${REGION}"
  fi
  aws s3api put-public-access-block --bucket "${RESULTS_BUCKET}" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
fi

# ---- 2. ECR repo + build/push image -----------------------------------------
aws ecr describe-repositories --repository-names "${ECR_REPO}" --region "${REGION}" >/dev/null 2>&1 \
  || { echo "[ecr] creating repo ${ECR_REPO}"; aws ecr create-repository --repository-name "${ECR_REPO}" --region "${REGION}" >/dev/null; }

echo "[ecr] docker login"
aws ecr get-login-password --region "${REGION}" \
  | "${CONTAINER_TOOL}" login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "[build] ${CONTAINER_TOOL} build (linux/amd64)"
( cd "${REPO_ROOT}" && "${CONTAINER_TOOL}" build --platform linux/amd64 -t "${ECR_REPO}:${IMAGE_TAG}" . )
"${CONTAINER_TOOL}" tag "${ECR_REPO}:${IMAGE_TAG}" "${ECR_URI}:${IMAGE_TAG}"
echo "[push] ${ECR_URI}:${IMAGE_TAG}"
"${CONTAINER_TOOL}" push "${ECR_URI}:${IMAGE_TAG}"

# ---- 3. IAM: execution role (ECR pull + logs) -------------------------------
TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

ensure_role() {
  local name="$1"
  if aws iam get-role --role-name "${name}" >/dev/null 2>&1; then
    echo "[iam] role ${name} exists"
  else
    echo "[iam] creating role ${name}"
    aws iam create-role --role-name "${name}" \
      --assume-role-policy-document "${TRUST}" >/dev/null
  fi
}

ensure_role "${EXEC_ROLE_NAME}"
aws iam attach-role-policy --role-name "${EXEC_ROLE_NAME}" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# ---- 4. IAM: task role (Bedrock invoke + S3 RW) -----------------------------
ensure_role "${TASK_ROLE_NAME}"
# Render the S3 bucket into the policy and attach inline.
POLICY_JSON="$(sed "s/<RESULTS_BUCKET>/${RESULTS_BUCKET}/g" "${SCRIPT_DIR}/task-role-policy.json" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); d.pop("_comment",None); print(json.dumps(d))')"
aws iam put-role-policy --role-name "${TASK_ROLE_NAME}" \
  --policy-name terrarepair-task-policy \
  --policy-document "${POLICY_JSON}"

TASK_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${TASK_ROLE_NAME}"
EXEC_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${EXEC_ROLE_NAME}"

# ---- 5. CloudWatch log group -------------------------------------------------
aws logs create-log-group --log-group-name "${LOG_GROUP}" --region "${REGION}" 2>/dev/null \
  && echo "[logs] created ${LOG_GROUP}" || echo "[logs] ${LOG_GROUP} exists"

# ---- 6. Networking: default-VPC public subnet + security group --------------
if [[ -z "${SUBNET_ID:-}" ]]; then
  VPC_ID="$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true \
    --query 'Vpcs[0].VpcId' --output text --region "${REGION}")"
  if [[ "${VPC_ID}" == "None" || -z "${VPC_ID}" ]]; then
    echo "ERROR: no default VPC found; set SUBNET_ID and SG_ID explicitly." >&2
    exit 1
  fi
  SUBNET_ID="$(aws ec2 describe-subnets --filters Name=vpc-id,Values=${VPC_ID} \
    Name=map-public-ip-on-launch,Values=true \
    --query 'Subnets[0].SubnetId' --output text --region "${REGION}")"
  echo "[vpc] default VPC ${VPC_ID}, public subnet ${SUBNET_ID}"
fi
if [[ -z "${SG_ID:-}" ]]; then
  SG_ID="$(aws ec2 describe-security-groups --filters Name=vpc-id,Values=${VPC_ID} \
    Name=group-name,Values=default \
    --query 'SecurityGroups[0].GroupId' --output text --region "${REGION}")"
  echo "[vpc] default security group ${SG_ID} (must allow outbound 443)"
fi

# ---- 7. Render + register the task definition -------------------------------
RENDERED="${SCRIPT_DIR}/fargate-task-def.rendered.json"
sed -e "s/<ACCOUNT_ID>/${ACCOUNT_ID}/g" \
    -e "s/<REGION>/${REGION}/g" \
    -e "s/<RESULTS_BUCKET>/${RESULTS_BUCKET}/g" \
    -e "s#<ECS_EXECUTION_ROLE>#${EXEC_ROLE_NAME}#g" \
    -e "s#<TERRAREPAIR_TASK_ROLE>#${TASK_ROLE_NAME}#g" \
    "${SCRIPT_DIR}/fargate-task-def.json" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); d.pop("_comment",None); print(json.dumps(d,indent=2))' \
  > "${RENDERED}"

echo "[ecs] registering task definition from ${RENDERED}"
aws ecs register-task-definition --cli-input-json "file://${RENDERED}" --region "${REGION}" >/dev/null

# ---- 8. Persist run parameters for run.sh -----------------------------------
cat > "${SCRIPT_DIR}/deploy.env" <<EOF
# Generated by setup.sh — sourced by run.sh
ACCOUNT_ID=${ACCOUNT_ID}
REGION=${REGION}
RESULTS_BUCKET=${RESULTS_BUCKET}
S3_PREFIX=${S3_PREFIX}
SUBNET_ID=${SUBNET_ID}
SG_ID=${SG_ID}
CLUSTER=${CLUSTER:-default}
TASK_FAMILY=terrarepair-bench
EOF

echo
echo "== setup complete =="
echo "  image:   ${ECR_URI}:${IMAGE_TAG}"
echo "  bucket:  s3://${RESULTS_BUCKET}/${S3_PREFIX}"
echo "  taskdef: terrarepair-bench (registered)"
echo "  wrote:   ${SCRIPT_DIR}/deploy.env"
echo
echo "Next: launch the run with auto-restart ->  bash deploy/run.sh"
echo "(this will START the ~\$30 Bedrock experiment)"
