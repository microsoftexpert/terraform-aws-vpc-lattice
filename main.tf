###############################################################################
# Local derivations
#
# - policy_target_ids/arns resolve the resource_identifier_key used by
# auth_policies / resource_policies / access_log_subscriptions ("service_network"
# or a services map key) to the underlying id/arn.
# - listener_service_ids resolves each listener's parent service id, needed by
# listener_rule (which requires BOTH service_identifier and listener_identifier).
# - timeouts_set / timeouts_set_no_update gate the shared var.timeouts object onto
# only the child resources whose schema actually supports each field (the
# keystone service_network, domain_verification, resource_policy, and
# access_log_subscription have NO timeouts block at all; target_group_attachment
# and service_network_resource_association support create/delete only).
###############################################################################

locals {
 policy_target_ids = merge({ service_network = aws_vpclattice_service_network.this.id },
 { for k, s in aws_vpclattice_service.this: k => s.id })
 policy_target_arns = merge({ service_network = aws_vpclattice_service_network.this.arn },
 { for k, s in aws_vpclattice_service.this: k => s.arn })

 listener_service_ids = { for k, l in var.listeners: k => aws_vpclattice_service.this[l.service_key].id }

 timeouts_set = var.timeouts.create != null || var.timeouts.update != null || var.timeouts.delete != null
 timeouts_set_no_update = var.timeouts.create != null || var.timeouts.delete != null
}

###############################################################################
# Service network (keystone)
#
# name and auth_type are the only arguments; auth_type defaults to "AWS_IAM"
# (SECURE DEFAULT). NOTE: aws_vpclattice_service_network has NO timeouts block
# in the provider schema, so var.timeouts is never wired here.
###############################################################################

resource "aws_vpclattice_service_network" "this" {
 name = var.service_network_name
 auth_type = var.auth_type

 tags = var.tags
}

###############################################################################
# VPC associations
#
# A VPC must be associated with the service network before workloads in that
# VPC can reach any Lattice service on it. service_network_identifier is always
# passed as the ARN (not just the id) so cross-account associations work
# without a second edit.
###############################################################################

resource "aws_vpclattice_service_network_vpc_association" "this" {
 for_each = var.vpc_associations

 vpc_identifier = each.value.vpc_id
 service_network_identifier = aws_vpclattice_service_network.this.arn
 security_group_ids = each.value.security_group_ids
 private_dns_enabled = each.value.private_dns_enabled

 dynamic "dns_options" {
 for_each = each.value.dns_options != null ? [each.value.dns_options]: []
 content {
 private_dns_preference = try(dns_options.value.private_dns_preference, null)
 private_dns_specified_domains = try(dns_options.value.private_dns_specified_domains, null)
 }
 }

 tags = merge(var.tags, each.value.tags)

 dynamic "timeouts" {
 for_each = local.timeouts_set ? [var.timeouts]: []
 content {
 create = try(timeouts.value.create, null)
 update = try(timeouts.value.update, null)
 delete = try(timeouts.value.delete, null)
 }
 }
}

###############################################################################
# Services
###############################################################################

resource "aws_vpclattice_service" "this" {
 for_each = var.services

 name = coalesce(each.value.name, each.key)
 auth_type = each.value.auth_type
 certificate_arn = each.value.certificate_arn
 custom_domain_name = each.value.custom_domain_name

 tags = merge(var.tags, each.value.tags)

 dynamic "timeouts" {
 for_each = local.timeouts_set ? [var.timeouts]: []
 content {
 create = try(timeouts.value.create, null)
 update = try(timeouts.value.update, null)
 delete = try(timeouts.value.delete, null)
 }
 }
}

###############################################################################
# Service <-> service network associations
###############################################################################

resource "aws_vpclattice_service_network_service_association" "this" {
 for_each = var.service_associations

 service_identifier = aws_vpclattice_service.this[each.value.service_key].id
 service_network_identifier = aws_vpclattice_service_network.this.arn

 tags = merge(var.tags, each.value.tags)

 dynamic "timeouts" {
 for_each = local.timeouts_set ? [var.timeouts]: []
 content {
 create = try(timeouts.value.create, null)
 update = try(timeouts.value.update, null)
 delete = try(timeouts.value.delete, null)
 }
 }
}

