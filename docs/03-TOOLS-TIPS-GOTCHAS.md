# Tools, Tips, Gotchas — with Pros/Cons

Format per tool: **Use for · Pros · Cons · Gotchas · Tips.** Windows-relevant notes flagged 🪟.

---

## AWS CLI v2
**Use for:** everything scripted on desktops (`.bat`) and quick ops.
**Pros:** single MSI 🪟, SSO-native, `--query` (JMESPath) + `--output table|text|json`, auto-uses OIDC env vars in CI.
**Cons:** JMESPath learning curve; pager surprises in scripts.
**Gotchas 🪟:** cmd quoting — wrap the whole `--query` in **double quotes**; single quotes inside (`Tags[?Key=='Name']`) are fine; **never** try to inline JSON on the cmd line — pass `file://params.json` instead. `&` inside a quoted `--query` (e.g., `sort_by(Images,&CreationDate)`) is safe *only* while quoted. Set `set "AWS_PAGER="` in every script (the templates do).
**Tips:** `aws configure sso` once, name profiles `dataapps-{env}`; `--dry-run` exists on many EC2 calls; `aws ec2 wait` subcommands replace sleep loops.

## Terraform 1.15 (HashiCorp)
**Pros:** plan/apply model, huge module ecosystem, `import`/`moved`/`removed` blocks, `terraform test`, ephemeral values + write-only args keep secrets out of state, S3-native state locking (`use_lockfile`).
**Cons:** BUSL license (fine internally; matters if you embed it in a service you sell); state is a critical secret-bearing artifact you must protect; HCL refactors need care.
**Gotchas:** the S3 backend's `dynamodb_table` is **deprecated** — finish migrating to `use_lockfile = true`, but only after all users/CI are ≥ 1.10 (older binaries won't honor the lockfile). `-target` is a foot-gun outside incidents. Provider **6.x upgrade** has breaking changes vs 5.x — read the upgrade guide before bumping shared modules; new per-resource `region` argument can collide with old multi-provider-alias patterns. Sensitive values still land in state even when marked `sensitive` — write-only args are the real fix.
**Tips:** commit `.terraform.lock.hcl`; `terraform providers lock -platform=linux_amd64 -platform=windows_amd64` so desktops 🪟 and Linux runners share the lock file; `plan -out` then `show -json` for MR review bots.

## OpenTofu (alternative)
**Pros:** MPL-licensed drop-in fork; GitLab's officially supported **CI/CD component** (since GitLab removed Terraform templates in 18.0); state encryption feature.
**Cons:** ecosystem mostly shared but diverging slowly; team must pick one binary org-wide to avoid state/feature skew.
**Tip:** if license review ever blocks Terraform, the provided CI file swaps to the OpenTofu component with ~10 lines changed.

## AWS Provider v6
**Pros:** per-resource `region`, faster multi-region; continuous releases.
**Cons:** major-version churn; some resources renamed/retired from v5.
**Gotcha:** pin `~> 6.0` (not `>=`) and upgrade deliberately with `terraform plan` review per stack.

## CloudFormation
**Pros:** zero state to manage (AWS holds it), StackSets for org-wide rollout, change sets = built-in plan review, drift detection, IaC generator imports console resources, stack refactoring moves resources between stacks, native rollback.
**Cons:** slower iteration than TF for day-to-day; intrinsic-function YAML gets gnarly; cross-stack refs (exports) create tight coupling.
**Gotchas:** 500 resources/template & 200 params (nest stacks); **16 KB user-data**; deleting a stack deletes data stores unless `DeletionPolicy: Retain|Snapshot`; failed creates can stick in `ROLLBACK_COMPLETE` (must delete, then recreate); exports can't change while imported.
**Tips:** `aws cloudformation deploy` is idempotent; param type `AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>` for the AMI pointer; **cfn-lint** (pip) + **CloudFormation Guard** for policy; **Rain** CLI is a nicer dev UX if wanted.

