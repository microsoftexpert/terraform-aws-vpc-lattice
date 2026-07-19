###############################################################################
# Identity (keystone)
###############################################################################

variable "service_network_name" {
 description = <<EOT
Name of the VPC Lattice service network (the keystone mesh boundary that VPCs
and services join). Must be unique within the account/Region. Valid characters
are a-z, 0-9, and hyphens (-); cannot start/end with a hyphen or use two in a
row.
EOT
 type = string

 validation {
 condition = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.service_network_name))
 error_message = "service_network_name must be lowercase alphanumeric or hyphens, and must not begin or end with a hyphen."
 }
}

###############################################################################
# Auth (secure default)
###############################################################################

variable "auth_type" {
 description = <<EOT
IAM auth policy type for the service network. SECURE DEFAULT: "AWS_IAM" so only
authenticated (SigV4) callers can reach services on this network — set "NONE"
only for a deliberately open mesh, and document the exception. An
aws_vpclattice_auth_policy (see auth_policies) is only active while auth_type is
"AWS_IAM"; any policy left in place while auth_type is "NONE" stays inactive.
EOT
 type = string
 default = "AWS_IAM"

 validation {
 condition = contains(["NONE", "AWS_IAM"], var.auth_type)
 error_message = "auth_type must be one of: NONE, AWS_IAM."
 }
}

###############################################################################
# VPC associations (child collection — for_each over map(object))
#
# A VPC must be associated with the service network before workloads in that
# VPC can reach any Lattice service on it — association is not implicit from
# creating a target group in that VPC.
###############################################################################

variable "vpc_associations" {
 description = <<EOT
Map of VPC-to-service-network associations keyed by a stable name, each
rendered as one aws_vpclattice_service_network_vpc_association. Wire vpc_id
from tf-mod-aws-vpc and security_group_ids from tf-mod-aws-security-group.

 - vpc_id: ID of the VPC to associate (required).
 - security_group_ids: security groups controlling traffic between the VPC
 and the service network. Omit to rely on the
 account/VPC defaults.
 - private_dns_enabled: whether private DNS is enabled for the association
 (default false).
 - dns_options: { private_dns_preference, private_dns_specified_domains }
 — only meaningful when private_dns_enabled is true.
 - tags: extra tags merged over module tags for this association.
EOT
 type = map(object({
 vpc_id = string
 security_group_ids = optional(list(string), [])
 private_dns_enabled = optional(bool, false)
 dns_options = optional(object({
 private_dns_preference = optional(string)
 private_dns_specified_domains = optional(list(string))
 }))
 tags = optional(map(string), {})
 }))
 default = {}

 validation {
 condition = alltrue([
 for k, v in var.vpc_associations: v.dns_options == null || contains(["VERIFIED_DOMAINS_ONLY", "ALL_DOMAINS", "VERIFIED_DOMAINS_AND_SPECIFIED_DOMAINS", "SPECIFIED_DOMAINS_ONLY"],
 coalesce(try(v.dns_options.private_dns_preference, null), "ALL_DOMAINS"))
 ])
 error_message = "Each vpc_associations[*].dns_options.private_dns_preference must be one of: VERIFIED_DOMAINS_ONLY, ALL_DOMAINS, VERIFIED_DOMAINS_AND_SPECIFIED_DOMAINS, SPECIFIED_DOMAINS_ONLY."
 }
}

###############################################################################
# Services (child collection — for_each over map(object))
###############################################################################

variable "services" {
 description = <<EOT
Map of routable Lattice services keyed by a stable name, each rendered as one
aws_vpclattice_service. The key is referenced by listeners (service_key),
service_associations (service_key), and by auth/resource-policy and
access-log-subscription entries via resource_identifier_key.

 - name: explicit service name. Defaults to the map key.
 Must be unique within the account, 3-40 characters.
 - auth_type: "AWS_IAM" (default, SECURE) or "NONE" per-service
 override of the network-level auth_type.
 - custom_domain_name: custom domain name for the service (optional).
 - certificate_arn: ACM certificate ARN for the custom domain, same Region
 as this module (wire from tf-mod-aws-acm).
 - tags: extra tags merged over module tags for this service.
EOT
 type = map(object({
 name = optional(string)
 auth_type = optional(string, "AWS_IAM")
 custom_domain_name = optional(string)
 certificate_arn = optional(string)
 tags = optional(map(string), {})
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.services: contains(["NONE", "AWS_IAM"], v.auth_type)])
 error_message = "Each services[*].auth_type must be one of: NONE, AWS_IAM."
 }
}