###############################################################################
# Target groups
#
# config is entirely omitted for LAMBDA targets (schema does not support it);
# health_check is omitted for ALB targets (unsupported — enforced by variable
# validation). matcher is itself a nested block, so matcher_value renders
# through its own dynamic gate.
###############################################################################

resource "aws_vpclattice_target_group" "this" {
 for_each = var.target_groups

 name = coalesce(each.value.name, each.key)
 type = each.value.type

 dynamic "config" {
 for_each = each.value.config != null ? [each.value.config]: []
 content {
 vpc_identifier = try(config.value.vpc_identifier, null)
 ip_address_type = try(config.value.ip_address_type, null)
 lambda_event_structure_version = try(config.value.lambda_event_structure_version, null)
 port = try(config.value.port, null)
 protocol = try(config.value.protocol, null)
 protocol_version = try(config.value.protocol_version, null)

 dynamic "health_check" {
 for_each = try(config.value.health_check, null) != null ? [config.value.health_check]: []
 content {
 enabled = try(health_check.value.enabled, null)
 health_check_interval_seconds = try(health_check.value.health_check_interval_seconds, null)
 health_check_timeout_seconds = try(health_check.value.health_check_timeout_seconds, null)
 healthy_threshold_count = try(health_check.value.healthy_threshold_count, null)
 unhealthy_threshold_count = try(health_check.value.unhealthy_threshold_count, null)
 path = try(health_check.value.path, null)
 port = try(health_check.value.port, null)
 protocol = try(health_check.value.protocol, null)
 protocol_version = try(health_check.value.protocol_version, null)

 dynamic "matcher" {
 for_each = try(health_check.value.matcher_value, null) != null ? [health_check.value.matcher_value]: []
 content {
 value = matcher.value
 }
 }
 }
 }
 }
 }

 tags = merge(var.tags, each.value.tags)

 dynamic "timeouts" {
 for_each = local.timeouts_set ? [var.timeouts]: []
 content {
 create = try(timeouts.value.create, null)
 update = try(timeouts.value.update, null)
 delete = try(timeouts.value.delete, null)
 }
 }
}

###############################################################################
# Static target registrations
#
# aws_vpclattice_target_group_attachment supports create/delete timeouts only
# (no update) and has no tags argument.
###############################################################################

resource "aws_vpclattice_target_group_attachment" "this" {
 for_each = var.target_group_attachments

 target_group_identifier = aws_vpclattice_target_group.this[each.value.target_group_key].id

 target {
 id = each.value.target_id
 port = try(each.value.port, null)
 }

 dynamic "timeouts" {
 for_each = local.timeouts_set_no_update ? [var.timeouts]: []
 content {
 create = try(timeouts.value.create, null)
 delete = try(timeouts.value.delete, null)
 }
 }
}

###############################################################################
# Listeners
#
# default_action renders exactly one of fixed_response or forward, gated on
# type + presence of the matching object (enforced by variable validation).
###############################################################################

resource "aws_vpclattice_listener" "this" {
 for_each = var.listeners

 name = coalesce(each.value.name, each.key)
 protocol = each.value.protocol
 port = try(each.value.port, null)
 service_identifier = aws_vpclattice_service.this[each.value.service_key].id

 default_action {
 dynamic "fixed_response" {
 for_each = each.value.default_action.fixed_response != null ? [each.value.default_action.fixed_response]: []
 content {
 status_code = fixed_response.value.status_code
 }
 }

 dynamic "forward" {
 for_each = each.value.default_action.forward != null ? [each.value.default_action.forward]: []
 content {
 dynamic "target_groups" {
 for_each = forward.value.target_groups
 content {
 target_group_identifier = aws_vpclattice_target_group.this[target_groups.value.target_group_key].id
 weight = try(target_groups.value.weight, null)
 }
 }
 }
 }
 }

 tags = merge(var.tags, each.value.tags)

 dynamic "timeouts" {
 for_each = local.timeouts_set ? [var.timeouts]: []
 content {
 create = try(timeouts.value.create, null)
 update = try(timeouts.value.update, null)
 delete = try(timeouts.value.delete, null)
 }
 }
}

