# terraform-aws-vpc-lattice — SCOPE

Composite module for **Amazon VPC Lattice** — the modern, IAM-native application
networking layer that connects services across VPCs and accounts without the
routing/peering/Transit-Gateway plumbing that PrivateLink and TGW require. A single
module call builds a service network, associates VPCs and services to it, wires
target groups (instances/IPs/Lambda/ALB) behind listeners and path/header rules, and
optionally attaches on-prem/other-VPC resources via a resource gateway.

- **Module type:** Composite
- **Primary resource (keystone):** `aws_vpclattice_service_network.this`

## In-scope resources

The module manages the following (allow-list — 15 resource types):

- `aws_vpclattice_service_network` — keystone; the mesh boundary VPCs/services join
- `aws_vpclattice_service_network_vpc_association` — join a VPC to the service network (`for_each`)
- `aws_vpclattice_service` — a routable application service (`for_each`)
- `aws_vpclattice_service_network_service_association` — join a service to the service network (`for_each`)
- `aws_vpclattice_target_group` — backend targets: INSTANCE/IP/LAMBDA/ALB (`for_each`)
- `aws_vpclattice_target_group_attachment` — static target registration (`for_each`)
- `aws_vpclattice_listener` — front door on a service (`for_each`)
- `aws_vpclattice_listener_rule` — path/header/method routing rules (`for_each`)
- `aws_vpclattice_resource_gateway` — ENI-backed ingress/egress point for resource associations (`for_each`)
- `aws_vpclattice_domain_verification` — proves ownership of a custom domain (`for_each`)
- `aws_vpclattice_resource_configuration` — describes a non-Lattice resource (DNS/IP/ARN) reachable via a resource gateway (`for_each`)
- `aws_vpclattice_service_network_resource_association` — join a resource configuration to the service network (`for_each`)
- `aws_vpclattice_auth_policy` — IAM-policy-shaped auth document on a service network or service (`for_each`)
- `aws_vpclattice_resource_policy` — IAM resource policy controlling cross-account sharing of a service network or service (`for_each`)
- `aws_vpclattice_access_log_subscription` — audit-trail log delivery for a service network or service (`for_each`)

## Out-of-scope resources (consumed by reference)

Referenced by `id`/`arn`, never created here:

- VPC — `vpc_associations[*].vpc_id`, `resource_gateways[*].vpc_id` (from `terraform-aws-vpc`)
- Subnets — `resource_gateways[*].subnet_ids` (from `terraform-aws-vpc`)
- Security groups — `vpc_associations[*].security_group_ids`, `resource_gateways[*].security_group_ids` (from `terraform-aws-security-group`)
- ACM certificate — `services[*].certificate_arn` (from `terraform-aws-acm`, regional)
- Target resources — EC2 instance IDs (`terraform-aws-ec2-instance`), IP addresses, Lambda function ARNs (`terraform-aws-lambda`, Phase 7), or ALB ARNs (`terraform-aws-lb`) referenced by `target_group_attachments[*].target_id`
- Resource-configuration targets — RDS/other resource ARNs (`resource_configurations[*].definition.arn_resource.arn`), on-prem/other-VPC DNS names or IPs
- Access-log destinations — CloudWatch Log Group ARN (`terraform-aws-cloudwatch-log-group`), S3 bucket ARN (`terraform-aws-s3-bucket`), or Kinesis Firehose ARN (`terraform-aws-kinesis-firehose`, Phase 2)

## Consumes

| Input | Type | Source module |
|---|---|---|
| `vpc_associations[*].vpc_id` | `string` (VPC id) | `terraform-aws-vpc` |
| `vpc_associations[*].security_group_ids` | `list(string)` | `terraform-aws-security-group` |
| `resource_gateways[*].vpc_id` | `string` (VPC id) | `terraform-aws-vpc` |
| `resource_gateways[*].subnet_ids` | `list(string)` | `terraform-aws-vpc` |
| `resource_gateways[*].security_group_ids` | `list(string)` | `terraform-aws-security-group` |
| `services[*].certificate_arn` | `string` (ACM cert ARN, regional) | `terraform-aws-acm` |
| `target_group_attachments[*].target_id` | `string` (instance id / IP / Lambda ARN / ALB ARN) | `terraform-aws-ec2-instance` / `terraform-aws-lambda` / `terraform-aws-lb` |
| `target_groups[*].config.vpc_identifier` | `string` (VPC id, omitted for LAMBDA) | `terraform-aws-vpc` |
| `resource_configurations[*].definition.arn_resource.arn` | `string` (ARN of the non-Lattice resource) | e.g. `terraform-aws-rds`, `terraform-aws-rds-aurora` |
| `access_log_subscriptions[*].destination_arn` | `string` (log destination ARN) | `terraform-aws-cloudwatch-log-group` / `terraform-aws-s3-bucket` / `terraform-aws-kinesis-firehose` |

