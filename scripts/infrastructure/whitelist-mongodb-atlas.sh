#!/bin/bash
set -e

echo "Whitelisting IPs in MongoDB Atlas..."

# Validate required environment variables
for var in MONGODB_ATLAS_PROJECT_ID MONGODB_ATLAS_PUBLIC_KEY MONGODB_ATLAS_PRIVATE_KEY ALL_NODE_IPS; do
  if [ -z "${!var}" ]; then
    echo "Error: $var is not set"
    exit 1
  fi
done

API_BASE="https://cloud.mongodb.com/api/atlas/v2"
PROJECT_ID="$MONGODB_ATLAS_PROJECT_ID"

# Helper: make an Atlas API call, print response body, and fail on HTTP errors
atlas_api() {
  local method="$1" url="$2" data="$3"
  local tmpfile
  tmpfile=$(mktemp)

  local args=(-s -w "\n%{http_code}" -X "$method" --user "$MONGODB_ATLAS_PUBLIC_KEY:$MONGODB_ATLAS_PRIVATE_KEY" --digest)
  args+=(--header "Content-Type: application/json" --header "Accept: application/vnd.atlas.2024-08-05+json")
  [ -n "$data" ] && args+=(--data "$data")

  local output
  output=$(curl "${args[@]}" "$url")
  local http_code
  http_code=$(echo "$output" | tail -1)
  local body
  body=$(echo "$output" | sed '$d')

  if [ "$http_code" -ge 400 ] 2>/dev/null; then
    echo "Atlas API error ($method $url): HTTP $http_code"
    echo "$body"
    rm -f "$tmpfile"
    return 1
  fi

  rm -f "$tmpfile"
  echo "$body"
}

echo "Whitelisting droplet IPs..."
IFS=',' read -ra IP_LIST <<< "$ALL_NODE_IPS"
for IP in "${IP_LIST[@]}"; do
  IP_CLEAN=$(echo "$IP" | tr -d '[]" ')
  echo "Whitelisting IP: $IP_CLEAN"
  atlas_api POST "$API_BASE/groups/$PROJECT_ID/accessList" \
    "[{\"ipAddress\": \"$IP_CLEAN\", \"comment\": \"Staxless droplet\"}]" || true
done

echo "MongoDB Atlas IP whitelist complete"
