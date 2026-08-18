#!/usr/bin/env bash
set -euo pipefail

readonly REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
readonly RENDER="$REPO_ROOT/skills/mermaid-skill/scripts/render-mermaid.sh"
TEST_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_no_file() {
  [[ ! -e "$1" ]] || fail "unexpected file: $1"
}

assert_contains() {
  LC_ALL=C grep -Fq -- "$2" "$1" || fail "expected '$2' in $1"
}

make_source() {
  local path=$1
  printf 'flowchart LR\n  A --> B\n' > "$path"
}

test_local_precedence_and_export() {
  local case_dir="$TEST_DIR/local" bin="$TEST_DIR/local/bin" log="$TEST_DIR/local/log"
  mkdir -p "$case_dir" "$bin"
  make_source "$case_dir/diagram.mmd"

  cat > "$bin/mmdc" <<'STUB'
#!/usr/bin/env bash
printf 'mmdc %s\n' "$*" >> "$TEST_LOG"
while [[ $# -gt 0 ]]; do
  if [[ "$1" == -o ]]; then
    shift
    printf '<svg xmlns="http://www.w3.org/2000/svg"/>\n' > "$1"
    exit 0
  fi
  shift
done
exit 2
STUB
  cat > "$bin/docker" <<'STUB'
#!/usr/bin/env bash
printf 'docker called\n' >> "$TEST_LOG"
exit 99
STUB
  cat > "$bin/curl" <<'STUB'
#!/usr/bin/env bash
printf 'curl called\n' >> "$TEST_LOG"
exit 99
STUB
  chmod +x "$bin/mmdc" "$bin/docker" "$bin/curl"

  TEST_LOG="$log" PATH="$bin:$PATH" bash "$RENDER" validate "$case_dir/diagram.mmd" >/dev/null
  TEST_LOG="$log" PATH="$bin:$PATH" bash "$RENDER" export "$case_dir/diagram.mmd" "$case_dir/diagram.png" >/dev/null
  assert_file "$case_dir/diagram.png"
  assert_contains "$log" "mmdc"
  if LC_ALL=C grep -Eq 'docker called|curl called' "$log"; then
    fail "a fallback backend was called after local mmdc succeeded"
  fi
}

test_container_fallback_security_flags() {
  local case_dir="$TEST_DIR/container" bin="$TEST_DIR/container/bin" log="$TEST_DIR/container/log"
  mkdir -p "$case_dir" "$bin"
  make_source "$case_dir/diagram.mmd"

  cat > "$bin/docker" <<'STUB'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >> "$TEST_LOG"
if [[ "$1 $2" == "image inspect" ]]; then
  exit 0
fi
output_dir=
output_name=
previous=
for argument in "$@"; do
  case "$argument" in
    type=bind,src=*,dst=/output)
      output_dir=${argument#type=bind,src=}
      output_dir=${output_dir%,dst=/output}
      ;;
  esac
  if [[ "$previous" == -o ]]; then
    output_name=${argument##*/}
  fi
  previous=$argument
done
[[ -n "$output_dir" && -n "$output_name" ]] || exit 3
printf '<svg xmlns="http://www.w3.org/2000/svg"/>\n' > "$output_dir/$output_name"
STUB
  chmod +x "$bin/docker"

  TEST_LOG="$log" PATH="$bin:$PATH" MERMAID_CONTAINER_RUNTIME=docker \
    bash "$RENDER" validate "$case_dir/diagram.mmd" >/dev/null
  assert_contains "$log" "--pull=never"
  assert_contains "$log" "--network=none"
  assert_contains "$log" "minlag/mermaid-cli:latest"
}

test_kroki_loopback_and_pdf_rejection() {
  local case_dir="$TEST_DIR/kroki" bin="$TEST_DIR/kroki/bin" log="$TEST_DIR/kroki/log"
  mkdir -p "$case_dir" "$bin"
  make_source "$case_dir/diagram.mmd"

  cat > "$bin/docker" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  cat > "$bin/curl" <<'STUB'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$TEST_LOG"
previous=
for argument in "$@"; do
  if [[ "$previous" == -o ]]; then
    printf '<svg xmlns="http://www.w3.org/2000/svg"/>\n' > "$argument"
  fi
  previous=$argument
done
STUB
  chmod +x "$bin/docker" "$bin/curl"

  TEST_LOG="$log" PATH="$bin:$PATH" MERMAID_CONTAINER_RUNTIME=docker \
    bash "$RENDER" validate "$case_dir/diagram.mmd" >/dev/null
  assert_contains "$log" "--noproxy *"
  assert_contains "$log" "http://127.0.0.1:8000/mermaid/svg"

  if TEST_LOG="$log" PATH="$bin:$PATH" MERMAID_CONTAINER_RUNTIME=docker \
    KROKI_URL='https://kroki.io' bash "$RENDER" validate "$case_dir/diagram.mmd" >/dev/null 2>&1; then
    fail "remote Kroki URL was accepted"
  fi

  if TEST_LOG="$log" PATH="$bin:$PATH" MERMAID_CONTAINER_RUNTIME=docker \
    bash "$RENDER" export "$case_dir/diagram.mmd" "$case_dir/diagram.pdf" >/dev/null 2>&1; then
    fail "Kroki was accepted as a PDF backend"
  fi
  assert_no_file "$case_dir/diagram.pdf"
}

test_external_reference_rejection() {
  local case_dir="$TEST_DIR/external"
  mkdir -p "$case_dir"
  printf 'flowchart LR\n  A["https://outside.example/secret"]\n' > "$case_dir/diagram.mmd"
  if bash "$RENDER" validate "$case_dir/diagram.mmd" >/dev/null 2>&1; then
    fail "external reference was accepted"
  fi
}

test_fix_and_revalidate_cycle() {
  local case_dir="$TEST_DIR/revalidate" bin="$TEST_DIR/revalidate/bin"
  mkdir -p "$case_dir/tmp" "$bin"
  printf 'BROKEN\n' > "$case_dir/diagram.mmd"

  cat > "$bin/mmdc" <<'STUB'
#!/usr/bin/env bash
input=
output=
previous=
for argument in "$@"; do
  [[ "$previous" == -i ]] && input=$argument
  [[ "$previous" == -o ]] && output=$argument
  previous=$argument
done
if LC_ALL=C grep -q BROKEN "$input"; then
  printf 'syntax error\n' >&2
  exit 1
fi
printf '<svg xmlns="http://www.w3.org/2000/svg"/>\n' > "$output"
STUB
  chmod +x "$bin/mmdc"

  if TMPDIR="$case_dir/tmp" PATH="$bin:$PATH" bash "$RENDER" validate "$case_dir/diagram.mmd" >/dev/null 2>&1; then
    fail "invalid Mermaid source passed validation"
  fi
  make_source "$case_dir/diagram.mmd"
  TMPDIR="$case_dir/tmp" PATH="$bin:$PATH" bash "$RENDER" validate "$case_dir/diagram.mmd" >/dev/null
  if [[ -n $(find "$case_dir/tmp" -mindepth 1 -print -quit) ]]; then
    fail "temporary validation artifacts were not removed"
  fi
}

test_local_precedence_and_export
test_container_fallback_security_flags
test_kroki_loopback_and_pdf_rejection
test_external_reference_rejection
test_fix_and_revalidate_cycle
printf 'All render-mermaid tests passed.\n'
