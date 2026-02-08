output "manager_ip" {
  value       = digitalocean_droplet.manager.ipv4_address
  description = "Manager node public IP"
}

output "manager_private_ip" {
  value       = digitalocean_droplet.manager.ipv4_address_private
  description = "Manager node private IP"
}

output "worker_ips" {
  value       = digitalocean_droplet.workers[*].ipv4_address
  description = "Worker nodes public IPs"
}

output "worker_private_ips" {
  value       = digitalocean_droplet.workers[*].ipv4_address_private
  description = "Worker nodes private IPs"
}

output "vpc_id" {
  value       = digitalocean_vpc.main.id
  description = "VPC ID"
}

output "all_node_ips" {
  value = concat(
    [digitalocean_droplet.manager.ipv4_address],
    digitalocean_droplet.workers[*].ipv4_address
  )
  description = "All node public IPs (for MongoDB whitelist)"
}
