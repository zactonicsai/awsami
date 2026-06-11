# Best Practices Guide — AWS Cloud Team for Data Applications

Companion templates live in this bundle; paths are referenced as `→ path`.
Stack currency (June 2026): Terraform 1.15.x / AWS provider 6.x · ansible-core 2.20 (Python ≥ 3.12) · AL2023 (AL2 EOL 2026-06-30) · GitLab 18.x · AWS CLI v2.

---

## 1. Identity & Access

- **Humans:** AWS IAM Identity Center (SSO) only. On Windows: `aws configure sso` once per account/role, then `aws sso login --profile <name>` (→ `scripts/windows/aws-login.bat`). Never create IAM users with long-lived `AKIA…` keys for people.
- **CI:** GitLab OIDC federation. The runner mints a short-lived ID token (`id_tokens:` in the job), AWS trusts the GitLab issuer, and the AWS SDK/CLI auto-assumes the role via `AWS_WEB_IDENTITY_TOKEN_FILE` + `AWS_ROLE_ARN`. No keys stored in either GitLab → nothing to sync or leak (→ `gitlab/ci/terraform.gitlab-ci.yml`).
  - Trust-policy condition should pin `aud` **and** `sub` (e.g., `project_path:dataapps-cloud/terraform-live:ref_type:branch:ref:main`). Create one IAM OIDC provider **per GitLab instance** (different issuer URLs) trusting the same roles.
- **Machines:** Instance profiles only. Baseline managed policies: `AmazonSSMManagedInstanceCore` + CloudWatch agent policy. Apps get scoped roles (e.g., Kafka role may read its Secrets Manager secret and write to its S3 bucket — nothing else).
- **Break-glass:** one monitored emergency role per account; every use raises an EventBridge alert and requires a ticket.

## 2. Accounts, Tagging, Naming

Minimum tag set, enforced (Tag Policies + AWS Config `required-tags` + Terraform `default_tags`):

| Tag | Example | Used by |
|-----|---------|---------|
| `Project` | `dataapps` | Ansible dynamic inventory, cost |
| `Environment` | `dev` / `test` / `prod` | inventory, Config rules, IAM conditions |
| `App` | `kafka`, `nifi`, `opensearch`, `javaapp-orders` | Ansible group mapping (`app_kafka`…) |
| `Owner` | team email | paging, cleanup |
| `ManagedBy` | `terraform` / `cloudformation` / `manual` | drift triage, "who owns this resource" |
| `CostCenter` | `CC1234` | FinOps |
| `AmiFamily` (AMIs) | `al2023-base` | AMI pointer publishing |

Naming: `<project>-<env>-<app>-<role>-<nn>` (e.g., `dataapps-prod-kafka-broker-01`).

## 3. The AMI Factory (custom AMIs from latest AWS Linux)

### 3.1 Base image
Always start from the **latest AL2023** via the public SSM parameter — never a hardcoded AMI ID:

```
/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64
```
(Packer resolves it with the `amazon-parameterstore` data source; Image Builder uses the managed parent image `amazon-linux-2023-x86/x.x.x` which always tracks latest.)

**dnf, not yum.** On AL2023 `yum` is just an alias for `dnf`. Old AL2 tooling that depends on `yum-cron`, `yum-versionlock` plugin names, or `/etc/yum.conf` semantics must be ported (→ `ami-factory/packer/scripts/`).

### 3.2 Patch allow/deny — three layers (all template-backed)

1. **Build-time, in the AMI (authoritative):**
   - `dnf upgrade --security -y` (or full upgrade) **within the AMI's locked release**. AL2023 repos are version-locked (deterministic `releasever`); you only move to a newer 2023.x point release deliberately (`--releasever=latest` or editing `/etc/dnf/vars/releasever`). This is exactly the "only approved patches" property you want — the build is reproducible.
   - **Remove unapproved packages:** every package in `patch-policy/denied-packages.txt` is `dnf remove`'d; the build **fails** if any remain (→ `scripts/02-patch-policy.sh`).
   - **Pin approved versions:** `dnf versionlock add` for everything in `patch-policy/approved-lock.txt` (plugin pkg: `python3-dnf-plugin-versionlock`).
   - **Never-touch list:** `excludepkgs=` appended to `/etc/dnf/dnf.conf` from `patch-policy/excluded-from-update.txt` so even an ad-hoc `dnf update` on a live box can't pull them.
2. **Run-time guardrail:** SSM **Patch Manager custom baseline** mirroring the same lists (`ApprovedPatches`, `RejectedPatches` with `BLOCK`), patch groups per environment, Maintenance Windows for scan (daily) and install (only if you patch in place — golden-AMI shops usually *scan only* and replace instances instead).
3. **Account guardrail:** EC2 **Allowed AMIs** setting — restrict launches to AMIs owned by your AMI account / tagged from the factory, so nobody can boot a random marketplace image even manually.

