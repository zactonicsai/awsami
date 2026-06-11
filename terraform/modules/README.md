# Terraform modules

| Module | Purpose |
|---|---|
| `ec2-app` | Generic N-node EC2 cluster for a data application: SG (least-priv + intra-cluster), IAM (SSM + CloudWatch agent), per-node map for stable addressing, encrypted gp3 root + optional data volume, IMDSv2 enforced, `App` tag drives Ansible dynamic inventory. |

## Conventions
- Modules NEVER resolve the AMI pointer themselves — the **root module** reads
  `data "aws_ssm_parameter" "ami"` and passes `ami_id` in. Keeps module pure/testable.
- `nodes` is a **map**, not a count: removing `kafka-2` only destroys kafka-2.
- `ignore_changes = [ami]` on instances: a moved pointer never surprise-replaces
  a stateful node. Rotate explicitly (taint/replace one node at a time).
- Pin module consumption by **git tag** (`?ref=v1.2.0`) in terraform-live —
  tags sync across both GitLab instances, branches drift.