###############################################################################
# Target groups (child collection — for_each over map(object))
#
# config shape depends entirely on `type`: LAMBDA takes no config at all;
# ALB takes config but NOT health_check (unsupported); INSTANCE/IP take the
# full config + optional health_check. Modeled as one deeply-typed object,
# enforced by validation rather than trusted from the caller.
###############################################################################

variable "target_groups" {
 description = <<EOT
Map of target groups keyed by a stable name, each rendered as one
aws_vpclattice_target_group. The key is referenced by target_group_attachments
(target_group_key) and by listener/listener_rule forward actions
(target_group_key inside default_action/action.forward.target_groups).

 - name: explicit target-group name. Defaults to the map key.
 - type: "INSTANCE" | "IP" | "LAMBDA" | "ALB".
 - config: target-group configuration (required for INSTANCE/IP/ALB; omit
 entirely, or leave null, for LAMBDA).
 - vpc_identifier: VPC ID (wire from tf-mod-aws-vpc).
 - ip_address_type: "IPV4" | "IPV6" (IP type only).
 - lambda_event_structure_version: "V1" | "V2" (LAMBDA type only).
 - port / protocol / protocol_version: routing to the targets
 ("HTTP"/"HTTPS", "HTTP1"/"HTTP2"/"GRPC").
 - health_check: per-target health probe. NOT SUPPORTED for type "ALB".
 - enabled, health_check_interval_seconds, health_check_timeout_seconds,
 healthy_threshold_count, unhealthy_threshold_count, matcher_value
 (HTTP success-code range, e.g. "200-299"), path, port, protocol,
 protocol_version.
 - tags: extra tags merged over module tags for this target group.
EOT
 type = map(object({
 name = optional(string)
 type = string
 config = optional(object({
 vpc_identifier = optional(string)
 ip_address_type = optional(string)
 lambda_event_structure_version = optional(string)
 port = optional(number)
 protocol = optional(string)
 protocol_version = optional(string, "HTTP1")
 health_check = optional(object({
 enabled = optional(bool, true)
 health_check_interval_seconds = optional(number, 30)
 health_check_timeout_seconds = optional(number, 5)
 healthy_threshold_count = optional(number, 5)
 unhealthy_threshold_count = optional(number, 2)
 matcher_value = optional(string)
 path = optional(string)
 port = optional(number)
 protocol = optional(string)
 protocol_version = optional(string, "HTTP1")
 }))
 }))
 tags = optional(map(string), {})
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.target_groups: contains(["INSTANCE", "IP", "LAMBDA", "ALB"], v.type)])
 error_message = "Each target_groups[*].type must be one of: INSTANCE, IP, LAMBDA, ALB."
 }

 validation {
 condition = alltrue([for k, v in var.target_groups: v.type == "LAMBDA" || v.config != null])
 error_message = "Each target_groups[*].config is required unless type is LAMBDA."
 }

 validation {
 condition = alltrue([
 for k, v in var.target_groups: v.type != "ALB" || try(v.config.health_check, null) == null
 ])
 error_message = "target_groups[*].config.health_check is not supported when type is ALB — omit it."
 }
}

variable "target_group_attachments" {
 description = <<EOT
Map of static target registrations keyed by a stable name, each rendered as one
aws_vpclattice_target_group_attachment.

 - target_group_key: key of the target group (in target_groups) to register to.
 - target_id: instance ID (INSTANCE), IP address (IP), Lambda function
 ARN (LAMBDA, wire from tf-mod-aws-lambda), or ALB ARN
 (ALB, wire from tf-mod-aws-lb).
 - port: override port (defaults to the target group port).
EOT
 type = map(object({
 target_group_key = string
 target_id = string
 port = optional(number)
 }))
 default = {}
}

###############################################################################
# Listeners (child collection — for_each over map(object))
###############################################################################

