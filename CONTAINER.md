# Containerized Runs — Local Smoke + Fargate Full Run

The same image runs the experiment **locally** (for a fast smoke test) and on
**AWS Fargate** (for the multi-hour full run that must survive laptop/SSH
death). Results persist to **S3**, which also drives resume: on start the
container pulls existing games from S3 and the runner auto-skips them.

Pinned in the image for reproducibility: **Trivy 0.74.0**, **Checkov 3.3.20**,
plus `requirements.txt`. The local (non-container) run path is unchanged.

---

## Build

```bash
cd /path/to/TerraRepair-Bench
docker build -t terrarepair-bench:latest .
```

`.dockerignore` keeps the context to `src/`, `scripts/`,
`experiments/configs/`, and the 16MB `data/terrads_sample` corpus — NOT the
1.8GB `data/` tree or any `experiments/results/`.

---

## Phase 1 — Local smoke in the container

Proves the image works end-to-end (scanners + Bedrock + scoring) on a tiny
slice, using your local AWS creds. Local-only mode (no S3) — omit
`RESULTS_S3_URI` and results stay in a mounted volume.

```bash
mkdir -p ./_container_smoke
docker run --rm \
  -e REGION=us-east-1 \
  -e MAX_MODULES=3 \
  -e CONCURRENCY=3 \
  -e MAX_TOKENS=4096 \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN \
  -v "$PWD/_container_smoke:/app/experiments/results" \
  terrarepair-bench:latest
```

- Passes your current shell AWS creds into the container (env-var form). For SSO
  profiles, export them first (`eval "$(aws configure export-credentials --format env)"`).
- `MAX_MODULES=3` keeps it to ~3×N-models calls and a few dollars at most.
- Inspect `./_container_smoke/<experiment>/games/*.json` afterwards.

Review the games + `run_manifest.json` (it records scanner versions,
concurrency, max_tokens). If the smoke is clean, proceed to Fargate.

---

## Phase 2 — Fargate full run

### Quickstart (scripted)
Two idempotent scripts do the whole deploy. They default to account
`<ACCOUNT_ID>`, `us-east-1`, a new bucket `terrarepair-bench-results-<ACCOUNT>`,
the default VPC's public subnet, and auto-created IAM roles — override any of it
via env vars at the top of `deploy/setup.sh`.

```bash
# 1. One-time infra + image (no experiment spend):
bash deploy/setup.sh
#    creates: S3 bucket, ECR repo + pushed image, exec role, task role
#    (Bedrock + S3), CloudWatch log group, registered task def; writes
#    deploy/deploy.env for run.sh.

# 2. Launch the full run WITH auto-restart (this STARTS the ~$30 run):
bash deploy/run.sh
#    re-launches on stop until run_complete.json appears in S3, then exits.
```
Monitoring + result retrieval commands are printed by `run.sh` (and below).

> **CDK alternative:** this could be expressed as an AWS CDK app (ECR asset +
> Fargate task def + IAM + S3 in TypeScript/Python). We chose scripts because a
> one-off benchmark doesn't justify a CDK toolchain + `cdk bootstrap` (which
> itself provisions S3/IAM) + synth/deploy cycle — the bash is smaller and has
> fewer moving parts to misconfigure. If this becomes a recurring, multi-env
> platform, port `deploy/` to CDK; the task-def and policy JSON here map
> directly to `ecs.FargateTaskDefinition` + `iam.PolicyStatement`.

### Manual reference (what the scripts do)
### What YOU must supply (the deploy assets use placeholders)
The task definition and policy cannot be invented — provide these and
substitute the `<PLACEHOLDERS>`:

- `<ACCOUNT_ID>`, `<REGION>` (e.g. us-east-1)
- `<RESULTS_BUCKET>` — an S3 bucket you own for results
- `<TERRAREPAIR_TASK_ROLE>` — task role with `deploy/task-role-policy.json`
  attached (Bedrock invoke + S3 RW to the bucket)
- `<ECS_EXECUTION_ROLE>` — standard ECS execution role (ECR pull + CloudWatch logs)
- VPC **subnet id(s)** and a **security group** with outbound internet/HTTPS
  (Bedrock + S3 + ECR). Public subnet + `assignPublicIp=ENABLED`, or private
  subnet + NAT.

### 1. Push the image to ECR
```bash
ACCOUNT_ID=<ACCOUNT_ID>; REGION=<REGION>
aws ecr create-repository --repository-name terrarepair-bench --region "$REGION" || true
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
docker tag terrarepair-bench:latest "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/terrarepair-bench:latest"
docker push "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/terrarepair-bench:latest"
```
NOTE: build on / for linux/amd64. On Apple Silicon add `--platform linux/amd64`
to `docker build` (the task def uses X86_64).

### 2. Create the task role + register the task def
```bash
# attach deploy/task-role-policy.json to <TERRAREPAIR_TASK_ROLE> (after filling <RESULTS_BUCKET>)
aws ecs register-task-definition --cli-input-json file://deploy/fargate-task-def.json --region "$REGION"
```

