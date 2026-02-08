#!/bin/bash
set -e

# Fixed: Uses -backend-config CLI args for state access (same fix as terraform-apply)

INFRA_DIR="$1"
DO_SPACES_ACCESS_KEY="$2"
DO_SPACES_SECRET_KEY="$3"
STATE_BUCKET="${4:-staxless-terraform-state}"
STATE_KEY="${5:-production/terraform.tfstate}"

echo "Destroying infrastructure..."

cd "$INFRA_DIR"

terraform init \
  -backend-config="access_key=$DO_SPACES_ACCESS_KEY" \
  -backend-config="secret_key=$DO_SPACES_SECRET_KEY" \
  -backend-config="bucket=$STATE_BUCKET" \
  -backend-config="key=$STATE_KEY"

echo "Resources to be destroyed:"
terraform show

echo "Starting destruction in 10 seconds..."
sleep 10

terraform destroy -auto-approve

echo "Infrastructure destroyed"
echo "MongoDB Atlas NOT destroyed - delete manually: https://cloud.mongodb.com"
