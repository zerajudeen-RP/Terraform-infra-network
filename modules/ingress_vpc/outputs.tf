output "vpc_id" { value = aws_vpc.this.id }
output "vpc_cidr_block" { value = aws_vpc.this.cidr_block }
output "tgw_attachment_id" { value = aws_ec2_transit_gateway_vpc_attachment.this.id }

# Per-environment subnet IDs
output "alb_demo_subnet_ids" { value = aws_subnet.alb_demo[*].id }
output "nlb_demo_subnet_ids" { value = aws_subnet.nlb_demo[*].id }
output "alb_stage_subnet_ids" { value = aws_subnet.alb_stage[*].id }
output "nlb_stage_subnet_ids" { value = aws_subnet.nlb_stage[*].id }
output "alb_prod_subnet_ids" { value = aws_subnet.alb_prod[*].id }
output "nlb_prod_subnet_ids" { value = aws_subnet.nlb_prod[*].id }

# Shared
output "firewall_subnet_ids" { value = aws_subnet.firewall[*].id }
output "tgw_subnet_ids" { value = aws_subnet.tgw[*].id }
output "nlb_security_group_id" { value = aws_security_group.nlb.id }
output "alb_security_group_id" { value = aws_security_group.alb.id }
output "internet_gateway_id" { value = aws_internet_gateway.this.id }
