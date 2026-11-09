#!/bin/sh
# Install the Marshal privacy guard (scripts/git-hooks/pre-push) as the pre-push hook of the git
# repository you are in. /marshal:init runs this for you. Template users run it once after cloning:
#   cd my-marshal && sh scripts/install-git-hooks.sh
#
# Usage: install-git-hooks.sh [--force]
#   --force   replace a different existing pre-push hook (the old one is kept as pre-push.bak)
# Exit codes: 0 installed or already installed, 1 usage, 2 not in a git repository, no hook file,
# or a different hook is already there.
set -eu

force=0
for arg in "$@"; do
    case "$arg" in
        --force) force=1 ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "unknown argument: $arg" >&2; exit 1 ;;
    esac
done

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
src="$script_dir/git-hooks/pre-push"
[ -r "$src" ] || { echo "hook file not found: $src" >&2; exit 2; }

top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not inside a git repository (run git init first)" >&2; exit 2; }
cd "$top"
hooks_dir=$(git rev-parse --git-path hooks)
case "$hooks_dir" in /*) ;; *) hooks_dir="$top/$hooks_dir" ;; esac
dst="$hooks_dir/pre-push"

if [ -e "$dst" ]; then
    if cmp -s "$src" "$dst"; then
        echo "Already installed: $dst"
        exit 0
    fi
    if [ "$force" -ne 1 ]; then
        echo "A different pre-push hook already exists: $dst" >&2
        echo "Look at it, then run  sh scripts/install-git-hooks.sh --force  to replace it (the old one is kept as pre-push.bak)." >&2
        exit 2
    fi
    cp -p "$dst" "$dst.bak"
fi

mkdir -p "$hooks_dir"
cp "$src" "$dst"
chmod +x "$dst"
echo "Installed the Marshal privacy guard: $dst"
