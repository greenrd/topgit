#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

terse=
graphviz=


## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-t)
		terse=1;;
	--graphviz)
		graphviz=1;;
	*)
		echo "Usage: tg [...] summary [-t | --graphviz]" >&2
		exit 1;;
	esac
done

curname="$(git symbolic-ref HEAD | sed 's#^refs/\(heads\|top-bases\)/##')"

if [ -n "$graphviz" ]; then
	cat <<EOT
# GraphViz output; pipe to:
#   | dot -Tpng -o <ouput>
# or
#   | dot -Txlib

digraph G {

graph [
  rankdir = "TB"
  label="TopGit Layout\n\n\n"
  fontsize = 14
  labelloc=top
  pad = "0.5,0.5"
];

EOT
fi


## List branches

git for-each-ref refs/top-bases |
	while read rev type ref; do
		name="${ref#refs/top-bases/}"
		if [ -n "$terse" ]; then
			echo "$name"
			continue
		fi
		if [ -n "$graphviz" ]; then
			git cat-file blob "$name:.topdeps" | while read dep; do
				echo "\"$name\" -> \"$dep\";"
			done
			continue
		fi

		missing_deps=

		current=' '
		[ "$name" != "$curname" ] || current='>'
		nonempty=' '
		! branch_empty "$name" || nonempty='0'
		remote=' '
		[ -z "$base_remote" ] || remote='l'
		! has_remote "$name" || remote='r'
		rem_update=' '
		[ "$remote" != 'r' ] || ! ref_exists "refs/remotes/$base_remote/top-bases/$name" || {
			branch_contains "refs/top-bases/$name" "refs/remotes/$base_remote/top-bases/$name" &&
			branch_contains "$name" "refs/remotes/$base_remote/$name"
		} || rem_update='R'
		[ "$rem_update" = 'R' ] || branch_contains "refs/remotes/$base_remote/$name" "$name" 2>/dev/null ||
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

if [ -n "$graphviz" ]; then
	echo '}'
fi