## Required IAM permissions

Least-privilege actions the Terraform identity needs:

| Action | Required for |
|---|---|
| `vpc-lattice:CreateServiceNetwork`, `vpc-lattice:DeleteServiceNetwork`, `vpc-lattice:GetServiceNetwork`, `vpc-lattice:UpdateServiceNetwork` | Service network lifecycle |
| `vpc-lattice:CreateServiceNetworkVpcAssociation`, `vpc-lattice:DeleteServiceNetworkVpcAssociation`, `vpc-lattice:GetServiceNetworkVpcAssociation` | VPC association |
| `vpc-lattice:CreateService`, `vpc-lattice:DeleteService`, `vpc-lattice:GetService`, `vpc-lattice:UpdateService` | Service lifecycle |
| `vpc-lattice:CreateServiceNetworkServiceAssociation`, `vpc-lattice:DeleteServiceNetworkServiceAssociation`, `vpc-lattice:GetServiceNetworkServiceAssociation` | Service association |
| `vpc-lattice:CreateTargetGroup`, `vpc-lattice:DeleteTargetGroup`, `vpc-lattice:GetTargetGroup`, `vpc-lattice:UpdateTargetGroup` | Target group lifecycle |
| `vpc-lattice:RegisterTargets`, `vpc-lattice:DeregisterTargets`, `vpc-lattice:ListTargets` | Target registration |
| `vpc-lattice:CreateListener`, `vpc-lattice:DeleteListener`, `vpc-lattice:GetListener`, `vpc-lattice:UpdateListener` | Listener lifecycle |
| `vpc-lattice:CreateRule`, `vpc-lattice:DeleteRule`, `vpc-lattice:GetRule`, `vpc-lattice:UpdateRule` | Listener-rule lifecycle |
| `vpc-lattice:CreateResourceGateway`, `vpc-lattice:DeleteResourceGateway`, `vpc-lattice:GetResourceGateway` | Resource gateway lifecycle |
| `vpc-lattice:CreateResourceConfiguration`, `vpc-lattice:DeleteResourceConfiguration`, `vpc-lattice:GetResourceConfiguration`, `vpc-lattice:UpdateResourceConfiguration` | Resource-configuration lifecycle |
| `vpc-lattice:CreateServiceNetworkResourceAssociation`, `vpc-lattice:DeleteServiceNetworkResourceAssociation`, `vpc-lattice:GetServiceNetworkResourceAssociation` | Resource association |
| `vpc-lattice:StartDomainVerification`, `vpc-lattice:GetDomainVerification`, `vpc-lattice:DeleteDomainVerification` | Custom-domain verification |
| `vpc-lattice:PutAuthPolicy`, `vpc-lattice:GetAuthPolicy`, `vpc-lattice:DeleteAuthPolicy` | Auth-policy management |
| `vpc-lattice:PutResourcePolicy`, `vpc-lattice:GetResourcePolicy`, `vpc-lattice:DeleteResourcePolicy` | Cross-account resource-policy management |
| `vpc-lattice:CreateAccessLogSubscription`, `vpc-lattice:DeleteAccessLogSubscription`, `vpc-lattice:GetAccessLogSubscription` | Access-log subscription |
| `vpc-lattice:TagResource`, `vpc-lattice:UntagResource`, `vpc-lattice:ListTagsForResource` | Tagging |
| `ec2:DescribeVpcs`, `ec2:DescribeSubnets`, `ec2:DescribeSecurityGroups` | Wiring validation |
| `acm:DescribeCertificate` | Resolving service certificates |
| `logs:CreateLogDelivery`, `s3:PutBucketPolicy` (on the destination, not this identity) | Access-log destination setup — owned by the destination module, not this one |

No `iam:PassRole` is required — VPC Lattice does not assume a service role on the
caller's behalf; `AWS_IAM` auth policies are evaluated against the *caller's* IAM
principal at request time, not a role owned by this module.

## AWS Prerequisites

