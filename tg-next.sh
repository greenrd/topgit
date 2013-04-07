#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# (c) Bert Wesarg <Bert.Wesarg@googlemail.com>  2009
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
		echo "Usage: tg next [-i | -w] [<name>]" >&2
		exit 1;;
	*)
		[ -z "$name" ] || die "name already specified ($name)"
		name="$arg";;
	esac
done

head="$(git rev-parse --abbrev-ref=loose HEAD)"
[ -n "$name" ] ||
	name="$head"

non_annihilated_branches |
	while read parent; do
		from=$head_from
		# select .topdeps source for HEAD branch
		[ "x$parent" = "x$head" ] ||
			from=

		cat_file "$parent:.topdeps" $from | fgrep -qx "$name" ||
			continue

		echo "$parent"
	done
