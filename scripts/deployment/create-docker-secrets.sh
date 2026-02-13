#!/bin/bash
set -e

# Fixed: No heredoc — each secret is piped individually via SSH
# This avoids the single-quoted 'SSHEOF' bug that prevented variable expansion

MANAGER_IP="$1"

echo "Creating Docker secrets..."

create_secret() {
  local name="$1"
  local value="$2"
  if [ -n "$value" ]; then
    printf '%s' "$value" | ssh root@"$MANAGER_IP" "docker secret create $name - 2>/dev/null" && echo "Created: $name" || echo "$name already exists"
  fi
}

# Database
create_secret "DATABASE_URL" "$DATABASE_URL"
create_secret "DATABASE_NAME" "$DATABASE_NAME"

# OAuth — Google
create_secret "GOOGLE_CLIENT_ID" "$GOOGLE_CLIENT_ID"
create_secret "GOOGLE_CLIENT_SECRET" "$GOOGLE_CLIENT_SECRET"
create_secret "GOOGLE_REDIRECT_URI" "$GOOGLE_REDIRECT_URI"

# OAuth — GitHub
create_secret "GH_OAUTH_CLIENT_ID" "$GH_OAUTH_CLIENT_ID"
create_secret "GH_OAUTH_CLIENT_SECRET" "$GH_OAUTH_CLIENT_SECRET"

# Stripe
create_secret "STRIPE_PRIVATE_KEY" "$STRIPE_PRIVATE_KEY"
create_secret "STRIPE_WEBHOOK_SECRET" "$STRIPE_WEBHOOK_SECRET"

# Mailgun
create_secret "MAILGUN_API_KEY" "$MAILGUN_API_KEY"

# Cloudflare
create_secret "CLOUDFLARE_TUNNEL_TOKEN" "$CLOUDFLARE_TUNNEL_TOKEN"

echo "Secrets created:"
ssh root@"$MANAGER_IP" "docker secret ls"
