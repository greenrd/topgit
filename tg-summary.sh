#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2


## Parse options

if [ -n "$1" ]; then
	echo "Usage: tg summary" >&2
	exit 1
fi


## List branches

git for-each-ref refs/top-bases |
	while read rev name ref; do
		name="${ref#refs/top-bases/}"
		missing_deps=

		nonempty=' '
		! branch_empty "$name" || nonempty='0'
		deps_update=' '
		needs_update "$name" >/dev/null || deps_update='D'
		deps_missing=' '
		[ -z "$missing_deps" ] || deps_missing='!'
		base_update=' '
		branch_contains "$name" "refs/top-bases/$name" || base_update='B'

		if [ "$(git rev-parse "$name")" != "$rev" ]; then
			subject="$(git cat-file blob "$name:.topmsg" | sed -n 's/^Subject: //p')"
		else
			# No commits yet
			subject="(No commits)"
		fi

		printf '%s%s%s%s\t%-31s\t%s\n' "$nonempty" "$deps_update" "$deps_missing" "$base_update" \
			"$name" "$subject"
	done
