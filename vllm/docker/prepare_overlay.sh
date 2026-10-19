#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Stage the build context for Dockerfile.overlay.
#
#   prepare_overlay.sh <base.patch> <new.patch> <vllm_version> <out_dir>
#
# Applies both multi-arc patches to a clean vLLM <vllm_version> checkout and
# copies the files that differ into <out_dir>/overlay.  Fails if anything
# outside vllm/ and tests/ changed, or a non-Python file changed, since the
# overlay cannot rebuild native code.

set -euo pipefail

base_patch=$(realpath "$1")
new_patch=$(realpath "$2")
vllm_version=$3
out=$4

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

git clone -q --depth 1 -b "$vllm_version" https://github.com/vllm-project/vllm.git "$work/src"
cd "$work/src"
git config user.name overlay
git config user.email overlay@localhost

git apply "$base_patch"
git add -A
git commit -qm base
base=$(git rev-parse HEAD)

git -c advice.detachedHead=false checkout -q HEAD~1
git apply "$new_patch"
git add -A
git commit -qm new
new=$(git rev-parse HEAD)

git diff --name-status --no-renames "$base" "$new" > "$work/delta"
echo "Patch delta:"
cat "$work/delta"

bad=$(awk '{print $2}' "$work/delta" | grep -vE '^(vllm|tests)/' || true)
bad+=$(awk '{print $2}' "$work/delta" | grep -E '^vllm/' | grep -vE '\.(py|json|jinja)$' || true)
if [ -n "$bad" ]; then
    echo "Overlay cannot handle these changes (native code or files outside vllm/, tests/):" >&2
    echo "$bad" >&2
    exit 1
fi

rm -rf "$out"
mkdir -p "$out/overlay"
: > "$out/OVERLAY_DELETED"
while read -r status path; do
    if [ "$status" = D ]; then
        echo "$path" >> "$out/OVERLAY_DELETED"
    else
        mkdir -p "$out/overlay/$(dirname "$path")"
        cp "$path" "$out/overlay/$path"
    fi
done < "$work/delta"
mkdir -p "$out/overlay/vllm"
echo "Staged $(find "$out/overlay" -type f | wc -l | tr -d ' ') files in $out/overlay"
