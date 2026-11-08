#!/bin/sh
# Install or refresh the Marshal worker-rules block in ~/.claude/CLAUDE.md.
#
# The block lives between two marker lines:
#   <!-- marshal:worker-rules:begin -->
#   <!-- marshal:worker-rules:end -->
# Text outside the markers is never touched. If the markers are missing, the
# block is appended at the end. If the target file is missing, it is created.
#
# Usage:
#   install-worker-rules.sh [--dry-run | --apply] [--target FILE] [--rules FILE]
#
#   --dry-run   (default) show what would change, write nothing
#   --apply     make a timestamped backup, then write the new file
#   --target    file to edit (default: $CLAUDE_MD, else $HOME/.claude/CLAUDE.md)
#   --rules     block content (default: ../docs/worker-rules.md relative to this script)
#
# Exit codes: 0 ok (changed, or already up to date), 1 usage, 2 bad markers or missing rules.
# Idempotent: running it twice makes no second change and no second backup.

set -eu

BEGIN='<!-- marshal:worker-rules:begin -->'
END='<!-- marshal:worker-rules:end -->'

mode=dry-run
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
rules="$script_dir/../docs/worker-rules.md"
target="${CLAUDE_MD:-$HOME/.claude/CLAUDE.md}"

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) mode=dry-run ;;
        --apply) mode=apply ;;
        --target) shift; [ $# -gt 0 ] || { echo "--target needs a file" >&2; exit 1; }; target=$1 ;;
        --rules) shift; [ $# -gt 0 ] || { echo "--rules needs a file" >&2; exit 1; }; rules=$1 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
    shift
done

[ -r "$rules" ] || { echo "rules file not readable: $rules" >&2; exit 2; }

tmp=$(mktemp "${TMPDIR:-/tmp}/worker-rules.XXXXXX")
trap 'rm -f "$tmp"' EXIT INT TERM

if [ -f "$target" ]; then
    n_begin=$(grep -cxF -- "$BEGIN" "$target" || true)
    n_end=$(grep -cxF -- "$END" "$target" || true)
    if [ "$n_begin" -gt 1 ] || [ "$n_end" -gt 1 ] || [ "$n_begin" -ne "$n_end" ]; then
        echo "markers damaged in $target (begin=$n_begin end=$n_end); fix by hand" >&2
        exit 2
    fi
    if [ "$n_begin" -eq 1 ]; then
        line_begin=$(grep -nxF -- "$BEGIN" "$target" | cut -d: -f1)
        line_end=$(grep -nxF -- "$END" "$target" | cut -d: -f1)
        if [ "$line_begin" -ge "$line_end" ]; then
            echo "end marker comes before begin marker in $target; fix by hand" >&2
            exit 2
        fi
        # Replace everything between the markers with the rules file.
        awk -v begin="$BEGIN" -v end="$END" -v rules="$rules" '
            $0 == begin { print; while ((getline line < rules) > 0) print line; close(rules); skip = 1; next }
            $0 == end   { skip = 0; print; next }
            !skip       { print }
        ' "$target" > "$tmp"
    else
        # No markers: append the block, making sure the file ends with a newline first.
        cat "$target" > "$tmp"
        if [ -s "$tmp" ] && [ "$(tail -c 1 "$tmp" | od -An -c | tr -d ' ')" != '\n' ]; then
            printf '\n' >> "$tmp"
        fi
        { printf '\n%s\n' "$BEGIN"; cat "$rules"; printf '%s\n' "$END"; } >> "$tmp"
    fi
else
    { printf '%s\n' "$BEGIN"; cat "$rules"; printf '%s\n' "$END"; } > "$tmp"
fi

if [ -f "$target" ] && cmp -s "$target" "$tmp"; then
    echo "No change: $target already has the current worker rules."
    exit 0
fi

if [ -f "$target" ]; then
    added=$(diff -u "$target" "$tmp" | grep -c '^+[^+]' || true)
    removed=$(diff -u "$target" "$tmp" | grep -c '^-[^-]' || true)
    echo "Change for $target: +$added -$removed lines"
    diff -u "$target" "$tmp" || true
else
    echo "Create $target: $(wc -l < "$tmp") lines"
fi

if [ "$mode" = dry-run ]; then
    echo "Dry run. Nothing written. Run with --apply to install."
    exit 0
fi

if [ -f "$target" ]; then
    backup="$target.bak.$(date +%Y%m%d-%H%M%S)"
    cp -p "$target" "$backup"
    echo "Backup: $backup"
else
    mkdir -p "$(dirname -- "$target")"
fi
cp "$tmp" "$target"
echo "Installed worker rules into $target"
