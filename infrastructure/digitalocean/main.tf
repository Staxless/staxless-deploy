terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    endpoints = {
      s3 = "https://nyc3.digitaloceanspaces.com"
    }
    region = "us-east-1"
    # bucket, key, access_key, secret_key provided via -backend-config
  }
}

provider "digitalocean" {
  token = var.do_token
}

resource "digitalocean_vpc" "main" {
  name   = "${var.stack_name}-vpc"
  region = var.region

  lifecycle {
    ignore_changes = [ip_range]
  }
}

resource "digitalocean_droplet" "manager" {
  name      = "${var.stack_name}-manager"
  region    = var.region
  size      = var.manager_size
  image     = "ubuntu-24-04-x64"
  vpc_uuid  = digitalocean_vpc.main.id
  ssh_keys  = [var.ssh_fingerprint]
  user_data = file("${path.module}/cloud-init-manager.yml")
  backups   = var.enable_backups
  tags      = [var.stack_name, "manager"]
}

resource "digitalocean_droplet" "workers" {
  count     = var.worker_count
  name      = "${var.stack_name}-worker-${count.index + 1}"
  region    = var.region
  size      = var.worker_size
  image     = "ubuntu-24-04-x64"
  vpc_uuid  = digitalocean_vpc.main.id
  ssh_keys  = [var.ssh_fingerprint]
  user_data = file("${path.module}/cloud-init-worker.yml")
  backups   = var.enable_backups
  tags      = [var.stack_name, "worker"]
}

resource "digitalocean_firewall" "main" {
  name = "${var.stack_name}-firewall"
  droplet_ids = concat(
    [digitalocean_droplet.manager.id],
    digitalocean_droplet.workers[*].id
  )

  # SSH — no permanent rule; whitelist-ssh/remove-ssh manage access dynamically

  # HTTP — Cloudflare only (Cloudflare terminates TLS, connects on port 80)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = var.cloudflare_ipv4
  }

  # Docker Swarm management
  inbound_rule {
    protocol         = "tcp"
    port_range       = "2377"
    source_addresses = [digitalocean_vpc.main.ip_range]
  }

  # Docker Swarm node communication (TCP)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "7946"
    source_addresses = [digitalocean_vpc.main.ip_range]
  }

  # Docker Swarm node communication (UDP)
  inbound_rule {
    protocol         = "udp"
    port_range       = "7946"
    source_addresses = [digitalocean_vpc.main.ip_range]
  }

  # Docker Swarm overlay network
  inbound_rule {
    protocol         = "udp"
    port_range       = "4789"
    source_addresses = [digitalocean_vpc.main.ip_range]
  }

  # Outbound: VPC internal (swarm inter-node, all ports)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = [digitalocean_vpc.main.ip_range]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = [digitalocean_vpc.main.ip_range]
  }

  # Outbound: HTTPS (Docker registry, MongoDB Atlas, Stripe, Mailgun, etc.)
  outbound_rule {
    protocol              = "tcp"
    port_range            = "443"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Outbound: HTTP
  outbound_rule {
    protocol              = "tcp"
    port_range            = "80"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Outbound: DNS
  outbound_rule {
    protocol              = "tcp"
    port_range            = "53"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "53"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Outbound: NTP
  outbound_rule {
    protocol              = "udp"
    port_range            = "123"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Outbound: ICMP
  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
