#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

name=
topic=


## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-i)
		[ -z "$topic" ] || die "-i and -w are mutually exclusive"
		topic=-i;;
	-w)
		[ -z "$topic" ] || die "-i and -w are mutually exclusive"
		topic=-w;;
	-*)
		echo "Usage: tg [...] files [-i | -w] [NAME]" >&2
		exit 1;;
	*)
		[ -z "$name" ] || die "name already specified ($name)"
		name="$arg";;
	esac
done


[ -n "$name" -a -n "$topic" ] &&
	die "-i/-w are mutually exclusive with NAME"

[ -n "$name" ] || name="$(git symbolic-ref HEAD | sed 's#^refs/\(heads\|top-bases\)/##')"
base_rev="$(git rev-parse --short --verify "refs/top-bases/$name" 2>/dev/null)" ||
	die "not a TopGit-controlled branch"

b_tree=$(pretty_tree "$name" -b)
t_tree=$(pretty_tree "$name" $topic)

git diff-tree --name-only -r $b_tree $t_tree

# vim:noet
