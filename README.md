# AWS Cloud Team Toolkit — Data Applications Platform

Everything an AWS Cloud team needs to run EC2-based data applications
(Kafka, ZooKeeper, NiFi, OpenSearch, Postgres, custom Java apps + Databricks)
with **governed custom AMIs**, **three provisioning methods** (Terraform,
CloudFormation, governed manual/CLI), **Ansible configuration**, **dual GitLab
instances**, and **Windows desktops**.

## Read in this order
| # | File | What it is |
|---|---|---|
| 1 | `docs/00-PLAN.md` | The plan: goals, architecture, workstreams, decisions (D1–D10), 30/60/90 |
| 2 | `docs/01-BEST-PRACTICES-GUIDE.md` | The standards: identity, tagging, AMI factory, TF/CFN/Ansible/CI rules, per-app guidance |
| 3 | `docs/02-TASK-CATALOG.md` | Every Cloud-team task (~70) mapped to method + template + cadence |
| 4 | `docs/03-TOOLS-TIPS-GOTCHAS.md` | Per-tool pros/cons/gotchas/tips + top-12 gotchas + things to avoid |
| 5 | `docs/04-AI-AUTOMATION.md` | Rule-based expert systems → AI-assisted → agentic, with guardrails |
| 6 | `docs/05-GITLAB-DUAL-SYNC.md` | Two-instance contract: single-writer, sync patterns, CI gating, runbook |

## What's runnable in here
```
ami-factory/packer/          Packer HCL2 build of AL2023 golden AMI + patch policy scripts
ami-factory/imagebuilder/    Same factory as managed EC2 Image Builder (CloudFormation)
terraform/                   modules/ec2-app + environments/dev example (Kafka x3)
cloudformation/              ec2-app-cluster.yaml + parameter files (SSM AMI pointer type)
ansible/                     dynamic inventory (EC2 tags) + roles: common, kafka(KRaft/ZK),
                             zookeeper, nifi, opensearch, postgres, java_app
scripts/windows/             .bat tooling: login, build/publish AMI, tf, cfn, ec2-ops, gitlab-sync
gitlab/                      .gitlab-ci.yml + per-stack CI incl. OIDC→AWS auth, dual-instance gating
```

## Windows desktop setup (one-time)
```bat
winget install Amazon.AWSCLI Amazon.SessionManagerPlugin
winget install Hashicorp.Terraform Hashicorp.Packer
winget install Git.Git jqlang.jq Python.Python.3.12
wsl --install -d Ubuntu-24.04   :: Ansible control node lives in WSL2
```
Inside WSL2 Ubuntu: `sudo apt update && sudo apt install -y python3-pip && pip install "ansible-core>=2.20,<2.21" boto3 botocore && cd ansible && ansible-galaxy collection install -r requirements.yml`
Keep the ansible repo clone **inside** the WSL filesystem (`~/work/...`), not `/mnt/c`.

## Quickstart (dev)
```bat
scripts\windows\aws-login.bat dataapps-dev
scripts\windows\build-ami.bat packer            :: or: pipeline
scripts\windows\publish-latest-ami.bat          :: releases /dataapps/ami/al2023-base/latest
scripts\windows\tf.bat dev init
scripts\windows\tf.bat dev plan
scripts\windows\tf.bat dev apply                :: Kafka x3 on the golden AMI
scripts\windows\cfn-deploy.bat dev kafka --preview  :: same cluster, CFN flavor
```
Then from WSL2: `ansible-playbook playbooks/site.yml --limit app_kafka`

## The one diagram to remember
```
   latest AL2023 ──► AMI FACTORY (Packer or Image Builder)
                       │ 00 update · 01 baseline · 02 PATCH POLICY (fail-closed) · 99 clean
                       ▼
              AMI + tags + deprecation
                       ▼
        SSM  /dataapps/ami/al2023-base/latest      ◄── publish-latest-ami.bat / EventBridge
            ▲              ▲                ▲
   Terraform data      CFN parameter     manual CLI/console
   aws_ssm_parameter   type SSM<ImageId> (governed: codify ≤5 days)
            ▼              ▼                ▼
                EC2 data-app clusters  ──►  Ansible (tags = inventory) configures apps
```

Replace every `REPLACE-*` placeholder before first use. Versions current as of
June 2026 — re-verify before adopting (`docs/03` lists where to check).
"# awsami" 
