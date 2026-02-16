#!/bin/bash
set -e

echo "Setting up Cloudflare Tunnel..."

# Skip if Cloudflare credentials are not configured
if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
  echo "CLOUDFLARE_API_TOKEN is not set — skipping Cloudflare setup"
  exit 0
fi

# Validate required environment variables
for var in CLOUDFLARE_ACCOUNT_ID DOMAIN STACK_NAME MANAGER_IP COMPOSE_FILE; do
  if [ -z "${!var}" ]; then
    echo "Error: $var is not set"
    exit 1
  fi
done

CF_API="https://api.cloudflare.com/client/v4"
ACCOUNT_ID="$CLOUDFLARE_ACCOUNT_ID"
TUNNEL_NAME="$STACK_NAME"

# Helper: make a Cloudflare API call, print response body, and fail on HTTP errors
cf_api() {
  local method="$1" url="$2" data="$3"

  local args=(-s -w "\n%{http_code}" -X "$method")
  args+=(--header "Authorization: Bearer $CLOUDFLARE_API_TOKEN")
  args+=(--header "Content-Type: application/json")
  [ -n "$data" ] && args+=(--data "$data")

  local output
  output=$(curl "${args[@]}" "$url")
  local http_code
  http_code=$(echo "$output" | tail -1)
  local body
  body=$(echo "$output" | sed '$d')

  if [ "$http_code" -ge 400 ] 2>/dev/null; then
    echo "Cloudflare API error ($method $url): HTTP $http_code"
    echo "$body"
    return 1
  fi

  echo "$body"
}

# ── Step 1: Check/create tunnel ────────────────────────────────────
echo "Checking for existing tunnel: $TUNNEL_NAME..."
TUNNELS_RESPONSE=$(cf_api GET "$CF_API/accounts/$ACCOUNT_ID/cfd_tunnel?name=$TUNNEL_NAME&is_deleted=false")
TUNNEL_COUNT=$(echo "$TUNNELS_RESPONSE" | jq '.result | length')

if [ "$TUNNEL_COUNT" -gt 0 ]; then
  TUNNEL_ID=$(echo "$TUNNELS_RESPONSE" | jq -r '.result[0].id')
  echo "Tunnel already exists: $TUNNEL_ID"
else
  echo "Creating tunnel: $TUNNEL_NAME..."
  TUNNEL_SECRET=$(openssl rand -base64 32)
  CREATE_RESPONSE=$(cf_api POST "$CF_API/accounts/$ACCOUNT_ID/cfd_tunnel" "{
    \"name\": \"$TUNNEL_NAME\",
    \"tunnel_secret\": \"$(echo -n "$TUNNEL_SECRET" | base64)\"
  }")
  TUNNEL_ID=$(echo "$CREATE_RESPONSE" | jq -r '.result.id')

  if [ -z "$TUNNEL_ID" ] || [ "$TUNNEL_ID" = "null" ]; then
    echo "Error: Failed to create tunnel"
    echo "$CREATE_RESPONSE"
    exit 1
  fi

  echo "Tunnel created: $TUNNEL_ID"
fi

# ── Step 2: Construct tunnel token ─────────────────────────────────
echo "Fetching tunnel token..."
TOKEN_RESPONSE=$(cf_api GET "$CF_API/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/token")
TUNNEL_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.result')

if [ -z "$TUNNEL_TOKEN" ] || [ "$TUNNEL_TOKEN" = "null" ]; then
  echo "Error: Failed to get tunnel token"
  echo "$TOKEN_RESPONSE"
  exit 1
fi

echo "::add-mask::$TUNNEL_TOKEN"

# ── Step 3: Get zone ID ────────────────────────────────────────────
echo "Looking up zone for: $DOMAIN..."
ZONE_RESPONSE=$(cf_api GET "$CF_API/zones?name=$DOMAIN")
ZONE_ID=$(echo "$ZONE_RESPONSE" | jq -r '.result[0].id')

if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" = "null" ]; then
  echo "Error: Zone not found for domain: $DOMAIN"
  echo "$ZONE_RESPONSE"
  exit 1
fi

echo "Zone ID: $ZONE_ID"

# ── Step 4: Upsert DNS CNAME records ──────────────────────────────
TUNNEL_CNAME="${TUNNEL_ID}.cfargotunnel.com"

