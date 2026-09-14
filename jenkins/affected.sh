#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  ¿A qué servicios les cambió la configuración?
#
#    affected.sh <commit-nuevo> <commit-base>...
#
#  Imprime por stdout las apps a reiniciar, en el orden de APPS (vacío = ninguna).
#  Se une el diff contra cada base: el Jenkinsfile pasa el último build exitoso Y el
#  último build a secas. Así, si un push rompió un servicio y el siguiente lo revierte,
#  el revert igual lo reinicia (contra el último exitoso, el diff neto sería vacío).
#
#    application.yml / application-*.yml   → todas (lo recibe cada servicio)
#    <app>.yml / <app>-*.yml               → esa app
#    el resto (docs, jenkins/, Jenkinsfile) → ninguna
# ─────────────────────────────────────────────────────────────────────────────
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

head="$1"
shift

files=""
for base in "$@"; do
  if [ -z "$base" ] || ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
    continue
  fi
  files+="$(git diff --name-only "$base" "$head")"$'\n'
done

if [ -z "${files//$'\n'/}" ]; then
  echo "Sin cambios respecto de los builds anteriores (o no hay ninguno registrado)." >&2
  exit 0
fi

echo "Archivos cambiados:" >&2
sort -u <<<"$files" | sed '/^$/d; s/^/  /' >&2

affected=""
for app in $APPS; do
  if grep -qE "^(application(-[^/]*)?|${app}(-[^/]*)?)\.ya?ml$" <<<"$files"; then
    affected+="$app "
  fi
done

echo "${affected% }"
