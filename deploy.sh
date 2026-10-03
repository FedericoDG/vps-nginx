#!/bin/sh
# Deploy stage-1: pull already done by caller (git reset --hard origin/main).
# Recreate (not restart): bind-mounts anchor to inodes; down/up is the only
# safe refresh for single-file mounts (runbook Fase 5 findings).
set -e
cd /root/vps-nginx

docker compose down
docker compose up -d
sleep 5

# Config sanity after bring-up
docker compose exec -T nginx nginx -t

# Health check: /health is served on the 443 vhost (10-*.conf)
i=0
until docker compose exec -T nginx wget -q -O /dev/null --no-check-certificate https://127.0.0.1/health; do
  i=$((i+1))
  if [ "$i" -ge 10 ]; then
    echo "HEALTH CHECK FAILED after 10 attempts" >&2
    exit 1
  fi
  sleep 3
done
echo "HEALTH OK"
