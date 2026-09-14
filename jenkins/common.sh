#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Utilidades compartidas por los scripts del pipeline de configuración.
#  Se incluye con:  . "$(dirname "${BASH_SOURCE[0]}")/common.sh"
#
#  Los stacks (/opt/rrhh/<servicio>) los crean y despliegan los jobs de
#  bull-code-system-backend. Este pipeline solo los REINICIA para que relean su
#  configuración: nunca buildea, ni cambia imágenes, ni copia compose.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# Clientes del Config Server, en el orden en que se reinician:
#   notification-service primero: el backend (modo remote) le pide los correos.
#   api-gateway al final: su smoke test pasa por el backend.
APPS="notification-service rrhh-backend api-gateway"

CONFIG_SERVER_DIR="/opt/rrhh/config-server"

# Datos de despliegue de cada app del Config Server (su spring.application.name).
# Tienen que coincidir con el Jenkinsfile y el docker-compose.prod.yml de cada servicio
# en bull-code-system-backend.
service_info() {
  case "$1" in
    rrhh-backend)
      DEPLOY_DIR="/opt/rrhh/backend"; SERVICE="backend"; SERVICE_PORT="8080"
      # 401 = sin sesión, la respuesta correcta.
      SMOKE_PATH="/api/auth/session"; SMOKE_EXPECT="401"
      PROFILES="dev docker prod" ;;
    api-gateway)
      DEPLOY_DIR="/opt/rrhh/api-gateway"; SERVICE="api-gateway"; SERVICE_PORT="8090"
      # 401 = la gateway encontró al backend en Eureka y el backend respondió.
      SMOKE_PATH="/api/auth/session"; SMOKE_EXPECT="401"
      PROFILES="default docker prod" ;;
    notification-service)
      DEPLOY_DIR="/opt/rrhh/notification-service"; SERVICE="notification-service"; SERVICE_PORT="8082"
      # 401 = vivo y exige credenciales (un 202 sería un buzón abierto).
      SMOKE_PATH="/internal/notifications/login-code"; SMOKE_EXPECT="401"
      PROFILES="default docker prod" ;;
    *)
      echo "App desconocida: $1 (conocidas: $APPS)" >&2
      return 1 ;;
  esac
}

# docker compose sobre el stack de <carpeta>, se llame desde donde se llame.
compose_in() {
  local dir="$1"
  shift
  docker compose --project-directory "$dir" -f "$dir/docker-compose.prod.yml" "$@"
}

# ¿El servicio ya se desplegó alguna vez? (el contenedor existe, en cualquier estado)
is_deployed() {
  [ -f "$DEPLOY_DIR/docker-compose.prod.yml" ] \
    && [ -n "$(compose_in "$DEPLOY_DIR" ps -a -q "$SERVICE" 2>/dev/null)" ]
}

is_running() {
  [ -n "$(compose_in "$1" ps -q --status running "$2" 2>/dev/null)" ]
}
