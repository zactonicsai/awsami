# AI Automation & Rule-Based Expert Systems for the Cloud Team

Goal: remove toil safely. Climb the ladder one rung at a time — **rules first** (deterministic, auditable), **AI-assisted** second (human stays in the loop), **agentic** last (only with hard guardrails).

```
L1  Rule-based expert systems   → deterministic IF/THEN, full audit, no surprises
L2  AI-assisted (copilot)       → human reviews every action (IaC gen, triage, MR review)
L3  Agentic with guardrails     → AI executes bounded runbooks; approvals + audit + rollback
```

---

## L1 — Rule-Based Expert Systems (start here; highest ROI)

These ARE expert systems: encode the senior engineer's "if X then Y" into managed rule engines.

### 1. Patch-approval expert system (your core requirement)
The approved/denied logic already lives in three rule layers — keep them as the single source of truth:
- **Build rules:** `patch-policy/*.txt` in git → MR review = the approval workflow; the AMI build *fails closed* if a denied package survives.
- **Runtime rules:** SSM Patch Manager baseline = declarative rules (`ApprovedPatches`, `RejectedPatches` + `BLOCK`, auto-approve-after-N-days for non-critical, never for kernel).
- **Account rules:** EC2 Allowed AMIs = "only factory images boot here."
*Optional add-on:* a Lambda "patch advisor" that diffs the latest AL2023 release notes/CVE feed against your lists and opens an MR proposing additions — rules propose, humans approve.

### 2. AWS Config + auto-remediation (compliance expert system)
Detective rule → SSM Automation remediation. Highest-value rules for this estate:
| Rule (managed) | Auto-remediation |
|---|---|
| `required-tags` | notify owner; quarantine SG after 7 days |
| `ec2-imdsv2-check` | `AWS-ConfigureEC2MetadataOptions` runbook |
| `encrypted-volumes` | block via SCP/Guard at create; flag legacy |
| `ec2-instance-managed-by-ssm` | alert (agent/role broken = Ansible blind spot) |
| approved-AMI custom rule (AMI not from factory & > N days old) | notify, then stop in dev |
Pack them into a **conformance pack** so both/all accounts get identical rule sets.

### 3. EventBridge rule patterns (the team's IF/THEN engine)
- `EC2 instance state-change → running` **and** missing `App` tag → Lambda tags from launch-template defaults or stops it (dev).
- `CloudTrail console write event` (ConsoleLogin sourced mutations) → weekly digest to the team channel → feeds the §6 manual-change governance.
- `Secrets Manager rotation failed` → page.
- `Image Builder pipeline SUCCESS` → Lambda runs the same logic as `publish-latest-ami.bat` (update SSM pointer) → optional: trigger downstream `terraform plan` pipelines via GitLab API.
- Cron `dev 20:00 stop / 07:00 start` instance scheduler (tag-driven) — typical 60–70% dev compute saving.

### 4. Policy-as-code = codified review expertise
cfn-guard / checkov / tflint rules in CI are an expert system for MR review. Example Guard rule (enforce IMDSv2 + encryption in any CFN MR):
```
let ec2 = Resources.*[ Type == 'AWS::EC2::LaunchTemplate' ]
rule imdsv2_required when %ec2 !empty {
  %ec2.Properties.LaunchTemplateData.MetadataOptions.HttpTokens == "required"
}
rule ebs_encrypted when %ec2 !empty {
  %ec2.Properties.LaunchTemplateData.BlockDeviceMappings[*].Ebs.Encrypted == true
}
```
Convention: a skip requires an inline justification comment + reviewer sign-off — the rule base only grows.

### 5. Housekeeping bots (Lambda or scheduled GitLab jobs)
Unattached EBS > 14 days → snapshot+delete (dev) / report (prod) · snapshots > retention → delete · AMIs past `deprecate_at` → deregister (factory lifecycle already covers its own) · idle EIPs/ELBs → report · **drift sentinel:** nightly `terraform plan -detailed-exitcode` + CFN `detect-stack-drift`; exit code 2 / DRIFTED opens an issue automatically.