###############################################################################
# Listener rules
#
# listener_rule requires BOTH service_identifier and listener_identifier —
# the service id is resolved through the parent listener's service_key via
# local.listener_service_ids. match/action are required single blocks (not
# dynamic), rendered directly since var.listener_rules guarantees their shape.
###############################################################################

resource "aws_vpclattice_listener_rule" "this" {
 for_each = var.listener_rules

 name = coalesce(each.value.name, each.key)
 service_identifier = local.listener_service_ids[each.value.listener_key]
 listener_identifier = aws_vpclattice_listener.this[each.value.listener_key].listener_id
 priority = each.value.priority

 match {
 http_match {
 method = try(each.value.match.http_match.method, null)

 dynamic "header_matches" {
 for_each = try(each.value.match.http_match.header_matches, [])
 content {
 name = header_matches.value.name
 case_sensitive = try(header_matches.value.case_sensitive, null)

 match {
 contains = try(header_matches.value.match.contains, null)
 exact = try(header_matches.value.match.exact, null)
 prefix = try(header_matches.value.match.prefix, null)
 }
 }
 }

 dynamic "path_match" {
 for_each = try(each.value.match.http_match.path_match, null) != null ? [each.value.match.http_match.path_match]: []
 content {
 case_sensitive = try(path_match.value.case_sensitive, null)

 match {
 exact = try(path_match.value.match.exact, null)
 prefix = try(path_match.value.match.prefix, null)
 }
 }
 }
 }
 }

 action {
 dynamic "fixed_response" {
 for_each = each.value.action.fixed_response != null ? [each.value.action.fixed_response]: []
 content {
 status_code = fixed_response.value.status_code
 }
 }

 dynamic "forward" {
 for_each = each.value.action.forward != null ? [each.value.action.forward]: []
 content {
 dynamic "target_groups" {
 for_each = forward.value.target_groups
 content {
 target_group_identifier = aws_vpclattice_target_group.this[target_groups.value.target_group_key].id
 weight = try(target_groups.value.weight, null)
 }
 }
 }
 }
 }

 tags = merge(var.tags, each.value.tags)

 dynamic "timeouts" {
 for_each = local.timeouts_set ? [var.timeouts]: []
 content {
 create = try(timeouts.value.create, null)
 update = try(timeouts.value.update, null)
 delete = try(timeouts.value.delete, null)
 }
 }
}

###############################################################################
# Resource gateways
#
# ENI-backed ingress/egress point for resource configurations. subnet_ids and
# vpc_id are effectively FORCE-NEW in practice (AZ/ENI placement); resource_
# config_dns_resolution is explicitly FORCE-NEW per the provider schema.
###############################################################################

resource "aws_vpclattice_resource_gateway" "this" {
 for_each = var.resource_gateways

 name = coalesce(each.value.name, each.key)
 vpc_id = each.value.vpc_id
 subnet_ids = each.value.subnet_ids
 security_group_ids = each.value.security_group_ids
 ip_address_type = try(each.value.ip_address_type, null)
 ipv4_addresses_per_eni = each.value.ipv4_addresses_per_eni
 resource_config_dns_resolution = each.value.resource_config_dns_resolution

 tags = merge(var.tags, each.value.tags)

 dynamic "timeouts" {
 for_each = local.timeouts_set ? [var.timeouts]: []
 content {
 create = try(timeouts.value.create, null)
 update = try(timeouts.value.update, null)
 delete = try(timeouts.value.delete, null)
 }
 }
}

###############################################################################
# Domain verifications
#
# NOTE: aws_vpclattice_domain_verification has NO timeouts block in the
# provider schema, so var.timeouts is never wired here.
###############################################################################

resource "aws_vpclattice_domain_verification" "this" {
 for_each = var.domain_verifications

 domain_name = each.value.domain_name

 tags = merge(var.tags, each.value.tags)
}

###############################################################################
# Resource configurations
#
# Exactly one of resource_gateway_key / resource_configuration_group_key is set
# per entry (enforced by variable validation); protocol is only meaningful for
# gateway-attached (non-CHILD) entries, so it is omitted when the entry
# inherits from a GROUP parent. resource_configuration_definition is a
# required single block rendered directly; exactly one of its three nested
# blocks is populated per entry (enforced by variable validation).
###############################################################################

