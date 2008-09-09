#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2


## Parse options

if [ -n "$1" ]; then
	echo "Usage: tg summary" >&2
	exit 1
fi

curname="$(git symbolic-ref HEAD | sed 's#^refs/\(heads\|top-bases\)/##')"


## List branches

git for-each-ref refs/top-bases |
	while read rev type ref; do
		name="${ref#refs/top-bases/}"
		missing_deps=

		current=' '
		[ "$name" != "$curname" ] || current='>'
		nonempty=' '
		! branch_empty "$name" || nonempty='0'
		remote=' '
		[ -z "$base_remote" ] || remote='l'
		! has_remote "$name" || remote='r'
		rem_update=' '
		[ "$remote" != 'r' ] || {
			branch_contains "refs/top-bases/$name" "refs/remotes/$base_remote/top-bases/$name" &&
			branch_contains "$name" "refs/remotes/$base_remote/$name"
		} || rem_update='R'
		[ "$rem_update" = 'R' ] || branch_contains "refs/remotes/$base_remote/$name" "$name" ||
			rem_update='L'
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

		printf '%s\t%-31s\t%s\n' "$current$nonempty$remote$rem_update$deps_update$deps_missing$base_update" \
			"$name" "$subject"
	done
