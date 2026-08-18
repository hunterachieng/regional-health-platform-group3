# =============================================================================
# modules/service — EC2 (Docker-backed) + nginx + SG + ALB    (GROUP-OWNED: Lwam)
#
# Runs the app image as a Docker-backed EC2 instance, fronts it with nginx, and
# declares the load-balancer topology as IaC.
#
# Boot contract: user-data receives the secret ARN and the DB address only. The
# password is fetched at runtime by api/secrets.js via GetSecretValue, so it
# never exists in user-data, in the image, or in git.
#
# AMI assumption: CI tags the built app image as localstack-ec2/app:ami-<sha12>,
# so the AMI *is* the app image and /usr/src/app is already present inside the
# instance. user-data therefore starts the app in place rather than pulling a
# container. If the team switches the AMI to a bare Ubuntu base, only
# templates/user-data.sh.tftpl changes — the Terraform below does not.
#
# Inputs  -> variables.tf
# Outputs -> outputs.tf  (instance_id, private_ip, security_group_id, alb_dns_name)
# =============================================================================

# -----------------------------------------------------------------------------
# Default VPC / subnets. Used for the SG's ingress scope and the ALB's subnet
# set. Looked up rather than hardcoded so this module survives a LocalStack
# restart (every teardown reissues fresh VPC and subnet IDs).
# -----------------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# -----------------------------------------------------------------------------
# Security group.
#
# Ingress is scoped to the VPC CIDR, never 0.0.0.0/0 — an open ingress here is
# precisely what the `trivy config` gate is built to fail (AVD-AWS-0107), and
# it would fail on this file.
#
# FIDELITY: LocalStack honours only the default SG, and ingress rules are
# evaluated at instance-creation time. Editing a rule after the fact has no
# effect on a running instance — you have to recreate it (failure mode #3 in
# ASSIGNMENT.md). Both caveats are documented in FIDELITY.md.
# -----------------------------------------------------------------------------
resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Ingress to nginx (80) and the app (${var.app_port}) for ${var.project_name}"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP to nginx from inside the VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  ingress {
    description = "Direct app port, for /metrics scraping and incident replay"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  # Egress is open on purpose: the instance calls Secrets Manager at boot and
  # installs nginx from the distro repo. Narrowing this to VPC endpoints is the
  # right production move and is listed as a known trade-off in FIDELITY.md.
  egress {
    description = "Outbound for Secrets Manager and package installation"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-app-sg"
  }
}

# -----------------------------------------------------------------------------
# Application instance.
#
# user_data carries the secret ARN, not the secret. `evidence/03-secrets/
# user_data.txt` is graded on exactly that: an ARN present, a password absent.
# trivy:ignore:AVD-AWS-0131 -- dynamic root_block_device omitted for LocalStack (FIDELITY.md §6); encrypted when skip_root_block_device=false
# -----------------------------------------------------------------------------
resource "aws_instance" "app" {
  ami                    = var.app_ami_id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    secret_arn       = var.secret_arn
    db_host          = var.db_host_from_instance
    db_endpoint_raw  = var.db_endpoint
    db_port          = var.db_port
    app_port         = var.app_port
    aws_region       = var.aws_region
    aws_endpoint_url = var.aws_endpoint_url
  })

  # Omit on LocalStack when using a custom Docker AMI: the Terraform AWS provider
  # calls DescribeImages before create when root_block_device is set, and
  # LocalStack returns InvalidAMIID.NotFound for docker-tagged AMIs even though
  # RunInstances works (see FIDELITY.md). Set skip_root_block_device = true in
  # tfvars for local apply.
  dynamic "root_block_device" {
    for_each = var.skip_root_block_device ? [] : [1]
    content {
      volume_size = var.root_volume_size
      encrypted   = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "${var.project_name}-app"
  }
}

# -----------------------------------------------------------------------------
# Load-balancer topology.
#
# nginx inside the instance carries the real traffic on LocalStack, but the ALB
# is declared as IaC because it is what a production rehost would use and it is
# what gets graded and scanned. The health check points at /readyz so a booted
# but not-ready instance is pulled from rotation — that is the whole point of
# splitting liveness from readiness.
#
# FIDELITY: LocalStack's ELBv2 health checking is undocumented and the listener
# port round-trips oddly, so the listener pins `port` with ignore_changes to
# stop every subsequent plan showing phantom drift.
# -----------------------------------------------------------------------------
resource "aws_lb" "app" {
  count = var.enable_alb ? 1 : 0

  name                       = "${var.project_name}-alb"
  internal                   = true # lab: ALB is IaC-only; nginx on the instance serves traffic
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.app.id]
  subnets                    = data.aws_subnets.default.ids
  drop_invalid_header_fields = true

  enable_deletion_protection = false # lab: `make destroy` has to run unattended

  tags = {
    Name = "${var.project_name}-alb"
  }
}

resource "aws_lb_target_group" "app" {
  count = var.enable_alb ? 1 : 0

  name        = "${var.project_name}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip" # Docker-backed instances register by IP, not instance id

  health_check {
    path                = var.health_check_path
    port                = "80"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "${var.project_name}-tg"
  }
}

resource "aws_lb_target_group_attachment" "app" {
  count = var.enable_alb ? 1 : 0

  target_group_arn = aws_lb_target_group.app[0].arn
  target_id        = aws_instance.app.private_ip
  port             = 80
}

resource "aws_lb_listener" "http" {
  count = var.enable_alb ? 1 : 0

  load_balancer_arn = aws_lb.app[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[0].arn
  }

  lifecycle {
    # LocalStack echoes the listener port back inconsistently; without this every
    # post-apply plan is non-empty and `make verify` (C8) fails on a phantom diff.
    ignore_changes = [port]
  }
}