resource "aws_vpclattice_resource_configuration" "this" {
 for_each = var.resource_configurations

 name = coalesce(each.value.name, each.key)
 type = each.value.type
 resource_gateway_identifier = each.value.resource_gateway_key != null ? aws_vpclattice_resource_gateway.this[each.value.resource_gateway_key].id: null
 resource_configuration_group_id = each.value.resource_configuration_group_key != null ? aws_vpclattice_resource_configuration.this[each.value.resource_configuration_group_key].id: null
 protocol = each.value.resource_gateway_key != null ? each.value.protocol: null
 port_ranges = each.value.port_ranges
 allow_association_to_shareable_service_network = try(each.value.allow_association_to_shareable_service_network, null)
 custom_domain_name = try(each.value.custom_domain_name, null)
 domain_verification_id = try(each.value.domain_verification_key, null) != null ? aws_vpclattice_domain_verification.this[each.value.domain_verification_key].id: null

 resource_configuration_definition {
 dynamic "dns_resource" {
 for_each = each.value.definition.dns_resource != null ? [each.value.definition.dns_resource]: []
 content {
 domain_name = dns_resource.value.domain_name
 ip_address_type = dns_resource.value.ip_address_type
 }
 }

 dynamic "ip_resource" {
 for_each = each.value.definition.ip_resource != null ? [each.value.definition.ip_resource]: []
 content {
 ip_address = ip_resource.value.ip_address
 }
 }

 dynamic "arn_resource" {
 for_each = each.value.definition.arn_resource != null ? [each.value.definition.arn_resource]: []
 content {
 arn = arn_resource.value.arn
 }
 }
 }

 tags = merge(var.tags, each.value.tags)

 dynamic "timeouts" {
 for_each = local.timeouts_set ? [var.timeouts]: []
 content {
 create = try(timeouts.value.create, null)
 update = try(timeouts.value.update, null)
 delete = try(timeouts.value.delete, null)
 }
 }
}

###############################################################################
# Resource <-> service network associations
#
# aws_vpclattice_service_network_resource_association supports create/delete
# timeouts only (no update).
###############################################################################

resource "aws_vpclattice_service_network_resource_association" "this" {
 for_each = var.resource_associations

 resource_configuration_identifier = aws_vpclattice_resource_configuration.this[each.value.resource_configuration_key].id
 service_network_identifier = aws_vpclattice_service_network.this.arn
 private_dns_enabled = each.value.private_dns_enabled

 tags = merge(var.tags, each.value.tags)

 dynamic "timeouts" {
 for_each = local.timeouts_set_no_update ? [var.timeouts]: []
 content {
 create = try(timeouts.value.create, null)
 delete = try(timeouts.value.delete, null)
 }
 }
}

###############################################################################
# Auth policies
#
# Only active while the target resource's auth_type is "AWS_IAM". NOTE:
# aws_vpclattice_auth_policy has NO tags argument in the provider schema.
###############################################################################

resource "aws_vpclattice_auth_policy" "this" {
 for_each = var.auth_policies

 resource_identifier = local.policy_target_arns[each.value.resource_identifier_key]
 policy = each.value.policy

 dynamic "timeouts" {
 for_each = local.timeouts_set ? [var.timeouts]: []
 content {
 create = try(timeouts.value.create, null)
 update = try(timeouts.value.update, null)
 delete = try(timeouts.value.delete, null)
 }
 }
}

###############################################################################
# Resource policies (cross-account sharing control)
#
# NOTE: aws_vpclattice_resource_policy has NO timeouts block and NO tags
# argument in the provider schema.
###############################################################################

resource "aws_vpclattice_resource_policy" "this" {
 for_each = var.resource_policies

 resource_arn = local.policy_target_arns[each.value.resource_identifier_key]
 policy = each.value.policy
}

###############################################################################
# Access log subscriptions (audit trail — secure-by-default recommendation)
#
# NOTE: aws_vpclattice_access_log_subscription has NO timeouts block and NO
# tags argument in the provider schema. destination_arn and resource_identifier
# are FORCE-NEW.
###############################################################################

resource "aws_vpclattice_access_log_subscription" "this" {
 for_each = var.access_log_subscriptions

 resource_identifier = local.policy_target_arns[each.value.resource_identifier_key]
 destination_arn = each.value.destination_arn
 service_network_log_type = each.value.service_network_log_type
}
