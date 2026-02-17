#!/bin/bash
set -e

SERVICES="${1:-all}"
MANAGER_IP="$2"
STACK_NAME="${3:-staxless}"
MAX_WAIT="${4:-120}"

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

  CURRENT_DIGEST=$(echo "$CURRENT_IMAGE" | grep -o 'sha256:[a-f0-9]*' || echo "")
  LATEST_DIGEST=$(ssh root@"$MANAGER_IP" "docker pull $NEW_IMAGE 2>/dev/null | grep 'Digest:' | awk '{print \$2}'" || echo "")

  if [ -n "$CURRENT_DIGEST" ] && [ -n "$LATEST_DIGEST" ] && [ "$CURRENT_DIGEST" = "$LATEST_DIGEST" ]; then
    echo "SKIP: $service already running latest image"
    continue
  fi

  # Use digest-pinned image so Docker sees an actual spec change
  FORCE_FLAG=""
  if [ -n "$LATEST_DIGEST" ]; then
    UPDATE_IMAGE="${IMAGE_BASE}@${LATEST_DIGEST}"
  else
    UPDATE_IMAGE="$NEW_IMAGE"
    FORCE_FLAG="--force"
  fi

  ssh root@"$MANAGER_IP" "docker service update \
    --with-registry-auth \
    --image $UPDATE_IMAGE \
    --update-parallelism 1 \
    --update-delay 10s \
    --update-failure-action rollback \
    --update-monitor 30s \
    $FORCE_FLAG \
    $service"

  ELAPSED=0
  INTERVAL=10
  CONVERGED=false

  while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))

    STATE=$(ssh root@"$MANAGER_IP" "docker service inspect $service --format '{{if .UpdateStatus}}{{.UpdateStatus.State}}{{else}}unknown{{end}}'")

    if [ "$STATE" = "completed" ]; then
      echo "$service converged on $NEW_IMAGE (${ELAPSED}s)"
      CONVERGED=true
      break
    elif [ "$STATE" = "unknown" ]; then
      # No UpdateStatus means stable — update completed or was a no-op
      RUNNING_COUNT=$(ssh root@"$MANAGER_IP" "docker service ps $service --filter desired-state=running -q | wc -l")
      if [ "$RUNNING_COUNT" -gt 0 ]; then
        echo "$service converged on $NEW_IMAGE (${ELAPSED}s, tasks running)"
        CONVERGED=true
        break
      fi
    elif [ "$STATE" = "rollback_completed" ]; then
      echo "FAILED: $service rolled back to previous image"
      FAILED=1
      break
    fi

    echo "  waiting for $service to converge (${ELAPSED}/${MAX_WAIT}s, state=$STATE)"
  done

  if [ "$CONVERGED" = "false" ] && [ "$FAILED" -eq 0 ]; then
    echo "FAILED: $service did not converge within ${MAX_WAIT}s (state=$STATE)"
    ssh root@"$MANAGER_IP" "docker service ps $service --no-trunc" || true
    FAILED=1
  fi
done

if [ "$FAILED" -eq 1 ]; then
  echo "One or more services failed"
  exit 1
fi

# Clean up dangling images left behind by previous deploys
echo "Pruning dangling images..."
ssh root@"$MANAGER_IP" "docker image prune -f" || true

echo "All services updated"
