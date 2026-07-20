terraform {
 required_version = ">= 1.12.0"

 required_providers {
 aws = {
 source = "hashicorp/aws"
 version = ">= 6.0, < 7.0"
 }
 }
}

###############################################################################
# Region / provider wiring (read before use)
#
# This module does NOT declare a `region` variable (region model) and does
# NOT hard-code a provider. The service network and every child object
# (services, target groups, listeners, resource gateways, resource
# configurations, policies, log subscriptions) are created with the single
# inherited `aws` provider, so the *caller* decides the Region by choosing
# which provider configuration to pass into the `aws` slot.
#
# VPC Lattice is a REGIONAL service with no us-east-1 global-resource quirk
# (unlike CloudFront/WAFv2-CLOUDFRONT/ACM-for-CloudFront). A multi-Region mesh
# requires one service network per Region, each associated independently —
# call this module once per Region/provider alias if you need that.
#
# Cross-account associations (a VPC or service in another account joining this
# service network) pass the service network's ARN rather than its id — this
# module always emits and consumes ARNs for that reason — but the actual
# cross-account trust (AWS RAM share, or the target account's own Terraform
# run) happens outside this module.
#
# module "app_mesh" {
# source = "git::https://github.com/microsoftexpert/terraform-aws-vpc-lattice?ref=v1.0.0"
# # inherits the default `aws` provider (whatever Region it points at)
# service_network_name = "core-app-mesh"
# vpc_associations = {
# app = { vpc_id = module.vpc.id }
# }
#...
# }
#
# Provider credentials, default_tags and assume_role all live in the caller's
# provider block — never in this module.
###############################################################################
