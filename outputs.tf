###############################################################################
# Primary outputs (id + arn) — service network (keystone)
###############################################################################

output "id" {
 description = "The ID of the VPC Lattice service network."
 value = aws_vpclattice_service_network.this.id
}

output "arn" {
 description = <<EOT
The ARN of the VPC Lattice service network (cross-resource reference type:
arn:aws:vpc-lattice:<region>:<account>:servicenetwork/<id>). Consumed by AWS RAM
shares, auth/resource policies, and cross-account VPC/service/resource
associations.
EOT
 value = aws_vpclattice_service_network.this.arn
}

output "name" {
 description = "The name of the VPC Lattice service network."
 value = aws_vpclattice_service_network.this.name
}

output "tags_all" {
 description = "All tags on the service network, including those inherited from provider default_tags (resource tags win on key conflict)."
 value = aws_vpclattice_service_network.this.tags_all
}

###############################################################################
# VPC associations
###############################################################################

output "vpc_association_ids" {
 description = "Map of vpc_associations key => association id."
 value = { for k, v in aws_vpclattice_service_network_vpc_association.this: k => v.id }
}

output "vpc_association_arns" {
 description = "Map of vpc_associations key => association ARN."
 value = { for k, v in aws_vpclattice_service_network_vpc_association.this: k => v.arn }
}

###############################################################################
# Services
###############################################################################

output "service_ids" {
 description = "Map of services key => service id."
 value = { for k, s in aws_vpclattice_service.this: k => s.id }
}

output "service_arns" {
 description = "Map of services key => service ARN. Consumed by AWS RAM shares and terraform-aws-route53-zone (custom-domain CNAME target)."
 value = { for k, s in aws_vpclattice_service.this: k => s.arn }
}

output "service_dns_entries" {
 description = "Map of services key => DNS entry (domain_name/hosted_zone_id) exposed by VPC Lattice for the service, when available."
 value = { for k, s in aws_vpclattice_service.this: k => try(s.dns_entry, null) }
}

###############################################################################
# Target groups
###############################################################################

output "target_group_ids" {
 description = "Map of target_groups key => target group id."
 value = { for k, tg in aws_vpclattice_target_group.this: k => tg.id }
}

output "target_group_arns" {
 description = "Map of target_groups key => target group ARN."
 value = { for k, tg in aws_vpclattice_target_group.this: k => tg.arn }
}

###############################################################################
# Listeners
###############################################################################

output "listener_ids" {
 description = "Map of listeners key => standalone listener id (listener_id attribute)."
 value = { for k, l in aws_vpclattice_listener.this: k => l.listener_id }
}

output "listener_arns" {
 description = "Map of listeners key => listener ARN."
 value = { for k, l in aws_vpclattice_listener.this: k => l.arn }
}

output "listener_rule_ids" {
 description = "Map of listener_rules key => rule_id."
 value = { for k, r in aws_vpclattice_listener_rule.this: k => r.rule_id }
}

output "listener_rule_arns" {
 description = "Map of listener_rules key => rule ARN."
 value = { for k, r in aws_vpclattice_listener_rule.this: k => r.arn }
}

###############################################################################
# Resource gateways / configurations / associations
###############################################################################

output "resource_gateway_ids" {
 description = "Map of resource_gateways key => id. Wire into terraform-aws-vpc subnet-capacity planning (ENIs are placed per AZ, similar to a NAT gateway)."
 value = { for k, rg in aws_vpclattice_resource_gateway.this: k => rg.id }
}

output "resource_gateway_arns" {
 description = "Map of resource_gateways key => ARN."
 value = { for k, rg in aws_vpclattice_resource_gateway.this: k => rg.arn }
}

output "resource_configuration_ids" {
 description = "Map of resource_configurations key => id."
 value = { for k, rc in aws_vpclattice_resource_configuration.this: k => rc.id }
}

output "resource_configuration_arns" {
 description = "Map of resource_configurations key => ARN."
 value = { for k, rc in aws_vpclattice_resource_configuration.this: k => rc.arn }
}

output "resource_association_ids" {
 description = "Map of resource_associations key => association id."
 value = { for k, ra in aws_vpclattice_service_network_resource_association.this: k => ra.id }
}

###############################################################################
# Domain verification
###############################################################################

output "domain_verification_ids" {
 description = "Map of domain_verifications key => id."
 value = { for k, dv in aws_vpclattice_domain_verification.this: k => dv.id }
}

output "domain_verification_txt_records" {
 description = <<EOT
Map of domain_verifications key => { name, value } — the TXT record that must be
published (e.g. via terraform-aws-route53-zone) to complete ownership verification
of the corresponding custom domain.
EOT
 value = {
 for k, dv in aws_vpclattice_domain_verification.this: k => {
 name = dv.txt_record_name
 value = dv.txt_record_value
 }
 }
}

###############################################################################
# Auth / resource policies / access logging
###############################################################################

output "auth_policy_states" {
 description = "Map of auth_policies key => policy state (active only while the target resource's auth_type is AWS_IAM)."
 value = { for k, p in aws_vpclattice_auth_policy.this: k => p.state }
}

output "access_log_subscription_arns" {
 description = "Map of access_log_subscriptions key => subscription ARN."
 value = { for k, a in aws_vpclattice_access_log_subscription.this: k => a.arn }
}
