#!/usr/bin/env bash
set -euo pipefail

readonly DEFAULT_IMAGE="minlag/mermaid-cli:latest"
readonly DEFAULT_KROKI_URL="http://127.0.0.1:8000"

usage() {
  printf 'Usage:\n  %s validate INPUT.mmd\n  %s export INPUT.mmd OUTPUT.{png|svg|pdf}\n' "$0" "$0" >&2
  exit 64
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_safe_source() {
  local input=$1
  [[ -f "$input" ]] || fail "input file does not exist: $input"
  [[ "$input" == *.mmd ]] || fail "input must have the .mmd extension"

  if LC_ALL=C grep -Eiq '(https?|ftp|file):[[:space:]]*//|(^|[^:])//' "$input"; then
    fail "external or file resource references are forbidden in Mermaid source"
  fi
}

normalize_kroki_url() {
  local url=${KROKI_URL:-$DEFAULT_KROKI_URL}
  url=${url%/}
  if [[ ! "$url" =~ ^http://(127\.0\.0\.1|localhost|\[::1\])(:[0-9]{1,5})?$ ]]; then
    fail "KROKI_URL must be an HTTP loopback endpoint without credentials or paths"
  fi
  printf '%s' "$url"
}

container_image() {
  printf '%s' "${MERMAID_CLI_IMAGE:-$DEFAULT_IMAGE}"
}

runtime_candidates() {
  case "${MERMAID_CONTAINER_RUNTIME:-auto}" in
    auto) printf '%s\n' docker podman ;;
    docker|podman) printf '%s\n' "$MERMAID_CONTAINER_RUNTIME" ;;
    *) fail "MERMAID_CONTAINER_RUNTIME must be auto, docker, or podman" ;;
  esac
}

image_is_local() {
  local runtime=$1 image=$2
  command -v "$runtime" >/dev/null 2>&1 || return 1
  if [[ "$runtime" == docker ]]; then
    docker image inspect "$image" >/dev/null 2>&1
  else
    podman image exists "$image" >/dev/null 2>&1
  fi
}

run_container() {
  local runtime=$1 input=$2 output=$3 image input_dir output_dir input_name output_name
  image=$(container_image)
  input_dir=$(cd "$(dirname "$input")" && pwd -P)
  output_dir=$(cd "$(dirname "$output")" && pwd -P)
  input_name=$(basename "$input")
  output_name=$(basename "$output")

  local -a common=(run --rm --pull=never --network=none)
  if [[ "$runtime" == docker ]]; then
    docker "${common[@]}" --user "$(id -u):$(id -g)" \
      --mount "type=bind,src=$input_dir,dst=/input,readonly" \
      --mount "type=bind,src=$output_dir,dst=/output" \
      "$image" -i "/input/$input_name" -o "/output/$output_name"
  else
    podman "${common[@]}" --userns=keep-id --user "$(id -u):$(id -g)" \
      --mount "type=bind,src=$input_dir,dst=/input,readonly" \
      --mount "type=bind,src=$output_dir,dst=/output" \
      "$image" -i "/input/$input_name" -o "/output/$output_name"
  fi
}

run_kroki() {
  local input=$1 output=$2 format=$3 url
  [[ "$format" == png || "$format" == svg ]] || return 2
  command -v curl >/dev/null 2>&1 || return 1
  url=$(normalize_kroki_url) || return 1
  curl --fail --silent --show-error --noproxy '*' --connect-timeout 3 --max-time 60 \
    -X POST -H 'Content-Type: text/plain' --data-binary "@$input" \
    "$url/mermaid/$format" -o "$output"
}

SELECTED_BACKEND=
SELECTED_RUNTIME=
WORK_DIR=

cleanup() {
  [[ -n "$WORK_DIR" ]] && rm -rf -- "$WORK_DIR"
}

select_backend() {
  local allow_kroki=$1 probe_dir=$2 probe_input probe_output
  probe_input="$probe_dir/probe.mmd"
  probe_output="$probe_dir/probe.svg"
  printf 'flowchart LR\n  A --> B\n' > "$probe_input"

  if command -v mmdc >/dev/null 2>&1 && mmdc -i "$probe_input" -o "$probe_output" >/dev/null 2>&1; then
    SELECTED_BACKEND=local
    return
  fi

  local runtime image
  image=$(container_image)
  while IFS= read -r runtime; do
    if image_is_local "$runtime" "$image" && run_container "$runtime" "$probe_input" "$probe_output" >/dev/null 2>&1; then
      SELECTED_BACKEND=container
      SELECTED_RUNTIME=$runtime
      return
    fi
  done < <(runtime_candidates)

  if [[ "$allow_kroki" == yes ]] && run_kroki "$probe_input" "$probe_output" svg >/dev/null 2>&1; then
    SELECTED_BACKEND=kroki
    return
  fi

  fail "no permitted local Mermaid rendering backend is available"
}

render_with_selected_backend() {
  local input=$1 output=$2 format=$3
  case "$SELECTED_BACKEND" in
    local) mmdc -i "$input" -o "$output" ;;
    container) run_container "$SELECTED_RUNTIME" "$input" "$output" ;;
    kroki) run_kroki "$input" "$output" "$format" ;;
    *) fail "internal error: no backend selected" ;;
  esac
}

main() {
  [[ $# -ge 2 ]] || usage
  local action=$1 input=$2 output=${3:-} format allow_kroki=yes
  [[ "$action" == validate || "$action" == export ]] || usage
  [[ "$action" == validate && $# -eq 2 || "$action" == export && $# -eq 3 ]] || usage
  require_safe_source "$input"

  WORK_DIR=$(mktemp -d)
  trap cleanup EXIT

  if [[ "$action" == export ]]; then
    format=${output##*.}
    format=${format,,}
    [[ "$format" == png || "$format" == svg || "$format" == pdf ]] || fail "output extension must be png, svg, or pdf"
    [[ -d "$(dirname "$output")" ]] || fail "output directory does not exist"
    [[ "$format" == pdf ]] && allow_kroki=no
  else
    format=svg
  fi

  select_backend "$allow_kroki" "$WORK_DIR"
  if ! render_with_selected_backend "$input" "$WORK_DIR/validation.svg" svg; then
    fail "Mermaid validation failed; fix the source and validate again"
  fi

  if [[ "$action" == validate ]]; then
    printf 'Validated with %s backend: %s\n' "$SELECTED_BACKEND" "$input"
    return
  fi

  if [[ "$format" == svg ]]; then
    mv -- "$WORK_DIR/validation.svg" "$output"
  else
    render_with_selected_backend "$input" "$WORK_DIR/output.$format" "$format"
    mv -- "$WORK_DIR/output.$format" "$output"
  fi
  printf 'Exported with %s backend: %s\n' "$SELECTED_BACKEND" "$output"
}

main "$@"