## Packer (HCL2) + amazon plugin
**Pros:** AMI build as code in your normal CI; shell/Ansible provisioners; `amazon-parameterstore` data source resolves latest AL2023; `deprecate_at`, `encrypt_boot`, multi-region copy built in.
**Cons:** BUSL (same note as TF); you own the build network/IAM; temp instances can leak on hard failures.
**Gotchas:** builds need egress (or VPC endpoints + an internal repo mirror) to reach dnf repos; default temp keypair/SG creation may violate strict SCPs — pass `subnet_id`/`security_group_id` explicitly (template does); clean **cloud-init**, machine-id, SSH host keys, and shell history or every child instance is a clone twin (template's `99-cleanup.sh`).
**Tip 🪟:** Packer runs fine natively on Windows for local experiments, but standardize on the CI build for anything published.

## EC2 Image Builder
**Pros:** managed pipeline + schedule, auto-rebuild when the AL2023 parent updates, built-in test phase, distribution (copy/share/encrypt) config, **lifecycle policies** retire old AMIs, defined fully in CFN (template provided).
**Cons:** component DSL less expressive than raw shell-in-Packer (we sidestep this by inlining the same scripts); log-diving for failed builds is via SSM/S3.
**Gotcha:** the build instance profile needs the `EC2InstanceProfileForImageBuilder` + SSM core policies (template includes).

## Ansible (ansible-core 2.20 / community 13)
**Pros:** agentless; AWS dynamic inventory turns tags into groups; SSM connection = no SSH anywhere; huge module set; idempotency model fits golden-AMI + converge.
**Cons:** **no Windows control node** 🪟 (WSL2 required); Python version treadmill (2.20 needs ≥ 3.12 on the control node); speed on large fleets needs tuning (forks, pipelining).
**Gotchas 🪟:** running a project from `/mnt/c/...` in WSL → world-writable dir → **`ansible.cfg` silently ignored**; keep repos in the WSL home (or set `ANSIBLE_CONFIG`). CRLF in templates/scripts breaks remote execution — `.gitattributes` provided. The SSM connection plugin needs an S3 bucket for file transfer + matching region. Collections are NOT pinned by ansible-core — pin in `requirements.yml` or runs differ between the two GitLabs' runners.
**Tips:** `ansible-lint` autofixes a lot (`--fix`); `--check --diff` as a nightly drift job; `interpreter_python = auto_silent` kills the noisy discovery warnings; bump `forks` + `pipelining=True` for fleet-wide runs.

## GitLab CI (18.x)
**Pros:** one platform for code, MR review, pipelines, environments, approvals; OIDC `id_tokens` → AWS roles with zero stored keys; components/includes keep both instances DRY.
**Cons:** premium features (pull mirroring, Geo, protected-env approvals matrix) tier-gated; runner fleet is yours to keep identical on both instances.
**Gotchas:** Terraform CI **templates were removed in 18.0** — pipelines referencing `Terraform/Base.gitlab-ci.yml` break; use the provided jobs or the OpenTofu component. Mirrored repos can double-run pipelines — gate with `rules` on `$CI_SERVER_HOST` (provided). CI/CD variables do **not** sync between instances by design — keep a parity checklist (doc 05).
**Tips:** protect `main` + environment `prod`; `resource_group: prod-apply` serializes applies; store the plan JSON as an MR artifact for reviewers.

## SSM suite (Session Manager · Run Command · Patch Manager · Automation · Parameter Store)
**Pros:** no inbound ports, full audit, fleet commands, patch baselines as data, parameters as the AMI pointer mechanism; agent preinstalled on AL2023.
**Cons:** needs instance role + (for private subnets) VPC endpoints; Session Manager shell ≠ full SSH semantics (port-forwarding covers most gaps).
**Gotchas 🪟:** install the **Session Manager plugin** on desktops or `aws ssm start-session` fails cryptically; Patch Manager "Rejected" needs action `BLOCK` to also stop dependency pull-ins.
**Tips:** advanced-tier parameters only when > 4 KB; use `aws ssm start-session --document-name AWS-StartPortForwardingSession` for private UIs like NiFi.

## Secrets Manager vs Parameter Store
Secrets Manager: rotation, cross-account, per-secret cost → credentials. Parameter Store: free standard tier, SecureString, hierarchical paths → config + the AMI pointer. **Avoid:** secrets in tfvars/user-data/repo; SecureString read into plain TF attributes (use write-only args / runtime Ansible lookups).

## Scanners & helpers
- **cfn-lint** (CFN syntax/best practice) and **CloudFormation Guard** (org policy) — both in CI template.
- **tflint** (TF correctness, AWS ruleset) + **checkov** or **trivy** (security; tfsec merged into trivy). Expect false positives → maintain an inline-skip convention with justification comments.
- **terraform-docs** (module READMEs), **infracost** (cost diff on MRs — great reviewer signal), **pre-commit** (fmt/lint locally 🪟 works fine on Windows + in WSL).
- **jq/yq** 🪟 via winget for anything `--query` can't express.

## Git on Windows 🪟
**Gotchas:** CRLF corrupting shell scripts (the #1 "works on my machine" for this stack) — enforced via `.gitattributes`; 260-char path limit — enable `core.longpaths` + OS policy; case-insensitive FS can hide module path typos until a Linux runner fails.

---

## Top gotchas (cross-cutting, memorize these)

1. **AL2023 ≠ AL2:** `dnf` semantics, versioned/locked `releasever`, no `yum-cron`; AL2 support **ends 2026-06-30**.
2. **Kafka 4.x has no ZooKeeper.** 3.9.x is the last ZK line — pin it until the KRaft migration project.
3. **Databricks ignores your AMI factory** — clusters use Databricks-managed images; standardize via provider + init scripts instead.
4. **NiFi 1→2 is a migration** (Java 21, templates/variable-registry removed), not a version bump.
5. **One resource, one owner:** never let TF and CFN both manage the same resource; tag `ManagedBy`.
6. **Apply the reviewed plan file**, never re-plan at apply time.
7. **Secrets reach Terraform state** unless you use write-only/ephemeral — `sensitive=true` only hides output.
8. **cmd.exe JSON:** always `file://`; always double-quote `--query`.
9. **WSL2 + /mnt/c = ignored ansible.cfg** and perm chaos — work inside the WSL filesystem.
10. **Mirrored GitLab pipelines double-fire** without `CI_SERVER_HOST` rules.
11. **16 KB user-data** — bootstrap minimal, let Ansible do real config.
12. **`ROLLBACK_COMPLETE` stacks must be deleted** before re-creating — design names/idempotent deploys accordingly.

## Things to avoid (with the why)

- Long-lived IAM user keys (leak + dual-GitLab sync nightmare) → SSO + OIDC.
- Hardcoded AMI IDs anywhere → SSM pointer.
- `latest` tags for provider/collection versions in CI → unreproducible across the two instances.
- Editing live boxes by hand without the §6 manual-change workflow → permanent drift.
- One mega-Terraform-state per environment → blast radius; split stacks.
- ZooKeeper on the same hosts as brokers in prod → coupled failure domains.
- OpenSearch heap > ~32 GB (compressed-oops cliff) and missing `vm.max_map_count`.
- Running prod patching as in-place mutation when you own a golden-AMI factory → replace instances instead.
