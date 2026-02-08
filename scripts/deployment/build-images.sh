#!/bin/bash
set -e

SERVICES="${1:-all}"
BAKE_FILE="${2:-docker/docker-bake.hcl}"

echo "Building images for: $SERVICES..."
echo "Bake file: $BAKE_FILE"

if [ "$SERVICES" = "all" ]; then
  docker buildx bake -f "$BAKE_FILE" --push
else
  IFS=',' read -ra SERVICE_LIST <<< "$SERVICES"
  for service in "${SERVICE_LIST[@]}"; do
    service=$(echo "$service" | xargs)
    echo "Building $service..."
    docker buildx bake -f "$BAKE_FILE" --push "$service"
  done
fi

echo "Images built and pushed"
