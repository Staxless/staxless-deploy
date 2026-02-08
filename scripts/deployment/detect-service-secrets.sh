#!/bin/bash
set -e

SERVICE_NAME="$1"
COMPOSE_FILE="${2:-docker/compose/docker-compose.prod.yml}"
BAKE_FILE="${3:-docker/docker-bake.hcl}"

echo "Detecting secrets for: $SERVICE_NAME..."

# Check in docker-compose
if ! grep -q "^\s*${SERVICE_NAME}:" "$COMPOSE_FILE"; then
  echo "Service not found in $COMPOSE_FILE"
  exit 1
fi

# Check in bake file
if ! grep -q "target \"${SERVICE_NAME}\"" "$BAKE_FILE"; then
  echo "Service not found in $BAKE_FILE"
  exit 1
fi

echo "Service definition found"

# Extract secrets using Python
python3 << PYEOF
import yaml
import sys
import os

service_name = "$SERVICE_NAME"
compose_file = "$COMPOSE_FILE"

try:
    with open(compose_file, 'r') as f:
        compose = yaml.safe_load(f)

    if 'services' not in compose or service_name not in compose['services']:
        sys.exit(1)

    service = compose['services'][service_name]
    secrets = []

    if 'secrets' in service:
        if isinstance(service['secrets'], list):
            for secret in service['secrets']:
                if isinstance(secret, dict) and 'source' in secret:
                    secrets.append(secret['source'])
                elif isinstance(secret, str):
                    secrets.append(secret)

    secrets_str = ','.join(secrets) if secrets else ''

    with open(os.environ['GITHUB_OUTPUT'], 'a') as f:
        f.write(f"secrets={secrets_str}\n")
        f.write(f"has_secrets={'true' if secrets else 'false'}\n")

    print(f"Found secrets: {secrets_str}")
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
PYEOF

echo "Secret detection complete"
