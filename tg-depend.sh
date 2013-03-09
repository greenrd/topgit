#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

name=


usage()
{
    echo "Usage: tg [...] depend add <name>" >&2
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

# Check that we are on a TopGit branch.
current_name="$(git symbolic-ref HEAD | sed 's#^refs/\(heads\|top-bases\)/##')"
current_base_rev="$(git rev-parse --short --verify "refs/top-bases/$current_name" 2>/dev/null)" ||
	die "not a TopGit-controlled branch"

## Record new dependency
depend_add()
{
	[ "$name" = "$current_name" ] &&
		die "$name cannot depend on itself."

	{ $tg summary --deps; echo "$current_name" "$name"; } |
		tsort >/dev/null ||
		die "tg: that dependency would introduce a dependency loop"

	grep -F -x -e "$name" "$root_dir/.topdeps" >/dev/null &&
		die "tg: $current_name already depends on $name"

	echo "$name" >>"$root_dir/.topdeps"
	git add -f "$root_dir/.topdeps"
	git commit -m"New TopGit dependency: $name"
	$tg update
}

depend_$subcmd

# vim:noet
