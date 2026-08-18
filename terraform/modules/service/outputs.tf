# =============================================================================
# modules/service — outputs consumed by the root module and `make verify`
#
# Nothing credential-shaped is exposed here. The secret ARN is an input, not an
# output, and the instance never learns the password in the first place.
# =============================================================================

output "instance_id" {
  description = "EC2 instance id. This is the output the root module's commented-out block is waiting on."
  value       = aws_instance.app.id
}

output "instance_private_ip" {
  description = "Instance private IP. Useful for hitting /metrics and /readyz directly during incident replay, bypassing the load balancer."
  value       = aws_instance.app.private_ip
}

output "security_group_id" {
  description = "Security group id. Recorded because SG ingress rules only take effect at instance creation on LocalStack — if a rule changes, the instance has to be recreated."
  value       = aws_security_group.app.id
}

output "alb_dns_name" {
  description = "ALB DNS name. Declared as IaC; on LocalStack nginx on the instance is what actually serves traffic."
  value       = aws_lb.app.dns_name
}

output "app_url" {
  description = "Base URL for smoke checks: append /healthz, /readyz, or /metrics."
  value       = "http://${aws_lb.app.dns_name}"
}
