###############################################################
# Module: ram
# AWS Resource Access Manager — share TGW with workload accounts
#
# The Transit Gateway lives in the network hub account.
# Workload accounts need a RAM share accepted before they can
# create TGW attachments.
#
# Flow:
#   1. RAM resource share created in hub account
#   2. TGW ARN associated with the share
#   3. Each workload account principal added to the share
#   4. If auto_accept = false, the workload account must accept
#      the invitation via RAM console or aws ram accept-resource-share-invitation
#   5. Once accepted, workload account can attach its VPC to the TGW
###############################################################

data "aws_caller_identity" "current" {}

###############################################################
# RAM Resource Share
###############################################################
resource "aws_ram_resource_share" "tgw" {
  name                      = "${var.name}-${var.environment}-tgw-share"
  allow_external_principals = var.allow_external_principals

  tags = merge(var.tags, {
    Name = "${var.name}-${var.environment}-tgw-share"
  })
}

###############################################################
# Associate the TGW with the share
###############################################################
resource "aws_ram_resource_association" "tgw" {
  resource_arn       = var.tgw_arn
  resource_share_arn = aws_ram_resource_share.tgw.arn
}

###############################################################
# Associate each workload account as a principal
# Accepts a list so multiple workload accounts can be added
###############################################################
resource "aws_ram_principal_association" "workload_accounts" {
  for_each = toset(var.workload_account_ids)

  # Principal can be an AWS account ID, OU ARN, or org ARN
  #principal          = "arn:aws:iam::${each.value}:root"
  principal     = each.value
  resource_share_arn = aws_ram_resource_share.tgw.arn
}
