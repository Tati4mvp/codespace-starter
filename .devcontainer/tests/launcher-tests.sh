#!/usr/bin/env bash
#
# launcher-tests.sh — CI tests for the launcher scripts (welcome.sh and the
# connect-repo wrapper). Run INSIDE the student image (see
# .github/workflows/launcher-tests.yml), where welcome.sh's $HOME side
# effects (wrapper install, .bashrc prompt append, user-settings write) land
# in a throwaway container home.
#
# Also runnable locally — but ONLY with a sandbox HOME, or it will edit your
# real ~/.bashrc:   HOME=$(mktemp -d) bash .devcontainer/tests/launcher-tests.sh
#
# Scope: everything testable without a GitHub login. connect-repo's real work
# (gh auth, repo creation) is deliberately out of scope — that stays a manual
# check in a live Codespace.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # .devcontainer
fails=0
fail() { echo "FAIL: $*" >&2; fails=$((fails + 1)); }
ok()   { echo "  ok: $*"; }

# ---- welcome.sh with no marker: banner + wrapper ------------------------
rm -f "$HOME/.student_repo"
if ! out="$(bash "$here/welcome.sh")"; then
  fail "welcome.sh exited non-zero"
fi

if grep -q "YOUR CODESPACE IS READY" <<<"$out"; then
  ok "banner shows READY"
else
  fail "banner missing 'YOUR CODESPACE IS READY'"
fi

if grep -q "connect-repo <insert-repo-name>" <<<"$out"; then
  ok "banner shows the short command"
else
  fail "banner missing 'connect-repo <insert-repo-name>'"
fi

# Retired lines must stay retired (redesign, 2026-08-15).
if grep -q "STUDENT_WORKFLOW" <<<"$out"; then
  fail "banner links the guide again (removed in redesign)"
else
  ok "banner has no guide link"
fi
if grep -q "remove this banner" <<<"$out"; then
  fail "banner mentions 'clear' again (removed in redesign)"
else
  ok "banner has no clear-hint"
fi

# ---- wrapper ------------------------------------------------------------
wrapper="$HOME/.local/bin/connect-repo"
if [[ -x "$wrapper" ]]; then
  ok "wrapper installed and executable"
else
  fail "wrapper missing or not executable at $wrapper"
fi

# From a foreign directory: args must forward, and the real script must still
# self-locate (this is why it's an exec wrapper, not a symlink — see welcome.sh).
if (cd /tmp && "$wrapper" --help | grep -q "connect-repo — create or connect"); then
  ok "wrapper --help works from a foreign directory"
else
  fail "wrapper --help failed from a foreign directory"
fi

# No-argument path: exit 2 with the short-form usage text.
rc=0
usage_out="$(cd /tmp && "$wrapper" 2>&1)" || rc=$?
if [[ "$rc" -eq 2 ]]; then
  ok "no-arg run exits 2"
else
  fail "no-arg run exited $rc, expected 2"
fi
if grep -q "Usage: connect-repo " <<<"$usage_out"; then
  ok "usage text uses the short name"
else
  fail "usage text is not short-form: $usage_out"
fi

# ---- welcome.sh with marker: silent, and idempotent on re-run -----------
touch "$HOME/.student_repo"
out2="$(bash "$here/welcome.sh")"
if grep -q "YOUR CODESPACE IS READY" <<<"$out2"; then
  fail "banner shown even though the student-repo marker exists"
else
  ok "banner silent once marker exists"
fi
rm -f "$HOME/.student_repo"

# Re-running must not stack prompt blocks in .bashrc (sentinel idempotency).
n="$(grep -cF 'codespace-starter:short-prompt' "$HOME/.bashrc" 2>/dev/null || true)"
if [[ "$n" -le 1 ]]; then
  ok "prompt block appended at most once (count: $n)"
else
  fail "prompt block duplicated in .bashrc (count: $n)"
fi

# ---- verdict ------------------------------------------------------------
if [[ "$fails" -gt 0 ]]; then
  echo "LAUNCHER TESTS: $fails failure(s)" >&2
  exit 1
fi
echo "LAUNCHER TESTS: all passed"
