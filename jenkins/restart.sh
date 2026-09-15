#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Reinicia <app> para que relea su configuración del Config Server:
#
#    restart.sh <app>
#
#  Recrea el contenedor con la MISMA imagen (:prod) y espera "healthy":
#    --no-deps   no toca dependencias (PostgreSQL es otro stack y no se toca)
#    --no-build  jamás buildea: las imágenes son de los jobs del backend
#  Recrear (y no "docker restart") también aplica lo que haya cambiado en el .env
#  del stack, igual que un deploy del servicio.
#
#  Mientras reinicia, el servicio no atiende (una sola instancia).
# ─────────────────────────────────────────────────────────────────────────────
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

app="$1"
service_info "$app"

if ! is_deployed; then
  echo "– $app: todavía no está desplegado, no hay nada que reiniciar."
  exit 0
fi

echo "Reiniciando $app ($SERVICE en $DEPLOY_DIR)…"
compose_in "$DEPLOY_DIR" up -d --no-deps --no-build --force-recreate --wait --wait-timeout 300 "$SERVICE"
