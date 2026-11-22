#!/bin/sh
# Packs a git ref of living_villages, plus this checkout's lv_keep, and copies it to the
# thinkpad as ~/lvmod-<tag>.tar for `lvw.sh start <world> <port> <tag>`. Also copies lvw.sh.
#
#   tools/lv_world/push-mod.sh [ref] [tag]   ref defaults to HEAD, tag to main
#
# Any branch, tag or commit can be pushed without checking it out. The tarball named
# lvmod.tar (tag main) is what lvw.sh starts by default, as ColonyFood always has.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
ref=${1:-HEAD}
tag=${2:-main}
host=${LV_HOST:-rodri@thinkpad-win11}
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
git -C "$here" archive --prefix=living_villages/ "$ref" | tar -x -C "$t"
git -C "$here" log --oneline -1 "$ref" > "$t/living_villages/.lvw_version"
cp -R "$here/lv_keep" "$t/"
name=lvmod-$tag.tar
[ "$tag" = main ] && name=lvmod.tar
(cd "$t" && tar -cf "$name" living_villages lv_keep)
scp -q "$t/$name" "$here/lvw.sh" "$host:"
echo "pushed $tag: $(cat "$t/living_villages/.lvw_version")"
