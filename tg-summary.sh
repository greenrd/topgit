#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

terse=
graphviz=
tsort=
deps=


## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-t)
		terse=1;;
	--graphviz)
		graphviz=1;;
	--sort=alphabetical)
		;;
	--sort=topological)
		tsort=1;;
	--sort)
		tsort=1;;
	--deps)
		deps=1;;
	*)
		echo "Usage: tg [...] summary [-t | --sort[=(alphabetical|topological)] | --deps | --graphviz]" >&2
		exit 1;;
	esac
done

curname="$(git symbolic-ref HEAD | sed 's#^refs/\(heads\|top-bases\)/##')"

[ "$terse$graphviz$tsort$deps" = "" ] ||
	[ "$terse$graphviz$tsort$deps" = "1" ] ||
	[ "$terse$tsort" = "11" -a "$graphviz$deps" = "" ] ||
	die "mutually exclusive options given"

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

process_branch()
{
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
}

if [ -n "$tsort" ] && [ -n "$terse" ]; then
	$tg summary --deps|
	tsort|
	while read name
	do
		ref_exists refs/top-bases/$name && echo $name
	done
	exit 0
fi

if [ -n "$tsort" ]; then
	$tg summary --sort=topological -t |
	while read name
	do
		ref=refs/top-bases/$name
		rev=`git rev-parse $ref`
		process_branch
	done
	exit 0
fi

git for-each-ref refs/top-bases |
	while read rev type ref; do
		name="${ref#refs/top-bases/}"
		if branch_annihilated "$name"; then
			continue;
		fi;

		if [ -n "$terse" ]; then
			echo "$name"
			continue
		fi
		if [ -n "$graphviz$deps" ]; then
			git cat-file blob "$name:.topdeps" | while read dep; do
				dep_is_tgish=true
				ref_exists "refs/top-bases/$dep"  ||
					dep_is_tgish=false
				if ! "$dep_is_tgish" || ! branch_annihilated $dep; then
					if [ -n "$graphviz" ]; then
						echo "\"$name\" -> \"$dep\";"
					else
						echo "$name $dep"
					fi
				fi
			done
			continue
		fi

		process_branch
	done

if [ -n "$graphviz" ]; then
	echo '}'
fi

# vim:noet