- **No service-linked role is required** for VPC Lattice itself.
- **A VPC must be associated with the service network
  (`aws_vpclattice_service_network_vpc_association`) before workloads in that VPC can
  reach any Lattice service** on the network — association is not implicit from
  creating a target group in that VPC.
- **VPC Lattice is the modern replacement for PrivateLink/Transit-Gateway-for-app-traffic**
  use cases: it removes the need for per-service VPC endpoints or full-mesh TGW
  routing for HTTP(S)/gRPC application traffic, at the cost of requiring `AWS_IAM`
  (SigV4) or open (`NONE`) auth semantics rather than security-group/route-table
  based segmentation.
- **Cross-account sharing** uses AWS RAM (Resource Access Manager) for service
  networks, plus `aws_vpclattice_resource_policy` for fine-grained principal control —
  RAM share setup itself is out of scope for this module (consumed as a prerequisite).
- **Resource gateways require a dedicated VPC/subnet allocation** (ENIs are created
  per AZ) — plan subnet CIDR budget accordingly, similar to NAT gateways.
- **Region:** VPC Lattice is regional; no us-east-1 constraint (unlike CloudFront/
  WAFv2-CLOUDFRONT/ACM-for-CloudFront). Cross-Region meshes require one service
  network per Region, associated independently.
- **Quotas:** default 3 service networks per account per Region (raisable); 50 VPC
  associations per service network; 200 services per service network; 10 listeners
  per service; 10 rules per listener; 300 target groups per account per Region; 5
  resource gateways per VPC (raisable via Service Quotas).

## Emits

| Output | Description | Consumed by |
|---|---|---|
| `id` | Service network id | tagging, cross-references within this call |
| `arn` | Service network ARN — cross-resource reference type | RAM share, resource/auth policies, cross-account associations |
| `name` | Service network name | audit, RAM share naming |
| `service_ids` | Map of service key → id | audit |
| `service_arns` | Map of service key → ARN | RAM share, `terraform-aws-route53-zone` (custom-domain CNAME target) |
| `service_dns_entries` | Map of service key → DNS entry (domain/hosted zone) | Route 53 records |
| `target_group_ids` | Map of target-group key → id | audit |
| `target_group_arns` | Map of target-group key → ARN | listener/rule wiring outside this call |
| `listener_ids` | Map of listener key → standalone listener id | import, audit |
| `listener_arns` | Map of listener key → ARN | audit |
| `resource_gateway_ids` | Map of resource-gateway key → id | `terraform-aws-vpc` (subnet capacity planning) |
| `resource_gateway_arns` | Map of resource-gateway key → ARN | audit |
| `resource_configuration_ids` | Map of resource-configuration key → id | resource association wiring |
| `resource_configuration_arns` | Map of resource-configuration key → ARN | audit |
| `domain_verification_ids` | Map of domain-verification key → id | `resource_configurations[*].domain_verification_key` |
| `domain_verification_txt_records` | Map of domain-verification key → `{name, value}` | `terraform-aws-route53-zone` (TXT record for proof) |
| `access_log_subscription_arns` | Map of access-log-subscription key → ARN | audit |
| `tags_all` | All tags incl. provider `default_tags` | governance/audit |

## Provider gotchas

- **`aws_vpclattice_target_group.config` shape depends entirely on `type`.** `LAMBDA`
  targets take no `config` block at all (or an empty one); `ALB` targets take
  `config` but **not** `health_check` (unsupported); `INSTANCE`/`IP` take the full
  `config` + optional `health_check`. The module models this as one deeply-typed
  `config` object with all sub-fields optional, and enforces the type-appropriate
  shape via `validation {}` on `var.target_groups` rather than trusting the caller.
- **`aws_vpclattice_listener.name`, `port`, and `protocol` are FORCE-NEW.** Changing
  the listener protocol or port replaces it (and any dependent listener rules).
- **`access_log_subscription` has no `tags` argument** (confirmed against the live
  v6.54 schema) — unlike every other resource in this module, it cannot be tagged.
  Do not add a `tags` key to `access_log_subscriptions[*]` entries; it is silently
  ignored if attempted since the resource schema has no such field.
- **`aws_vpclattice_auth_policy` and `aws_vpclattice_resource_policy` also have no
  `tags` argument** — same as above. Auth/resource policy identity is entirely
  carried by `resource_identifier`/`resource_arn` + `policy`, not tags.
