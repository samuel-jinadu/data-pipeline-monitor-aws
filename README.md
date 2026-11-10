# Data Pipeline Monitor

A **self-contained, end-to-end data pipeline demo**: synthetic messy warehouse data, deployed as a containerized Streamlit app on **AWS ECS**, backed by **S3** — all runnable locally against [FakeCloud](https://github.com/) (a LocalStack-style AWS simulator) and portable to real AWS with a single environment file swap.

It's designed as a learning/reference project that exercises the full stack: data generation → object storage → container build → ECR → ECS task → monitoring UI.

---

## What it demonstrates

- **Synthetic data with intentional chaos** — [chaoslake](https://pypi.org/project/chaoslake/) generates Parquet files with nulls, duplicates, and drift, the way real pipelines break.
- **Data quality monitoring UI** — A Streamlit app reads Parquet directly from `s3://` and surfaces **null** and **duplicate** reports (including business-key duplicates that ignore the surrogate `id`).
- **Realistic AWS topology, simulated locally** — FakeCloud provides S3, ECR, ECS, IAM and CloudWatch Logs on `localhost:4566`, so you can rehearse a real deploy without an AWS account.
- **Two deployment paths, one codebase** — Flip from `environments/fakecloud.env` to `environments/aws.env` and the same `Makefile` targets deploy to real AWS.
- **Container-first** — A single `Dockerfile` builds the app; `docker-compose.yaml` for quick local iteration; ECR push + ECS task definition for "production".
- **Idempotent-ish IaC scripts** — IAM role, ECR repo, log group and cluster creation all tolerate already-existing resources (`|| true`).

---

## Architecture

```
┌──────────────────────┐        ┌──────────────────────────┐
│  chaoslake.yaml      │        │  Local host              │
│  (schema + chaos)    │        │  ┌────────────────────┐  │
└──────────┬───────────┘        │  │  FakeCloud         │  │
           │ gen.sh             │  │  :4566             │  │
           ▼                    │  │  S3 · ECR · ECS    │  │
  customers.parquet  ──upload──▶│  │  IAM · Logs        │  │
  orders.parquet                │  └─────────┬──────────┘  │
                                │            │             │
                                │  ┌─────────▼──────────┐  │
                                │  │  Docker build      │  │
                                │  │  data-pipeline-    │  │
                                │  │  monitor:latest    │  │
                                │  └─────────┬──────────┘  │
                                │            │ push        │
                                │  ┌─────────▼──────────┐  │
                                │  │  ECS task          │  │
                                │  │  Streamlit :8501   │  │
                                │  └─────────┬──────────┘  │
                                │            │             │
                                │  ┌─────────▼──────────┐  │
                                │  │  Browser           │  │
                                │  │  localhost:8501    │  │
                                │  └────────────────────┘  │
                                └──────────────────────────┘
```

---

## Project structure

```
.
├── Dockerfile                     # Streamlit app image (uv-based, Python 3.12)
├── Makefile                       # One-liner orchestration targets
├── docker-compose.yaml            # Fast local dev (mounts host.docker.internal)
├── fakecloud.sh                   # Starts FakeCloud with persistent storage
├── environments/
│   ├── aws.env                    # Real AWS credentials / region
│   └── fakecloud.env              # FakeCloud defaults (test creds, :4566)
├── infra/
│   ├── push-image.sh              # Build → tag → push to ECR (FakeCloud or AWS)
│   ├── run-container.sh           # Register task def + run ECS task
│   └── policies/
│       ├── apply.sh               # Create StreamlitAppTaskRole + S3 read policy
│       ├── ecs-trust-policy.json  # Allow ECS tasks to assume the role
│       └── s3-read-policy.json    # Read access to data-warehouse-raw/*
└── streamlit-app/
    ├── app.py                     # Streamlit app (all report logic)
    ├── pyproject.toml / uv.lock   # Dependencies (uv-managed)
    ├── README.md                  # App-specific docs
    └── data/
        ├── chaoslake.yaml         # Schema + chaos configuration
        ├── gen.sh                 # Regenerate Parquet files
        ├── upload.sh              # Upload Parquet files to S3
        ├── customers.parquet
        └── orders.parquet
```

---

## Prerequisites

| Tool | Purpose |
|---|---|
| **Docker** | Build and run the app image |
| **Python ≥ 3.12** + **[uv](https://docs.astral.sh/uv/)** | Local app development |
| **AWS CLI v2** | Talks to FakeCloud via `--endpoint-url` |
| **[FakeCloud](https://github.com/)** | Local AWS emulator on `:4566` |
| `make`, `bash`, `curl` | Orchestration scripts |

---

## Quick start — FakeCloud (recommended)

The whole pipeline runs locally on `localhost:4566`.

### 1. Start FakeCloud

```bash
./fakecloud.sh &
```

This launches FakeCloud in **persistent** mode at `/var/lib/fakecloud`. Everything you create (buckets, images, roles) survives restarts.

### 2. Set up environment

```bash
source environments/fakecloud.env
```

This exports:
- `AWS_ENDPOINT_URL=http://localhost:4566`
- `AWS_ACCESS_KEY_ID=test`, `AWS_SECRET_ACCESS_KEY=test`
- `ACCOUNT_ID=000000000000`

### 3. Run the full pipeline

```bash
make deploy-all
```

That single target chains the four steps below:

```bash
make setup-data              # generate parquet → upload to s3://data-warehouse-raw/
make deploy-iam              # create StreamlitAppTaskRole + S3 read policy
make deploy-image-fakecloud  # build image → push to FakeCloud ECR
make deploy-ecs              # register task def → run ECS task
```

### 4. Open the app

Once the ECS task is running, point your browser at:

**<http://localhost:8501>**

You should see the Data Pipeline Monitor with null and duplicate reports populated from the chaos-lake Parquet files.

> **Tip:** `make deploy-ecs` uses `networkMode: bridge` and publishes `8501:8501`. If the task fails, check `docker ps` — you may need to run the container directly with `docker run -p 8501:8501 ...` (see `docker-compose.yaml`).

---

## Running the app locally (no ECS)

For fast iteration on `app.py`:

```bash
# 1. Install deps
cd streamlit-app && uv sync && cd ..

# 2. Ensure FakeCloud is running and data is uploaded
source environments/fakecloud.env
aws s3 ls s3://data-warehouse-raw/     # should show customers.parquet, orders.parquet

# 3. Run the app
cd streamlit-app && uv run streamlit run app.py
```

Or with Docker Compose:

```bash
docker compose up --build
```

The compose file uses `host.docker.internal:4566`, so FakeCloud running on the host is reachable from inside the container.

---

## Regenerating the synthetic data

The `data/chaoslake.yaml` schema defines two tables (`customers`, `orders`) with deliberate chaos:

| Chaos feature | Where | Effect |
|---|---|---|
| `null_probability` | both tables | Random nulls (2–3%) |
| `duplicate_probability` | `orders` | 1% full-row duplicates |
| `drift` | `orders.amount` | Distribution shifts after row 4000 |
| `format_inconsistency` | `orders.order_date` | Mixed US date formats |

Regenerate the Parquet files:

```bash
cd streamlit-app/data
./gen.sh          # wraps: chaoslake generate --schema chaoslake.yaml --format parquet
./upload.sh ../../environments/fakecloud.env
```

---

## Deploying to real AWS

The only difference is the environment file. Before running:

### 1. Configure real credentials

```bash
source environments/aws.env
```

That file:
- Sets `AWS_DEFAULT_REGION` (default `us-east-1`)
- **Unsets** `AWS_ENDPOINT_URL` so the CLI and SDK target real AWS
- Looks up `ACCOUNT_ID` from `aws sts get-caller-identity`

Make sure your shell has working `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` with permissions for S3, ECR, ECS, IAM, CloudWatch Logs.

### 2. Deploy

```bash
make deploy-iam
make deploy-image-aws       # uses the real amazonaws.com registry
make deploy-ecs             # NOTE: edit run-container.sh to pass aws.env
```

> ⚠️ `run-container.sh` currently hardcodes `../environments/fakecloud.env` as its default. For real AWS, either pass `environments/aws.env` as the first argument or change the default.

> ⚠️ The bucket `data-warehouse-raw` must already exist on real AWS. Create it once:
> ```bash
> aws s3 mb s3://data-warehouse-raw
> ```
> The `FakeCloud` bucket is created implicitly by `upload.sh`.

---

## Environment files explained

**`environments/fakecloud.env`**

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
export AWS_ENDPOINT_URL=http://localhost:4566
export ACCOUNT_ID="000000000000"
```

**`environments/aws.env`**

```bash
export AWS_DEFAULT_REGION=us-east-1
unset  AWS_ENDPOINT_URL
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

The scripts branch on `AWS_ENDPOINT_URL` to decide between:
- `…localhost:4566` registry/endpoint (FakeCloud)
- `…amazonaws.com` registry/endpoint (real AWS)

---

## Makefile targets

| Target | What it does |
|---|---|
| `make setup-data` | `chaoslake generate` + `aws s3 cp` to `s3://data-warehouse-raw/` |
| `make deploy-iam` | Create IAM role + attach `S3ReadOnlyPolicy` |
| `make deploy-image-fakecloud` | Build → tag → push image to FakeCloud ECR |
| `make deploy-image-aws` | Build → tag → push image to real AWS ECR |
| `make deploy-ecs` | Register task def → `ecs run-task` |
| `make deploy-all` | Full FakeCloud pipeline (`setup-data → deploy-iam → deploy-image-fakecloud → deploy-ecs`) |

---

## Tech stack

| Layer | Tool |
|---|---|
| **Data generation** | [chaoslake](https://pypi.org/project/chaoslake/) — schema-driven synthetic data with chaos |
| **Data format** | Apache Parquet (columnar, read directly by Polars) |
| **Data engine** | [Polars](https://pola.rs/) — fast, lazy-friendly DataFrames |
| **UI** | [Streamlit](https://streamlit.io/) — declarative, cached app |
| **Local cloud** | [FakeCloud](https://github.com/) — S3/ECR/ECS/IAM/Logs emulator on `:4566` |
| **Cloud (prod)** | AWS ECS (Fargate-compatible), ECR, S3, IAM, CloudWatch Logs |
| **Packaging** | Docker (multi-stage, `uv`-installed deps) |
| **Python deps** | [uv](https://docs.astral.sh/uv/) — fast, lockfile-based |
