#!/usr/bin/env bash
# Comprueba que el Info.plist de la app compilada tiene las descripciones de privacidad que
# exigen las peticiones de permiso de EventKit que hace el código, y ninguna sobrante.
#
# Uso: scripts/check-privacy-keys.sh <ruta a RememberMe.app> [directorio de fuentes]
#
# Reglas (iOS 17+, TN3152 de Apple):
#   requestFullAccessToEvents      -> NSCalendarsFullAccessUsageDescription
#   requestWriteOnlyAccessToEvents -> NSCalendarsWriteOnlyAccessUsageDescription
#   requestFullAccessToReminders   -> NSRemindersFullAccessUsageDescription
# Con iOS 17 como versión mínima no deben aparecer NSCalendarsUsageDescription ni
# NSRemindersUsageDescription.
set -euo pipefail

app="${1:?Indica la ruta de RememberMe.app}"
sources="${2:-RememberMe}"
plist="$app/Info.plist"

if [[ ! -f "$plist" ]]; then
  echo "::error title=Privacidad::No existe $plist"
  exit 1
fi

failures=0

has_key() {
  plutil -extract "$1" raw -o - "$plist" >/dev/null 2>&1
}

uses_api() {
  grep -rq --include='*.swift' "$1" "$sources"
}

check_pair() {
  local api="$1" key="$2"
  if uses_api "$api"; then
    if has_key "$key"; then
      local text
      text="$(plutil -extract "$key" raw -o - "$plist")"
      if [[ -z "${text// }" ]]; then
        echo "::error title=Privacidad::$key está vacía"
        failures=$((failures + 1))
      else
        echo "OK  $api -> $key: $text"
      fi
    else
      echo "::error title=Privacidad::El código usa $api pero falta $key en el Info.plist"
      failures=$((failures + 1))
    fi
  elif has_key "$key"; then
    echo "::error title=Privacidad::$key está en el Info.plist pero el código no usa $api"
    failures=$((failures + 1))
  else
    echo "OK  sin $api ni $key"
  fi
}

check_pair requestFullAccessToEvents NSCalendarsFullAccessUsageDescription
check_pair requestWriteOnlyAccessToEvents NSCalendarsWriteOnlyAccessUsageDescription
check_pair requestFullAccessToReminders NSRemindersFullAccessUsageDescription

for legacy in NSCalendarsUsageDescription NSRemindersUsageDescription; do
  if has_key "$legacy"; then
    echo "::error title=Privacidad::$legacy es de iOS 16 o anterior y la versión mínima es iOS 17"
    failures=$((failures + 1))
  fi
done

if uses_api 'requestAccess(to:'; then
  echo "::error title=Privacidad::requestAccess(to:) está obsoleto en iOS 17 y no muestra la petición"
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  exit 1
fi

keys="$(plutil -convert json -o - "$plist" | python3 -c 'import json,sys; print(", ".join(k for k in sorted(json.load(sys.stdin)) if k.endswith("UsageDescription")))')"
echo "::notice title=Privacidad::Info.plist compilado con: ${keys}"
