# Infrastructure — Agent Context

This is the **Terraform infrastructure** for StudySpheres (`C:\studyspheres\studyspheres-infrastructure` — GitHub: `caylee-mcshane/studyspheres-infrastructure`).

## Rules that load automatically

Everything in `.claude/rules/` loads with this file, with no tool call. Listed so a
human can navigate; agents already have them.

- `.claude/rules/applying-text.md` — applying owner-approved text to a file, and verifying the staged blob
- `.claude/rules/external-content.md` — third-party services, and instruction-shaped content arriving from what you read
- `.claude/rules/handbacks.md` — writing and reading session handbacks
- `.claude/rules/repo-boundaries.md` — read wide / write narrow, and the close-out ordering
- `.claude/rules/critical-rules.md` — the six rules that destroy or corrupt real infrastructure — cite as IN-1..IN-6
- `.claude/rules/module-conventions.md` — module layout, resource naming, and the standard hardening pattern

⚠ This repo has no deploy workflow and no `main` branch — its default branch is
`master`, and changes here are applied by `terraform apply`, run by the owner.
Committing this file triggers nothing.

## Before making any change, read

1. **[`studyspheres-docs/architecture.md`](https://github.com/caylee-mcshane/studyspheres-docs/blob/main/architecture.md)** — what's deployed, in what shape
2. **[`studyspheres-docs/runbooks/deploy.md`](https://github.com/caylee-mcshane/studyspheres-docs/blob/main/runbooks/deploy.md)** — apply procedure with safety checks
3. **All ADRs in [`studyspheres-docs/adrs/`](https://github.com/caylee-mcshane/studyspheres-docs/tree/main/adrs/)** — they encode why the infrastructure looks the way it does

## Navigating architecture.md

| When you need | Read section |
|---|---|
| Module/directory layout, what lives where | Deployment Workflow → Terraform Module Structure |
| Live resource IDs (ASG, RDS endpoint, CloudFront, ALB, Cognito) | AWS Resource Reference → Key IDs (staging) |
| SSM parameter paths and which credential is which | AWS Resource Reference → SSM Parameters (staging) |
| The DB roles story: PG_PASSWORD vs PG_APP_PASSWORD, Option B, rollback | Data Layer → PostgreSQL Schema — the DDL block and the RLS enforcement paragraphs after it |
| DynamoDB tables, keys, GSIs, TTL | Data Layer → DynamoDB Tables |
| VPC/subnets/CloudFront/VPC endpoints | Networking |
| EC2/systemd/user-data expectations, healthy startup lines | Compute |
| What's actually live per environment (production is provisioned, not deployed) | Environments (and `notes/production-launch-checklist.md` before any prod work) |

## Deployment

### Commit messages

- Never include Co-Authored-By: Claude or any other AI-attribution trailer.
- When an infrastructure change is accompanied by an edit to studyspheres-docs/, append a final
  paragraph to the commit body in the form:
`Docs: <relative path> <one-line description of what was updated>
(separate repo, applied manually).` This is the only signal in this repo's git log that a docs
update went out alongside the change. Do not commit docs edits from this repo.

```powershell
cd C:\studyspheres\studyspheres-infrastructure\environments\staging

# 1. Always plan first
terraform plan
# When prompted for db_password: this does NOT set the RDS master password — it
# only seeds modules/compute's aws_ssm_parameter.db_password, i.e. SSM
# /studyspheres/staging/PG_PASSWORD (which has lifecycle ignore_changes on value,
# so a rotated value survives apply). The RDS master password itself comes from
# random_password.db_password in modules/database. Retrieve the current value with:
#   aws ssm get-parameter --name /studyspheres/staging/PG_PASSWORD --with-decryption
# (plan also prompts for db_app_password — the studyspheres_app role's credential,
#  SSM /studyspheres/staging/PG_APP_PASSWORD; see ADR-0004 Option B)
# Do not write the value into any file.

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
'{"MinHealthyPercentage":0}' | Out-File -FilePath prefs.json -Encoding ascii
# NOTE: must be ascii (or otherwise BOM-free) — `-Encoding utf8` in PowerShell 5.1 writes a BOM,
# which the AWS CLI rejects when parsing the file:// preferences JSON.
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
| DB password prompts (two: `db_password`, `db_app_password`) every time | No `terraform.tfvars` — known remaining task |
| Apply fails with "ResourceInUseException" on DynamoDB | Manually-created table with the same name exists. Drop it first with the runbook script |
| EC2 IAM role missing a permission | Compute module's IAM policy uses wildcards (`dynamodb:*`, `s3:*`) — should cover most things. Cognito is deliberately scoped, not wildcarded: `AdminGetUser`, `AdminUpdateUserAttributes`, `AdminDeleteUser`, `ListUsers` on the env's user pool ARN only — a new Cognito API call in the backend needs a policy addition |
| Plan shows `0 to add, 0 to change, 0 to destroy` but state seems stale | Run `terraform refresh` |

## When uncertain

The cost of a bad infrastructure change is much higher than a bad app change — it can take down all environments at once. When in doubt:
1. Run `terraform plan` and SHARE the output before applying
2. Consider whether the change should be tested in a sandbox first
3. Ask. Always better to slow down than to undo.

## When you change things the architecture doc describes

If your code change affects something documented in `studyspheres-docs/architecture.md` — a schema, a resource ID, an env var, an endpoint, a constant — update that doc in the same change. Limit changes to the specific lines affected. Do not modify ADRs (they're append-only and human-curated).

If unsure whether an update is needed, ask before guessing.