- **`auth_policy`/`resource_policy` `policy` is a raw JSON string with no newlines or
  blank lines** — always build it with `jsonencode()`, never a heredoc, or the API
  rejects the plan. Prefer an explicit least-privilege principal/action list over a
  wildcard `Principal = "*"` (the AWS example uses `"*"` scoped down by a
  `StringNotEqualsIgnoreCase` anonymous-principal condition — treat that as the
  minimum bar, not the target state, for NPI-adjacent services).
- **`resource_configuration_definition` takes exactly one of `arn_resource`,
  `dns_resource`, or `ip_resource`** — the module validates exactly one is set per
  entry in `var.resource_configurations`.
- **`resource_configuration_group_id` vs `resource_gateway_identifier` +
  `protocol`** — a `CHILD` type resource configuration inherits its gateway/protocol
  from its `GROUP` parent and must set `resource_configuration_group_id` instead;
  every other type must set `resource_gateway_identifier`. The module validates one
  of `resource_gateway_key` / `resource_configuration_group_key` is present per entry.
- **A VPC must be associated to the service network before its resources can reach
  services on it** — creating a target group in a VPC does not implicitly join that
  VPC to the mesh; wire a `vpc_associations` entry for every consuming VPC.
- **`aws_vpclattice_service_network_vpc_association` and
  `..._service_association`/`..._resource_association` `service_network_identifier`
  must be an ARN (not just the id) when the associated resource lives in a different
  AWS account** — same-account associations may use either form; this module always
  passes the service network's `arn` output for maximum portability.
- **`aws_vpclattice_access_log_subscription`'s `destination_arn` and
  `resource_identifier` are FORCE-NEW** — redirecting logs to a new destination
  replaces the subscription (brief gap in delivery).
- **Destroy ordering:** listener rules → listeners → target group attachments →
  target groups; service associations → services; VPC/resource associations →
  service network. Terraform sequences all of this via implicit `for_each` key
  references; no explicit `depends_on` should be necessary.

## Secure-by-default decisions

| Posture | Default | Opt-out |
|---|---|---|
| Service-network auth | `auth_type = "AWS_IAM"` (authenticated SigV4 callers only) | `auth_type = "NONE"` (open — discouraged; document the exception) |
| Per-service auth | `services[*].auth_type = "AWS_IAM"` | per-service `auth_type = "NONE"` |
| Auth/resource policies | caller-supplied, `jsonencode()`-built least-privilege document; module never synthesizes a wildcard `Principal = "*"` policy on the caller's behalf | caller opts into a broader policy explicitly — this module will not write one for you |
| Access logging | first-class `access_log_subscriptions` map wired to CloudWatch/S3/Firehose for full audit trail of cross-VPC/cross-account application traffic; strongly recommended in every environment | leaving the map empty (`{}`) is allowed for a quick-start but is a **documented exception** for anything NPI-adjacent |
| Target-group protocol | caller-supplied per target group (`HTTP`/`HTTPS`); README examples default to `HTTPS` for anything crossing a VPC boundary | `HTTP` target groups (internal, same-VPC only) |

## Design decisions

- One composite owns the service network plus every child object (VPC/service/
  resource associations, services, target groups, attachments, listeners, rules,
  resource gateways, resource configurations, domain verifications, auth/resource
  policies, access-log subscriptions) so a single call produces a complete,
  IAM-authenticated, audit-logged application-networking mesh.
- Every child collection is `for_each` over `map(object(...))` keyed by a stable
  caller string — no `count` — mirroring `terraform-aws-lb`'s target-group/listener/
  rule pattern. Cross-references between collections (e.g. a listener's
  `service_key`, a listener rule's `listener_key`, a resource configuration's
  `resource_gateway_key`) resolve through the sibling map's key, not a numeric index.
- `auth_policies`, `resource_policies`, and `access_log_subscriptions` all target
  either the service network or a service by a single `resource_identifier_key`
  field (`"service_network"` or a `services` map key) resolved through a local
  lookup map — this keeps three otherwise-repetitive "which resource does this
  attach to" variables consistent with each other.
- `target_groups[*].config` is one deeply-typed object covering all four target
  types rather than four separate variables, because a caller keys the whole
  target-group map by a single stable string regardless of type; `validation {}`
  blocks catch a type/config mismatch at plan time instead of a runtime API error.
- `terraform-aws-vpc-lattice` sits below `terraform-aws-lambda` (Phase 7) and
  `terraform-aws-rds`/`terraform-aws-rds-aurora` in dependency order for target
  registration, but above `terraform-aws-vpc`/`terraform-aws-security-group`/`terraform-aws-acm`
  which it consumes directly.
