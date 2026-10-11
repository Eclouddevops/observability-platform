# Terraform Infrastructure — Observability Platform

AWS infrastructure for `UAT` and `DEV` environments in the **Mumbai region (ap-south-1)**
on account `496251222247`.

---

## Directory Structure

```
terraform/
├── README.md                         ← This file
├── bootstrap/
│   └── main.tf                       ← One-time: S3 state bucket + DynamoDB lock
├── modules/
│   ├── networking/                   ← VPC, subnets, IGW, NAT GW, route tables
│   ├── security/                     ← Security groups (ALB, EC2, RDS)
│   ├── secrets/                      ← AWS Secrets Manager + IAM policy
│   ├── rds/                          ← RDS PostgreSQL
│   ├── loadbalancer/                 ← ALB + NLB + target groups + listeners
│   └── compute/                      ← Launch Template + ASG + IAM role
├── environments/
│   ├── uat/
│   │   ├── providers.tf
│   │   ├── variables.tf
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── uat.tfvars               ← UAT variable values
│   └── dev/
│       ├── providers.tf
│       ├── variables.tf
│       ├── main.tf
│       ├── outputs.tf
│       └── dev.tfvars               ← DEV variable values
└── docs/
    └── postgresql-cross-region-dr.md
```

---

## Architecture Overview

### UAT
| Resource | Action | Detail |
|---|---|---|
| VPC | **Reused** | `vpc-091ee3e5d86345078` |
| Internet Gateway | **Reused** | Existing IGW attached to UAT VPC |
| Public Subnets | **Created** | `10.0.10.0/24`, `10.0.11.0/24` across 2 AZs |
| Private Subnets | **Created** | `10.0.20.0/24`, `10.0.21.0/24` across 2 AZs |
| NAT Gateways | **Created** | 1 per AZ (2 total) |
| Route Tables | **Created** | Public + Private |
| Security Groups | **Created** | ALB, EC2, RDS |
| ALB | **Created** | Public-facing, HTTP → app port |
| NLB | **Created** | Public-facing, TCP |
| Launch Template | **Created** | Amazon Linux 2023, t2.micro, IMDSv2 |
| Auto Scaling Group | **Created** | desired=4, min=2, max=8 |
| RDS PostgreSQL | **Created** | Private subnets, encrypted, `db.t3.micro` |
| Secrets Manager | **Created** | Auto-generated password |
| VPC Flow Logs | **Created** | CloudWatch, 30-day retention |

### DEV
| Resource | Action | Detail |
|---|---|---|
| VPC | **Created** | `10.1.0.0/16` |
| All other resources | **Created** | Same pattern as UAT, isolated state |

---

## Prerequisites

```bash
# 1. Install Terraform >= 1.6
terraform version

# 2. Configure AWS credentials
aws configure
# or use environment variables:
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=ap-south-1

# 3. Verify account access
aws sts get-caller-identity
# Expected: { "Account": "496251222247", ... }
```

---

## Step 0 — Bootstrap Remote State (once per account)

```bash
cd terraform/bootstrap
terraform init
terraform plan
terraform apply
```

This creates:
- S3 bucket: `496251222247-terraform-state` (versioned, encrypted, private)
- DynamoDB table: `terraform-state-lock`

Then **uncomment** the `backend "s3"` block in:
- `environments/uat/providers.tf`
- `environments/dev/providers.tf`

---

## Step 1 — Inspect Existing UAT VPC (IMPORTANT)

Before applying UAT, verify the existing subnet CIDRs to avoid conflicts:

```bash
# List existing subnets in the UAT VPC
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=vpc-091ee3e5d86345078" \
  --query 'Subnets[*].{ID:SubnetId,CIDR:CidrBlock,AZ:AvailabilityZone,Tags:Tags}' \
  --output table

# List existing route tables
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=vpc-091ee3e5d86345078" \
  --query 'RouteTables[*].{ID:RouteTableId,Routes:Routes[*].DestinationCidrBlock}' \
  --output table

# List existing Internet Gateway
aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=vpc-091ee3e5d86345078" \
  --output table

# Get VPC CIDR
aws ec2 describe-vpcs \
  --vpc-ids vpc-091ee3e5d86345078 \
  --query 'Vpcs[0].CidrBlock'
```

