#!/bin/sh
# Create a new Marshal workspace: your own folder, and your own git repository, holding Marshal's
# rules (CLAUDE.md), docs/ and state/ templates. /marshal:init runs this.
#
# Usage: init-workspace.sh FOLDER [--with-usage] [--with-bus]
#   FOLDER         where the workspace goes (created if needed; a leading ~ is expanded)
#   --with-usage   also copy the budget recorder (scripts/usage/)
#   --with-bus     also copy the optional bus for several Marshals (scripts/bus/, docs/specs/, .claude/settings.json)
#
# What it does: copies the template files from this plugin (or checkout) into FOLDER, never
# overwriting a file that is already there; runs git init when FOLDER is not a repository (no
# history, no remote); installs the privacy guard as .git/hooks/pre-push (scripts/install-git-hooks.sh).
# It never commits and never pushes. Run it again later with a flag to add an optional piece.
#
# Exit codes: 0 ok, 1 usage, 2 refused (FOLDER is inside this plugin, or is a repository whose remote
# is the public Marshal repo), 3 the privacy guard could not be installed.
set -eu

src_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)

folder=''
with_usage=0
with_bus=0
for arg in "$@"; do
    case "$arg" in
        --with-usage) with_usage=1 ;;
        --with-bus) with_bus=1 ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        -*) echo "unknown argument: $arg" >&2; exit 1 ;;
        *) [ -z "$folder" ] || { echo "only one folder allowed" >&2; exit 1; }; folder=$arg ;;
    esac
done
[ -n "$folder" ] || { echo "usage: init-workspace.sh FOLDER [--with-usage] [--with-bus]" >&2; exit 1; }

case "$folder" in
    "~") folder=$HOME ;;
    "~/"*) folder="$HOME/${folder#"~/"}" ;;
esac

mkdir -p "$folder"
target=$(CDPATH= cd -- "$folder" && pwd -P)

case "$target/" in
    "$src_root"/*)
        echo "Refusing: $target is inside the Marshal plugin ($src_root). Pick a folder of your own, for example ~/marshal-workspace." >&2
        exit 2 ;;
esac

# An existing repository there must not point at the public Marshal repo.
if [ -e "$target/.git" ]; then
    git -C "$target" config --get-regexp '^remote\..*\.(push)?url$' 2>/dev/null | while read -r _key url; do
        if sh "$src_root/scripts/git-hooks/pre-push" --is-public-url "$url"; then
            echo "Refusing: $target is a git repository whose remote points at the PUBLIC Marshal repo ($url)." >&2
            echo "Your state/ would end up in a public repo. Use a new folder, or remove that remote first." >&2
            exit 1
        fi
    done || exit 2
fi

copy_file() {
    rel=$1
    if [ -e "$target/$rel" ]; then
        echo "kept   $rel (already there)"
        return 0
    fi
    mkdir -p "$target/$(dirname -- "$rel")"
    cp -p "$src_root/$rel" "$target/$rel"
    echo "copied $rel"
}

# copy_tree DIR [EXCLUDED-SUBDIR]: every file under DIR, minus compiled Python and the excluded subfolder.
copy_tree() {
    (cd "$src_root" && find "$1" -type f ! -name '*.pyc' ! -path '*/__pycache__/*' ${2:+! -path "$2/*"} | LC_ALL=C sort) |
        while IFS= read -r rel; do copy_file "$rel"; done
}

copy_file CLAUDE.md
copy_file GLOSSARY.md
copy_file .gitignore
copy_tree docs docs/specs
copy_tree state
copy_tree scripts/git-hooks
copy_file scripts/install-git-hooks.sh
copy_file scripts/install-worker-rules.sh
if [ "$with_usage" -eq 1 ]; then copy_tree scripts/usage; fi
if [ "$with_bus" -eq 1 ]; then
    copy_tree scripts/bus
    copy_tree docs/specs
    copy_file .claude/settings.json
fi

if [ ! -e "$target/.git" ]; then
    git init -q -b main "$target" 2> /dev/null || git init -q "$target"
    echo "git init: new repository in $target (no history, no remote)"
fi

if ! (cd "$target" && sh scripts/install-git-hooks.sh); then
    echo "The workspace files are in place, but the privacy guard (pre-push hook) is NOT installed. Fix that before you add a remote." >&2
    exit 3
fi

cat <<MSG

Marshal workspace ready: $target
Next:
  1. Fill in the {{placeholders}}:  grep -rn '{{' CLAUDE.md state docs
  2. Put this folder in your OWN PRIVATE GitHub repo (see the README, "Install", step 5).
     Never fork the public Marshal repo for your workspace, and never push your state/ there.
MSG
