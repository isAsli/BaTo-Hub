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
#   6. inline python programs, which the shell can silently alter
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
  panel_available_versions panel_install_version
  panel_ssl_issue panel_ssl_renew panel_ssl_status panel_ssl_remove
  panel_template_apply panel_template_remove panel_template_status
  panel_update panel_logs panel_menu
)

# Metadata every panel must declare for version selection.
PANEL_VERSION_FIELDS=(source_repo supports_version_pinning version_pin_scope dev_channel_argument)

TOOL_FUNCTIONS=(
  tool_detect tool_version tool_status tool_install tool_update tool_logs
  tool_configure tool_uninstall tool_menu
)

# Metadata every tool must declare, including whether its source supports a
# version pin and which command owns the installation after the fact.
TOOL_FIELDS=(source_repo supports_version_pinning version_pin_scope dev_channel_argument)

PANEL_FILES=(panel.json module.sh ssl/module.sh templates/module.sh update/module.sh menu/module.sh)

# Every section the release documents has to be both defined and reachable from
# the hub menu, so a section cannot be documented while the interface has no way
# to open it.
FEATURE_SECTIONS=(
  nodes_menu ssl_menu_multi backup_delivery_menu migration_menu server_tools_menu
  container_menu alerts_menu reports_menu bot_menu admins_menu
)

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
  for field in "${PANEL_VERSION_FIELDS[@]}"; do
    python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); sys.exit(0 if sys.argv[2] in data else 1)' \
      "${panel_dir}panel.json" "$field" ||
      fail "panel ${panel} does not declare ${field} in panel.json"
  done
  pinning="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["supports_version_pinning"])' "${panel_dir}panel.json")"
  [[ "$pinning" == "True" || "$pinning" == "False" ]] ||
    fail "panel ${panel} declares supports_version_pinning as ${pinning}, which is not a boolean"
done

