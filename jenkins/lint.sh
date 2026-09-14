#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Chequeos estáticos del repo (no necesitan Docker ni el Config Server):
#
#  1. Todo .yml de la raíz es de una app conocida o global. Un nombre con un error
#     de tipeo (rrhh-bakend-prod.yml) no falla en ningún lado: el Config Server
#     simplemente no lo sirve nunca.
#  2. Ningún secreto en texto plano: toda clave de tipo password/secret/token lleva
#     un ${VARIABLE}, y ninguna URL tiene credenciales fuera de un ${...}.
# ─────────────────────────────────────────────────────────────────────────────
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

cd "$(dirname "${BASH_SOURCE[0]}")/.."
shopt -s nullglob

errors=0
apps_regex="$(tr ' ' '|' <<<"$APPS")"

for file in *.yml *.yaml; do
  if ! grep -qE "^(application|${apps_regex})(-[^.]+)?\.ya?ml$" <<<"$file"; then
    echo "✗ $file: no es de ninguna app conocida ($APPS) ni global (application*.yml)."
    errors=$((errors + 1))
  fi

  # Solo clases POSIX ([[:space:]]): el script también tiene que correr en Git Bash.
  bad="$(awk -v q="'" '
    {
      line = $0
      if (line ~ /^[[:space:]]*#/) next
      sub(/[[:space:]]+#.*$/, "", line)                     # comentario al final

      # URL con usuario:contraseña fuera de un ${...} (adentro es el default de dev).
      plain = line
      gsub(/\$\{[^}]*\}/, "", plain)
      if (plain ~ /:\/\/[^:\/@[:space:]]+:[^@\/[:space:]]+@/) { printf "  línea %d: %s\n", NR, $0; next }

      # Clave sensible con un valor que no arranca con ${.
      if (!match(line, /:[[:space:]]*/)) next
      key = tolower(substr(line, 1, RSTART - 1))
      value = substr(line, RSTART + RLENGTH)
      gsub("^[\"" q "]|[\"" q "]$", "", value)
      if (value == "" || value ~ /^\$\{/) next
      if (key ~ /(password|secret|token|credential|private-key|api-key)[[:space:]]*$/)
        printf "  línea %d: %s\n", NR, $0
    }' "$file")"
  if [ -n "$bad" ]; then
    echo "✗ $file: secreto en texto plano (tiene que ser \${VARIABLE}):"
    echo "$bad"
    errors=$((errors + 1))
  fi
done

if [ "$errors" -gt 0 ]; then
  echo "Lint: $errors problema(s)."
  exit 1
fi
echo "Lint: OK."
