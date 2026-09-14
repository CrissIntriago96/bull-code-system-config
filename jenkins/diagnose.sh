#!/usr/bin/env bash
# Estado y últimos logs de <app> y del Config Server (lo corre el pipeline cuando falla).
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

app="${1:-}"

if [ -n "$app" ] && service_info "$app" && [ -f "$DEPLOY_DIR/docker-compose.prod.yml" ]; then
  compose_in "$DEPLOY_DIR" ps || true
  compose_in "$DEPLOY_DIR" logs --no-color --tail=150 "$SERVICE" || true
fi

if [ -f "$CONFIG_SERVER_DIR/docker-compose.prod.yml" ]; then
  compose_in "$CONFIG_SERVER_DIR" logs --no-color --tail=50 config-server || true
fi
