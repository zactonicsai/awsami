# Cloud Team Platform Plan — Data Applications on AWS

**Audience:** Cloud/Infrastructure team supporting data applications (Kafka, ZooKeeper, NiFi, OpenSearch, Databricks, PostgreSQL, SQLite, custom Java apps)
**Constraints honored:** Custom AMIs from the latest AWS Linux (Amazon Linux 2023), dnf/yum-based patch allow/deny control, Terraform + CloudFormation + governed manual changes all supported, dual synced GitLabs, Ansible + custom scripts for configuration, Windows desktops.
**Last reviewed:** June 2026

---

## 1. Goals

1. One repeatable, auditable **AMI factory**: latest AL2023 base → org patches applied → unapproved packages removed/locked → tested → published as the only AMI anyone launches from.
2. **Three provisioning methods, one source of truth per resource**: Terraform (default), CloudFormation (where required), and governed manual changes (break-glass, then codified).
3. **Identical, synced GitLab structure** on two instances, with pipelines that behave correctly on both.
4. **Ansible-driven configuration** of every data application, runnable from Windows desktops (via WSL2) and from CI.
5. **Windows-first operator experience**: every routine task has a `.bat` wrapper using AWS CLI v2.
6. A path to **rule-based and AI automation** that reduces toil without giving up control.

## 2. Current-state assumptions

- Multiple AWS accounts (at minimum dev / test / prod) under AWS Organizations.
- Two GitLab instances (e.g., "GitLab-A" connected network, "GitLab-B" restricted/secondary) synced by a dedicated sync tool.
- Operators on Windows 10/11 desktops; CI runners are Linux (required for Packer/Ansible jobs).
- **Time-critical:** Amazon Linux 2 reaches end of life **June 30, 2026**. AL2023 is the current AWS Linux (no new major version in 2025/2026; AL2023 is supported into 2029). All AMI work in this plan targets **AL2023**, which uses **dnf** (the `yum` command is an alias) — scripts written for AL2 yum plugins must be reviewed.

## 3. Target architecture (AMI-centric view)

```
                 ┌─────────────────────────────────────────────────────────┐
                 │                     AMI FACTORY                         │
  AWS public SSM │  latest AL2023 AMI                                      │
  parameter ───► │  /aws/service/ami-amazon-linux-latest/                  │
                 │      al2023-ami-kernel-default-x86_64                   │
                 │        │                                                │
                 │        ▼                                                │
                 │  Packer (CI) ──or── EC2 Image Builder pipeline          │
                 │   • dnf upgrade (within locked releasever)              │
                 │   • install approved packages/agents                    │
                 │   • REMOVE denied packages (denied-packages.txt)        │
                 │   • dnf versionlock approved versions                   │
                 │   • excludepkgs= for never-touch packages               │
                 │   • harden, clean, tag                                  │
                 │        │                                                │
                 │        ▼                                                │
                 │  Test instance (SSM doc / Ansible smoke tests)          │
                 │        │ pass                                           │
                 │        ▼                                                │
                 │  Encrypted AMI  ──share──►  dev/test/prod accounts      │
                 │        │                                                │
                 │        ▼                                                │
                 │  SSM Parameter  /dataapps/ami/al2023-base/latest        │
                 └─────────┬───────────────────────────────────────────────┘
                           │ (single AMI pointer consumed by everything)
        ┌──────────────────┼──────────────────────┐
        ▼                  ▼                      ▼
   Terraform           CloudFormation        Manual launch (break-glass,
   data "aws_ssm_      Parameter type        console restricted by
   parameter"          AWS::SSM::Parameter   EC2 "Allowed AMIs" setting)
        │                  │                      │
        └────────► EC2 instances (IMDSv2, gp3, SSM role, tagged) ◄────────┘
                           │
                           ▼
                 Ansible (dynamic aws_ec2 inventory by tags, SSM connection)
                 roles: common, kafka, zookeeper, nifi, opensearch,
                        postgres, java_app   (Databricks: provider-managed —
                        custom AMIs are NOT supported there; see guide)
```

## 4. Repository layout (identical on both GitLabs)

```
group: dataapps-cloud/
├── platform-toolkit/            ← this bundle (docs, standards, shared CI)
├── ami-factory/                 ← packer + imagebuilder + patch policy
├── terraform-modules/           ← versioned reusable modules (tagged releases)
├── terraform-live/              ← environments/{dev,test,prod}/<stack>
├── cloudformation/              ← templates + parameters per env
├── ansible/                     ← inventories, roles, playbooks
└── windows-scripts/             ← .bat operator tooling
```
Rules: same group/subgroup/repo paths, same default branch (`main`), same protected-branch names on both instances. Instance-specific things (CI/CD variables, runner tags, tokens, mirror settings) are **never** stored in the repo — see `05-GITLAB-DUAL-SYNC.md`.

## 5. Workstreams, deliverables, exit criteria

