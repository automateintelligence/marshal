#!/bin/sh
# Print the manifest of the shipped state/ templates: one line "<git blob id>  <path>" per file,
# sorted by path. scripts/git-hooks/pre-push compares a pushed state/ against it.
# Regenerate after editing any file under state/ (the tests fail until you do):
#   sh scripts/make-state-manifest.sh > scripts/git-hooks/state-templates.manifest
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
find state -type f | LC_ALL=C sort | while IFS= read -r f; do
    printf '%s  %s\n' "$(git hash-object --no-filters -- "$f")" "$f"
done
