#!/bin/bash
set -e

# Fixed: Uses piped printf instead of echo with single quotes
# to prevent variable expansion issues

MANAGER_IP="$1"

echo "Creating service secrets..."

REQUIRED_SECRETS="$2"

if [ -z "$REQUIRED_SECRETS" ]; then
  echo "No secrets required"
  exit 0
fi

IFS=',' read -ra SECRETS <<< "$REQUIRED_SECRETS"

for secret in "${SECRETS[@]}"; do
  secret_upper=$(echo "$secret" | tr '[:lower:]' '[:upper:]')
  secret_value="${!secret_upper}"

  if [ -n "$secret_value" ]; then
    echo "Creating: $secret"
    printf '%s' "$secret_value" | ssh root@"$MANAGER_IP" "docker secret create $secret - 2>/dev/null" || echo "$secret already exists"
  else
    echo "WARNING: $secret_upper not set"
  fi
done

echo "Secrets created"
