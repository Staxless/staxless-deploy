#!/bin/bash
set -e

MANAGER_IP="$1"
STACK_NAME="${2:-staxless}"

echo "Starting graceful shutdown..."

if ! ssh -o ConnectTimeout=5 root@"$MANAGER_IP" "echo ready" 2>/dev/null; then
  echo "Manager not reachable - skipping"
  exit 0
fi

SERVICES=$(ssh root@"$MANAGER_IP" "docker service ls --format '{{.Name}}' | grep '^${STACK_NAME}_'" 2>/dev/null || echo "")

if [ -z "$SERVICES" ]; then
  echo "No services found"
  exit 0
fi

echo "Step 1: Scale down services"
for service in $SERVICES; do
  echo "Scaling down: $service"
  ssh root@"$MANAGER_IP" "docker service scale $service=0" || true
  sleep 2
done

echo "Waiting 30 seconds..."
sleep 30

echo "Step 2: Remove services"
for service in $SERVICES; do
  ssh root@"$MANAGER_IP" "docker service rm $service" || true
done
sleep 10

echo "Step 3: Remove stack"
ssh root@"$MANAGER_IP" "docker stack rm $STACK_NAME" 2>/dev/null || true
sleep 20

echo "Step 4: Leave swarm"
ssh root@"$MANAGER_IP" "docker swarm leave --force" 2>/dev/null || true

echo "Graceful shutdown complete"
