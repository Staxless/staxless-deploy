#!/bin/bash
set -e

echo "Setting up MongoDB Atlas..."

API_BASE="https://cloud.mongodb.com/api/atlas/v1.0"
PROJECT_ID="$MONGODB_ATLAS_PROJECT_ID"

# Generate random password
DB_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

# Create cluster
echo "Creating M10 cluster..."
curl -s -X POST "$API_BASE/groups/$PROJECT_ID/clusters" \
  --user "$MONGODB_ATLAS_PUBLIC_KEY:$MONGODB_ATLAS_PRIVATE_KEY" \
  --digest \
  --header "Content-Type: application/json" \
  --data '{
    "name": "staxless-production",
    "clusterType": "REPLICASET",
    "providerSettings": {
      "providerName": "AWS",
      "instanceSizeName": "M10",
      "regionName": "US_EAST_1"
    }
  }'

echo "Waiting for cluster to be ready (7-10 minutes)..."
for i in {1..60}; do
  STATE=$(curl -s "$API_BASE/groups/$PROJECT_ID/clusters/staxless-production" \
    --user "$MONGODB_ATLAS_PUBLIC_KEY:$MONGODB_ATLAS_PRIVATE_KEY" \
    --digest | jq -r '.stateName')

  if [ "$STATE" = "IDLE" ]; then
    echo "Cluster ready"
    break
  fi

  echo "Status: $STATE (attempt $i/60)"
  sleep 10
done

# Create database user
echo "Creating database user..."
curl -s -X POST "$API_BASE/groups/$PROJECT_ID/databaseUsers" \
  --user "$MONGODB_ATLAS_PUBLIC_KEY:$MONGODB_ATLAS_PRIVATE_KEY" \
  --digest \
  --header "Content-Type: application/json" \
  --data "{
    \"databaseName\": \"admin\",
    \"username\": \"staxless-app\",
    \"password\": \"$DB_PASSWORD\",
    \"roles\": [
      {\"databaseName\": \"auth\", \"roleName\": \"readWrite\"},
      {\"databaseName\": \"users\", \"roleName\": \"readWrite\"},
      {\"databaseName\": \"stripe\", \"roleName\": \"readWrite\"}
    ]
  }"

# Whitelist IPs (must be called AFTER infrastructure is provisioned)
echo "Whitelisting droplet IPs..."
IFS=',' read -ra IP_LIST <<< "$ALL_NODE_IPS"
for IP in "${IP_LIST[@]}"; do
  IP_CLEAN=$(echo "$IP" | tr -d '[]" ')
  curl -s -X POST "$API_BASE/groups/$PROJECT_ID/whitelist" \
    --user "$MONGODB_ATLAS_PUBLIC_KEY:$MONGODB_ATLAS_PRIVATE_KEY" \
    --digest \
    --header "Content-Type: application/json" \
    --data "[{\"ipAddress\": \"$IP_CLEAN\", \"comment\": \"Staxless droplet\"}]"
done

# Get connection string
CLUSTER_HOSTNAME=$(curl -s "$API_BASE/groups/$PROJECT_ID/clusters/staxless-production" \
  --user "$MONGODB_ATLAS_PUBLIC_KEY:$MONGODB_ATLAS_PRIVATE_KEY" \
  --digest | jq -r '.srvAddress')

DATABASE_URL="mongodb+srv://staxless-app:${DB_PASSWORD}@${CLUSTER_HOSTNAME}"

echo "DATABASE_URL=$DATABASE_URL" >> "$GITHUB_ENV"
echo "DATABASE_NAME=staxless" >> "$GITHUB_ENV"

echo "MongoDB Atlas setup complete"
