#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
readonly REPO_ROOT
readonly MANAGER="$REPO_ROOT/manage-skill.sh"
TEST_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_no_path() {
  [[ ! -e "$1" && ! -L "$1" ]] || fail "unexpected path: $1"
}

run_manager() {
  HOME="$TEST_DIR/home" CODEX_HOME="$TEST_DIR/codex" bash "$MANAGER" "$@"
}

test_codex_lifecycle() {
  local target="$TEST_DIR/codex/skills/mermaid-skill"
  run_manager install >/dev/null
  assert_file "$target/SKILL.md"
  assert_file "$target/.managed-by-robertonetresults-mermaid-skill"
  [[ -x "$target/scripts/render-mermaid.sh" ]] || fail "render helper lost executable permission"

  printf 'tampered\n' > "$target/SKILL.md"
  run_manager update >/dev/null
  LC_ALL=C grep -Fq '# Mermaid Diagrams' "$target/SKILL.md" || fail "update did not refresh the installed skill"

  run_manager uninstall >/dev/null
  assert_no_path "$target"
}

test_cross_agent_targets() {
  local agents_target="$TEST_DIR/home/.agents/skills/mermaid-skill"
  local project="$TEST_DIR/project"
  local custom="$TEST_DIR/custom skills"
  mkdir -p "$project"

  run_manager install --agents >/dev/null
  assert_file "$agents_target/SKILL.md"
  run_manager uninstall --agents >/dev/null

  run_manager install --project "$project" >/dev/null
  assert_file "$project/.agents/skills/mermaid-skill/SKILL.md"
  run_manager uninstall --project "$project" >/dev/null

  run_manager install --destination "$custom" >/dev/null
  assert_file "$custom/mermaid-skill/SKILL.md"
  run_manager uninstall --destination "$custom" >/dev/null
}

test_unmanaged_target_is_preserved() {
  local target="$TEST_DIR/codex/skills/mermaid-skill"
  mkdir -p "$target"
  printf 'user data\n' > "$target/keep.txt"

  if run_manager install >/dev/null 2>&1; then
    fail "install accepted an existing unmanaged target"
  fi
  if run_manager update >/dev/null 2>&1; then
    fail "update accepted an unmanaged target"
  fi
  if run_manager uninstall >/dev/null 2>&1; then
    fail "uninstall accepted an unmanaged target"
  fi
  assert_file "$target/keep.txt"
  rm -rf -- "$TEST_DIR/codex"
}

test_pull_modes() {
  local bin="$TEST_DIR/fake-git/bin" log="$TEST_DIR/fake-git/log"
  mkdir -p "$bin"
  cat > "$bin/git" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_GIT_LOG"
if [[ "$*" == *"diff --quiet"* && "${TEST_GIT_DIRTY:-0}" == 1 ]]; then
  exit 1
fi
if [[ "$*" == *"pull --ff-only"* && "${TEST_GIT_PULL_FAIL:-0}" == 1 ]]; then
  exit 1
fi
exit 0
STUB
  chmod +x "$bin/git"

  run_manager install >/dev/null
  TEST_GIT_LOG="$log" PATH="$bin:$PATH" HOME="$TEST_DIR/home" CODEX_HOME="$TEST_DIR/codex" \
    bash "$MANAGER" update --pull >/dev/null
  LC_ALL=C grep -Fq 'pull --ff-only' "$log" || fail "update --pull did not invoke a fast-forward-only pull"

  if TEST_GIT_DIRTY=1 TEST_GIT_LOG="$log" PATH="$bin:$PATH" HOME="$TEST_DIR/home" CODEX_HOME="$TEST_DIR/codex" \
    bash "$MANAGER" update --pull >/dev/null 2>&1; then
    fail "update --pull accepted a dirty checkout"
  fi
  if TEST_GIT_PULL_FAIL=1 TEST_GIT_LOG="$log" PATH="$bin:$PATH" HOME="$TEST_DIR/home" CODEX_HOME="$TEST_DIR/codex" \
    bash "$MANAGER" update --pull >/dev/null 2>&1; then
    fail "update --pull ignored a pull failure"
  fi
  assert_file "$TEST_DIR/codex/skills/mermaid-skill/SKILL.md"
  run_manager uninstall >/dev/null
}

test_update_rollback() {
  local bin="$TEST_DIR/fake-mv/bin" real_mv log="$TEST_DIR/fake-mv/log"
  mkdir -p "$bin"
  real_mv=$(command -v mv)
  cat > "$bin/mv" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_MV_LOG"
arguments=" $* "
if [[ "$arguments" == *".mermaid-skill.stage."* && "$arguments" == *"/mermaid-skill "* ]]; then
  exit 1
fi
exec "$TEST_REAL_MV" "$@"
STUB
  chmod +x "$bin/mv"

  run_manager install >/dev/null
  printf 'previous installation\n' > "$TEST_DIR/codex/skills/mermaid-skill/sentinel.txt"
  if TEST_MV_LOG="$log" TEST_REAL_MV="$real_mv" PATH="$bin:$PATH" HOME="$TEST_DIR/home" CODEX_HOME="$TEST_DIR/codex" \
    bash "$MANAGER" update >/dev/null 2>&1; then
    fail "simulated replacement failure unexpectedly succeeded"
  fi
  assert_file "$TEST_DIR/codex/skills/mermaid-skill/sentinel.txt"
  run_manager uninstall >/dev/null
}

test_codex_lifecycle
test_cross_agent_targets
test_unmanaged_target_is_preserved
test_pull_modes
test_update_rollback
printf 'All manage-skill tests passed.\n'
