#!/bin/bash
set -e

MANAGER_IP="$1"
STACK_NAME="${2:-staxless}"
WAIT="${3:-30}"

echo "Running health checks..."
sleep "$WAIT"

FAILED=0
while IFS= read -r line; do
  SERVICE=$(echo "$line" | awk '{print $1}')
  REPLICAS=$(echo "$line" | awk '{print $2}')
  RUNNING=$(echo "$REPLICAS" | cut -d'/' -f1)
  DESIRED=$(echo "$REPLICAS" | cut -d'/' -f2)

  if [ "$RUNNING" != "$DESIRED" ]; then
    echo "UNHEALTHY: $SERVICE ($RUNNING/$DESIRED)"
    FAILED=1
  else
    echo "HEALTHY: $SERVICE ($RUNNING/$DESIRED)"
  fi
done <<< "$(ssh root@"$MANAGER_IP" "docker service ls --filter name=${STACK_NAME}_ --format '{{.Name}} {{.Replicas}}'")"

if [ "$FAILED" -eq 1 ]; then
  echo ""
  ssh root@"$MANAGER_IP" "docker service ls"
  echo ""
  echo "One or more services are unhealthy"
  exit 1
fi

echo "All services healthy"