variable "listeners" {
 description = <<EOT
Map of listeners keyed by a stable name, each rendered as one
aws_vpclattice_listener attached to a service. The key is referenced by
listener_rules (listener_key).

 - service_key: key of the service (in services) this listener attaches to.
 - name: explicit listener name (unique within the service).
 Defaults to the map key. FORCE-NEW.
 - protocol: "HTTP" | "HTTPS" | "TLS_PASSTHROUGH". FORCE-NEW.
 - port: listener port. Defaults to 80 (HTTP) or 443 (HTTPS) when
 omitted. FORCE-NEW.
 - default_action: action applied when no rule matches.
 - type: "forward" or "fixed_response".
 - fixed_response: { status_code } (type fixed_response).
 - forward: { target_groups = [{ target_group_key, weight }] }
 (type forward; weight default 100, only meaningful
 with >1 target group).
 - tags: extra tags merged over module tags for this listener.
EOT
 type = map(object({
 service_key = string
 name = optional(string)
 protocol = string
 port = optional(number)
 default_action = object({
 type = string
 fixed_response = optional(object({
 status_code = number
 }))
 forward = optional(object({
 target_groups = list(object({
 target_group_key = string
 weight = optional(number, 100)
 }))
 }))
 })
 tags = optional(map(string), {})
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.listeners: contains(["HTTP", "HTTPS", "TLS_PASSTHROUGH"], v.protocol)])
 error_message = "Each listeners[*].protocol must be one of: HTTP, HTTPS, TLS_PASSTHROUGH."
 }

 validation {
 condition = alltrue([for k, v in var.listeners: contains(["forward", "fixed_response"], v.default_action.type)])
 error_message = "Each listeners[*].default_action.type must be one of: forward, fixed_response."
 }

 validation {
 condition = alltrue([
 for k, v in var.listeners: ((v.default_action.type == "forward" && v.default_action.forward != null && v.default_action.fixed_response == null) ||
 (v.default_action.type == "fixed_response" && v.default_action.fixed_response != null && v.default_action.forward == null))
 ])
 error_message = "Each listeners[*].default_action must set exactly the block matching its type (forward -> forward{}, fixed_response -> fixed_response{})."
 }
}

variable "listener_rules" {
 description = <<EOT
Map of listener rules keyed by a stable name, each rendered as one
aws_vpclattice_listener_rule (path/header/method routing on a listener).

 - listener_key: key of the listener (in listeners) the rule attaches to.
 - name: explicit rule name (unique within the listener). Defaults
 to the map key.
 - priority: evaluation priority, unique within the listener (lower =
 evaluated first).
 - match: { http_match = { method, header_matches, path_match } }
 - method: HTTP method to match (e.g. "GET").
 - header_matches: list of { name, case_sensitive, match = { contains |
 exact | prefix } } — exactly one of contains/exact/
 prefix per entry.
 - path_match: { case_sensitive, match = { exact | prefix } } —
 exactly one of exact/prefix.
 - action: same shape as listeners[*].default_action (forward or
 fixed_response).
 - tags: extra tags merged over module tags for this rule.
EOT
 type = map(object({
 listener_key = string
 name = optional(string)
 priority = number
 match = object({
 http_match = object({
 method = optional(string)
 header_matches = optional(list(object({
 name = string
 case_sensitive = optional(bool, false)
 match = object({
 contains = optional(string)
 exact = optional(string)
 prefix = optional(string)
 })
 })), [])
 path_match = optional(object({
 case_sensitive = optional(bool, false)
 match = object({
 exact = optional(string)
 prefix = optional(string)
 })
 }))
 })
 })
 action = object({
 type = string
 fixed_response = optional(object({
 status_code = number
 }))
 forward = optional(object({
 target_groups = list(object({
 target_group_key = string
 weight = optional(number, 100)
 }))
 }))
 })
 tags = optional(map(string), {})
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.listener_rules: v.priority >= 1])
 error_message = "Each listener_rules[*].priority must be a positive integer, unique within its listener."
 }

 validation {
 condition = alltrue([for k, v in var.listener_rules: contains(["forward", "fixed_response"], v.action.type)])
 error_message = "Each listener_rules[*].action.type must be one of: forward, fixed_response."
 }

 validation {
 condition = alltrue([
 for k, v in var.listener_rules: ((v.action.type == "forward" && v.action.forward != null && v.action.fixed_response == null) ||
 (v.action.type == "fixed_response" && v.action.fixed_response != null && v.action.forward == null))
 ])
 error_message = "Each listener_rules[*].action must set exactly the block matching its type (forward -> forward{}, fixed_response -> fixed_response{})."
 }

 validation {
 condition = alltrue([
 for k, v in var.listener_rules: (try(v.match.http_match.method, null) != null ||
 length(try(v.match.http_match.header_matches, [])) > 0 ||
 try(v.match.http_match.path_match, null) != null)
 ])
 error_message = "Each listener_rules[*].match.http_match must set at least one of method, header_matches, or path_match."
 }
}