### 3. Run the task
```bash
aws ecs run-task \
  --cluster <CLUSTER_NAME_OR_default> \
  --launch-type FARGATE \
  --task-definition terrarepair-bench \
  --network-configuration 'awsvpcConfiguration={subnets=[<SUBNET_ID>],securityGroups=[<SG_ID>],assignPublicIp=ENABLED}' \
  --region "$REGION"
```

### 4. Monitor (without waiting hours)
- **Logs:** CloudWatch group `/ecs/terrarepair-bench` — the runner emits a
  heartbeat every `HEARTBEAT_SECS` (`[heartbeat <ts>] N/total games`).
- **Metrics (for troubleshooting):** `metrics.json` is snapshotted on each
  heartbeat and synced to S3. It has overall progress + rate (`games_per_min`),
  event counts (scored / hcl_valid / throttled / timed_out / scan_failed /
  resumed / size_driven), cumulative cost, and a per-model breakdown — so a
  stalled or cost-runaway run is diagnosable at a glance:
  ```bash
  BASE=s3://<RESULTS_BUCKET>/terrarepair/full_refresh_2026-09
  aws s3 cp $BASE/metrics.json - | python3 -m json.tool
  ```
  A run that's stuck shows a flat `done` and `games_per_min -> 0`; a throttled
  run shows rising `throttled`; a cost surprise shows in `by_model[*].cost_usd`.
- **Progress via S3:** the container syncs up every `SYNC_INTERVAL` (120s):
  ```bash
  aws s3 ls $BASE/games/ | wc -l
  aws s3 cp $BASE/skip_manifest.jsonl - | tail
  aws s3 ls $BASE/run_complete.json    # exists only when the run is DONE
  ```

### 5. Resume after a stop/crash
Just `run-task` again with the same definition. The entrypoint pulls existing
games from S3 first; the runner skips them and continues. At most one
`SYNC_INTERVAL` of games is ever re-done.

---

## Auto-restart WITHOUT losing work

Resume is built in (S3 sync-down + the runner's auto-skip). The remaining piece
is *automatically* relaunching a task that stops before the run finishes.

**Completion signal.** When the runner finishes every (module, model) item it
writes `run_complete.json` (LAST, only on clean completion) and syncs it to S3.
The entrypoint checks for it on startup: **if present, the container exits 0
immediately without re-running.** So an auto-restart after completion is a
clean, non-billable no-op. This is what makes restart safe.

### Recommended: AWS Batch with retries (right tool for a FINITE job)
Register the same image as a Batch job definition with `"attempts": N` (e.g. 5)
and a Fargate compute environment. Batch restarts the job **only if it exits
non-zero**, up to N attempts, and stops when it exits 0 — exactly the semantics
a finite batch job needs. Each attempt runs the same entrypoint, so it resumes
from S3 and skips completed games. Set the env vars (RESULTS_S3_URI etc.) in the
Batch job definition identically to `deploy/fargate-task-def.json`.

### Alternative: a re-run loop (no extra infra)
From any always-on shell (or a tiny Lambda on a schedule), loop `run-task` until
the completion marker appears:
```bash
S3=s3://<RESULTS_BUCKET>/terrarepair/full_refresh_2026-09
until aws s3 ls "$S3/run_complete.json" >/dev/null 2>&1; do
  echo "not complete; (re)launching task..."
  TASK=$(aws ecs run-task --cluster <CLUSTER> --launch-type FARGATE \
    --task-definition terrarepair-bench \
    --network-configuration 'awsvpcConfiguration={subnets=[<SUBNET>],securityGroups=[<SG>],assignPublicIp=ENABLED}' \
    --query 'tasks[0].taskArn' --output text)
  aws ecs wait tasks-stopped --cluster <CLUSTER> --tasks "$TASK"   # blocks until this task stops
done
echo "run complete."
```
The `run_complete.json` check both terminates the loop and (via the entrypoint)
makes any stray relaunch a no-op.

### DO NOT use a plain ECS Service for this
An ECS Service with `desiredCount: 1` restarts the task **even after it exits 0**
— it's built for always-on daemons, not batch jobs. It would loop the finished
experiment forever (and keep billing Bedrock on any resumed-but-not-idempotent
edge). Use Batch (`attempts`) or the re-run loop above, both of which respect the
completion marker.

### 6. Retrieve results when done
```bash
aws s3 sync s3://<RESULTS_BUCKET>/terrarepair/full_refresh_2026-09 \
  experiments/results/full_refresh_2026-09
python3 scripts/analyze_corrected.py \
  --games experiments/results/full_refresh_2026-09/games \
  --out   experiments/results/full_refresh_2026-09
```

---

## Cost & safety notes
- Fargate compute is a few cents/hour (I/O-bound); **Bedrock token spend
  (~$30, mostly Sonnet 5 + Grok) dominates** and is identical to running
  anywhere else — the container doesn't add model cost.
- S3 storage for results is negligible (tens of MB).
- The task role scopes Bedrock + the one results bucket only (least privilege).
- `claude-sonnet-4` is Legacy-blocked on account <ACCOUNT_ID>; it will log
  skips, not spend. Reactivate or drop it in the config as desired.
- Every skip/throttle/size-note is in `skip_manifest.jsonl` in S3 — the run
  stays fully auditable.