upsert_dns() {
  local record_name="$1"
  echo "Checking DNS record: $record_name..."

  local existing
  existing=$(cf_api GET "$CF_API/zones/$ZONE_ID/dns_records?type=CNAME&name=$record_name")
  local count
  count=$(echo "$existing" | jq '.result | length')

  local payload="{
    \"type\": \"CNAME\",
    \"name\": \"$record_name\",
    \"content\": \"$TUNNEL_CNAME\",
    \"proxied\": true
  }"

  if [ "$count" -gt 0 ]; then
    local record_id
    record_id=$(echo "$existing" | jq -r '.result[0].id')
    echo "Updating existing record: $record_id"
    cf_api PATCH "$CF_API/zones/$ZONE_ID/dns_records/$record_id" "$payload" > /dev/null
  else
    echo "Creating new CNAME record: $record_name → $TUNNEL_CNAME"
    cf_api POST "$CF_API/zones/$ZONE_ID/dns_records" "$payload" > /dev/null
  fi

  echo "DNS record configured: $record_name"
}

upsert_dns "$DOMAIN"
upsert_dns "api.$DOMAIN"

# ── Step 5: Parse ports from compose file ──────────────────────────
echo "Parsing ports from compose file: $COMPOSE_FILE..."

PORTS_JSON=$(python3 -c "
import yaml, json, sys

with open('$COMPOSE_FILE') as f:
    compose = yaml.safe_load(f)

services = compose.get('services', {})

# Get frontend PORT from environment
frontend_port = '3000'
frontend = services.get('frontend', {})
for env in frontend.get('environment', []):
    if isinstance(env, str) and env.startswith('PORT='):
        frontend_port = env.split('=', 1)[1]
    elif isinstance(env, dict) and 'PORT' in env:
        frontend_port = str(env['PORT'])

# If environment is a dict (mapping form)
if isinstance(frontend.get('environment', []), dict):
    frontend_port = str(frontend['environment'].get('PORT', frontend_port))

# Get Kong port from KONG_PROXY_LISTEN
kong_port = '8000'
kong = services.get('kong-api-gateway', {})
kong_env = kong.get('environment', {})
if isinstance(kong_env, dict):
    listen = kong_env.get('KONG_PROXY_LISTEN', '')
    if ':' in listen:
        kong_port = listen.rsplit(':', 1)[1].strip().split()[0]
elif isinstance(kong_env, list):
    for env in kong_env:
        if isinstance(env, str) and env.startswith('KONG_PROXY_LISTEN='):
            listen = env.split('=', 1)[1]
            if ':' in listen:
                kong_port = listen.rsplit(':', 1)[1].strip().split()[0]

print(json.dumps({'frontend_port': frontend_port, 'kong_port': kong_port}))
")

FRONTEND_PORT=$(echo "$PORTS_JSON" | jq -r '.frontend_port')
KONG_PORT=$(echo "$PORTS_JSON" | jq -r '.kong_port')

echo "Frontend port: $FRONTEND_PORT"
echo "Kong port: $KONG_PORT"

# ── Step 6: Set tunnel ingress config ──────────────────────────────
echo "Configuring tunnel ingress rules..."
cf_api PUT "$CF_API/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" "{
  \"config\": {
    \"ingress\": [
      {
        \"hostname\": \"$DOMAIN\",
        \"service\": \"http://frontend:$FRONTEND_PORT\"
      },
      {
        \"hostname\": \"api.$DOMAIN\",
        \"service\": \"http://kong-api-gateway:$KONG_PORT\"
      },
      {
        \"service\": \"http_status:404\"
      }
    ]
  }
}" > /dev/null

echo "Tunnel ingress configured"

# ── Step 7: Create Docker secret on manager ────────────────────────
echo "Creating Docker secret: CLOUDFLARE_TUNNEL_TOKEN..."
ssh root@"$MANAGER_IP" "docker secret rm CLOUDFLARE_TUNNEL_TOKEN 2>/dev/null" || true
printf '%s' "$TUNNEL_TOKEN" | ssh root@"$MANAGER_IP" "docker secret create CLOUDFLARE_TUNNEL_TOKEN -"
echo "Docker secret created"

# ── Step 8: Store as GitHub repo secret ────────────────────────────
echo "Storing CLOUDFLARE_TUNNEL_TOKEN as GitHub repo secret..."
echo "$TUNNEL_TOKEN" | gh secret set CLOUDFLARE_TUNNEL_TOKEN --repo "$GITHUB_REPOSITORY"
echo "GitHub secret set"

# ── Step 9: Write outputs ──────────────────────────────────────────
if [ -n "$GITHUB_OUTPUT" ]; then
  echo "tunnel_id=$TUNNEL_ID" >> "$GITHUB_OUTPUT"
fi

echo "Cloudflare setup complete"
echo "  Tunnel: $TUNNEL_NAME ($TUNNEL_ID)"
echo "  DNS: $DOMAIN → $TUNNEL_CNAME"
echo "  DNS: api.$DOMAIN → $TUNNEL_CNAME"
