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
		echo "Usage: tg info [NAME]" >&2
		exit 1;;
	*)
		[ -z "$name" ] || die "name already specified ($name)"
		name="$arg";;
	esac
done

[ -n "$name" ] || name="$(git symbolic-ref HEAD | sed 's#^refs/heads/##')"
base_rev="$(git rev-parse --short --verify "refs/top-bases/$name" 2>/dev/null)" ||
	die "not a TopGit-controlled branch"

measure="$(measure_branch "$name" "$base_rev")"

echo "Topic Branch: $name ($measure)"
if [ "$(git rev-parse --short "$name")" = "$base_rev" ]; then
	echo "No commits."
	exit 0
fi

git cat-file blob "$name:.topmsg" | grep ^Subject:

echo "Base: $base_rev"
branch_contains "$name" "$base_rev" ||
	echo "Base is newer than head! Please run \`tg update\`."

deps="$(git cat-file blob "$name:.topdeps")"
echo "Depends: $deps"

depcheck="$(mktemp)"
needs_update "$name" >"$depcheck"
if [ -s "$depcheck" ]; then
	echo "Needs update from:"
	cat "$depcheck" |
		sed 's/ [^ ]* *$//' | # last is $name
		sed 's/^: //' | # don't distinguish base updates
		while read dep chain; do
			echo -n "$dep "
			[ -n "$chain" ] && echo -n "(<= $(echo "$chain" | sed 's/ / <= /')) "
			dep_parent="${chain%% *}"
			echo -n "($(measure_branch "$dep" "${dep2:-$name}"))"
			echo
		done | sed 's/^/\t/'
else
	echo "Up-to-date."
fi
rm "$depcheck"
