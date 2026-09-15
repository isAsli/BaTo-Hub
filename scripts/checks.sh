#!/usr/bin/env bash
set -Eeuo pipefail

# Repository checks.
#
# Runs the same validations locally and in CI:
#   1. bash -n on every shell file
#   2. shellcheck and shfmt when they are installed
#   3. JSON validity for every metadata file
#   4. panel and tool interface checks
#   5. documentation, hygiene and wording checks
#
# Exits non-zero if any check fails.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FAILURES=0
CURRENT_STEP=""

step() {
  CURRENT_STEP="$1"
  printf '\n== %s\n' "$CURRENT_STEP"
}

fail() {
  printf 'FAIL [%s] %s\n' "$CURRENT_STEP" "$1" >&2
  FAILURES=$((FAILURES + 1))
}

pass() {
  printf 'ok   %s\n' "$1"
}

shell_files() {
  find . -type f \( -name '*.sh' -o -name 'batohub' -o -name 'uninstall' \) \
    -not -path './.git/*' | sort
}

PANEL_FUNCTIONS=(
  panel_detect panel_version panel_status panel_install panel_uninstall
  panel_ssl_issue panel_ssl_renew panel_ssl_status panel_ssl_remove
  panel_template_apply panel_template_remove panel_template_status
  panel_update panel_logs panel_menu
)

TOOL_FUNCTIONS=(
  tool_detect tool_version tool_status tool_install tool_uninstall tool_menu
)

PANEL_FILES=(panel.json module.sh ssl/module.sh templates/module.sh update/module.sh menu/module.sh)

step "shell syntax"
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  if bash -n "$file" 2>/tmp/batohub-syntax.$$; then
    :
  else
    fail "syntax error in $file"
    sed 's/^/     /' /tmp/batohub-syntax.$$ >&2
  fi
done < <(shell_files)
rm -f "/tmp/batohub-syntax.$$"
[[ "$FAILURES" -eq 0 ]] && pass "bash -n on every shell file"

step "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if shellcheck --severity=warning "$file"; then
      :
    else
      fail "shellcheck reported problems in $file"
    fi
  done < <(shell_files)
  pass "shellcheck completed"
else
  printf 'shellcheck is not installed; this check is skipped locally\n'
fi

step "shell formatting"
if command -v shfmt >/dev/null 2>&1; then
  if shfmt --diff --indent 2 . >/tmp/batohub-shfmt.$$ 2>&1; then
    pass "shfmt reports no differences"
  else
    fail "shfmt reports formatting differences"
    head -n 60 /tmp/batohub-shfmt.$$ >&2
  fi
  rm -f "/tmp/batohub-shfmt.$$"
else
  printf 'shfmt is not installed; this check is skipped locally\n'
fi

step "metadata files"
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  if python3 -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$file"; then
    :
  else
    fail "invalid JSON: $file"
  fi
done < <(find . -type f -name '*.json' -not -path './.git/*' -not -path './node_modules/*' | sort)
pass "JSON metadata parsed"

step "panel and tool interface"
for panel_dir in panels/*/; do
  panel="$(basename "$panel_dir")"
  for required in "${PANEL_FILES[@]}"; do
    [[ -r "${panel_dir}${required}" ]] || fail "panel ${panel} is missing ${required}"
  done
  [[ -r "${panel_dir}panel.json" ]] || continue
  module="${panel_dir}module.sh"
  [[ -r "$module" ]] || continue
  for fn in "${PANEL_FUNCTIONS[@]}"; do
    grep -qE "^[[:space:]]*${fn}[[:space:]]*\(\)" "$module" || fail "panel ${panel} does not define ${fn}"
  done
  declared_name="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "${panel_dir}panel.json")"
  [[ "$declared_name" == "$panel" ]] || fail "panel ${panel} declares the name ${declared_name}"
done

for tool_dir in tools/*/; do
  tool="$(basename "$tool_dir")"
  [[ -r "${tool_dir}tool.json" ]] || fail "tool ${tool} is missing tool.json"
  [[ -r "${tool_dir}module.sh" ]] || fail "tool ${tool} is missing module.sh"
  for fn in "${TOOL_FUNCTIONS[@]}"; do
    grep -qE "^[[:space:]]*${fn}[[:space:]]*\(\)" "${tool_dir}module.sh" || fail "tool ${tool} does not define ${fn}"
  done
done
pass "panel and tool interfaces checked"

step "interfaces load in a shell"
if PANEL_DIR="$ROOT/panels" TOOL_DIR="$ROOT/tools" BATOHUB_ROOT="$ROOT" \
  bash -c '
    set -Eeuo pipefail
    . "$BATOHUB_ROOT/lib/common.sh"
    . "$BATOHUB_ROOT/lib/panel_helpers.sh"
    . "$BATOHUB_ROOT/core/panel_loader.sh"
    for panel in $(loader_panels); do
      loader_load_panel "$panel" >/dev/null || { echo "failed to load panel: $panel"; exit 1; }
    done
    for tool in $(loader_tools); do
      tool_load "$tool" >/dev/null || { echo "failed to load tool: $tool"; exit 1; }
    done
    exit 0
  ' 2>/tmp/batohub-load.$$; then
  pass "every panel and tool loads"
else
  fail "a panel or tool failed to load"
  sed 's/^/     /' /tmp/batohub-load.$$ >&2
fi
rm -f "/tmp/batohub-load.$$"

step "version consistency"
version="$(tr -d '[:space:]' <VERSION)"
[[ "$version" == "$(python3 -c 'import json; print(json.load(open("manifest.json"))["version"])')" ]] ||
  fail "manifest.json version does not match VERSION"
[[ "$version" == "$(grep -E '^APP_VERSION=' config/batohub.conf | cut -d'"' -f2)" ]] ||
  fail "config/batohub.conf APP_VERSION does not match VERSION"
for metadata in panels/*/panel.json tools/*/tool.json; do
  declared="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$metadata")"
  [[ "$declared" == "$version" ]] || fail "${metadata} version ${declared} does not match VERSION ${version}"
done
pass "version ${version} is consistent"

step "documentation and hygiene"
required_docs=(
  README.md README.fa.md CHANGELOG.md LICENSE
  SECURITY.md SECURITY.fa.md CONTRIBUTING.md CONTRIBUTING.fa.md
  SUPPORT.md SUPPORT.fa.md CODE_OF_CONDUCT.md CODE_OF_CONDUCT.fa.md
)
for doc in "${required_docs[@]}"; do
  [[ -s "$doc" ]] || fail "documentation file is missing or empty: $doc"
done

if [[ ! -s LICENSE ]] || [[ "$(wc -l <LICENSE)" -lt 600 ]]; then
  fail "LICENSE does not contain the full GPL-3.0 text"
fi
if ! grep -q 'GNU GENERAL PUBLIC LICENSE' LICENSE || ! grep -q 'Version 3, 29 June 2007' LICENSE; then
  fail "LICENSE is not the GNU GPL version 3 text"
fi
pass "required documents present"

step "source hygiene"
if python3 scripts/checks_text.py "$ROOT"; then
  :
else
  FAILURES=$((FAILURES + 1))
fi

step "result"
if [[ "$FAILURES" -eq 0 ]]; then
  printf 'All checks passed.\n'
  exit 0
fi
printf '%s check(s) failed.\n' "$FAILURES" >&2
exit 1
