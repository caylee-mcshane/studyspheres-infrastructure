# Infrastructure — Agent Context

This is the **Terraform infrastructure** for StudySpheres (`C:\studyspheres\studyspheres-infrastructure` — local-only, not yet in GitHub).

## Before making any change, read

1. **[`studyspheres-docs/architecture.md`](https://github.com/caylee-mcshane/studyspheres-docs/blob/main/architecture.md)** — what's deployed, in what shape
2. **[`studyspheres-docs/runbooks/deploy.md`](https://github.com/caylee-mcshane/studyspheres-docs/blob/main/runbooks/deploy.md)** — apply procedure with safety checks
3. **All ADRs in [`studyspheres-docs/adrs/`](https://github.com/caylee-mcshane/studyspheres-docs/tree/main/adrs/)** — they encode why the infrastructure looks the way it does

## Critical rules — must never violate

1. **Never run `terraform apply` without reviewing the plan first.** Always read the "X to add, Y to change, Z to destroy" line and inspect every line under "destroy."
2. **`terraform destroy` is essentially never the right answer.** Comment out resources or remove blocks, then `apply` — let Terraform figure out what changes.
3. **Deletion protection is on every DynamoDB table.** Do NOT remove it. If you genuinely need to recreate a table, the runbook covers the temp-disable + recreate dance.
4. **Hardcoded production resources don't exist yet** — `environments/production/main.tf` has structure but no resources have been created. When standing up production, use `cd environments/production && terraform apply`. Do NOT modify staging to "also" be production.
5. **State is in S3 (`studyspheres-terraform-state-2026`) with DynamoDB lock table.** Never edit state files by hand. If state seems corrupt, ask before running `terraform state` commands.
6. **DB password and other secrets** flow through SSM Parameter Store, NOT Terraform variables. The exception is `db_password` which is prompted at plan/apply time — there's a remaining task to add a `terraform.tfvars` for that.

## Module conventions

```
studyspheres-infrastructure/
├── bootstrap/                ← Terraform state backend (S3 + DynamoDB lock table)
│   └── main.tf
├── environments/
│   ├── staging/main.tf       ← root config — calls all modules with environment="staging"
│   └── production/main.tf    ← (planned)
└── modules/
    ├── compute/              ← EC2, ASG, ALB, SQS, IAM role + policy, user data script
    ├── database/             ← RDS PostgreSQL only
    ├── dynamodb/             ← All NoSQL tables (added v1.4)
    ├── networking/           ← VPC, subnets, route tables, IGW, NAT
    ├── security/             ← Cognito, IAM (some — most IAM lives in compute module)
    └── storage/              ← S3 buckets, CloudFront, OAC
```

### Resource naming
- DynamoDB: `${var.environment}-TableName` (e.g., `staging-UserProfiles`)
  - One legacy exception: `ProcessingSessions-${var.environment}` (suffix style)
- Most other AWS resources: `studyspheres-${var.environment}-<role>` (e.g., `studyspheres-staging-asg`)
- Tags applied via provider `default_tags`: `Environment`, `Project`, `ManagedBy`. Per-resource `Name` and `Component` tags as needed.

### Standard hardening for stateful resources
Every DynamoDB table:
- `billing_mode = "PAY_PER_REQUEST"` (see ADR-0002)
- `point_in_time_recovery { enabled = true }`
- `server_side_encryption { enabled = true }`
- `deletion_protection_enabled = true`
- Streams enabled where future Lambda consumers are anticipated

When adding a new DynamoDB table, copy the pattern from any existing table in `modules/dynamodb/main.tf` rather than starting from scratch.

## Deployment

```powershell
cd C:\studyspheres\studyspheres-infrastructure\environments\staging

# 1. Always plan first
terraform plan
# (prompts for db_password — value is in the architecture doc resource reference)

# 2. Read the plan output carefully:
#    - Any "destroy" lines need scrutiny
#    - Any RDS / S3-bucket / CloudFront changes need extra scrutiny

# 3. Apply
terraform apply
# type 'yes'

# 4. If launch template changed → instance refresh (see runbook)
```

Detailed procedure: [`studyspheres-docs/runbooks/deploy.md`](https://github.com/caylee-mcshane/studyspheres-docs/blob/main/runbooks/deploy.md).

## Things that require an instance refresh after `terraform apply`

The launch template changed if any of these were modified:
- `modules/compute/main.tf` user data script
- IAM role or instance profile
- Instance type, AMI, security group attachment
- Any `aws_launch_template` field

Procedure to refresh:
```powershell
'{"MinHealthyPercentage":0}' | Out-File -FilePath prefs.json -Encoding utf8
aws autoscaling start-instance-refresh `
  --auto-scaling-group-name studyspheres-staging-asg `
  --preferences file://prefs.json
```

## Module outputs you can rely on

The `dynamodb` module exposes:
- `table_arns` — map of logical names → ARNs
- `all_arns_for_iam` — list of every table ARN PLUS GSI ARNs (for IAM policies)
- `stream_arns` — map of streams (for Lambda event sources)
- `table_names` — map of logical names → actual table names

Use these for cross-module wiring rather than hardcoding ARNs.

## Common gotchas

| Symptom | Most likely cause |
|---|---|
| `terraform plan` wants to recreate every resource | Probably running from the wrong directory or wrong workspace |
| DB password prompt every time | No `terraform.tfvars` — known remaining task |
| Apply fails with "ResourceInUseException" on DynamoDB | Manually-created table with the same name exists. Drop it first with the runbook script |
| EC2 IAM role missing a permission | Compute module's IAM policy uses wildcards (`dynamodb:*`, `s3:*`) — should cover most things. Cognito IS NOT wildcarded — that's a known IAM gap |
| Plan shows `0 to add, 0 to change, 0 to destroy` but state seems stale | Run `terraform refresh` |

## When uncertain

The cost of a bad infrastructure change is much higher than a bad app change — it can take down all environments at once. When in doubt:
1. Run `terraform plan` and SHARE the output before applying
2. Consider whether the change should be tested in a sandbox first
3. Ask. Always better to slow down than to undo.

## When you change things the architecture doc describes

If your code change affects something documented in `studyspheres-docs/architecture.md` — a schema, a resource ID, an env var, an endpoint, a constant — update that doc in the same change. Limit changes to the specific lines affected. Do not modify ADRs (they're append-only and human-curated).

If unsure whether an update is needed, ask before guessing.