###############################################################################
# Resource gateways (child collection — for_each over map(object))
#
# An ENI-backed ingress/egress point in a VPC used by resource configurations
# to reach non-Lattice resources (on-prem, other VPCs/accounts, RDS by ARN).
###############################################################################

variable "resource_gateways" {
 description = <<EOT
Map of resource gateways keyed by a stable name, each rendered as one
aws_vpclattice_resource_gateway. Wire vpc_id/subnet_ids from tf-mod-aws-vpc and
security_group_ids from tf-mod-aws-security-group. The key is referenced by
resource_configurations (resource_gateway_key).

 - name: explicit gateway name. Defaults to the map key.
 - vpc_id: VPC ID for the gateway (required).
 - subnet_ids: subnets to place gateway ENIs in (required,
 plan AZ/CIDR budget like a NAT gateway).
 - security_group_ids: security groups for the gateway ENIs.
 - ip_address_type: "IPV4" (default AWS behavior) | "IPV6" |
 "DUALSTACK".
 - ipv4_addresses_per_eni: IPv4 addresses per ENI (IPV4/DUALSTACK only,
 default 16).
 - resource_config_dns_resolution: "PUBLIC" (default) | "IN_VPC" — how DNS
 resolves for resource configurations
 associated to this gateway. FORCE-NEW.
 - tags: extra tags merged over module tags for this gateway.
EOT
 type = map(object({
 name = optional(string)
 vpc_id = string
 subnet_ids = list(string)
 security_group_ids = optional(list(string), [])
 ip_address_type = optional(string)
 ipv4_addresses_per_eni = optional(number, 16)
 resource_config_dns_resolution = optional(string, "PUBLIC")
 tags = optional(map(string), {})
 }))
 default = {}

 validation {
 condition = alltrue([
 for k, v in var.resource_gateways: v.ip_address_type == null || contains(["IPV4", "IPV6", "DUALSTACK"], v.ip_address_type)
 ])
 error_message = "Each resource_gateways[*].ip_address_type must be one of: IPV4, IPV6, DUALSTACK (or null)."
 }

 validation {
 condition = alltrue([for k, v in var.resource_gateways: contains(["PUBLIC", "IN_VPC"], v.resource_config_dns_resolution)])
 error_message = "Each resource_gateways[*].resource_config_dns_resolution must be one of: PUBLIC, IN_VPC."
 }
}

###############################################################################
# Domain verifications (child collection — for_each over map(object))
###############################################################################

variable "domain_verifications" {
 description = <<EOT
Map of custom-domain ownership proofs keyed by a stable name, each rendered as
one aws_vpclattice_domain_verification. Pair the emitted TXT record output with
a record in tf-mod-aws-route53-zone to complete verification. The key is
referenced by resource_configurations (domain_verification_key).

 - domain_name: the domain name to verify ownership for.
 - tags: extra tags merged over module tags for this verification.
EOT
 type = map(object({
 domain_name = string
 tags = optional(map(string), {})
 }))
 default = {}
}

###############################################################################
# Resource configurations (child collection — for_each over map(object))
#
# Describes a non-Lattice resource (DNS name, IP address, or ARN) reachable
# through a resource gateway. Exactly one of arn_resource/dns_resource/
# ip_resource is set per entry.
###############################################################################

