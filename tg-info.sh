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
		echo "Usage: tg [...] info [NAME]" >&2
		exit 1;;
	*)
		[ -z "$name" ] || die "name already specified ($name)"
		name="$arg";;
	esac
done

[ -n "$name" ] || name="$(git symbolic-ref HEAD | sed 's#^refs/\(heads\|top-bases\)/##')"
base_rev="$(git rev-parse --short --verify "refs/top-bases/$name" 2>/dev/null)" ||
	die "not a TopGit-controlled branch"

measure="$(measure_branch "$name" "$base_rev")"

echo "Topic Branch: $name ($measure)"
if [ "$(git rev-parse --short "$name")" = "$base_rev" ]; then
	echo "* No commits."
	exit 0
fi

git cat-file blob "$name:.topmsg" | grep ^Subject: || :

echo "Base: $base_rev"
branch_contains "$name" "$base_rev" ||
	echo "* Base is newer than head! Please run \`$tg update\`."

if has_remote "$name"; then
	echo "Remote Mate: $base_remote/$name"
	branch_contains "$base_rev" "refs/remotes/$base_remote/top-bases/$name" ||
		echo "* Local base is out of date wrt. the remote base."
	branch_contains "$name" "refs/remotes/$base_remote/$name" ||
		echo "* Local head is out of date wrt. the remote head."
	branch_contains "refs/remotes/$base_remote/$name" "$name" ||
		echo "* Local head is ahead of the remote head."
fi

git cat-file blob "$name:.topdeps" |
	sed '1{ s/^/Depends: /; n; }; s/^/         /;'

depcheck="$(get_temp tg-depcheck)"
depcheck1="$(get_temp tg-depcheck)"
missing_deps=
missing_recursive_deps=
needs_update "$name" >"$depcheck" || :
if [ -n "$missing_deps" ]; then
	echo "MISSING: $missing_deps"
fi
[ -z "$missing_deps" ] && grep -q '^!' "$depcheck" && missing_recursive_deps=1
cat "$depcheck" |
	sed '/^!/d' | # we cannot do anything about missing depends
	sed 's/ [^ ]* *$//' | # last is $name
	sed 's/^: //' | # don't distinguish base updates
	uniq |
	cat > "$depcheck1"
if [ -s "$depcheck1" ]; then
	echo "Needs update from:"
	cat "$depcheck1" |
		while read dep chain; do
			echo -n "$dep "
			[ -n "$chain" ] && echo -n "(<= $(echo "$chain" | sed 's/ / <= /')) "
			dep_parent="${chain%% *}"
			echo -n "($(measure_branch "$dep" "${dep2:-$name}"))"
			echo
		done | sed 's/^/\t/'
else
	echo -n "Up-to-date"
	[ -z "$missing_recursive_deps" ] || echo -n " (but some recursive dependencies are missing)"
	echo "."
fi

# vim:noet
