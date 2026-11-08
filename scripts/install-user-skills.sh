#!/usr/bin/env bash
# Copy Marshal's vetted skills into ~/.claude/skills so they work in every project on this machine.
# Safe by default: skips any skill that already exists. Use --force to overwrite.
# Run on each machine where you work (laptop, WSL, a Linux server):
#   <CHECKOUT>/scripts/install-user-skills.sh   (<CHECKOUT> is where you cloned this repo)
set -euo pipefail
src="$(cd "$(dirname "$0")/.." && pwd)/.claude/skills"
dst="${CLAUDE_HOME:-$HOME/.claude}/skills"
force=0; [ "${1:-}" = "--force" ] && force=1
mkdir -p "$dst"
for dir in "$src"/*/; do
  name="$(basename "$dir")"
  if [ -e "$dst/$name" ] && [ "$force" -eq 0 ]; then
    echo "skip   $name (already installed; use --force to overwrite)"
  else
    rm -rf "$dst/$name"; cp -r "$dir" "$dst/$name"; echo "copied $name"
  fi
done
echo "Done. Skills are in $dst. Restart Claude Code sessions to pick them up."
