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

git for-each-ref | cut -f 2 |
	while read ref; do
		name="${ref#refs/heads/}"
		[ "$name" != "$ref" ] ||
			continue # eew, not a branch
		git rev-parse --verify "refs/top-bases/$name" >/dev/null 2>&1 ||
			continue # not a TopGit branch

		deps_update=' '
		[ -z "$(needs_update "$name")" ] || deps_update='D'
		base_update=' '
		branch_contains "$name" "refs/top-bases/$name" || base_update='B'

		if [ "$(git rev-parse "$name")" != "$(git rev-parse "refs/top-bases/$name")" ]; then
			subject="$(git cat-file blob "$name:.topmsg" | sed -n 's/^Subject: //p')"
		else
			# No commits yet
			subject="(No commits)"
		fi

		printf '%s%s\t%-31s\t%s\n' "$deps_update" "$base_update" "$name" "$subject"
	done