| # | Workstream | Key deliverables (in this bundle) | Exit criteria |
|---|------------|-----------------------------------|---------------|
| 0 | Foundations | Tagging standard, IAM Identity Center profiles, GitLab→AWS OIDC roles | No long-lived access keys on desktops or in CI; `aws sso login` works for every operator |
| 1 | AMI factory | `ami-factory/packer/*`, `ami-factory/imagebuilder/*`, `publish-latest-ami.bat` | Monthly (and on-demand) AMI builds pass tests; SSM pointer updated automatically; old AMIs auto-deprecated |
| 2 | Patch governance | `patch-policy/*` files, SSM Patch Manager custom baseline | Approved/denied package lists are version-controlled; instances report compliant in Patch Manager |
| 3 | Terraform standard | `terraform/*`, `gitlab/ci/terraform.gitlab-ci.yml`, `tf.bat` | State in S3 with native lockfile; plan-as-artifact + manual apply gate in CI |
| 4 | CloudFormation standard | `cloudformation/*`, `cfn-deploy.bat`, cfn-lint job | Change-set review before every prod deploy; drift detection scheduled |
| 5 | Manual-change governance | Process in `01-BEST-PRACTICES-GUIDE.md` §6 | Every console change has a ticket + is imported into IaC within 5 business days |
| 6 | Ansible config mgmt | `ansible/*`, WSL2 setup in README | `ansible-playbook site.yml --limit app_kafka` converges a fresh instance from the golden AMI |
| 7 | GitLab pipelines + dual sync | `gitlab/*`, `docs/05-GITLAB-DUAL-SYNC.md`, `gitlab-sync.bat` | Pipelines green on primary; mirror policy enforced; divergence runbook tested |
| 8 | Windows operator tooling | `scripts/windows/*.bat` | Login, AMI build, TF plan/apply, CFN deploy, EC2 ops, SSM connect all one command |
| 9 | Automation & AI | `docs/04-AI-AUTOMATION.md` quick wins | At least 3 rule-based remediations live (tags, drift, AMI age); AI assist piloted with guardrails |

## 6. Key decisions (ADR summary)

| ID | Decision | Why | Alternative considered |
|----|----------|-----|------------------------|
| D1 | Base OS = **AL2023**, package mgr = **dnf** | AL2 EOL 2026-06-30; AL2023 supported to 2029, deterministic versioned repos help patch control | RHEL/Rocky (more cost/ops), staying on AL2 (unsupported in 3 weeks) |
| D2 | **Both** Packer and EC2 Image Builder templates provided | Packer = flexible, runs in GitLab CI; Image Builder = managed scheduling, lifecycle policies, no runner needed | Pick one (you can later; interfaces kept identical via shared shell scripts) |
| D3 | AMI consumed via **SSM parameter pointer** `/dataapps/ami/<family>/latest` | One integration point works for Terraform, CloudFormation, CLI, and console | Hardcoding AMI IDs (drift, per-region pain) |
| D4 | Terraform state = **S3 backend with `use_lockfile = true`** (Terraform ≥ 1.10) | Native S3 locking; the DynamoDB lock table is deprecated and no longer needed | DynamoDB locking (legacy), GitLab-managed state (couples state to one GitLab — bad for dual-instance) |
| D5 | CI auth = **GitLab OIDC → AWS assume-role** | No stored keys to sync/rotate between two GitLabs | CI/CD variables with access keys (leak + sync risk) |
| D6 | Ansible control node = **WSL2 Ubuntu** on desktops, container image in CI | ansible-core does not support Windows as a control node; current ansible-core 2.20 needs Python ≥ 3.12 | Dedicated Linux bastion (extra hop), Cygwin (unsupported) |
| D7 | Ansible connects over **SSM** (`community.aws.aws_ssm`), not SSH | No port 22, no key distribution, full session logging | SSH with bastion (key sprawl) |
| D8 | Kafka pinned to **3.9.x while ZooKeeper is required**; KRaft migration planned | Kafka 4.x removed ZooKeeper entirely; 3.9 is the last ZK-capable line | Jump straight to 4.x KRaft (bigger blast radius; do it as its own project) |
| D9 | **Databricks compute is NOT covered by custom AMIs** | Databricks manages its own images; customize via init scripts, cluster policies, and the Databricks Terraform provider | Forcing AMI standard onto Databricks (unsupported) |
| D10 | GitLab pipelines use **our own Terraform jobs** (provided) | GitLab 18 removed the built-in Terraform CI templates (license change); options are your own jobs/image or the OpenTofu CI/CD component | OpenTofu component (valid; documented as alternative) |

## 7. Milestones

- **Days 0–30:** Workstreams 0–2. Ship the AMI factory + patch policy; turn on EC2 "Allowed AMIs" in dev. Migrate any remaining AL2 hosts (hard deadline June 30, 2026).
- **Days 31–60:** Workstreams 3–6. Terraform/CFN pipelines live with OIDC; Ansible converging Kafka/ZK + one Java app in dev; Windows scripts adopted by the team.
- **Days 61–90:** Workstreams 7–9. Dual-GitLab sync validated with a forced-divergence drill; prod cutover; first three rule-based automations; AI assist pilot (Amazon Q / MCP) in read-only mode.

## 8. Risks

| Risk | Mitigation |
|------|------------|
| AL2 stragglers past 2026-06-30 | Inventory via `aws ssm describe-instance-information` + Config rule; block AL2 AMIs with Allowed AMIs |
| Two GitLabs diverge | Single-writer policy + sync monitoring + divergence runbook (doc 05) |
| Patch lists drift from reality | Lists live in git; AMI build fails if a denied package is present at the end of the build |
| Secrets leak into Terraform state | Write-only arguments / ephemeral values (TF ≥ 1.11) + Secrets Manager; state bucket KMS + restricted |
| Windows line-endings break Linux scripts | `.gitattributes` enforces LF for `*.sh`, CRLF for `*.bat` (included) |
| Kafka 4 surprise | Version pinned in Ansible defaults; upgrade is an explicit ADR change |

**Next:** read `01-BEST-PRACTICES-GUIDE.md`, then explore the template directories. Every template is referenced from the task catalog in `02-TASK-CATALOG.md`.