variable "resource_configurations" {
 description = <<EOT
Map of resource configurations keyed by a stable name, each rendered as one
aws_vpclattice_resource_configuration. The key is referenced by
resource_associations (resource_configuration_key) and, for CHILD-type entries,
by other resource_configurations entries (resource_configuration_group_key).

 - name: explicit name. Defaults to the map key.
 - type: "SINGLE" (default) | "GROUP" | "CHILD" | "ARN".
 - resource_gateway_key: key of the resource gateway (in
 resource_gateways) this configuration is
 reached through. Required unless
 resource_configuration_group_key is set.
 - resource_configuration_group_key: key of a GROUP-type entry in this same
 map (for type "CHILD"). Mutually
 exclusive with resource_gateway_key.
 - protocol: "TCP" (only supported value today).
 - port_ranges: list of ports/ranges, e.g. ["80"] or
 ["8080-8081"] (required).
 - allow_association_to_shareable_service_network: allow/deny association to
 a shareable (RAM) service network.
 - custom_domain_name: custom domain for this resource.
 - domain_verification_key: key of a domain_verifications entry
 proving ownership of custom_domain_name.
 - definition: exactly one of:
 - dns_resource = { domain_name, ip_address_type }
 - ip_resource = { ip_address }
 - arn_resource = { arn } (e.g. an RDS cluster/instance ARN)
 - tags: extra tags merged over module tags.
EOT
 type = map(object({
 name = optional(string)
 type = optional(string, "SINGLE")
 resource_gateway_key = optional(string)
 resource_configuration_group_key = optional(string)
 protocol = optional(string, "TCP")
 port_ranges = list(string)
 allow_association_to_shareable_service_network = optional(bool)
 custom_domain_name = optional(string)
 domain_verification_key = optional(string)
 definition = object({
 dns_resource = optional(object({
 domain_name = string
 ip_address_type = string
 }))
 ip_resource = optional(object({
 ip_address = string
 }))
 arn_resource = optional(object({
 arn = string
 }))
 })
 tags = optional(map(string), {})
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.resource_configurations: contains(["SINGLE", "GROUP", "CHILD", "ARN"], v.type)])
 error_message = "Each resource_configurations[*].type must be one of: SINGLE, GROUP, CHILD, ARN."
 }

 validation {
 condition = alltrue([
 for k, v in var.resource_configurations: ((v.resource_gateway_key != null && v.resource_configuration_group_key == null) ||
 (v.resource_gateway_key == null && v.resource_configuration_group_key != null))
 ])
 error_message = "Each resource_configurations[*] must set exactly one of resource_gateway_key or resource_configuration_group_key."
 }

 validation {
 condition = alltrue([
 for k, v in var.resource_configurations: length(compact([
 try(v.definition.dns_resource, null) != null ? "x": "",
 try(v.definition.ip_resource, null) != null ? "x": "",
 try(v.definition.arn_resource, null) != null ? "x": "",
 ])) == 1
 ])
 error_message = "Each resource_configurations[*].definition must set exactly one of dns_resource, ip_resource, or arn_resource."
 }
}

###############################################################################
# Service network associations (services / resources)
###############################################################################

variable "service_associations" {
 description = <<EOT
Map of service-to-service-network associations keyed by a stable name, each
rendered as one aws_vpclattice_service_network_service_association.

 - service_key: key of the service (in services) to associate.
 - tags: extra tags merged over module tags for this association.
EOT
 type = map(object({
 service_key = string
 tags = optional(map(string), {})
 }))
 default = {}
}

variable "resource_associations" {
 description = <<EOT
Map of resource-configuration-to-service-network associations keyed by a
stable name, each rendered as one
aws_vpclattice_service_network_resource_association.

 - resource_configuration_key: key of the resource configuration (in
 resource_configurations) to associate.
 - private_dns_enabled: whether private DNS is enabled (default
 false). The referenced resource configuration
 must have a custom domain or group domain when
 true.
 - tags: extra tags merged over module tags.
EOT
 type = map(object({
 resource_configuration_key = string
 private_dns_enabled = optional(bool, false)
 tags = optional(map(string), {})
 }))
 default = {}
}

###############################################################################
# Auth policy / resource policy / access-log subscriptions
#
# All three attach to either the service network itself or a specific
# service, selected via resource_identifier_key: use the literal string
# "service_network" for the keystone, or a key from var.services for a
# specific service. NOTE: none of these three resources accept a `tags`
# argument in the live v6.54 schema — do not add one.
###############################################################################

