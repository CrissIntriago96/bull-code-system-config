#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Cada ${VARIABLE} sin default que <app> usa en prod existe en su contenedor:
#
#    env-check.sh <app>
#
#  En prod, un ${VAR} sin default que no está definido hace que el servicio NO
#  arranque. Una variable nueva va al .env del servicio Y a su docker-compose.prod.yml
#  (en bull-code-system-backend, y se aplica con el deploy de ese servicio): Compose
#  le pasa al contenedor solo las variables que declara, no el .env entero.
#
#  Mira el contenedor que corre hoy. Si está caído, no se puede verificar: avisa
#  y sigue (puede ser justamente el servicio que este push viene a arreglar).
# ─────────────────────────────────────────────────────────────────────────────
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

app="$1"
service_info "$app"
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! is_deployed; then
  echo "– $app: todavía no está desplegado (toma su configuración en el primer deploy)."
  exit 0
fi
if ! is_running "$DEPLOY_DIR" "$SERVICE"; then
  echo "⚠ $app: el contenedor no está corriendo, no se pueden verificar sus variables."
  exit 0
fi

# Lo que el servicio carga en prod. En los archivos base todo placeholder lleva
# default (convención del repo), así que de ahí no sale ninguna.
files=""
for file in application.yml application-prod.yml "$app.yml" "$app-prod.yml"; do
  [ -f "$file" ] && files+="$file "
done
# shellcheck disable=SC2086  # la lista de archivos se separa a propósito
vars="$(grep -ohE '\$\{[A-Z][A-Z0-9_]*\}' $files | tr -d '${}' | sort -u || true)"

if [ -z "$vars" ]; then
  echo "✓ $app: no usa variables sin default."
  exit 0
fi

# printenv sale con error si la variable no está definida (vacía cuenta como definida:
# Spring la resuelve a "" sin fallar). Solo se imprimen NOMBRES, nunca valores.
# shellcheck disable=SC2086
missing="$(compose_in "$DEPLOY_DIR" exec -T "$SERVICE" sh -c \
  'for v; do printenv "$v" >/dev/null || echo "$v"; done' sh $vars)"

if [ -n "$missing" ]; then
  echo "✗ $app: faltan en el contenedor: $(tr '\n' ' ' <<<"$missing")"
  echo "  Agregalas a $DEPLOY_DIR/.env y al docker-compose.prod.yml del servicio, y desplegalo."
  exit 1
fi
echo "✓ $app: $(wc -l <<<"$vars" | tr -d ' ') variable(s) presentes."
