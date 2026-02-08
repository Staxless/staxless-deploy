#!/bin/bash
set -e

MANAGER_IP="$1"
COMPOSE_FILE="${2:-docker/compose/docker-compose.prod.yml}"
STACK_NAME="${3:-staxless}"

echo "Deploying stack: $STACK_NAME"

scp "$COMPOSE_FILE" root@"$MANAGER_IP":/root/stack.yml

ssh root@"$MANAGER_IP" "docker stack deploy -c /root/stack.yml --with-registry-auth $STACK_NAME"

echo "Stack deployed"
sleep 10
ssh root@"$MANAGER_IP" "docker service ls"
