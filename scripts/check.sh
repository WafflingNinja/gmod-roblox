#!/usr/bin/env bash
# One pass/fail gate: format, lint, types, logic tests. Run from anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."

DEFS="${LUAU_GLOBAL_TYPES:-$HOME/.claude/luau/globalTypes.d.luau}"

echo "== stylua =="
stylua --check src tests

echo "== selene =="
[ -f roblox.yml ] || selene generate-roblox-std
selene src

echo "== luau-lsp (strict types) =="
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --definitions="$DEFS" --sourcemap=sourcemap.json src

echo "== lune tests =="
for t in tests/*.spec.luau; do
	echo "-- $t"
	lune run "$t"
done

echo "ALL CHECKS PASSED"
