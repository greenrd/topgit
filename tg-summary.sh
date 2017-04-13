#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

terse=
graphviz=
sort=
deps=
head_from=

## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-i|-w)
		[ -z "$head_from" ] || die "-i and -w are mutually exclusive"
		head_from="$arg";;
	-t)
		terse=1;;
	--graphviz)
		graphviz=1;;
	--sort)
		sort=1;;
	--deps)
		deps=1;;
	*)
		echo "Usage: tg [...] summary [-t | --sort | --deps | --graphviz] [-i | -w]" >&2
		exit 1;;
	esac
done

curname="$(git symbolic-ref HEAD | sed 's#^refs/\(heads\|top-bases\)/##')"

[ "$terse$graphviz$sort$deps" = "" ] ||
	[ "$terse$graphviz$sort$deps" = "1" ] ||
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

if [ -n "$sort" ]; then
	tsort_input="$(get_temp tg-summary-sort)"
	exec 4>$tsort_input
	exec 5<$tsort_input
fi

## List branches

process_branch()
{
	missing_deps=

	current=' '
	[ "$name" != "$curname" ] || current='>'
	from=$head_from
	[ "$name" = "$curname" ] ||
		from=
	nonempty=' '
	! branch_empty "$name" $from || nonempty='0'
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
		subject="$(cat_file "$name:.topmsg" $from | sed -n 's/^Subject: //p')"
	else
		# No commits yet
		subject="(No commits)"
	fi

	printf '%s\t%-31s\t%s\n' "$current$nonempty$remote$rem_update$deps_update$deps_missing$base_update" \
		"$name" "$subject"
}

if [ -n "$deps" ]; then
	list_deps $head_from
	exit 0
fi

non_annihilated_branches |
	while read name || [[ -n "$name" ]]; do
		if [ -n "$terse" ]; then
			echo "$name"
		elif [ -n "$graphviz$sort" ]; then
			from=$head_from
			[ "$name" = "$curname" ] ||
				from=
			cat_file "$name:.topdeps" $from | while read dep || [[ -n "$dep" ]]; do
				dep_is_tgish=true
				ref_exists "refs/top-bases/$dep"  ||
					dep_is_tgish=false
				if ! "$dep_is_tgish" || ! branch_annihilated $dep; then
					if [ -n "$graphviz" ]; then
						echo "\"$name\" -> \"$dep\";"
						if [ "$name" = "$curname" ] || [ "$dep" = "$curname" ]; then
							echo "\"$curname\" [style=filled,fillcolor=yellow];"
						fi
					else
						echo "$name $dep" >&4
					fi
				fi
			done
		else
			process_branch
		fi
	done

if [ -n "$graphviz" ]; then
	echo '}'
fi

if [ -n "$sort" ]; then
	tsort <&5
fi


# vim:noet
