<!-- PER-REPO FILE. Deliberately NOT identical across repos — this is a declared
     exception to one-home-per-fact. Infrastructure-specific. Each rule carries a stable ID; cite the ID, never a position. -->

## Critical rules — must never violate

**IN-1.** **Never run `terraform apply` without reviewing the plan first.** Always read the "X to add, Y to change, Z to destroy" line and inspect every line under "destroy."
**IN-2.** **`terraform destroy` is essentially never the right answer.** Comment out resources or remove blocks, then `apply` — let Terraform figure out what changes.
**IN-3.** **Deletion protection is on every DynamoDB table.** Do NOT remove it. If you genuinely need to recreate a table, the runbook covers the temp-disable + recreate dance.
**IN-4.** **Production is provisioned but undeployed** — `environments/production/main.tf` has created real resources (VPC, RDS, ASG — it calls only the networking/database/compute modules, 3 of the 6), but there is no app, no S3 buckets, most SSM secrets are absent, and there are no users. See `notes/production-launch-checklist.md` before any production work. When standing up production, use `cd environments/production && terraform apply`. Do NOT modify staging to "also" be production.
**IN-5.** **State is in S3 (`studyspheres-terraform-state-2026`) with DynamoDB lock table.** Never edit state files by hand. If state seems corrupt, ask before running `terraform state` commands.
**IN-6.** **DB password and other secrets** flow through SSM Parameter Store, NOT Terraform variables. The exception: staging prompts for TWO sensitive variables at plan/apply time — `db_password` (seeds `aws_ssm_parameter.db_password`, the master `PG_PASSWORD` param) and `db_app_password` (seeds `aws_ssm_parameter.app_db_password`, the `studyspheres_app` role's `PG_APP_PASSWORD` param). The compute module's `db_app_user` variable selects which parameter the app reads — see ADR-0004 (Option B). There's a remaining task to add a `terraform.tfvars` for the prompts.
