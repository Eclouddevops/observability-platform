# PostgreSQL Cross-Region Disaster Recovery & Replication

## Overview

This document describes recommended approaches for PostgreSQL disaster recovery
and replication across AWS regions for the `observability-platform` infrastructure.

---

## Option 1: RDS Read Replica (Recommended for Production)

### How it works
AWS RDS supports native cross-region read replicas for PostgreSQL.
A standby replica is created in a secondary region (e.g., `ap-southeast-1`)
and continuously receives replication from the primary in `ap-south-1`.

### Architecture
```
Primary Region (ap-south-1)          DR Region (ap-southeast-1)
─────────────────────────            ───────────────────────────
RDS Primary (postgres) ──────────►  RDS Read Replica (postgres)
     │                                       │
     └── Automated Backups                   └── Promoted to Primary
         (S3, region-local)                      on failover
```

### Terraform Implementation
```hcl
resource "aws_db_instance" "dr_replica" {
  provider = aws.dr   # secondary region provider

  identifier              = "observability-uat-postgres-dr"
  replicate_source_db     = aws_db_instance.primary.arn
  instance_class          = "db.t3.micro"
  publicly_accessible     = false
  skip_final_snapshot     = false
  deletion_protection     = true
  storage_encrypted       = true

  vpc_security_group_ids = [aws_security_group.rds_dr.id]
  db_subnet_group_name   = aws_db_subnet_group.dr.name

  tags = {
    Name = "observability-uat-postgres-dr"
    Role = "read-replica-dr"
  }
}
```

### Failover Procedure
1. **Detect failure** — CloudWatch alarm on `DatabaseConnections`, `FreeStorageSpace`, or RDS events.
2. **Promote replica** — `aws rds promote-read-replica --db-instance-identifier observability-uat-postgres-dr`
3. **Update Secrets Manager** — update the `host` field in the secret to point to the promoted replica endpoint.
4. **Trigger Instance Refresh** on the ASG — instances reload credentials from Secrets Manager on next startup.
5. **Verify application** — check ALB health checks, application logs.
6. **RPO (Recovery Point Objective)**: ~1–2 seconds (async replication lag).
7. **RTO (Recovery Time Objective)**: ~5–10 minutes (promotion + DNS propagation).

### Cost (ap-southeast-1)
- `db.t3.micro` replica: ~$0.034/hr (~$24/month)
- Cross-region data transfer: ~$0.02/GB

---

## Option 2: AWS Backup with Cross-Region Copy

### How it works
AWS Backup creates automated snapshots of RDS and copies them to a secondary region.
This provides a point-in-time recovery target without maintaining a live replica.

### When to Use
- Lower RPO is acceptable (e.g., 24 hours)
- Cost is the primary constraint
- DEV/UAT environments where live replication is unnecessary

### Terraform Implementation
```hcl
resource "aws_backup_vault" "dr" {
  provider = aws.dr
  name     = "observability-uat-dr-vault"
}

resource "aws_backup_plan" "rds_dr" {
  name = "observability-uat-rds-dr"

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.dr.name
    schedule          = "cron(0 2 * * ? *)"   # 02:00 UTC daily

    lifecycle {
      delete_after = 30
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn
    }
  }
}
```

### RPO / RTO
- **RPO**: Up to 24 hours (last backup)
- **RTO**: 30–60 minutes (restore from snapshot + DNS change)

---

## Option 3: Aurora Global Database (Future / Production Scale)

### How it works
Amazon Aurora PostgreSQL-compatible Global Database maintains a primary in `ap-south-1`
with read replicas in up to 5 secondary regions, with sub-second lag.

### Key Benefits
- **Sub-second replication lag** globally
- **Managed failover** in under 1 minute
- **Storage-level replication** (no application changes required)

### Terraform (future reference)
```hcl
resource "aws_rds_global_cluster" "observability" {
  global_cluster_identifier = "observability-global"
  engine                    = "aurora-postgresql"
  engine_version            = "15.4"
  database_name             = "appdb"
  storage_encrypted         = true
}
```

### Cost consideration
Aurora costs ~3x RDS per instance. Recommended only when:
- Strict RPO < 1 second is required
- Throughput exceeds RDS limits
- Multi-region active-active reads are needed

---

## Environment Recommendations

| Environment | DR Strategy            | RPO      | RTO      | Est. Cost/Mo |
|-------------|------------------------|----------|----------|--------------|
| UAT         | Cross-region read replica | ~2s   | ~10 min  | +$24         |
| DEV         | AWS Backup (snapshot)  | 24 hrs   | ~45 min  | +$2–5        |
| PROD (future) | Aurora Global DB     | <1s      | <1 min   | +$80+        |

---

## Current State (as of this implementation)

- UAT and DEV are provisioned in `ap-south-1` (Mumbai) only.
- No cross-region replication is active by default.
- The Terraform modules are structured to support adding a secondary region
  by adding a second AWS provider alias and a `dr_replica` module instantiation.
- Secrets Manager secrets are region-local; update logic must be added for failover automation.

---

## Enabling Multi-Region (Checklist)

- [ ] Add secondary AWS provider alias in `providers.tf` (e.g., `ap-southeast-1`)
- [ ] Create VPC + subnets in secondary region using the `networking` module
- [ ] Add `aws_db_instance` read replica resource pointing to primary ARN
- [ ] Create CloudWatch alarm → SNS → Lambda for automated failover notification
- [ ] Add Route53 health check + failover routing records
- [ ] Test promotion procedure in a lower environment before UAT
- [ ] Document RTO/RPO targets and notify stakeholders
