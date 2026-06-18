output "certificate_arn" {
  value = aws_acm_certificate.this.arn
}

output "certificate_status" {
  value = aws_acm_certificate.this.status
}
