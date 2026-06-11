# Windows scripts (cmd / .bat, AWS CLI v2)

All scripts are plain `cmd` batch — no PowerShell required — and call
`_env.bat` for shared defaults (region, profile, `AWS_PAGER=` so CLI v2
never opens a pager mid-script).

| Script | Does |
|---|---|
| `aws-login.bat [profile]` | SSO login + `sts get-caller-identity` check |
| `build-ami.bat packer\|pipeline` | Packer build OR trigger Image Builder pipeline |
| `publish-latest-ami.bat [family]` | Point `/dataapps/ami/<family>/latest` at newest AMI (the release step) |
| `tf.bat <env> <action>` | Terraform with enforced `plan -out` → `apply tfplan.bin` |
| `cfn-deploy.bat <env> <app>` | cfn-lint (if installed) + `cloudformation deploy` with param file; `--preview` = change set only |
| `ec2-ops.bat ...` | list/start/stop/image/snapshot/SSM-session |
| `gitlab-sync.bat <writer> <reader>` | Manual one-way `git push --mirror` fallback for the sync tool |

Files are CRLF on purpose (`.gitattributes` keeps them that way).
Prereqs: see root `README.md` (winget one-liners).
