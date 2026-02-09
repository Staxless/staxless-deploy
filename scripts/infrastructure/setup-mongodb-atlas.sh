#!/bin/bash
set -e

echo "Setting up MongoDB Atlas..."

# Validate required environment variables
for var in MONGODB_ATLAS_PROJECT_ID MONGODB_ATLAS_PUBLIC_KEY MONGODB_ATLAS_PRIVATE_KEY; do
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

# Generate random password
DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

# Create cluster (skip if it already exists)
echo "Creating M10 cluster..."
if atlas_api GET "$API_BASE/groups/$PROJECT_ID/clusters/staxless-production" &>/dev/null; then
  echo "Cluster already exists, skipping creation"
else
  atlas_api POST "$API_BASE/groups/$PROJECT_ID/clusters" '{
    "name": "staxless-production",
    "clusterType": "REPLICASET",
    "replicationSpecs": [{
      "regionConfigs": [{
        "providerName": "AWS",
        "regionName": "US_EAST_1",
        "priority": 7,
        "electableSpecs": { "instanceSize": "M10", "nodeCount": 3 }
      }]
    }]
  }'
fi

echo "Waiting for cluster to be ready (7-10 minutes)..."
for i in $(seq 1 60); do
  RESPONSE=$(atlas_api GET "$API_BASE/groups/$PROJECT_ID/clusters/staxless-production")
  STATE=$(echo "$RESPONSE" | jq -r '.stateName')

  if [ "$STATE" = "IDLE" ]; then
    echo "Cluster ready"
    break
  fi

  echo "Status: $STATE (attempt $i/60)"
  sleep 10
done

if [ "$STATE" != "IDLE" ]; then
  echo "Error: Cluster did not become ready in time"
  exit 1
fi

# Create database user
echo "Creating database user..."
atlas_api POST "$API_BASE/groups/$PROJECT_ID/databaseUsers" "{
  \"databaseName\": \"admin\",
  \"username\": \"staxless-app\",
  \"password\": \"$DB_PASSWORD\",
  \"roles\": [
    {\"databaseName\": \"auth\", \"roleName\": \"readWrite\"},
    {\"databaseName\": \"users\", \"roleName\": \"readWrite\"},
    {\"databaseName\": \"stripe\", \"roleName\": \"readWrite\"}
  ]
}" || echo "User may already exist, continuing..."

# Whitelist IPs (must be called AFTER infrastructure is provisioned)
if [ -n "$ALL_NODE_IPS" ]; then
  echo "Whitelisting droplet IPs..."
  IFS=',' read -ra IP_LIST <<< "$ALL_NODE_IPS"
  for IP in "${IP_LIST[@]}"; do
    IP_CLEAN=$(echo "$IP" | tr -d '[]" ')
    atlas_api POST "$API_BASE/groups/$PROJECT_ID/accessList" \
      "[{\"ipAddress\": \"$IP_CLEAN\", \"comment\": \"Staxless droplet\"}]" || true
  done
else
  echo "Warning: ALL_NODE_IPS not set, skipping IP whitelist"
fi

# Get connection string
CLUSTER_INFO=$(atlas_api GET "$API_BASE/groups/$PROJECT_ID/clusters/staxless-production")
CLUSTER_HOSTNAME=$(echo "$CLUSTER_INFO" | jq -r '.srvAddress' | sed 's|mongodb+srv://||')

DATABASE_URL="mongodb+srv://staxless-app:${DB_PASSWORD}@${CLUSTER_HOSTNAME}"

echo "DATABASE_URL=$DATABASE_URL" >> "$GITHUB_ENV"
echo "DATABASE_NAME=staxless" >> "$GITHUB_ENV"

echo "MongoDB Atlas setup complete"
