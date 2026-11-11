# TerraRepair-Bench experiment runner — portable image.
# Runs the same locally (smoke) and on AWS Fargate (full run).
#
# Pins the dual-scanner stack for reproducibility (audit: pin scanner versions):
#   Trivy   0.74.0
#   Checkov 3.3.20
# and the Python deps from requirements.txt.
#
# Build (from repo root):
#   docker build -t terrarepair-bench:latest .
# Local smoke / run: see CONTAINER.md.

FROM python:3.11-slim AS base

# --- OS deps: curl (fetch trivy), git (some checkov paths), ca-certs, aws cli deps ---
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates git unzip \
    && rm -rf /var/lib/apt/lists/*

# --- Trivy (pinned) ---
ARG TRIVY_VERSION=0.74.0
RUN curl -sfL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
        -o /tmp/trivy.tar.gz \
    && tar -xzf /tmp/trivy.tar.gz -C /usr/local/bin trivy \
    && rm /tmp/trivy.tar.gz \
    && trivy --version

# --- AWS CLI v2 (for S3 sync in the entrypoint on Fargate) ---
RUN curl -sfL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws \
    && aws --version

WORKDIR /app

# --- Python deps first (layer caching) ---
COPY requirements.txt .
# checkov is a CLI dep not in requirements.txt; pin it explicitly.
ARG CHECKOV_VERSION=3.3.20
RUN pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir "checkov==${CHECKOV_VERSION}" \
    && trivy --version && checkov --version

# --- App code + corpus ---
# .dockerignore keeps this to source + the 16MB terrads_sample corpus, NOT the
# 1.8GB data/ tree (poc dirs, venvs, results).
COPY src ./src
COPY scripts ./scripts
COPY experiments/configs ./experiments/configs
COPY data/terrads_sample ./data/terrads_sample
COPY pyproject.toml requirements.txt ./

# Retrieval-ablation INPUT artifacts (pool / targets / Titan embeddings). These
# are static inputs the ablation runner reads; baked in so the container is
# self-contained. (Outputs under games/ are excluded via .dockerignore.)
COPY experiments/results/retrieval_ablation/hardened_pool.json \
     experiments/results/retrieval_ablation/ablation_targets.json \
     experiments/results/retrieval_ablation/embeddings_titan_v2.json \
     ./experiments/results/retrieval_ablation/

# Provenance: .git is excluded from the build context, so the source commit is
# passed in at build time and read by run_experiment._git_provenance().
#   finch build --build-arg GIT_COMMIT=$(git rev-parse HEAD) --build-arg GIT_DIRTY=false ...
ARG GIT_COMMIT=""
ARG GIT_DIRTY=""
ENV TERRAREPAIR_GIT_COMMIT=${GIT_COMMIT} \
    TERRAREPAIR_GIT_DIRTY=${GIT_DIRTY}

ENV PYTHONPATH=/app \
    PYTHONUNBUFFERED=1 \
    AWS_REGION=us-east-1

# Two entrypoints: the main experiment and the retrieval ablation. The image
# default is the main one (back-compat); the ablation task def overrides the
# container command to the ablation entrypoint.
COPY scripts/container_entrypoint.sh /usr/local/bin/container_entrypoint.sh
COPY scripts/container_entrypoint_ablation.sh /usr/local/bin/container_entrypoint_ablation.sh
RUN chmod +x /usr/local/bin/container_entrypoint.sh \
             /usr/local/bin/container_entrypoint_ablation.sh

ENTRYPOINT ["/usr/local/bin/container_entrypoint.sh"]
