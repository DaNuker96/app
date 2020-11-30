output "public_dns_alb" {
  value = aws_alb.application_load_balancer.dns_name
}

output "cluster_id" {
  description = "The ID of the created ECS cluster."
  value       = aws_ecs_cluster.main_cluster.id
}


