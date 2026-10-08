# Client Discovery Question Bank
### Pre-Demo Infrastructure Assessment — Prometheus & Grafana on AWS

> Use this question bank before a client demo to understand their AWS environment and tailor the Prometheus & Grafana setup accordingly.

---

## 🏗️ 1. General AWS Infrastructure

| # | Question | Why It Matters |
|---|----------|----------------|
| 1 | How many AWS accounts do you manage? (single vs. multi-account) | Determines if we need multi-account discovery |
| 2 | Which AWS regions are your workloads deployed in? | Region-specific scraping & CloudWatch config |
| 3 | Do you use AWS Organizations for account management? | Affects IAM role federation strategy |
| 4 | Are you using AWS Landing Zone or Control Tower? | Helps with IAM & permission boundaries |

---

## 💻 2. Compute (EC2)

| # | Question | Why It Matters |
|---|----------|----------------|
| 5 | How many EC2 instances are running across all environments? | Sizing & target configuration |
| 6 | What OS types are in use? (Amazon Linux, Ubuntu, Windows Server) | Node Exporter vs. Windows Exporter selection |
| 7 | Do your EC2 instances use Auto Scaling Groups (ASGs)? | Dynamic target discovery is needed |
| 8 | Are instances tagged consistently? (e.g., `env`, `team`, `app`) | Tag-based auto-discovery in Prometheus |
| 9 | Do instances have internet access or are they in private subnets? | Determines if exporters need internal scraping |
| 10 | Are EC2 instances managed via AWS Systems Manager (SSM)? | Can use SSM for exporter installation |

---

## 🐳 3. Containers & Serverless

| # | Question | Why It Matters |
|---|----------|----------------|
| 11 | Are you using Amazon ECS? If so, EC2 launch type or Fargate? | ECS-specific metrics collection differs |
| 12 | Do you use Amazon EKS (Kubernetes)? | Needs kube-state-metrics + Prometheus Operator |
| 13 | Are you using AWS Lambda functions? | CloudWatch Exporter or Lambda Insights needed |
| 14 | How many Lambda functions are being monitored? | Determines scrape volume |

---

## 🌐 4. Networking & Load Balancing

| # | Question | Why It Matters |
|---|----------|----------------|
| 15 | Do you use Application Load Balancers (ALB) or Network Load Balancers (NLB)? | ALB/NLB metrics via CloudWatch Exporter |
| 16 | Are you using API Gateway? (REST / HTTP / WebSocket) | API Gateway metrics & WAF rules dashboards |
| 17 | Do you use AWS WAF? If so, attached to CloudFront or ALB? | WAF dashboard panel configuration |
| 18 | Are there any public-facing websites or endpoints to monitor SSL certs? | SSL/TLS cert expiry monitoring with Blackbox Exporter |
| 19 | Are you using Route 53 health checks? | Can supplement Blackbox probes |
| 20 | Do you use VPC endpoints or PrivateLink? | Affects network path for scraping |

---

## 🗄️ 5. Databases & Storage

| # | Question | Why It Matters |
|---|----------|----------------|
| 21 | Are you using Amazon RDS or Aurora? What engines? (MySQL, Postgres, etc.) | RDS Exporter configuration |
| 22 | Do you use ElastiCache (Redis/Memcached)? | CloudWatch Exporter for cache metrics |
| 23 | Are you using DynamoDB? | DynamoDB metrics via CloudWatch |
| 24 | Do you use S3 buckets with storage metrics monitoring requirements? | S3 storage lens / CloudWatch |

---

## 🔐 6. IAM & Security

| # | Question | Why It Matters |
|---|----------|----------------|
| 25 | Can we create IAM roles for cross-account access? | Required for multi-account auto-discovery |
| 26 | Do you follow least-privilege principles? Can we get read-only CloudWatch/EC2 permissions? | IAM policy scoping |
| 27 | Are there any SCPs (Service Control Policies) that restrict API calls? | May block `ec2:DescribeInstances` calls |
| 28 | Is there a VPN or Direct Connect between on-prem and AWS? | Affects Prometheus scrape paths |

---

## 📬 7. Alerting & Notifications

| # | Question | Why It Matters |
|---|----------|----------------|
| 29 | What is your current alerting setup? (CloudWatch Alarms, PagerDuty, etc.) | Understanding gaps we fill |
| 30 | Do you use Microsoft Teams, Slack, or email for incident notifications? | Alertmanager receiver configuration |
| 31 | Do you have an on-call rotation or incident management tool? (OpsGenie, PagerDuty) | Alertmanager integration |
| 32 | Are there existing SLA/SLO thresholds we should configure alerts around? | Alert rule tuning |

---

## 📊 8. Current Monitoring Maturity

| # | Question | Why It Matters |
|---|----------|----------------|
| 33 | What monitoring tools are currently in use? (Datadog, New Relic, CloudWatch, etc.) | Avoid duplication, plan migration |
| 34 | Do you have any existing dashboards? Can we see what metrics matter most? | Dashboard design priorities |
| 35 | Do you have log aggregation in place? (CloudWatch Logs, Splunk, ELK) | Loki + Promtail integration opportunity |
| 36 | Is there a defined retention period for metrics? (30 days, 90 days, 1 year?) | Prometheus storage & Thanos planning |

---

## 🚀 9. Deployment & Operations

| # | Question | Why It Matters |
|---|----------|----------------|
| 37 | How is your infrastructure managed? (Terraform, CloudFormation, CDK, manual?) | Exporter deployment method |
| 38 | Do you use CI/CD pipelines? Which tool? (GitHub Actions, Jenkins, CodePipeline) | Automated dashboard deployment support |
| 39 | Where would the Prometheus/Grafana stack be hosted? (EC2, ECS, or existing Kubernetes?) | Architecture planning |
| 40 | Do you have a preference for managed vs. self-hosted Grafana? (Grafana Cloud vs. self-hosted) | Licensing & cost discussion |

---

## 🎯 Quick Priority Checklist (Must-Ask Before Demo)

> These are the **top 5 essential questions** to answer before walking in:

1. ✅ **Single or multi-account AWS setup?**
2. ✅ **EC2 + ECS/EKS/Lambda usage?**
3. ✅ **Windows or Linux (or both) EC2 instances?**
4. ✅ **Current alerting channel (Teams/Slack/email)?**
5. ✅ **Self-hosted or managed Grafana preference?**

---

*Last updated: October 2026*