variable "auth_policies" {
 description = <<EOT
Map of IAM-shaped auth-policy documents keyed by a stable name, each rendered
as one aws_vpclattice_auth_policy. Only active while the target resource's
auth_type is "AWS_IAM"; inactive (but still stored) while "NONE".

 - resource_identifier_key: "service_network" (the keystone) or a key from
 services (a specific service).
 - policy: JSON auth-policy document. ALWAYS build with
 jsonencode() — the API rejects a policy string
 containing newlines or blank lines. Prefer an
 explicit least-privilege principal/action list
 over a wildcard Principal = "*".
EOT
 type = map(object({
 resource_identifier_key = string
 policy = string
 }))
 default = {}
}

variable "resource_policies" {
 description = <<EOT
Map of cross-account resource-sharing IAM policies keyed by a stable name,
each rendered as one aws_vpclattice_resource_policy — controls which
principals may associate their VPCs/services/resources with this service
network or service.

 - resource_identifier_key: "service_network" (the keystone) or a key from
 services (a specific service).
 - policy: JSON resource-policy document. ALWAYS build with
 jsonencode(); no newlines or blank lines.
EOT
 type = map(object({
 resource_identifier_key = string
 policy = string
 }))
 default = {}
}

variable "access_log_subscriptions" {
 description = <<EOT
Map of access-log subscriptions keyed by a stable name, each rendered as one
aws_vpclattice_access_log_subscription. SECURE-BY-DEFAULT RECOMMENDATION: wire
at least one subscription per service network (or per service) in any
environment carrying PII-adjacent traffic — this is the audit trail for
cross-VPC/cross-account application traffic. Left empty ({}) only for a
documented quick-start exception.

 - resource_identifier_key: "service_network" (the keystone) or a key from
 services (a specific service).
 - destination_arn: ARN of the log destination. Wire from
 tf-mod-aws-cloudwatch-log-group, tf-mod-aws-s3-bucket,
 or tf-mod-aws-kinesis-firehose. FORCE-NEW.
 - service_network_log_type: "SERVICE" (default) | "RESOURCE" — which traffic
 class is logged when subscribed at the service
 network level. FORCE-NEW.
EOT
 type = map(object({
 resource_identifier_key = string
 destination_arn = string
 service_network_log_type = optional(string, "SERVICE")
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.access_log_subscriptions: contains(["SERVICE", "RESOURCE"], v.service_network_log_type)])
 error_message = "Each access_log_subscriptions[*].service_network_log_type must be one of: SERVICE, RESOURCE."
 }
}

###############################################################################
# Universal tail
###############################################################################

variable "tags" {
 description = <<EOT
A map of tags to assign to all taggable resources created by this module
(service network, VPC/service/resource associations, services, target groups,
listeners, listener rules, resource gateways, resource configurations, and
domain verifications). These merge with provider-level default_tags; resource
tags win on key conflict. Per-item tags on child collections merge over this
map. The computed tags_all output reflects the merged set.

NOT applied to aws_vpclattice_target_group_attachment, aws_vpclattice_auth_policy,
aws_vpclattice_resource_policy, or aws_vpclattice_access_log_subscription — none
of these four resource types accept a tags argument in the AWS provider schema.
EOT
 type = map(string)
 default = {}
}

variable "timeouts" {
 description = <<EOT
Optional Terraform operation timeouts applied uniformly to every child
resource in this module whose schema supports operation timeouts. NOTE:
aws_vpclattice_service_network (the keystone) and
aws_vpclattice_domain_verification, aws_vpclattice_resource_policy, and
aws_vpclattice_access_log_subscription have NO timeouts block in the AWS
provider schema and never receive this value. aws_vpclattice_target_group_attachment
and aws_vpclattice_service_network_resource_association only support create/
delete (no update) — the update value is ignored for those two.

 - create: how long to wait for create operations.
 - update: how long to wait for update operations (where supported).
 - delete: how long to wait for delete operations.
EOT
 type = object({
 create = optional(string)
 update = optional(string)
 delete = optional(string)
 })
 default = {}
}