### 3.3 Pipeline stages (Packer and Image Builder templates implement the same flow)

`resolve latest AL2023 → provision temp instance → 00-os-update → 01-baseline (agents, hardening) → 02-patch-policy (remove/lock/exclude) → 99-cleanup (cloud-init clean, machine-id, ssh host keys, shell history, logs) → create encrypted AMI → smoke test → tag + share → publish SSM pointer → deprecate old`

- **Encrypt** AMIs with a customer-managed KMS key; share the key + AMI to member accounts (or copy per account). Org-share via RAM if you prefer central ownership.
- **Tag** AMIs: `AmiFamily`, `SourceAmi`, `BuildPipeline`, `BuildDate`, `GitSha`.
- **Lifecycle:** set `deprecate_at` (Packer supports it natively; Image Builder has lifecycle policies). Enable deregistration protection on the current prod AMI. Keep N=3 previous AMIs for rollback; the pointer parameter is your rollback lever (`publish-latest-ami.bat` can pin any specific AMI).
- **Cadence:** monthly scheduled + on-demand for CVEs. Image Builder pipelines can trigger automatically when the parent image updates (dependency-update trigger).
- **Kernel live patching** is available on AL2023 if you must extend in-place life between AMI rolls — but prefer replace-over-patch.

### 3.4 Packer vs EC2 Image Builder (keep both? pick one?)

| | Packer (→ `ami-factory/packer/`) | EC2 Image Builder (→ `ami-factory/imagebuilder/`) |
|---|---|---|
| Pros | Runs in GitLab CI like any job; HCL; same workflow for other clouds; rich provisioners (shell, Ansible) | Fully managed; scheduling + auto-trigger on parent updates; built-in test phase; lifecycle policies; no runner/network plumbing; defined in CloudFormation |
| Cons | You manage runner network/IAM; BUSL license (fine for internal use, not for embedding in a competing service) | AWS-only; component DSL is more limited; debugging build instances is clunkier |
| Pick when | You want everything in one GitLab pipeline | You want hands-off monthly rebuilds + AWS-native governance |

Both templates call the **same shell scripts**, so policy lives in one place.

## 4. Terraform Standards

- **Versions:** pin `required_version = ">= 1.10.0, < 2.0.0"` (1.15 recommended) and `aws = "~> 6.0"`. Commit `.terraform.lock.hcl`. Provider 6.x supports a per-resource `region` argument — one provider block can now manage multiple regions; remove alias-only provider sprawl gradually.
- **State:** S3 backend with **`use_lockfile = true`** (native S3 locking, TF ≥ 1.10; the old `dynamodb_table` argument is deprecated — drop the lock table once everyone is ≥ 1.10). Bucket: versioning on, KMS, public access blocked, access logged. One key per env+stack: `data-apps/<env>/<stack>.tfstate`. **Do not** use GitLab-managed state with two GitLabs — state must not depend on which instance is up.
- **Layout:** small **stacks per env** under `environments/<env>/<stack>` (network, ami-pipeline, kafka, opensearch, …) calling **versioned modules** (`source = "git::https://gitlab…//modules/ec2-app?ref=v1.4.0"` or the GitLab Terraform module registry). Prefer directories-per-env over workspaces — explicit > implicit, and it maps 1:1 to CI rules and state keys.
- **Secrets:** never in state. Use **write-only arguments + ephemeral resources** (TF ≥ 1.11), e.g.:
  ```hcl
  ephemeral "aws_secretsmanager_secret_version" "db" { secret_id = var.db_secret_arn }
  resource "aws_db_instance" "pg" {
    password_wo         = ephemeral.aws_secretsmanager_secret_version.db.secret_string
    password_wo_version = 1   # bump to rotate
  }
  ```
- **CI flow:** `fmt -check` → `validate` → `tflint` → `checkov`/`trivy` → `plan -out=tfplan.bin` (artifact, with `terraform show -json` for the MR) → **manual** `apply tfplan.bin` on protected branch only. Apply must consume the *reviewed plan file*, never re-plan.
- **Adopting existing/manual resources:** `import {}` blocks + `terraform plan -generate-config-out=generated.tf`, then refactor with `moved {}` blocks. Use `removed {}` to drop from state without destroying.
- **Tests:** `terraform test` for modules (plan-time assertions are cheap); `terraform-docs` in pre-commit for module READMEs.
- **Don't:** put providers in modules; `terraform apply -auto-approve` outside CI; share one state file across envs; manage a resource in both TF *and* CFN.

## 5. CloudFormation Standards