for tool_dir in tools/*/; do
  tool="$(basename "$tool_dir")"
  [[ -r "${tool_dir}tool.json" ]] || fail "tool ${tool} is missing tool.json"
  [[ -r "${tool_dir}module.sh" ]] || fail "tool ${tool} is missing module.sh"
  [[ -r "${tool_dir}install/module.sh" ]] || fail "tool ${tool} is missing install/module.sh"
  [[ -r "${tool_dir}menu/module.sh" ]] || fail "tool ${tool} is missing menu/module.sh"
  for fn in "${TOOL_FUNCTIONS[@]}"; do
    grep -qE "^[[:space:]]*${fn}[[:space:]]*\(\)" "${tool_dir}module.sh" || fail "tool ${tool} does not define ${fn}"
  done
  declared_name="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "${tool_dir}tool.json")"
  [[ "$declared_name" == "$tool" ]] || fail "tool ${tool} declares the name ${declared_name}"
  for field in "${TOOL_FIELDS[@]}"; do
    python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); sys.exit(0 if sys.argv[2] in data else 1)' \
      "${tool_dir}tool.json" "$field" ||
      fail "tool ${tool} does not declare ${field} in tool.json"
  done
  pinning="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["supports_version_pinning"])' "${tool_dir}tool.json")"
  [[ "$pinning" == "True" || "$pinning" == "False" ]] ||
    fail "tool ${tool} declares supports_version_pinning as ${pinning}, which is not a boolean"
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

step "release manifest"
# The checked in manifest must describe the files of this tree exactly, so a
# stale entry cannot survive into a release. The same code path builds the
# manifest for a release.
if bash scripts/build-release.sh --verify-manifest; then
  pass "manifest.json matches the working tree"
else
  fail "manifest.json does not match the working tree"
fi

step "release body generator"
# The release body must list only the assets that are attached: the signature is
# mentioned when a signing key produced one, and never otherwise.
if body_signed="$(bash scripts/release-body.sh --signed yes)" &&
  body_unsigned="$(bash scripts/release-body.sh --signed no)"; then
  case "$body_signed" in
  *manifest.json.asc*) pass "the signed release body lists the signature" ;;
  *) fail "the signed release body does not list manifest.json.asc" ;;
  esac
  case "$body_unsigned" in
  *manifest.json.asc*) fail "the unsigned release body advertises a signature that is not attached" ;;
  *) pass "the unsigned release body does not advertise a signature" ;;
  esac
else
  fail "scripts/release-body.sh did not produce a release body"
fi

step "git history"
# No commit in the history may carry a co-author trailer or a line that names a
# development tool. Only branches and tags are read, so a stale remote-tracking
# ref from before a rewrite cannot fail the check. A shallow clone cannot see
# the history, so it is reported instead of being treated as a pass.
if [[ -d .git && ! -f .git/shallow ]]; then
  if history_hits="$(git log --branches --tags --format='%B' | grep -inE 'co-authored-by|signed-off-by|assisted by|generated with|generated by|codebuff|openai|anthropic|chatgpt|copilot|claude|gemini|windsurf|deepseek')"; then
    fail "the git history contains a trailer or a tool reference"
    printf '%s\n' "$history_hits" | head -n 20 | sed 's/^/     /' >&2
  else
    pass "no co-author trailer and no tool reference in the git history"
  fi
else
  printf 'the checkout is shallow, so the history check is skipped\n'
fi

step "documentation and hygiene"
required_docs=(
  README.md README.fa.md DOCS.md DOCS.fa.md SECURITY.md LICENSE
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

step "documentation structure"
# The English and Persian documents must stay in step: the same numbered
# sections in the same order, so a reader can cross reference one against the
# other. Either a missing section or a reordered one fails the check.
if doc_problems="$(python3 -c '
import os, re, sys


def sections(path):
    with open(path, encoding="utf-8") as handle:
        return [m.group(1) for m in (re.match(r"^##\s+(\d+)\.", line) for line in handle) if m]


root = sys.argv[1]
problems = []
for english, persian in (("README.md", "README.fa.md"), ("DOCS.md", "DOCS.fa.md")):
    en = sections(os.path.join(root, english))
    fa = sections(os.path.join(root, persian))
    if not en:
        problems.append(f"{english} has no numbered sections")
    elif en != fa:
        problems.append(f"{english} sections {en} do not match {persian} sections {fa}")
sys.stdout.write("; ".join(problems))
sys.exit(1 if problems else 0)
' "$ROOT" 2>&1)"; then
  pass "English and Persian documents share the same section numbers"
else
  fail "documentation sections do not match: ${doc_problems}"
fi

step "feature sections"
for function_name in "${FEATURE_SECTIONS[@]}"; do
  if grep -rqE "^${function_name}\\(\\)" core lib; then
    :
  else
    fail "no section defines ${function_name}"
  fi
  if grep -q "\\b${function_name}\\b" core/hub_menu.sh; then
    :
  else
    fail "${function_name} is not reachable from the hub menu"
  fi
done
[[ "$FAILURES" -eq 0 ]] && pass "every documented section is defined and reachable"

step "documentation coverage"
if python3 - "$ROOT" <<'PY'; then
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
docs = (root / "DOCS.md").read_text(encoding="utf-8")
fa = (root / "DOCS.fa.md").read_text(encoding="utf-8")

alerts = (root / "lib/alert_helpers.sh").read_text(encoding="utf-8")
alert_block = re.search(r"ALERT_TYPES=\((.*?)\)", alerts, re.S)
alert_names = [line.strip() for line in alert_block.group(1).splitlines() if line.strip()]

admins = (root / "lib/admin_helpers.sh").read_text(encoding="utf-8")
permission_block = re.search(r"ADMIN_PERMISSIONS=\((.*?)\)", admins, re.S)
permissions = [line.strip() for line in permission_block.group(1).splitlines() if line.strip()]

reports = (root / "lib/report_helpers.sh").read_text(encoding="utf-8")
report_body = re.search(r"report_names\(\) \{(.*?)\n\}", reports, re.S).group(1)
report_names = [
    token for token in re.findall(r"[a-z][a-z_]{2,}", report_body) if token not in {"printf", "return"}
]

problems = []
for label, names in (("alert", alert_names), ("permission", permissions), ("report", report_names)):
    for name in names:
        if name not in docs:
            problems.append("%s %s is not described in DOCS.md" % (label, name))
        elif name not in fa:
            problems.append("%s %s is not described in DOCS.fa.md" % (label, name))
for item in problems:
    print("FAIL [documentation] %s" % item)
print("ok   %d alert(s), %d permission(s) and %d report(s) are documented" % (len(alert_names), len(permissions), len(report_names)))
sys.exit(1 if problems else 0)
PY
  :
else
  FAILURES=$((FAILURES + 1))
fi

step "inline python programs"
if python3 scripts/checks_inline.py "$ROOT"; then
  pass "every inline python program is intact"
else
  FAILURES=$((FAILURES + 1))
fi

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