**Update** `environments/uat/uat.tfvars` if the default CIDRs conflict with existing subnets.

---

## Step 2 — Deploy UAT

```bash
cd terraform/environments/uat

# Initialize
terraform init

# Validate syntax
terraform validate

# Format check
terraform fmt -check -recursive

# Preview — REVIEW CAREFULLY before applying
terraform plan -var-file="uat.tfvars" -out=uat.plan

# Apply (only after reviewing the plan)
terraform apply uat.plan
```

---

## Step 3 — Deploy DEV

```bash
cd terraform/environments/dev

terraform init
terraform validate
terraform plan -var-file="dev.tfvars" -out=dev.plan
terraform apply dev.plan
```

---

## Post-Deployment Verification

```bash
# View outputs
terraform output

# Verify RDS is private (should return no public endpoint)
aws rds describe-db-instances \
  --db-instance-identifier observability-uat-postgres \
  --query 'DBInstances[0].PubliclyAccessible'

# Verify ASG has 4 instances
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names observability-uat-asg \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Instances:Instances[*].InstanceId}'

# Verify ALB is healthy
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw alb_target_group_arn 2>/dev/null || echo "")
```

---

## Destroy (with caution)

```bash
# DEV — safe to destroy
cd terraform/environments/dev
terraform destroy -var-file="dev.tfvars"

# UAT — deletion protection is enabled on RDS and LBs
# You must first disable protection manually or via:
# terraform apply -var="deletion_protection=false" -var-file="uat.tfvars"
cd terraform/environments/uat
terraform destroy -var-file="uat.tfvars"
```

> ⚠️ **UAT VPC will NOT be destroyed** — it is managed outside Terraform.

---

## Security Notes

| Practice | Implementation |
|---|---|
| DB passwords | Auto-generated by `random_password`, stored in Secrets Manager |
| IMDSv2 enforced | `http_tokens = "required"` in Launch Template |
| No public RDS | `publicly_accessible = false` |
| Least-privilege SGs | EC2 only receives traffic from ALB SG / VPC CIDR |
| EBS encryption | All volumes encrypted at rest |
| RDS encryption | `storage_encrypted = true` |
| VPC Flow Logs | Enabled on all VPCs |
| ALB access logs | Stored in S3, 90-day lifecycle |
| SSH access | Empty by default — set `ssh_allowed_cidrs` to VPN/bastion range |

---

## AWS Service Quotas to Check

| Quota | Default | Check |
|---|---|---|
| VPCs per region | 5 | `aws service-quotas get-service-quota --service-code vpc --quota-code L-F678F1CE` |
| EIPs per region | 5 | Needed for NAT GWs (2 per env = 4 total) |
| RDS instances | 40 | `aws service-quotas list-service-quotas --service-code rds` |
| t2.micro vCPUs | Varies | Check EC2 On-Demand limits |

---

## Estimated Monthly Cost (ap-south-1)

| Resource | UAT | DEV |
|---|---|---|
| EC2 t2.micro × 4 | ~$18 | ~$18 |
| NAT Gateway × 2 | ~$65 | ~$65 |
| RDS db.t3.micro | ~$16 | ~$16 |
| ALB | ~$18 | ~$18 |
| NLB | ~$18 | ~$18 |
| Secrets Manager | ~$0.40 | ~$0.40 |
| S3 (logs) | ~$1 | ~$1 |
| **Total** | **~$136/mo** | **~$136/mo** |

> NAT Gateways are the largest cost driver. For DEV, consider a single NAT GW
> (`enable_nat_gateway = true`, set `private_subnet_cidrs` to a single AZ) to halve costs.

---

## Multi-Region Expansion

See [`docs/postgresql-cross-region-dr.md`](docs/postgresql-cross-region-dr.md) for the
full DR runbook, Terraform snippets, and RPO/RTO targets per environment.
