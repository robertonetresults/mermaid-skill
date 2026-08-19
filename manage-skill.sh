#!/usr/bin/env bash
set -euo pipefail

readonly SKILL_NAME="mermaid-skill"
readonly MARKER_NAME=".managed-by-robertonetresults-mermaid-skill"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
readonly SCRIPT_DIR
readonly SOURCE_DIR="$SCRIPT_DIR/skills/$SKILL_NAME"

usage() {
  cat >&2 <<'USAGE'
Usage:
  ./manage-skill.sh install   [--agents | --project DIR | --destination DIR]
  ./manage-skill.sh update    [--pull] [--agents | --project DIR | --destination DIR]
  ./manage-skill.sh uninstall [--agents | --project DIR | --destination DIR]

Targets:
  default            ${CODEX_HOME:-$HOME/.codex}/skills/mermaid-skill
  --agents           $HOME/.agents/skills/mermaid-skill
  --project DIR      DIR/.agents/skills/mermaid-skill
  --destination DIR  DIR/mermaid-skill

The update command uses the current checkout by default. Add --pull to run
"git pull --ff-only" first; tracked local changes make that operation abort.
USAGE
  exit 64
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

ACTION=${1:-}
[[ "$ACTION" == install || "$ACTION" == update || "$ACTION" == uninstall ]] || usage
shift

TARGET_MODE=codex
TARGET_VALUE=
PULL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pull)
      [[ "$ACTION" == update ]] || fail "--pull is valid only with update"
      PULL=true
      shift
      ;;
    --agents)
      [[ "$TARGET_MODE" == codex ]] || fail "choose only one target option"
      TARGET_MODE=agents
      shift
      ;;
    --project|--destination)
      [[ $# -ge 2 ]] || fail "$1 requires a directory"
      [[ "$TARGET_MODE" == codex ]] || fail "choose only one target option"
      if [[ "$1" == --project ]]; then
        TARGET_MODE=project
      else
        TARGET_MODE=destination
      fi
      TARGET_VALUE=$2
      shift 2
      ;;
    -h|--help) usage ;;
    *) fail "unknown option: $1" ;;
  esac
done

[[ -d "$SOURCE_DIR" && -f "$SOURCE_DIR/SKILL.md" ]] || fail "skill source not found: $SOURCE_DIR"
[[ -f "$SCRIPT_DIR/LICENSE" ]] || fail "license file not found: $SCRIPT_DIR/LICENSE"

case "$TARGET_MODE" in
  codex) TARGET_PARENT="${CODEX_HOME:-$HOME/.codex}/skills" ;;
  agents) TARGET_PARENT="$HOME/.agents/skills" ;;
  project)
    [[ -d "$TARGET_VALUE" ]] || fail "project directory does not exist: $TARGET_VALUE"
    TARGET_PARENT="$(cd "$TARGET_VALUE" && pwd -P)/.agents/skills"
    ;;
  destination)
    [[ -n "$TARGET_VALUE" ]] || fail "destination directory is empty"
    if [[ -d "$TARGET_VALUE" ]]; then
      TARGET_PARENT=$(cd "$TARGET_VALUE" && pwd -P)
    else
      TARGET_PARENT=$TARGET_VALUE
    fi
    ;;
esac

[[ -n "$TARGET_PARENT" && "$TARGET_PARENT" != / ]] || fail "unsafe target parent"
TARGET_DIR="${TARGET_PARENT%/}/$SKILL_NAME"
[[ "$TARGET_DIR" != / && "$TARGET_DIR" != "$HOME" && "$TARGET_DIR" != "$SCRIPT_DIR" ]] || fail "unsafe target directory: $TARGET_DIR"

is_managed() {
  [[ -f "$TARGET_DIR/$MARKER_NAME" ]] &&
    LC_ALL=C grep -Fqx 'managed-by=robertonetresults/mermaid-skill' "$TARGET_DIR/$MARKER_NAME"
}

pull_source() {
  command -v git >/dev/null 2>&1 || fail "git is required for update --pull"
  git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "installer is not running from a Git checkout"
  if ! git -C "$SCRIPT_DIR" diff --quiet || ! git -C "$SCRIPT_DIR" diff --cached --quiet; then
    fail "tracked changes are present; commit or stash them before update --pull"
  fi
  git -C "$SCRIPT_DIR" pull --ff-only
}

STAGE_DIR=
BACKUP_HOLDER=

cleanup() {
  [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]] && rm -rf -- "$STAGE_DIR"
  [[ -n "$BACKUP_HOLDER" && -d "$BACKUP_HOLDER" ]] && rm -rf -- "$BACKUP_HOLDER"
  return 0
}
trap cleanup EXIT

stage_skill() {
  mkdir -p -- "$TARGET_PARENT"
  STAGE_DIR=$(mktemp -d "$TARGET_PARENT/.${SKILL_NAME}.stage.XXXXXX")
  cp -a -- "$SOURCE_DIR/." "$STAGE_DIR/"
  cp -a -- "$SCRIPT_DIR/LICENSE" "$STAGE_DIR/LICENSE"
  printf 'managed-by=robertonetresults/mermaid-skill\n' > "$STAGE_DIR/$MARKER_NAME"
}

install_skill() {
  if [[ -e "$TARGET_DIR" || -L "$TARGET_DIR" ]]; then
    fail "target already exists; use update only if it is managed by this installer: $TARGET_DIR"
  fi
  stage_skill
  mv -- "$STAGE_DIR" "$TARGET_DIR"
  STAGE_DIR=
  printf 'Installed %s\n' "$TARGET_DIR"
}

update_skill() {
  [[ -d "$TARGET_DIR" ]] || fail "managed installation not found: $TARGET_DIR"
  is_managed || fail "refusing to update an installation not owned by this installer: $TARGET_DIR"
  "$PULL" && pull_source
  stage_skill

  BACKUP_HOLDER=$(mktemp -d "$TARGET_PARENT/.${SKILL_NAME}.backup.XXXXXX")
  mv -- "$TARGET_DIR" "$BACKUP_HOLDER/original"
  if ! mv -- "$STAGE_DIR" "$TARGET_DIR"; then
    mv -- "$BACKUP_HOLDER/original" "$TARGET_DIR"
    fail "replacement failed; the previous installation was restored"
  fi
  STAGE_DIR=
  rm -rf -- "$BACKUP_HOLDER"
  BACKUP_HOLDER=
  printf 'Updated %s\n' "$TARGET_DIR"
}

uninstall_skill() {
  [[ -d "$TARGET_DIR" ]] || fail "managed installation not found: $TARGET_DIR"
  is_managed || fail "refusing to remove an installation not owned by this installer: $TARGET_DIR"

  BACKUP_HOLDER=$(mktemp -d "$TARGET_PARENT/.${SKILL_NAME}.remove.XXXXXX")
  mv -- "$TARGET_DIR" "$BACKUP_HOLDER/original"
  rm -rf -- "$BACKUP_HOLDER"
  BACKUP_HOLDER=
  printf 'Uninstalled %s\n' "$TARGET_DIR"
}

case "$ACTION" in
  install) install_skill ;;
  update) update_skill ;;
  uninstall) uninstall_skill ;;
esac