- Use CFN where it's the better fit: StackSets across accounts/OUs, Service Catalog products, AWS-sample-derived stacks, teams that prefer it. **Rule: every resource has exactly one IaC owner** (`ManagedBy` tag tells you which).
- **AMI input pattern:** parameter type `AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>` defaulting to `/dataapps/ami/al2023-base/latest` — stacks pick up new AMIs on next update with zero template edits (→ `cloudformation/templates/ec2-app-cluster.yaml`).
- **Safety rails:** change sets reviewed before prod (`cfn-deploy.bat` has a changeset mode); stack policies on stateful resources; `DeletionPolicy: Retain`/`Snapshot` on data stores; termination protection on prod stacks; scheduled **drift detection** with results to the team channel.
- **Quality gates:** `cfn-lint` (in CI and pre-commit) + **CloudFormation Guard** rules for org policy (encrypted volumes, IMDSv2, mandatory tags).
- **Modernize:** prefer `aws cloudformation deploy` (idempotent create-or-update); use the **IaC generator** to capture console-built resources into templates; **stack refactoring** to move resources between stacks without recreate; Git sync if you want CFN to track a repo branch directly.
- Limits to remember: 500 resources/template (split via nested stacks), 200 parameters, 16 KB EC2 user-data.

## 6. Governed Manual Changes (the third supported method)

Manual is legitimate for break-glass and true one-offs — but it's a *workflow*, not a free-for-all:

1. Ticket first (or immediately after, for incidents). 2. Make the change; tag the resource `ManagedBy=manual` + ticket ID. 3. Within **5 business days**: codify (Terraform `import` block or CFN IaC-generator) or schedule deletion. 4. Weekly: drift detection (CFN drift + `terraform plan` scheduled pipelines) and an AWS Config diff report catch anything that skipped 1–3.
Console hygiene: read-only roles by default; write roles require explicit role-switch; CloudTrail console-write events feed a weekly "who changed what outside IaC" digest (easy EventBridge→Lambda, see doc 04).

## 7. Ansible Standards

- **Control node:** Linux only. On Windows desktops use **WSL2** (Ubuntu 24.04), `pipx install ansible-core` (2.20 needs Python ≥ 3.12). In CI use a pinned container. ⚠️ Run from inside the WSL filesystem (`~/src/...`), not `/mnt/c/...` — world-writable directories make Ansible **ignore `ansible.cfg`** and file perms get weird.
- **Collections pinned** in `requirements.yml` (`amazon.aws`, `community.aws`, `community.general`) and installed in CI every run — reproducibility across both GitLabs' runners.
- **Inventory = AWS tags**, never static files: `amazon.aws.aws_ec2` plugin filtered by `Project`/`Environment`, `keyed_groups` on the `App` tag → groups `app_kafka`, `app_nifi`, … (→ `ansible/inventories/dev/aws_ec2.yml`). Launch an instance with the right tags and it's already in inventory.
- **Connection = SSM**, not SSH: `ansible_connection: community.aws.aws_ssm` (+ an S3 transfer bucket). No port 22 anywhere, sessions logged in CloudTrail/Session Manager. SSH remains a documented fallback.
- **Roles:** one per app (provided), defaults overridable in `group_vars`; idempotent (`creates=`, handlers, `changed_when`); secrets via `amazon.aws.aws_secret`/`aws_ssm` lookups at runtime — never in vars files (Vault is the fallback for non-AWS secrets).
- **Quality:** `ansible-lint` in CI; `--check --diff` job on MRs; Molecule for the kafka/common roles when you can invest.
- Custom shell scripts: keep them, but invoke via roles (`ansible.builtin.script`) so inventory/limits/logging stay consistent.

## 8. GitLab CI/CD Standards (both instances)

- **Heads-up:** GitLab 18 **removed the bundled Terraform CI templates** (HashiCorp license change). Use the jobs provided here (plain `hashicorp/terraform` image — fine for internal use) **or** GitLab's **OpenTofu CI/CD component**. The GitLab Terraform *state* backend still exists but we avoid it (dual-instance, see D4).
- Stages: `lint → validate → plan/build → deploy(manual) → verify`. Protected branches + protected environments gate prod applies to named approvers.
- Runners: Linux runners (Docker executor) required for Packer/Ansible/Terraform jobs; tag them (`aws`, `linux`) identically on both instances. Windows runners only if you later CI the `.bat` tooling.
- Caching: `.terraform` plugin dir and pip/galaxy caches per project to keep dual-instance runners fast and identical.
- Pipeline portability rule: jobs must not assume which GitLab they run on. Anything instance-specific comes from CI/CD variables (`AWS_ROLE_ARN`, runner tags), and mirror-side pipeline policy is explicit (→ doc 05).

## 9. Application-Specific Guidance

