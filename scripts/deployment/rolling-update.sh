#!/bin/bash
set -e

SERVICES="${1:-all}"
MANAGER_IP="$2"
STACK_NAME="${3:-staxless}"

echo "Running rolling update for: $SERVICES..."

if [ "$SERVICES" = "all" ]; then
  SERVICE_LIST=$(ssh root@"$MANAGER_IP" "docker service ls --format '{{.Name}}' | grep '^${STACK_NAME}_'")
else
  SERVICE_LIST=""
  IFS=',' read -ra SERVICE_NAMES <<< "$SERVICES"
  for service in "${SERVICE_NAMES[@]}"; do
    service=$(echo "$service" | xargs)
    SERVICE_LIST="$SERVICE_LIST ${STACK_NAME}_${service}"
  done
fi

FAILED=0
for service in $SERVICE_LIST; do
  echo "Updating: $service"

  CURRENT_IMAGE=$(ssh root@"$MANAGER_IP" "docker service inspect $service --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}'")
  IMAGE_BASE=$(echo "$CURRENT_IMAGE" | cut -d: -f1)
  NEW_IMAGE="${IMAGE_BASE}:latest"

  ssh root@"$MANAGER_IP" "docker service update \
    --image $NEW_IMAGE \
    --update-parallelism 1 \
    --update-delay 10s \
    --update-failure-action rollback \
    --update-monitor 30s \
    $service"

  sleep 5

  UPDATE_STATUS=$(ssh root@"$MANAGER_IP" "docker service inspect $service --format '{{.UpdateStatus.State}}'")

  if [ "$UPDATE_STATUS" = "completed" ]; then
    echo "$service updated"
  elif [ "$UPDATE_STATUS" = "rollback_completed" ]; then
    echo "FAILED: $service rolled back"
    FAILED=1
  else
    echo "$service status: $UPDATE_STATUS"
  fi
done

if [ "$FAILED" -eq 1 ]; then
  echo "One or more services failed"
  exit 1
fi

echo "All services updated"
