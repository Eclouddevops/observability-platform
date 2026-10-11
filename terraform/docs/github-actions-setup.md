# GitHub Actions — Terraform CI/CD Setup

## Overview

The workflow `.github/workflows/terraform.yml` runs automatically:

| Trigger | Jobs |
|---|---|
| PR opened / updated (`terraform/**` changed) | validate → plan → **auto-approve** → **auto-merge** |
| Push to `main` (`terraform/**` changed) | validate → plan → **apply** (UAT then DEV) |
| `workflow_dispatch` | plan / apply / destroy for a chosen environment |

---

## Required GitHub Secrets

Navigate to: **Repository → Settings → Secrets and variables → Actions**

| Secret | Value | Required |
|---|---|---|
| `AWS_TERRAFORM_ROLE_ARN` | ARN of the IAM Role GitHub Actions assumes via OIDC | ✅ |

---

## Step 1 — Create the GitHub OIDC Provider in AWS (once per account)

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

---

## Step 2 — Create the Terraform Execution IAM Role

```bash
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::496251222247:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:Eclouddevops/observability-platform:*"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name github-actions-terraform \
  --assume-role-policy-document file://trust-policy.json

# Attach required permissions
aws iam attach-role-policy \
  --role-name github-actions-terraform \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# (Recommended: replace AdministratorAccess with a scoped policy in production)

# Get the ARN to add as a secret
aws iam get-role --role-name github-actions-terraform --query 'Role.Arn' --output text
```

Add the output ARN as secret `AWS_TERRAFORM_ROLE_ARN` in GitHub.

---

## Step 3 — Enable Auto-Merge on the Repository

GitHub requires auto-merge to be enabled at the repo level:

```
Repository → Settings → General → Pull Requests → Allow auto-merge ✅
```

Or via CLI:
```bash
gh api repos/Eclouddevops/observability-platform \
  -X PATCH \
  -f allow_auto_merge=true
```

---

## Step 4 — Create GitHub Environments for Apply Gate

Navigate to: **Repository → Settings → Environments**

Create two environments:

| Environment Name | Protection Rules |
|---|---|
| `terraform-uat` | Optional: required reviewers for extra gate |
| `terraform-dev` | No restrictions (auto-deploys) |
| `terraform-uat-destroy` | Required reviewers (prevent accidental destroy) |
| `terraform-dev-destroy` | Required reviewers |

---

## Workflow Sequence (PR Flow)

```
Developer opens PR with terraform/** changes
         │
         ▼
  ┌─────────────────┐
  │  terraform-     │  fmt / init / validate
  │  validate       │  (UAT + DEV in parallel)
  └────────┬────────┘
           │ ✅ pass
           ▼
  ┌─────────────────┐
  │  terraform-     │  plan (UAT + DEV)
  │  plan           │  posts plan output as PR comment
  └────────┬────────┘
           │ ✅ pass
           ▼
  ┌─────────────────┐
  │  auto-approve   │  posts approval review
  └────────┬────────┘
           │
           ▼
  ┌─────────────────┐
  │  auto-merge     │  squash-merges PR to main
  └────────┬────────┘
           │
           ▼ (push to main triggers apply workflow)
  ┌─────────────────┐
  │  terraform-     │  apply UAT → apply DEV
  │  apply          │  (sequential, auto-approved)
  └─────────────────┘
```

---

## Manual Override

To manually trigger plan/apply/destroy on a specific environment:

```
GitHub → Actions → Terraform CI/CD → Run workflow
  → environment: uat | dev
  → action: plan | apply | destroy
```

---

## Notes

- **Destroy** is only available via `workflow_dispatch` with action=`destroy` — it never runs automatically.
- Plan artifacts are retained for 5 days and attached to each workflow run.
- The `auto-approve` job uses [`hmarr/auto-approve-action`](https://github.com/hmarr/auto-approve-action).
- The `auto-merge` job uses [`peter-evans/enable-pull-request-automerge`](https://github.com/peter-evans/enable-pull-request-automerge).
