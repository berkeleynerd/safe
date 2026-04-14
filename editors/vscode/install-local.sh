#!/bin/sh
set -eu

SCRIPT_DIR=$(
  CDPATH= cd -- "$(dirname "$0")" && pwd
)
PACKAGE_JSON="$SCRIPT_DIR/package.json"
EXTENSIONS_DIR="${HOME}/.vscode/extensions"

metadata=$(
  python3 - "$PACKAGE_JSON" <<'PY'
import json
import sys
from pathlib import Path

package_path = Path(sys.argv[1])
payload = json.loads(package_path.read_text(encoding="utf-8"))
publisher = payload["publisher"]
name = payload["name"]
version = payload["version"]
print(publisher)
print(name)
print(version)
PY
)

IFS='
'
set -- $metadata
unset IFS
publisher=$1
name=$2
version=$3
install_name="${publisher}.${name}-${version}"
install_path="${EXTENSIONS_DIR}/${install_name}"

case "$install_name" in
  ""|*/*)
    printf 'install-local: invalid extension install name: %s\n' "$install_name" >&2
    exit 1
    ;;
esac

case "$install_path" in
  "$EXTENSIONS_DIR"/*)
    ;;
  *)
    printf 'install-local: refusing to remove path outside VS Code extensions: %s\n' "$install_path" >&2
    exit 1
    ;;
esac

mkdir -p "$EXTENSIONS_DIR"

for candidate in "${EXTENSIONS_DIR}/${publisher}.${name}-"*; do
  if [ -L "$candidate" ]; then
    rm -f "$candidate"
  fi
done

if [ -e "$install_path" ]; then
  rm -rf "$install_path"
fi

ln -s "$SCRIPT_DIR" "$install_path"

printf 'Installed local VS Code extension symlink:\n'
printf '  %s -> %s\n' "$install_path" "$SCRIPT_DIR"
printf '\nReload VS Code to pick up the extension:\n'
printf '  Cmd+Shift+P -> "Reload Window"\n'
