resource "aws_lb" "gitlab_internal_lb" {
  count = var.elb_internal_create ? 1 : 0

  name               = "${format("%.28s", var.prefix)}-int"
  load_balancer_type = "network"
  internal           = true
  subnets            = coalesce(local.backend_subnet_ids, local.default_subnet_ids)

  security_groups = [
    aws_security_group.gitlab_internal_networking.id
  ]

  enable_cross_zone_load_balancing = true

  tags = merge(var.custom_tags, var.elb_internal_custom_tags)
}

# GitLab Rails
resource "aws_lb_target_group" "gitlab_internal_gitlab_rails" {
  count = var.elb_internal_create && var.gitlab_rails_node_count > 0 ? 1 : 0

  name     = "${format("%.15s", var.prefix)}-int-gitlab-rails"
  port     = 80
  protocol = "TCP"
  vpc_id   = coalesce(local.vpc_id, local.default_vpc_id)

  health_check {
    enabled = true

    protocol = "TCP"

    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "gitlab_internal_gitlab_rails" {
  count = var.elb_internal_create ? var.gitlab_rails_node_count : 0

  target_group_arn = aws_lb_target_group.gitlab_internal_gitlab_rails[0].arn
  target_id        = module.gitlab_rails.instance_ids[count.index]
}

resource "aws_lb_listener" "gitlab_internal_gitlab_rails" {
  count = var.elb_internal_create && var.gitlab_rails_node_count > 0 ? 1 : 0

  load_balancer_arn = aws_lb.gitlab_internal_lb[0].arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gitlab_internal_gitlab_rails[0].arn
  }
}

# PgBouncer
resource "aws_lb_target_group" "gitlab_internal_pgbouncer" {
  count = var.elb_internal_create && var.pgbouncer_node_count > 0 ? 1 : 0

  name     = "${format("%.18s", var.prefix)}-int-pgbouncer"
  port     = 6432
  protocol = "TCP"
  vpc_id   = coalesce(local.vpc_id, local.default_vpc_id)

  health_check {
    enabled = true

    protocol = "TCP"

    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "gitlab_internal_pgbouncer" {
  count = var.elb_internal_create ? var.pgbouncer_node_count : 0

  target_group_arn = aws_lb_target_group.gitlab_internal_pgbouncer[0].arn
  target_id        = module.pgbouncer.instance_ids[count.index]
}

resource "aws_lb_listener" "gitlab_internal_pgbouncer" {
  count = var.elb_internal_create && var.pgbouncer_node_count > 0 ? 1 : 0

  load_balancer_arn = aws_lb.gitlab_internal_lb[0].arn
  port              = 6432
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gitlab_internal_pgbouncer[0].arn
  }
}

# Praefect
resource "aws_lb_target_group" "gitlab_internal_praefect" {
  count = var.elb_internal_create && var.praefect_node_count > 0 ? 1 : 0

  name     = "${format("%.19s", var.prefix)}-int-praefect"
  port     = var.elb_internal_praefect_port
  protocol = "TCP"
  vpc_id   = coalesce(local.vpc_id, local.default_vpc_id)

  health_check {
    enabled = true

    protocol = "TCP"

    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "gitlab_internal_praefect" {
  count = var.elb_internal_create ? var.praefect_node_count : 0

  target_group_arn = aws_lb_target_group.gitlab_internal_praefect[0].arn
  target_id        = module.praefect.instance_ids[count.index]
}

resource "aws_lb_listener" "gitlab_internal_praefect" {
  count = var.elb_internal_create && var.praefect_node_count > 0 ? 1 : 0

  load_balancer_arn = aws_lb.gitlab_internal_lb[0].arn
  port              = var.elb_internal_praefect_port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gitlab_internal_praefect[0].arn
  }
}

# Postgres Primary for Geo Replication
resource "aws_lb_target_group" "gitlab_internal_postgres_primary" {
  count = var.elb_internal_create && var.postgres_node_count > 0 && var.geo_site != null ? 1 : 0

  name     = "${format("%.11s", var.prefix)}-int-postgres-primary"
  port     = 5432
  protocol = "TCP"
  vpc_id   = coalesce(local.vpc_id, local.default_vpc_id)

  health_check {
    enabled = true

    protocol = "TCP"
    port     = 8008

    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "gitlab_internal_postgres_primary" {
  count = var.elb_internal_create && var.geo_site != null ? var.postgres_node_count : 0

  target_group_arn = aws_lb_target_group.gitlab_internal_postgres_primary[0].arn
  target_id        = module.postgres.instance_ids[count.index]
}

resource "aws_lb_listener" "gitlab_internal_postgres_primary" {
  count = var.elb_internal_create && var.postgres_node_count > 0 && var.geo_site != null ? 1 : 0

  load_balancer_arn = aws_lb.gitlab_internal_lb[0].arn
  port              = 5432
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gitlab_internal_postgres_primary[0].arn
  }
}

output "elb_internal" {
  value = {
    "elb_internal_host"    = try(aws_lb.gitlab_internal_lb[0].dns_name, "")
    "elb_internal_zone_id" = try(aws_lb.gitlab_internal_lb[0].zone_id, "")
  }
}
