#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

name=
head_from=


## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-i|-w)
		[ -z "$head_from" ] || die "-i and -w are mutually exclusive"
		head_from="$arg";;
	-*)
		echo "Usage: tg [...] files [-i | -w] [<name>]" >&2
		exit 1;;
	*)
		[ -z "$name" ] || die "name already specified ($name)"
		name="$arg";;
	esac
done


head="$(git symbolic-ref HEAD)"
head="${head#refs/heads/}"

[ -n "$name" ] ||
	name="$head"
base_rev="$(git rev-parse --short --verify "refs/top-bases/$name" 2>/dev/null)" ||
	die "not a TopGit-controlled branch"

if [ -n "$head_from" ] && [ "$name" != "$head" ]; then
	die "$head_from makes only sense for the current branch"
fi

b_tree=$(pretty_tree "$name" -b)
t_tree=$(pretty_tree "$name" $head_from)

git diff-tree --name-only -r $b_tree $t_tree

# vim:noet

