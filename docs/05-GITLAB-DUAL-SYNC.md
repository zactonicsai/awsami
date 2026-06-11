# Dual-GitLab Structure & Sync Strategy

Two GitLab instances ("**A**" = primary/connected, "**B**" = secondary/restricted) with **identical structure**, kept in sync by your dedicated sync tool. This doc defines the contract that makes that safe, regardless of which tool moves the bits.

## 1. Single-writer rule (the one rule that prevents 90% of pain)

Every repository has exactly **one writable home** at a time. Default: **A is authoritative for all repos; B is read-only mirror** (used for build/runs/DR). If a specific repo must be authored on B (e.g., restricted-network content), flip ownership *for that repo only* and record it:

| Repo | Writer | Reader | Notes |
|---|---|---|---|
| platform-toolkit | A | B | |
| ami-factory | A | B | |
| terraform-modules | A | B | tags must sync (module pins!) |
| terraform-live | A | B | applies may run on either, code authored on A |
| cloudformation | A | B | |
| ansible | A | B | |
| windows-scripts | A | B | |

Bidirectional read-write sync of the same branch is the failure mode to refuse — merge conflicts inside a sync tool have no good resolution.

## 2. Identical structure contract

Must match on both instances (sync tool moves the first group; humans/scripts assert the second):

**Synced by tool (git data):** group/subgroup/repo paths · default branch `main` · all branches & **tags** (module version pins live in tags!) · commit history (mirror, not squash).

**NOT synced — configure per instance, keep a parity checklist:**
- CI/CD variables (`AWS_ROLE_ARN` differs per instance's OIDC provider!)
- Runner registrations + tags (`aws`, `linux` on both)
- Protected branches/tags & approval rules (same names, set twice)
- Webhooks, integrations, tokens, deploy keys
- GitLab version itself — keep A and B within one minor release; CI features (e.g., `id_tokens`, components) must exist on both.

Quarterly parity audit: a small script via the GitLab API on each instance dumps protected branches, variables (names only), runner tags → diff.

## 3. Sync patterns (pick per your tool's nature)

| Pattern | How | Pros | Cons / gotchas |
|---|---|---|---|
| **Native push mirroring** (A→B) | Per-repo "Mirroring repositories" with a B project token | Built-in, near-real-time, all tiers | Per-repo setup (script it via API); token rotation on B; mirrors only git data |
| **Native pull mirroring** (B pulls A) | Premium feature | B controls cadence (good for restricted networks) | Tier-gated; same git-only scope |
| **GitLab Geo** | Instance-level replication | Whole-instance DR, includes more than git | Premium/Ultimate; B is strictly secondary — conflicts with "B sometimes writes" |
| **Special sync tool / scripted** (your case) | Tool drives `git fetch` from writer + `git push --mirror` to reader (or bundle transfer) | Works across air gaps; tool can also sync artifacts/registries | YOU must enforce single-writer; `--mirror` force-pushes — pointing it the wrong direction destroys the reader's extras |
| **Air-gapped bundles** | `git bundle create repo.bundle --all` on A → transfer → `git fetch repo.bundle` + push on B | Survives any network policy | Cadence is manual; tags easy to forget (`--all` includes them — verify) |

The fallback/manual version of the scripted pattern is provided: `→ scripts/windows/gitlab-sync.bat` (fetch from writer, `push --mirror` to reader, with confirmation).

## 4. CI behavior on two instances (avoid double work, keep DR value)

Add an instance guard so pipelines know where they are. In `.gitlab-ci.yml` (provided):

```yaml
workflow:
  rules:
    # Full pipelines on the writer instance
    - if: '$CI_SERVER_HOST == $PRIMARY_GITLAB_HOST'
    # On the mirror: only jobs explicitly marked mirror-safe (e.g., lint) or manual DR runs
    - if: '$CI_SERVER_HOST != $PRIMARY_GITLAB_HOST && $RUN_ON_MIRROR == "true"'
      when: always
    - when: never
```
Set `PRIMARY_GITLAB_HOST` as an instance-level CI variable **on both** (same value). DR drill = set `RUN_ON_MIRROR=true` on B and run a plan/apply to prove B can deploy alone. Note: native push mirrors can also simply disable pipeline triggering on B; the rules above make intent explicit either way.

State & artifacts: Terraform state in **S3** (never GitLab-managed state — it would live on one instance); pipeline artifacts that matter long-term (plans for audit, AMI manifests) also copy to S3.

## 5. Hygiene that prevents sync corruption

- `.gitattributes` committed (provided at repo root): `*.sh eol=lf`, `*.bat eol=crlf`, `* text=auto` — stops CRLF churn commits from Windows desktops that make every sync a diff.
- No binaries > a few MB in git (AMI artifacts → S3; installers → an artifact repo). Use LFS only if BOTH instances + the sync tool support it — verify before first LFS object.
- Signed commits optional but verify the sync tool preserves signatures if you adopt them.
- Force-push to `main` disabled on the writer (protected branch) — history rewrites poison mirrors.

## 6. Divergence runbook (when B has commits A doesn't, or vice versa)

1. **Freeze**: pause the sync tool; protect both repos against pushes.
2. **Diagnose**: `git fetch` both into one local clone (`remote-a`, `remote-b`); `git log --oneline remote-a/main..remote-b/main` and the reverse.
3. **Decide writer truth**: per the table in §1. Commits stranded on the reader get cherry-picked into the writer via a normal MR (review applies!).
4. **Re-baseline reader**: `git push --mirror <reader>` from the writer clone.
5. **Resume** sync; post-incident: how did the reader get writes? (usually a missing protected-branch setting on B — fix the parity checklist).

## 7. Day-1 setup checklist

- [ ] Create identical group tree on B (GitLab API script or manual).
- [ ] Register Linux runners on B with matching tags.
- [ ] Instance CI variables on both: `PRIMARY_GITLAB_HOST`, per-instance `AWS_ROLE_ARN`s.
- [ ] IAM OIDC provider for B's issuer URL; trust policies updated.
- [ ] Protected branches/tags mirrored manually on B; pushes to `main` on B blocked.
- [ ] Sync tool configured A→B for all repos incl. tags; alert on sync failure > 1h.
- [ ] Run the divergence drill once on a sandbox repo before trusting prod repos.
