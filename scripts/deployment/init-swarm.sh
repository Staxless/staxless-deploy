#!/bin/bash
set -e

MANAGER_IP="$1"
WORKER_IPS="$2"

echo "Initializing Docker Swarm..."

# Wait for manager
for i in $(seq 1 60); do
  if ssh -o ConnectTimeout=5 root@"$MANAGER_IP" "echo ready" 2>/dev/null; then
    echo "Manager ready"
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "Manager not ready after 60 attempts"
    exit 1
  fi
  echo "Attempt $i/60..."
  sleep 10
done

# Initialize swarm — skip if already a swarm manager
PRIVATE_IP=$(ssh root@"$MANAGER_IP" "ip addr show eth1 | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1")
SWARM_STATE=$(ssh root@"$MANAGER_IP" "docker info --format '{{.Swarm.LocalNodeState}}'" 2>/dev/null || echo "inactive")
if [ "$SWARM_STATE" = "active" ]; then
  echo "Node is already part of a swarm, skipping init"
else
  ssh root@"$MANAGER_IP" "docker swarm init --advertise-addr $PRIVATE_IP"
fi

# Get token
WORKER_TOKEN=$(ssh root@"$MANAGER_IP" "docker swarm join-token worker -q")
MANAGER_PRIVATE_IP="$PRIVATE_IP"

# Join workers
IFS=',' read -ra WORKERS <<< "$WORKER_IPS"
for WORKER_IP in "${WORKERS[@]}"; do
  echo "Joining worker: $WORKER_IP"
  for i in $(seq 1 60); do
    if ssh -o ConnectTimeout=5 root@"$WORKER_IP" "echo ready" 2>/dev/null; then
      break
    fi
    if [ "$i" -eq 60 ]; then
      echo "Worker $WORKER_IP not ready after 60 attempts"
      exit 1
    fi
    sleep 10
  done

  WORKER_SWARM_STATE=$(ssh root@"$WORKER_IP" "docker info --format '{{.Swarm.LocalNodeState}}'" 2>/dev/null || echo "inactive")
  if [ "$WORKER_SWARM_STATE" = "active" ]; then
    echo "$WORKER_IP is already part of a swarm, skipping join"
  else
    ssh root@"$WORKER_IP" "docker swarm join --token $WORKER_TOKEN $MANAGER_PRIVATE_IP:2377"
    echo "$WORKER_IP joined"
  fi
done

echo "Swarm initialized"
ssh root@"$MANAGER_IP" "docker node ls"
