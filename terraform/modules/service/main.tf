# =============================================================================
# modules/service — EC2 (Docker-backed) + nginx + SG + ALB   (GROUP-OWNED: build)
#
# Run the app image as a Docker-backed EC2 instance, front it with nginx, and
# declare the load-balancer topology as IaC. Read "The four things that will
# break first" in ASSIGNMENT.md before you start.
#
# Expected inputs (variables.tf): app_ami_id (the localstack-ec2/app:ami-<sha12>
#   image CI tags), instance_type (default "t3.small"), secret_arn, db_endpoint,
#   db_port (default 3306), app_port (default 3000).
# Expected outputs (outputs.tf): instance_id.
# =============================================================================

# TODO: resource "aws_security_group" "app" — ingress 80 (+ app_port), egress.
#   FIDELITY: on LocalStack only the default SG is honoured, and rules apply only
#   at instance creation. `trivy config` flags 0.0.0.0/0 — scope it.

# TODO: resource "aws_instance" "app" — ami = var.app_ami_id, instance_type,
#   vpc_security_group_ids = [sg]. Pass the secret ARN + DB endpoint into
#   user_data (templatefile) — NEVER the secret value; the app resolves it at
#   runtime via Secrets Manager. A root_block_device needs an explicit
#   volume_size on LocalStack.

# TODO: declare the ALB topology as IaC (graded + scanned) even though nginx
#   carries the real traffic: aws_lb + aws_lb_target_group + aws_lb_listener
#   (you'll need data.aws_vpc.default + data.aws_subnets.default). Expect
#   LocalStack ELBv2 quirks (e.g. the listener port round-trips oddly) — pin
#   them with lifecycle { ignore_changes = [...] } and note them in FIDELITY.md.
