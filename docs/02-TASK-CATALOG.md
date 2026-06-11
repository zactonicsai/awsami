# Cloud Team Task Catalog

Every recurring task, the standard tool, and where the template/script lives in this bundle.
Method legend: **TF** = Terraform · **CFN** = CloudFormation · **ANS** = Ansible · **BAT** = Windows script (AWS CLI) · **MAN** = governed manual.

## A. Foundations & Identity

| Task | Method | Template / How | Cadence |
|---|---|---|---|
| Create/baseline AWS accounts (Organizations, OUs, SCPs) | TF (or Control Tower) | own `org` stack; Control Tower if starting fresh | rare |
| Identity Center: permission sets, group→account assignments | TF | `aws_ssoadmin_*` resources | as needed |
| Operator SSO profile setup & login | BAT | `scripts/windows/aws-login.bat` | daily |
| GitLab OIDC providers + CI roles (per GitLab instance) | TF | `aws_iam_openid_connect_provider` + role w/ `sub` conditions | once + on repo adds |
| Break-glass role + alerting on use | TF + EventBridge | doc 04 §rule patterns | once |
| Tag policy + required-tags Config rule | TF | org stack | once |
| Access review (who can assume what) | MAN + IAM Access Analyzer | quarterly report | quarterly |

## B. Networking

| Task | Method | Template / How | Cadence |
|---|---|---|---|
| VPCs, subnets, route tables, NAT, endpoints (ssm/ssmmessages/ec2messages/s3/logs) | TF | `network` stack per env | rare |
| Security groups for each app tier | TF/CFN | created by `modules/ec2-app` & CFN template | per app |
| Inter-account/VPC connectivity (TGW/peering/PrivateLink) | TF | network stack | as needed |
| DNS (Route 53 zones/records), ACM certs | TF | per-app stacks | per app |
| Databricks workspace networking (customer-managed VPC, PrivateLink) | TF | `databricks` + `aws` providers | per workspace |
| SG drift / open-port audit | Config + Security Hub | doc 04 | continuous |

## C. AMI Factory & Patch Governance (core mandate)

| Task | Method | Template / How | Cadence |
|---|---|---|---|
| Resolve latest AL2023 base AMI | Packer/CFN | SSM public param (in both templates) | every build |
| Build custom AMI (update, remove denied pkgs, versionlock, harden, clean) | Packer **or** Image Builder | `ami-factory/packer/al2023-base.pkr.hcl` · `ami-factory/imagebuilder/imagebuilder-pipeline.yaml` | monthly + CVE |
| Trigger a build from desktop | BAT | `scripts/windows/build-ami.bat` (packer \| pipeline modes) | on demand |
| Maintain approved/denied/excluded package lists | git | `ami-factory/packer/patch-policy/*.txt` (MR-reviewed) | as approved |
| Smoke-test candidate AMI | ANS/SSM doc | run `site.yml --check` against test instance; Image Builder test phase | every build |
| Encrypt + share AMI to member accounts | Packer/CFN | `encrypt_boot`/distribution config in templates | every build |
| Publish "latest approved" pointer | BAT/CI | `scripts/windows/publish-latest-ami.bat` → SSM `/dataapps/ami/<family>/latest` | every build |
| Deprecate/retire old AMIs (+snapshots) | Packer `deprecate_at` / Image Builder lifecycle | in templates; cleanup query in `ec2-ops.bat` notes | monthly |
| Restrict account to factory AMIs | MAN once | EC2 **Allowed AMIs** setting | once/env |
| Runtime patch compliance scan | SSM Patch Manager | custom baseline mirroring patch-policy lists; scan-only for golden-AMI fleets | daily scan |
| Fleet refresh onto new AMI | TF/CFN | bump = SSM param already bumped → `terraform plan` shows replacement / ASG instance refresh | monthly |
| AL2 stragglers hunt (EOL 2026-06-30) | BAT/Config | `aws ssm describe-instance-information` filter PlatformName | weekly until zero |

## D. Compute Provisioning (three supported methods)

| Task | Method | Template / How | Cadence |
|---|---|---|---|
| Stand up app node group (SG, IAM, instances/ASG, volumes) — Terraform path | TF | `terraform/modules/ec2-app` used by `environments/dev/main.tf` | per app/env |
| Same — CloudFormation path | CFN | `cloudformation/templates/ec2-app-cluster.yaml` + `parameters/dev-kafka.json` via `cfn-deploy.bat` | per app/env |
| Same — manual path (break-glass) | MAN | console launch from pointer AMI, tag `ManagedBy=manual`, codify ≤ 5 days (guide §6) | exception |
| Start/stop/reboot, list fleet, snapshot, image, connect | BAT | `scripts/windows/ec2-ops.bat` (menu) | daily |
| Resize instance / volume (gp3 throughput/IOPS) | TF/CFN + BAT | change in IaC; emergency via ec2-ops | as needed |
| Keypair-less access (Session Manager) | BAT | `ec2-ops.bat` option 6 / `aws ssm start-session` | daily |

