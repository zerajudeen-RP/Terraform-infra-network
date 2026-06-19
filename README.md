# MCT Australia — Centralized Network Hub

Centralized repo to provision the network hub for the Australia region (`ap-southeast-2`).  
This hub provides shared ingress, egress, inspection, and AWS service endpoint connectivity for all workload accounts (demo, stage, prod).

---

## Architecture Diagram

![Network Hub Architecture](./network-hub-architecture.drawio)

> Open the `.drawio` file in [draw.io](https://app.diagrams.net) or VS Code with the Draw.io extension for an interactive view.

---

## Traffic Flow Overview

### Ingress Path (Internet → Workload)

```
Internet
    │
    ▼
IGW (Ingress VPC)
    │
    ▼  ← IGW Edge RT routes NLB/ALB subnet CIDRs → NFW endpoints
Ingress Network Firewall (Suricata inspection)
    │
    ▼
NLB (per environment: demo / stage / prod) — public, internet-facing
    │
    ▼  ← TCP forward, target_type="alb"
ALB (per environment: demo / stage / prod) — internal
    │
    ▼  ← ALB listener rules (host-header / path-pattern) route to target IPs
TGW (via ALB subnet RT: spoke_cidrs → TGW)
    │
    ▼  ← Core RT has propagated spoke CIDRs
Workload VPC (stage / prod / demo account)
```

### Egress Path (Workload → Internet)

```
Workload VPC
    │
    ▼  ← TGW attachment associated with Spoke RT
TGW (Spoke RT: 0.0.0.0/0 → Inspect VPC attachment)
    │
    ▼
Inspect VPC — TGW Subnet
    │
    ▼  ← TGW RT: 0.0.0.0/0 → NFW endpoint
Egress Network Firewall (Suricata inspection)
    │
    ▼  ← FW RT: 0.0.0.0/0 → NAT GW
NAT Gateway (per AZ)
    │
    ▼  ← NAT RT: 0.0.0.0/0 → IGW
IGW (Inspect VPC)
    │
    ▼
Internet
```

### AWS Service Traffic (Workload → Endpoints VPC)

```
Workload VPC
    │
    ▼  ← Spoke RT: endpoints_vpc_cidr → endpoints attachment
TGW
    │
    ▼
Endpoints VPC — Interface Endpoints (S3, ECR, SSM, KMS, etc.)
    │
    ▼  ← Response returns via TGW to spoke
Workload VPC
```

---

## Resources Created


| Module | Resources | Purpose |
|--------|-----------|---------|
| `ipam` | IPAM Pool lookup | Provides pool ID for VPC CIDR allocation |
| `tgw` | Transit Gateway, 3 Route Tables (Core, Spoke-Stage, Spoke-Prod) | Central routing between all VPCs |
| `ingress_vpc` | VPC, IGW, Subnets (NLB×3 envs, ALB×3 envs, FW×3, TGW×3), SGs, Route Tables, TGW Attachment | Ingress traffic handling |
| `ingress_nfw` | AWS Network Firewall, Suricata rule group, CloudWatch logs | Ingress traffic inspection |
| `inspect_vpc` | VPC, IGW, Subnets (FW×3, TGW×3, NAT×3), NAT GWs, EIPs, Route Tables, TGW Attachment | Egress traffic inspection + NAT |
| `network_firewall` | AWS Network Firewall, Suricata rule group, CloudWatch logs | Egress traffic inspection (in inspect VPC) |
| `endpoints_vpc` | VPC, Subnets (Endpoints×3, TGW×3), Interface Endpoints (18 services), Gateway Endpoints (S3, DynamoDB), SG, TGW Attachment | Centralized AWS PrivateLink access |
| `alb` (×3) | Internal ALB, Listeners (HTTP/HTTPS), Target Groups, Listener Rules | L7 routing per environment |
| `nlb` (×3) | Internet-facing NLB, Listeners (TCP/TLS), ALB Target Group | L4 entry point per environment |
| `waf` (×3) | WAFv2 Web ACL, Rate limiting, Logging | Web application firewall per ALB |
| `acm` (×3) | ACM Certificate, Route53 CNAME validation records | TLS certificates per environment |
| `ram` | RAM Resource Share, Principal Associations | Share TGW with workload accounts |
| `tgw_routes` | Static routes in Core RT and Spoke RTs, Blackhole routes | TGW route population |
| `tgw_spoke_attachments` | RT Associations, RT Propagations (spoke + core) | Cross-account workload onboarding |

---

## VPCs and Subnets

### Ingress VPC (`/21` — 2048 IPs)

| Subnet Tier | Size | Count | Purpose |
|-------------|------|-------|---------|
| ALB Demo | /27 (32 IPs) | 3 AZs | Internal ALB for demo |
| NLB Demo | /27 (32 IPs) | 3 AZs | Public NLB for demo |
| ALB Stage | /27 (32 IPs) | 3 AZs | Internal ALB for stage |
| NLB Stage | /27 (32 IPs) | 3 AZs | Public NLB for stage |
| ALB Prod | /25 (128 IPs) | 3 AZs | Internal ALB for prod |
| NLB Prod | /25 (128 IPs) | 3 AZs | Public NLB for prod |
| Firewall | /27 (32 IPs) | 3 AZs | Ingress NFW endpoints |
| TGW Attach | /28 (16 IPs) | 3 AZs | TGW attachment ENIs |

### Inspect VPC (`/22` — 1024 IPs)

| Subnet Tier | Size | Count | Purpose |
|-------------|------|-------|---------|
| Firewall | /24 (256 IPs) | 3 AZs | Egress NFW endpoints |
| NAT | /28 (16 IPs) | 3 AZs | NAT Gateways |
| TGW Attach | /28 (16 IPs) | 3 AZs | TGW attachment ENIs |

### Endpoints VPC (`/23` — 512 IPs)

| Subnet Tier | Size | Count | Purpose |
|-------------|------|-------|---------|
| Endpoints | /25 (128 IPs) | 3 AZs | Interface endpoint ENIs |
| TGW Attach | /28 (16 IPs) | 3 AZs | TGW attachment ENIs |

---

## Route Tables — Complete Reference


### Ingress VPC Route Tables

#### IGW Edge Route Table
*Associated with: Internet Gateway*

| Destination | Target | Purpose |
|-------------|--------|---------|
| NLB Demo CIDRs (per AZ) | NFW Endpoint (per AZ) | Inspect inbound before reaching NLB |
| ALB Demo CIDRs (per AZ) | NFW Endpoint (per AZ) | Inspect inbound before reaching ALB |
| NLB Stage CIDRs (per AZ) | NFW Endpoint (per AZ) | Inspect inbound before reaching NLB |
| ALB Stage CIDRs (per AZ) | NFW Endpoint (per AZ) | Inspect inbound before reaching ALB |
| NLB Prod CIDRs (per AZ) | NFW Endpoint (per AZ) | Inspect inbound before reaching NLB |
| ALB Prod CIDRs (per AZ) | NFW Endpoint (per AZ) | Inspect inbound before reaching ALB |

#### Firewall Route Table (per AZ)
*Associated with: Firewall subnets*

| Destination | Target | Purpose |
|-------------|--------|---------|
| 0.0.0.0/0 | IGW | Post-inspection traffic exits to internet |

#### NLB Route Table (per AZ)
*Associated with: NLB Demo, NLB Stage, NLB Prod subnets*

| Destination | Target | Purpose |
|-------------|--------|---------|
| 0.0.0.0/0 | NFW Endpoint (per AZ) | Return traffic goes through firewall |

#### ALB Route Table (per AZ)
*Associated with: ALB Demo, ALB Stage, ALB Prod subnets*

| Destination | Target | Purpose |
|-------------|--------|---------|
| 0.0.0.0/0 | NFW Endpoint (per AZ) | Return traffic to internet via firewall |
| spoke_cidrs (each) | TGW | Forward to workload VPCs via Transit Gateway |

#### TGW Attach Route Table (per AZ)
*Associated with: TGW attachment subnets*

| Destination | Target | Purpose |
|-------------|--------|---------|
| NLB Demo CIDR (per AZ) | NFW Endpoint | Return from workload to NLB via firewall |
| ALB Demo CIDR (per AZ) | NFW Endpoint | Return from workload to ALB via firewall |
| NLB Stage CIDR (per AZ) | NFW Endpoint | Return from workload to NLB via firewall |
| ALB Stage CIDR (per AZ) | NFW Endpoint | Return from workload to ALB via firewall |
| NLB Prod CIDR (per AZ) | NFW Endpoint | Return from workload to NLB via firewall |
| ALB Prod CIDR (per AZ) | NFW Endpoint | Return from workload to ALB via firewall |

---

### Inspect VPC Route Tables

#### TGW Attach Route Table (per AZ)
*Associated with: TGW attachment subnets*

| Destination | Target | Purpose |
|-------------|--------|---------|
| 0.0.0.0/0 | NFW Endpoint (per AZ) | All egress traffic goes to firewall for inspection |

#### Firewall Route Table (per AZ)
*Associated with: Firewall subnets*

| Destination | Target | Purpose |
|-------------|--------|---------|
| 0.0.0.0/0 | NAT Gateway (per AZ) | Post-inspection egress via NAT |
| 10.220.0.0/16 | TGW | Return traffic to spoke/hub VPCs |

#### NAT Route Table (per AZ)
*Associated with: NAT subnets*

| Destination | Target | Purpose |
|-------------|--------|---------|
| 0.0.0.0/0 | IGW | NAT Gateway exits to internet |
| 10.220.0.0/16 | TGW | Return traffic to spoke/hub VPCs |

---

### Endpoints VPC Route Tables

#### Endpoint Subnet Route Table (per AZ)
*Associated with: Endpoint subnets*

| Destination | Target | Purpose |
|-------------|--------|---------|
| 0.0.0.0/0 | TGW | All return traffic routes back through TGW |

#### TGW Attach Route Table (per AZ)
*Associated with: TGW attachment subnets*

| Destination | Target | Purpose |
|-------------|--------|---------|
| 0.0.0.0/0 | TGW | Return traffic back to originating spoke |

---


### Transit Gateway Route Tables

#### Core Route Table
*Associated with: Ingress VPC, Inspect VPC, Endpoints VPC attachments*

| Destination | Target | Purpose |
|-------------|--------|---------|
| Ingress VPC CIDR | Ingress VPC Attachment | Traffic to ingress VPC (ALB return, health checks) |
| Inspect VPC CIDR | Inspect VPC Attachment | Traffic to inspect VPC |
| Endpoints VPC CIDR | Endpoints VPC Attachment | Traffic to endpoints VPC |
| Spoke VPC CIDRs | Spoke Attachments (propagated) | Forward traffic to workload VPCs |
| 10.0.0.0/9 | Blackhole | Drop unexpected RFC1918 traffic |
| 10.128.0.0/9 | Blackhole | Drop unexpected RFC1918 traffic |
| 172.16.0.0/12 | Blackhole | Drop unexpected RFC1918 traffic |
| 192.168.0.0/16 | Blackhole | Drop unexpected RFC1918 traffic |

#### Spoke Stage Route Table
*Associated with: Stage workload VPC TGW attachments*

| Destination | Target | Purpose |
|-------------|--------|---------|
| 0.0.0.0/0 | Inspect VPC Attachment | All egress → inspect VPC for NAT + firewall |
| Ingress VPC CIDR | Ingress VPC Attachment | Return traffic to ALB/NLB |
| Endpoints VPC CIDR | Endpoints VPC Attachment | Access AWS service endpoints |
| spoke_cidrs (each) | Blackhole | Prevent spoke-to-spoke lateral movement |
| 10.0.0.0/9 | Blackhole | Drop unexpected RFC1918 traffic |
| 10.128.0.0/9 | Blackhole | Drop unexpected RFC1918 traffic |
| 172.16.0.0/12 | Blackhole | Drop unexpected RFC1918 traffic |
| 192.168.0.0/16 | Blackhole | Drop unexpected RFC1918 traffic |

#### Spoke Prod Route Table
*Associated with: Prod workload VPC TGW attachments*

| Destination | Target | Purpose |
|-------------|--------|---------|
| 0.0.0.0/0 | Inspect VPC Attachment | All egress → inspect VPC for NAT + firewall |
| Ingress VPC CIDR | Ingress VPC Attachment | Return traffic to ALB/NLB |
| Endpoints VPC CIDR | Endpoints VPC Attachment | Access AWS service endpoints |
| spoke_cidrs (each) | Blackhole | Prevent spoke-to-spoke lateral movement |
| 10.0.0.0/9 | Blackhole | Drop unexpected RFC1918 traffic |
| 10.128.0.0/9 | Blackhole | Drop unexpected RFC1918 traffic |
| 172.16.0.0/12 | Blackhole | Drop unexpected RFC1918 traffic |
| 192.168.0.0/16 | Blackhole | Drop unexpected RFC1918 traffic |

---

## Environment Isolation

| Mechanism | How it works |
|-----------|--------------|
| Separate NLB/ALB per env | Each environment has its own NLB+ALB pair in dedicated subnets. DNS routes users to the correct NLB. |
| Separate TGW Route Tables | Stage workloads associate to Spoke Stage RT, Prod workloads associate to Spoke Prod RT. |
| Blackhole Routes | Spoke RTs blackhole each spoke CIDR to prevent cross-environment communication. |
| ALB Listener Rules | Host-header and path-pattern matching routes traffic to specific workload target IPs. |
| Security Groups | ALB SG only allows traffic from NLB SG. NLB SG allows 80/443 from internet. |

---

## Cross-Account Connectivity

### How workload accounts connect:

1. **RAM Share** — TGW is shared via AWS RAM to workload account IDs (configured in `workload_account_ids`)
2. **Accept Invitation** — Workload account accepts RAM share (auto-accept if same AWS Org)
3. **Create TGW Attachment** — Workload account attaches its VPC to the shared TGW
4. **Hub Onboarding** — Add the attachment ID to `spoke_attachment_ids` in the hub's `terraform.tfvars`
5. **Apply Hub** — `tgw_spoke_attachments` module associates the attachment to the correct spoke RT and propagates its CIDR to both spoke and core RTs

### Current configuration:

```hcl
# terraform.tfvars
workload_account_ids = ["034866042265"]  # stage account
```

To add more accounts:
```hcl
workload_account_ids = [
  "034866042265",   # stage
  "XXXXXXXXXXXX",   # prod
  "XXXXXXXXXXXX",   # demo
]
```

---


## Security Controls

| Layer | Control | Details |
|-------|---------|---------|
| Edge | Ingress Network Firewall | Suricata rules inspect all inbound traffic at IGW |
| L4 | NLB Security Group | Only allows TCP 80/443 from 0.0.0.0/0 |
| L7 | ALB Security Group | Only allows traffic from NLB security group |
| L7 | WAFv2 | Rate limiting + managed rule sets on each ALB |
| Egress | Egress Network Firewall | Suricata rules inspect all outbound traffic |
| Network | TGW Blackholes | RFC1918 blackholes prevent unintended routing |
| Network | Spoke Isolation | Blackhole routes prevent spoke-to-spoke traffic |
| TLS | ACM Certificates | Wildcard certs per environment with DNS validation |

---

## Endpoints VPC — Available Services

| Service | Type | Endpoint |
|---------|------|----------|
| S3 | Gateway | com.amazonaws.ap-southeast-2.s3 |
| DynamoDB | Gateway | com.amazonaws.ap-southeast-2.dynamodb |
| SSM | Interface | com.amazonaws.ap-southeast-2.ssm |
| SSM Messages | Interface | com.amazonaws.ap-southeast-2.ssmmessages |
| EC2 Messages | Interface | com.amazonaws.ap-southeast-2.ec2messages |
| EC2 | Interface | com.amazonaws.ap-southeast-2.ec2 |
| KMS | Interface | com.amazonaws.ap-southeast-2.kms |
| Secrets Manager | Interface | com.amazonaws.ap-southeast-2.secretsmanager |
| CloudWatch Logs | Interface | com.amazonaws.ap-southeast-2.logs |
| ECR API | Interface | com.amazonaws.ap-southeast-2.ecr.api |
| ECR Docker | Interface | com.amazonaws.ap-southeast-2.ecr.dkr |
| STS | Interface | com.amazonaws.ap-southeast-2.sts |
| SNS | Interface | com.amazonaws.ap-southeast-2.sns |
| SQS | Interface | com.amazonaws.ap-southeast-2.sqs |
| CloudWatch | Interface | com.amazonaws.ap-southeast-2.monitoring |
| EventBridge | Interface | com.amazonaws.ap-southeast-2.events |
| ELB | Interface | com.amazonaws.ap-southeast-2.elasticloadbalancing |
| Auto Scaling | Interface | com.amazonaws.ap-southeast-2.autoscaling |
| EKS | Interface | com.amazonaws.ap-southeast-2.eks |
| S3 (Interface) | Interface | com.amazonaws.ap-southeast-2.s3 |

---

## ACM Certificates

| Environment | Domain | Status |
|-------------|--------|--------|
| Demo | `*.demo.au.mosaiclinical.ai` | Pending (requires NS delegation) |
| Stage | `*.stage.au.mosaiclinical.ai` | Pending (requires NS delegation) |
| Prod | `*.prod.au.mosaiclinical.ai` | Pending (requires NS delegation) |

**Prerequisite:** Parent zone (`au.mosaiclinical.ai`) must delegate NS records to the Route53 hosted zone nameservers for each subdomain. ACM uses DNS validation via CNAME records in the hosted zone.

---

## IPAM

- **Pool:** `mct-au-network-pool`
- **Supernet:** `10.220.192.0/19`
- All VPC CIDRs are allocated from this pool automatically via `ipv4_ipam_pool_id` on each VPC resource.

---

## Prerequisites

- Terraform >= 1.5.0
- AWS Provider ~> 5.0
- IPAM pool must exist in the account
- Route53 hosted zones must be created for each environment subdomain
- NS delegation must be configured at the parent domain

---

## Usage

```bash
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```
