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
			head_="${head_#refs/heads/}"
			git rev-parse -q --verify "refs/top-bases/$head_" >/dev/null || exit 0;;
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

check_cycle_name()
{
	[ "$head_" != "$_dep" ] ||
		die "TopGit dependencies form a cycle: perpetrator is $_name"
}

# we only need to check newly added deps and for these if a path exists to the
# current HEAD
git diff --cached "$root_dir/.topdeps" |
	awk '
BEGIN      { in_hunk = 0; }
/^@@ /     { in_hunk = 1; }
/^\+/      { if (in_hunk == 1) printf("%s\n", substr($0, 2)); }
/^[^@ +-]/ { in_hunk = 0; }
' |
	while read newly_added; do
		ref_exists "$newly_added" ||
			die "Invalid branch as dependent: $newly_added"

		# check for self as dep
		[ "$head_" != "$newly_added" ] ||
			die "Can't have myself as dep"

		# deps can be non-tgish but we can't run recurse_deps() on them
		ref_exists "refs/top-bases/$newly_added" ||
			continue

		# recurse_deps uses dfs but takes the .topdeps from the tree,
		# therefore no endless loop in the cycle-check
		no_remotes=1 recurse_deps check_cycle_name "$newly_added"
	done

# check for repetitions of deps
depdir="$(get_temp tg-depdir -d)" ||
	die "Can't check for multiple occurrences of deps"
cat_file "$head_:.topdeps" -i |
	while read dep; do
		[ ! -d "$depdir/$dep" ] ||
			die "Multiple occurrences of the same dep: $dep"
		mkdir -p "$depdir/$dep" ||
			die "Can't check for multiple occurrences of deps"
	done