## E. Configuration Management & App Deploys

| Task | Method | Template / How | Cadence |
|---|---|---|---|
| Converge OS baseline | ANS | `roles/common` | every run |
| Install/config Kafka (ZK 3.9.x or KRaft) | ANS | `roles/kafka` (+`roles/zookeeper`) | per change |
| Install/config NiFi 2.x | ANS | `roles/nifi` | per change |
| Install/config OpenSearch | ANS | `roles/opensearch` | per change |
| Install/config PostgreSQL | ANS | `roles/postgres` | per change |
| Deploy custom Java app version | ANS | `roles/java_app` (artifact from S3, systemd) | per release |
| Databricks cluster policies / init scripts / permissions | TF | `databricks` provider stack (no AMIs!) | per change |
| Ad-hoc command across fleet | ANS/SSM | `ansible app_kafka -m shell -a ...` or SSM Run Command | as needed |
| Config drift check | ANS | scheduled `--check --diff` pipeline (gitlab/ci/ansible) | nightly |

## F. CI/CD & Repositories

| Task | Method | Template / How | Cadence |
|---|---|---|---|
| Terraform pipeline (fmt/validate/lint/sec/plan/apply-gated) | GitLab CI | `gitlab/ci/terraform.gitlab-ci.yml` | every MR |
| CFN pipeline (cfn-lint/guard/changeset/deploy) | GitLab CI | `gitlab/ci/cloudformation.gitlab-ci.yml` | every MR |
| Packer AMI pipeline | GitLab CI | `gitlab/ci/packer.gitlab-ci.yml` | monthly/manual |
| Ansible pipeline (lint/check/apply) | GitLab CI | `gitlab/ci/ansible.gitlab-ci.yml` | every MR |
| Keep both GitLabs in sync; verify; repair divergence | sync tool + BAT | `docs/05-GITLAB-DUAL-SYNC.md`, `scripts/windows/gitlab-sync.bat` | continuous |
| Module/provider version bumps | Renovate bot (doc 04) | scheduled MRs | weekly |

## G. Observability

| Task | Method | Template / How | Cadence |
|---|---|---|---|
| CloudWatch agent + default log/metric config | AMI + ANS | baked in `01-baseline.sh`; per-app config in roles | build/run |
| Alarms & dashboards as code | TF/CFN | per-app stack alongside compute | per app |
| Log retention & subscription filters | TF | logging stack | once/env |
| Synthetic checks for app endpoints | TF | CloudWatch Synthetics canaries | per app |
| AI-assisted incident triage | CloudWatch investigations / Q | doc 04 | per incident |

## H. Data Protection / Backup / DR

| Task | Method | Template / How | Cadence |
|---|---|---|---|
| Backup plans by tag (EBS/RDS/EFS) | TF | AWS Backup stack | once + audits |
| On-demand snapshot before risky change | BAT | `ec2-ops.bat` option 5 | as needed |
| Cross-region copy for tier-1 | TF | backup plan copy actions | continuous |
| Restore test | MAN + ANS | quarterly game-day; converge restored node with Ansible | quarterly |
| Kafka/OpenSearch data-level DR (MirrorMaker2 / snapshots to S3) | ANS | app-specific roles/runbooks | per design |

## I. Security & Compliance

| Task | Method | Template / How | Cadence |
|---|---|---|---|
| CloudTrail/Config/GuardDuty/Security Hub org-wide | TF | security stack | once |
| Policy-as-code gates (encrypted vols, IMDSv2, tags) | cfn-guard/checkov | wired in CI templates | every MR |
| Secrets rotation | Secrets Manager | rotation lambdas; write-only TF args | scheduled |
| Vulnerability scanning of AMIs/instances | Inspector | enable per account; gate AMI publish on findings | continuous |
| Console-change weekly digest | EventBridge→Lambda | doc 04 recipe | weekly |
| Patch compliance report | SSM Patch Manager | compliance dashboard export | weekly |

## J. Cost (FinOps)

| Task | Method | Template / How | Cadence |
|---|---|---|---|
| Budgets + anomaly alerts | TF | finops stack | once |
| Dev off-hours scheduling | EventBridge/Instance Scheduler | doc 04 quick win | continuous |
| Rightsizing review (Compute Optimizer) | MAN/BAT report | monthly export | monthly |
| Savings Plans / RIs for steady fleets | MAN (Finance) | quarterly review | quarterly |
| Orphan cleanup (unattached EBS, old snaps, idle EIPs) | BAT/Lambda | query in `ec2-ops.bat` notes; automate per doc 04 | weekly |

## K. Lifecycle / Decommission

| Task | Method | Template / How | Cadence |
|---|---|---|---|
| Decommission app/env | TF/CFN | `terraform destroy` plan-reviewed / stack delete with Retain on data | as needed |
| State surgery (rename/move/remove) | TF | `moved{}` / `removed{}` blocks, never raw `state rm` first | as needed |
| AMI/snapshot retention enforcement | lifecycle policies | factory templates | continuous |
| Offboard operator | Identity Center | group removal; access review | as needed |
