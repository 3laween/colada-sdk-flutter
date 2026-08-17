#!/usr/bin/env bash
#
# check-no-private-refs.sh
#
# CI gate: fail the build if any internal-only reference has been pasted into
# this repo, which goes public. This is the mechanical answer to "did an
# internal doc or private-repo coordinate get committed by mistake?"
#
# Scans only files that could actually be committed: everything git tracks plus
# untracked files that are NOT gitignored. This deliberately skips build output
# and vendored dependencies (example/ios/Pods, build/, .dart_tool) — a
# downloaded native binary that embeds an internal path in its debug metadata is
# not our leak, and none of it is ever committed.
#
# Two paths are excluded even though they can be committed:
#   1. docs/COLADA_SDK_FLUTTER_PLAN.md — the internal plan, the ONE named path
#      allowed to contain these strings (it trips every pattern by design).
#      Hard-coded as a single named path, never a directory glob, because docs/
#      is also where public integrator documentation lives.
#   2. this script itself — it necessarily contains every pattern (it searches
#      for them); a grep cannot scan itself for its own needles.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Strings that must never appear in the public repo.
PATTERNS=(
  'colada-sdk-android-core'
  'colada-sdk-ios-core'
  'colada_backend'
  'colada_user_app'
  'ANDROID_SDK_STATUS'
  'AGENT_HANDOFF'
  'filter-repo'
)

JOINED="$(IFS='|'; echo "${PATTERNS[*]}")"

files="$(git ls-files --cached --others --exclude-standard \
  | grep -vE '^(docs/COLADA_SDK_FLUTTER_PLAN\.md|tool/check-no-private-refs\.sh)$' \
  || true)"

hits=""
if [ -n "$files" ]; then
  hits="$(printf '%s\n' "$files" | tr '\n' '\0' \
    | xargs -0 grep -InHE "$JOINED" 2>/dev/null || true)"
fi

if [ -n "$hits" ]; then
  echo "❌ check-no-private-refs: forbidden internal reference(s) found:"
  echo "$hits"
  echo
  echo "These strings must not appear in the public repo. If this is the internal"
  echo "plan document, it must live outside this repo (see Phase 17), not be"
  echo "committed and later removed — git history is forever."
  exit 1
fi

echo "✅ check-no-private-refs: clean (no internal references found)."
