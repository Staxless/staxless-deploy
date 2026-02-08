#!/bin/bash
set -e

SERVICE_NAME="$1"
MANAGER_IP="$2"
COMPOSE_FILE="${3:-docker/compose/docker-compose.prod.yml}"
STACK_NAME="${4:-staxless}"

echo "Deploying new service: $SERVICE_NAME..."

scp "$COMPOSE_FILE" root@"$MANAGER_IP":/root/stack.yml

ssh root@"$MANAGER_IP" "docker stack deploy -c /root/stack.yml --with-registry-auth $STACK_NAME"

echo "Service deployed"
sleep 10

ssh root@"$MANAGER_IP" "docker service ls | grep $SERVICE_NAME"