**Pros of L1:** deterministic, cheap, fully auditable, no model risk. **Cons:** only handles anticipated cases; rule sprawl needs ownership (review the rulebook quarterly).

---

## L2 — AI-Assisted (human in the loop)

| Tool | Where it helps this team | Cautions |
|---|---|---|
| **Amazon Q Developer** (console, IDE, CLI) | "Why is this instance unreachable?" console triage; generate first-draft Terraform/CFN/Ansible; explain unfamiliar errors; CLI agent can draft `aws` commands | Treat output as a junior engineer's draft — always `plan`/changeset before apply |
| **CloudWatch investigations / DevOps Guru** | AI-assisted incident correlation across metrics/logs/deploy events for Kafka/OpenSearch incidents | Suggestions, not conclusions; wire to your alarm topics |
| **GitLab Duo** | MR summaries, code review suggestions on TF/Ansible MRs, root-cause hints on failed jobs | License per instance; verify availability on the restricted GitLab |
| **MCP servers + Claude/Q on the desktop 🪟** | AWS Labs publishes **MCP servers** (AWS docs, CDK, cost, Terraform) and HashiCorp ships a **Terraform MCP server** — point Claude Desktop/IDE at them and the assistant answers from *live registry/docs and your real estate* instead of stale memory. Killer for "write a module using current provider 6 syntax" | Start **read-only**; scope IAM of any server that can call AWS; log usage |
| **Bedrock (Claude) summarizers** | Nightly job: summarize Patch Manager compliance + drift reports + cost anomalies into one morning digest | Summaries can omit — keep links to raw data |

Practical first wins: (1) Q Developer in VS Code for TF/Ansible authoring; (2) Terraform MCP server for provider-accurate codegen; (3) Duo MR summaries on `terraform-live`.

---

## L3 — Agentic with Guardrails (later, narrow scope)

Pattern: **Bedrock agent (or Q automation) + Action Group = only pre-approved SSM Automation runbooks**, e.g. "restart NiFi service", "expand gp3 volume +20%", "roll one Kafka broker to latest AMI". The agent chooses *which approved runbook*, never free-form API calls.

Non-negotiable guardrails:
1. Agent IAM = invoke-listed-runbooks only; runbooks themselves are least-privilege and idempotent.
2. Production actions require human approval step (SSM Automation approval action / GitLab manual job).
3. Dry-run/`--check` mode first run, always.
4. Every action → CloudTrail + a dedicated audit log; weekly review.
5. Kill switch: disable the agent role with one SCP toggle.
6. Measure before trusting: shadow-mode (agent recommends, human executes) for 30 days; compare.

**Pros:** 24/7 first-responder for the boring 80%. **Cons:** failure modes are novel; cost; you must invest in evals/audit or don't do it.

---

## Quick-win matrix (effort × payoff)

| Automation | Layer | Effort | Payoff |
|---|---|---|---|
| Patch baseline + Allowed AMIs | L1 | S | High (your core mandate, fails closed) |
| AMI pointer auto-publish on build success | L1 | S | High (zero-touch AMI rollout) |
| Dev off-hours scheduler | L1 | S | High ($) |
| Tag-enforcement Config rule + remediation | L1 | S | Med-High |
| Nightly drift sentinel (TF+CFN) → auto-issue | L1 | M | High |
| Console-change weekly digest | L1 | S | Med (governs manual method) |
| Q Developer + Terraform MCP for authoring | L2 | S | Med-High (speed) |
| Duo MR review on IaC repos | L2 | S | Med |
| Morning AI digest (patch/drift/cost) | L2 | M | Med |
| Renovate bot for provider/collection bumps | L1 | M | Med (kills version-drift between GitLabs) |
| Agentic runbook responder | L3 | L | High *if* guardrailed |

**Sequencing advice:** ship every "S/L1" row this quarter; pilot two L2 items with a feedback doc; revisit L3 only after the drift sentinel and runbook library exist (agents need good runbooks more than good prompts).
