#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Prueba de humo de <app>, DENTRO de su contenedor (los mismos chequeos que el
#  job del servicio en bull-code-system-backend):
#
#    smoke-test.sh <app>
#
#    GET /actuator/health/readiness → 200
#    GET $SMOKE_PATH                → $SMOKE_EXPECT (ver service_info en common.sh)
# ─────────────────────────────────────────────────────────────────────────────
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

app="$1"
service_info "$app"

if ! is_deployed; then
  echo "– $app: todavía no está desplegado, sin smoke test."
  exit 0
fi

# Código HTTP de una ruta. wget de busybox imprime los headers con -S y sale con
# error ante un 4xx: por eso el "|| true" adentro y afuera.
check() {
  compose_in "$DEPLOY_DIR" exec -T "$SERVICE" sh -c \
    "wget -S -q -O /dev/null http://localhost:$SERVICE_PORT$1 2>&1 || true" \
    | awk '/HTTP\//{ print $2; exit }' || true
}

for attempt in $(seq 1 12); do
  ready="$(check /actuator/health/readiness)"
  probe="$(check "$SMOKE_PATH")"
  echo "$app, intento $attempt: readiness → $ready (esperado 200) | GET $SMOKE_PATH → $probe (esperado $SMOKE_EXPECT)"
  if [ "$ready" = "200" ] && [ "$probe" = "$SMOKE_EXPECT" ]; then
    exit 0
  fi
  sleep 5
done

exit 1
