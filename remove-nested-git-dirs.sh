#!/usr/bin/env bash
#
# Remove nested Git repositories under a target directory while preserving
# the root repository's own .git directory, then convert orphaned gitlinks
# into normal tracked files.
#
# Usage:
#   bash scripts/remove-nested-git-dirs.sh
#   bash scripts/remove-nested-git-dirs.sh /path/to/target
#   bash scripts/remove-nested-git-dirs.sh --yes /path/to/target
#
# Behavior:
# - Keeps:   <target>/.git
# - Removes: any other .git directory or .git file below <target>
# - Converts: index gitlinks without a matching .gitmodules entry into regular files
# 
# Warning:
# This permanently deletes nested .git directories with rm -rf.
# Run only if you are sure those nested repositories are no longer needed.

set -euo pipefail

ASSUME_YES="${CI:-false}"
ROOT_DIR="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      ASSUME_YES="true"
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage:
  bash scripts/remove-nested-git-dirs.sh [--yes] [target]

Options:
  -y, --yes   Skip the confirmation prompt.
  -h, --help  Show this help text.
EOF
      exit 0
      ;;
    *)
      ROOT_DIR="$1"
      shift
      ;;
  esac
done

ROOT_DIR="${ROOT_DIR%/}"
if [[ -z "$ROOT_DIR" ]]; then
  ROOT_DIR="."
fi

echo "WARNING: This will permanently delete all nested .git directories under: $ROOT_DIR"
echo "The root .git directory at $ROOT_DIR/.git will be preserved."

if [[ "$ASSUME_YES" != "true" ]]; then
  printf "Type 'yes' to continue: "
  read -r CONFIRM

  if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted."
    exit 1
  fi
else
  echo "Confirmation skipped."
fi

find "$ROOT_DIR" \
  -path "$ROOT_DIR/.git" -prune -o \
  \( -type d -o -type f \) -name .git -prune -exec rm -rf {} +

if git -C "$ROOT_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$ROOT_DIR" rev-parse --show-toplevel)"
  cd "$REPO_ROOT"

  mapfile -t GITLINK_PATHS < <(
    git ls-files --stage \
      | awk '$1 == "160000" {print $4}'
  )

  if [[ ${#GITLINK_PATHS[@]} -gt 0 ]]; then
    for gitlink_path in "${GITLINK_PATHS[@]}"; do
      if [[ ! -e "$gitlink_path" ]]; then
        continue
      fi

      if [[ -f .gitmodules ]] && git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}' | grep -Fxq "$gitlink_path"; then
        continue
      fi

      echo "Converting orphaned gitlink to regular files: $gitlink_path"
      git rm --cached -r -- "$gitlink_path" >/dev/null
      git add -A -- "$gitlink_path"
    done
  fi
fi

echo "Done."
