#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2


## Set up all the tg machinery

set -e
tg__include=1
tg_util() {
	. "@bindir@"/tg
}
tg_util


## Generally have fun

# Don't do anything on non-topgit branch
if head_=$(git symbolic-ref -q HEAD); then
	case "$head_" in
		refs/heads/*)
			git rev-parse -q --verify "refs/top-bases${head_#refs/heads}" >/dev/null || exit 0;;
		*)
			exit 0;;
	esac

else
	exit 0;
fi

check_topfile()
{
	local tree file ls_line type size
	tree=$1
	file=$2

	ls_line="$(git ls-tree --long "$tree" "$file")" ||
		die "Can't ls tree for $file"

	[ -n "$ls_line" ] ||
		die "$file is missing"

	# check for type and size
	set -- $ls_line
	type=$2
	size=$4

	# check file is of type blob (file)
	[ "x$type" = "xblob" ] ||
		die "$file is not a file"

	# check for positive size
	[ "$size" -gt 0 ] ||
		die "$file has empty size"
}

tree=$(git write-tree) ||
	die "Can't write tree"

check_topfile "$tree" ".topdeps"
check_topfile "$tree" ".topmsg"

# TODO: Verify .topdeps for valid branch names and against cycles
