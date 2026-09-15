#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  El Config Server de producción sirve la configuración de ESTE commit:
#
#    served.sh <commit> [--required]
#
#  Pide cada app × perfil con el commit como label (/<app>/<perfil>/<commit>) y
#  exige 200 y "version" = <commit>. Un YAML roto da error acá, ANTES de reiniciar
#  nada, y no en el arranque del servicio. Como el label es el commit, un push que
#  llegue mientras corre el pipeline no cambia lo que se valida.
#
#  La consulta corre DENTRO del contenedor del Config Server, con sus propias
#  credenciales: no pasan por Jenkins ni por los logs.
#
#  Sin Config Server corriendo: con --required falla (hay servicios para reiniciar
#  y sin él no arrancarían); si no, avisa y sigue.
# ─────────────────────────────────────────────────────────────────────────────
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

commit="$1"
required="${2:-}"

if [ ! -f "$CONFIG_SERVER_DIR/docker-compose.prod.yml" ] || ! is_running "$CONFIG_SERVER_DIR" config-server; then
  if [ "$required" = "--required" ]; then
    echo "✗ config-server no está corriendo ($CONFIG_SERVER_DIR): los servicios no podrían leer su configuración."
    exit 1
  fi
  echo "⚠ config-server no está corriendo: se omite la validación contra el servidor."
  exit 0
fi

# Status HTTP + version, calculados adentro del contenedor (wget de busybox: -S manda
# los headers a stderr y sale con error ante un 4xx/5xx; por eso los "|| true").
fetch() {
  compose_in "$CONFIG_SERVER_DIR" exec -T config-server sh -c '
    auth="$(printf "%s:%s" "$CONFIG_SERVER_USERNAME" "$CONFIG_SERVER_PASSWORD" | base64 | tr -d "\n")"
    out="$(wget -S -q -O - --header "Authorization: Basic $auth" "http://localhost:8888$1" 2>&1 || true)"
    status="$(printf "%s\n" "$out" | awk "/HTTP\\//{ print \$2; exit }")"
    version="$(printf "%s" "$out" | grep -o "\"version\":\"[0-9a-f]*\"" | head -n 1 | cut -d\" -f4 || true)"
    echo "$status $version"
  ' sh "$1" || true
}

errors=0
for app in $APPS; do
  service_info "$app"
  for profile in $PROFILES; do
    read -r status version <<<"$(fetch "/$app/$profile/$commit")"
    if [ "$status" = "200" ] && [ "$version" = "$commit" ]; then
      echo "✓ $app/$profile"
    else
      echo "✗ $app/$profile → HTTP ${status:-sin respuesta}, version ${version:-ninguna} (esperada $commit)"
      errors=$((errors + 1))
    fi
  done
done

if [ "$errors" -gt 0 ]; then
  echo "config-server no pudo servir $errors combinación(es). Logs: docker logs config-server"
  exit 1
fi
