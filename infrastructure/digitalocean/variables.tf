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

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.17.0.0/16"
}

variable "authorized_ssh_ips" {
  description = "IP addresses authorized for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_backups" {
  description = "Enable droplet backups"
  type        = bool
  default     = true
}
