variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "ssh_fingerprint" {
  description = "SSH key fingerprint registered in DigitalOcean"
  type        = string
}

variable "domain" {
  description = "Domain name for the deployment"
  type        = string
}

variable "stack_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "staxless"
}

variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "nyc3"
}

variable "manager_size" {
  description = "Manager droplet size"
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "worker_size" {
  description = "Worker droplet size"
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "cloudflare_ipv4" {
  description = "Cloudflare IPv4 ranges for HTTP ingress"
  type        = list(string)
  default = [
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "108.162.192.0/18",
    "131.0.72.0/22",
    "141.101.64.0/18",
    "162.158.0.0/15",
    "172.64.0.0/13",
    "173.245.48.0/20",
    "188.114.96.0/20",
    "190.93.240.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
  ]
}

variable "enable_backups" {
  description = "Enable droplet backups"
  type        = bool
  default     = false
}
