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

# Initialize swarm — no heredoc, direct commands to avoid variable expansion bug
PRIVATE_IP=$(ssh root@"$MANAGER_IP" "ip addr show eth1 | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1")
ssh root@"$MANAGER_IP" "docker swarm init --advertise-addr $PRIVATE_IP"

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

  ssh root@"$WORKER_IP" "docker swarm join --token $WORKER_TOKEN $MANAGER_PRIVATE_IP:2377"
  echo "$WORKER_IP joined"
done

echo "Swarm initialized"
ssh root@"$MANAGER_IP" "docker node ls"
