#!/bin/bash
set -e

# Fixed: Uses -backend-config CLI args instead of heredoc
# The original wrote literal "$DO_SPACES_ACCESS_KEY" strings due to single-quoted heredoc

INFRA_DIR="$1"
DO_SPACES_ACCESS_KEY="$2"
DO_SPACES_SECRET_KEY="$3"
STATE_BUCKET="${4:-staxless-terraform-state}"
STATE_KEY="${5:-production/terraform.tfstate}"

echo "Provisioning infrastructure with Terraform..."

cd "$INFRA_DIR"

terraform init -upgrade \
  -backend-config="access_key=$DO_SPACES_ACCESS_KEY" \
  -backend-config="secret_key=$DO_SPACES_SECRET_KEY" \
  -backend-config="bucket=$STATE_BUCKET" \
  -backend-config="key=$STATE_KEY"

terraform validate
terraform plan -out=tfplan
terraform apply -auto-approve tfplan

# Get outputs
MANAGER_IP=$(terraform output -raw manager_ip)
WORKER_IPS=$(terraform output -json worker_ips | jq -r 'join(",")')
ALL_NODE_IPS=$(terraform output -json all_node_ips)

echo "MANAGER_IP=$MANAGER_IP" >> "$GITHUB_ENV"
echo "WORKER_IPS=$WORKER_IPS" >> "$GITHUB_ENV"
echo "ALL_NODE_IPS=$ALL_NODE_IPS" >> "$GITHUB_ENV"

echo "Infrastructure provisioned"
echo "Manager IP: $MANAGER_IP"
echo "Worker IPs: $WORKER_IPS"
