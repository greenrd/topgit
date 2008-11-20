#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

name=


## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-*)
		echo "Usage: tg [...] patch [NAME]" >&2
		exit 1;;
	*)
		[ -z "$name" ] || die "name already specified ($name)"
		name="$arg";;
	esac
done

[ -n "$name" ] || name="$(git symbolic-ref HEAD | sed 's#^refs/\(heads\|top-bases\)/##')"
base_rev="$(git rev-parse --short --verify "refs/top-bases/$name" 2>/dev/null)" ||
	die "not a TopGit-controlled branch"

git cat-file blob "$name:.topmsg"
echo
[ -n "$(git grep '^[-]--' "$name" -- ".topmsg")" ] || echo '---'

# Evil obnoxious hack to work around the lack of git diff --exclude
git_is_stupid="$(mktemp -t tg-patch-changes.XXXXXX)"
git diff-tree --name-only "$base_rev" "$name" |
	fgrep -vx ".topdeps" |
	fgrep -vx ".topmsg" >"$git_is_stupid" || : # fgrep likes to fail randomly?
if [ -s "$git_is_stupid" ]; then
	cat "$git_is_stupid" | xargs git diff --patch-with-stat "$base_rev" "$name" --
else
	echo "No changes."
fi
rm "$git_is_stupid"

echo '-- '
echo "tg: ($base_rev..) $name (depends on: $(git cat-file blob "$name:.topdeps" | paste -s -d' '))"
branch_contains "$name" "$base_rev" ||
	echo "tg: The patch is out-of-date wrt. the base! Run \`$tg update\`."

# vim:noet
