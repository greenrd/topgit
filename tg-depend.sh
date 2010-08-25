#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

name=


usage()
{
    echo "Usage: tg [...] depend add NAME" >&2
    exit 1
}

## Parse options

subcmd="$1"; shift || :
case "$subcmd" in
	-h|"")
		usage;;
	add)
		;;
	*)
		die "unknown subcommand ($subcmd)";;
esac

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-*)
		usage;;
	*)
		[ -z "$name" ] || die "name already specified ($name)"
		name="$arg";;
	esac
done


## Sanity checks

[ -n "$name" ] || die "no branch name specified"
branchrev="$(git rev-parse --verify "$name" 2>/dev/null)" ||
	die "invalid branch name: $name"

## Record new dependency
depend_add()
{
	echo "$name" >>"$root_dir/.topdeps"
	git add -f "$root_dir/.topdeps"
	git commit -m"New TopGit dependency: $name"
	$tg update
}

depend_$subcmd

# vim:noet
