#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

force= # Whether to delete non-empty branch, or branch where only the base is left.
name=


## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-f)
		force=1;;
	-*)
		echo "Usage: tg [...] delete [-f] NAME" >&2
		exit 1;;
	*)
		[ -z "$name" ] || die "name already specified ($name)"
		name="$arg";;
	esac
done


## Sanity checks

[ -n "$name" ] || die "no branch name specified"
branchrev="$(git rev-parse --verify "$name" 2>/dev/null)" ||
	if [ -n "$force" ]; then
		info "invalid branch name: $name; assuming it has been deleted already"
	else
		die "invalid branch name: $name"
	fi
baserev="$(git rev-parse --verify "refs/top-bases/$name" 2>/dev/null)" ||
	die "not a TopGit topic branch: $name"
! git symbolic-ref HEAD >/dev/null || [ "$(git symbolic-ref HEAD)" != "refs/heads/$name" ] ||
	die "cannot delete your current branch"

[ -z "$force" ] && { branch_empty "$name" || die "branch is non-empty: $name"; }


## Wipe out

git update-ref -d "refs/top-bases/$name" "$baserev"
[ -z "$branchrev" ] || git update-ref -d "refs/heads/$name" "$branchrev"

# vim:noet