| App | Self-managed notes (Ansible role provided) | Managed alternative worth evaluating |
|-----|--------------------------------------------|--------------------------------------|
| **Kafka** | Pin **3.9.x while you need ZooKeeper — Kafka 4.x removed ZK entirely (KRaft only)**. Role supports both modes; plan a KRaft migration project. Java 17/21 (Corretto). Separate gp3 data volume, `XX:+UseG1GC`, broker `node.id` from tags. | Amazon MSK (incl. MSK Serverless) |
| **ZooKeeper** | 3.9.x; odd-sized ensemble (3/5); `myid` from inventory index; dedicated small instances; goes away with KRaft. | (retired with KRaft) |
| **NiFi** | **NiFi 2.x requires Java 21** and removed 1.x templates/variable registry — migration is a project, not an upgrade. Single-user creds via `nifi.sh set-single-user-credentials`; cluster mode needs ZK (or embedded). | — |
| **OpenSearch** | 3.x needs Java 21 (bundled); `vm.max_map_count=262144`, `bootstrap.memory_lock`, heap = 50% RAM ≤ ~32 GB; gp3 with provisioned IOPS for hot nodes; security plugin admin password is mandatory at install. | Amazon OpenSearch Service |
| **Databricks** | **Custom AMIs are not supported** — clusters run Databricks-managed images even in your VPC. Standardize instead via the `databricks` Terraform provider: cluster policies, init scripts, instance profiles, Unity Catalog. Your VPC/SG/PrivateLink IS your Terraform's job. | (it is the managed service) |
| **PostgreSQL** | Role installs from AL2023 repos (`postgresql16`/`17`); separate data volume; WAL archiving to S3 (e.g., pgBackRest); `pg_hba` templated. Honest default for new DBs: **RDS/Aurora** unless you need OS access. | RDS / Aurora PostgreSQL |
| **SQLite** | It's an embedded library, not a server — nothing to provision beyond the package; data file durability = the app's EBS/EFS strategy + AWS Backup. Don't put it on shared NFS for concurrent writers. | — |
| **Custom Java** | Amazon **Corretto** (17/21 LTS; 25 is the newest LTS) from AL2023 repos; one systemd unit pattern (provided), JVM flags in `/etc/sysconfig/<app>`; artifacts pulled from S3/CodeArtifact by version. | App Runner/ECS if containerizable |

## 10. Windows Desktop Standard Setup

```bat
winget install -e --id Amazon.AWSCLI
winget install -e --id Amazon.SessionManagerPlugin
winget install -e --id Hashicorp.Terraform
winget install -e --id Hashicorp.Packer
winget install -e --id Git.Git
winget install -e --id jqlang.jq
winget install -e --id Python.Python.3.12      :: for cfn-lint/checkov via pip
wsl --install -d Ubuntu-24.04                  :: Ansible control node
```
Git config: `git config --global core.autocrlf input` and rely on the provided `.gitattributes` (LF for `.sh`, CRLF for `.bat`). Enable Windows long paths (`git config --global core.longpaths true` + the registry policy) — Terraform `.terraform` trees and NiFi archives hit 260 chars fast. Set `AWS_PAGER=` to stop CLI output paging in scripts (the `.bat` templates do this).

## 11. Security & Operations Baseline

- **Compute:** IMDSv2 required (AL2023 default — keep it that way in launch templates), EBS encryption-by-default on in every account/region, gp3 volumes, no public IPs for data apps (SSM + VPC endpoints: `ssm`, `ssmmessages`, `ec2messages`, `s3`, `logs`).
- **Audit/posture:** Org CloudTrail, AWS Config recorder + conformance pack, Security Hub + GuardDuty, IAM Access Analyzer.
- **Secrets:** Secrets Manager (rotation) for credentials; SSM Parameter Store (SecureString) for config. Nothing secret in user-data, AMIs, tfvars, or repo.
- **Logging/monitoring:** CloudWatch agent baked into the AMI with a default config (system + app logs); alarms-as-code in the same stack as the app; one dashboard per app per env.
- **Backup/DR:** AWS Backup plans by tag (`Backup=daily|hourly`) for EBS/RDS/EFS; quarterly restore *tests*; AMI+snapshot copies cross-region for tier-1.
- **Cost:** budgets + anomaly detection per account; weekly rightsizing report (Compute Optimizer); schedule dev instances off-hours (Instance Scheduler or the EventBridge pattern in doc 04); Savings Plans for steady-state Kafka/OpenSearch fleets; gp2→gp3 migration if any remain.

→ Full task list with owners and template references: `02-TASK-CATALOG.md`.
→ Tool-by-tool pros/cons/gotchas: `03-TOOLS-TIPS-GOTCHAS.md`.
→ Automation & AI: `04-AI-AUTOMATION.md`. Dual-GitLab: `05-GITLAB-DUAL-SYNC.md`.
