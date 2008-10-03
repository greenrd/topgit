#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

name=
branches=
output=
driver=collapse


## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-b)
		branches="$1"; shift;;
	--quilt)
		driver=quilt;;
	--collapse)
		driver=collapse;;
	-*)
		echo "Usage: tg [...] export ([--collapse] NEWBRANCH | [-b BRANCH1,BRANCH2...] --quilt DIRECTORY)" >&2
		exit 1;;
	*)
		[ -z "$output" ] || die "output already specified ($output)"
		output="$arg";;
	esac
done


name="$(git symbolic-ref HEAD | sed 's#^refs/heads/##')"
base_rev="$(git rev-parse --short --verify "refs/top-bases/$name" 2>/dev/null)" ||
	die "not on a TopGit-controlled branch"

[ -z "$branches" -o "$driver" = "quilt" ] ||
	die "-b works only with the quilt driver"


playground="$(mktemp -d -t tg-export.XXXXXX)"
trap 'rm -rf "$playground"' EXIT


## Collapse driver

# pretty_tree NAME
# Output tree ID of a cleaned-up tree without tg's artifacts.
pretty_tree()
{
	(export GIT_INDEX_FILE="$playground/^index"
	 git read-tree "$1"
	 git update-index --force-remove ".topmsg" ".topdeps"
	 git write-tree)
}

# collapsed_commit NAME
# Produce a collapsed commit of branch NAME.
collapsed_commit()
{
	name="$1"

	rm -f "$playground/^pre" "$playground/^post"
	>"$playground/^body"

	# Get commit message and authorship information
	git cat-file blob "$name:.topmsg" | git mailinfo "$playground/^msg" /dev/null > "$playground/^info"

	GIT_AUTHOR_NAME="$(sed -n '/^Author/ s/Author: //p' "$playground/^info")"
	GIT_AUTHOR_EMAIL="$(sed -n '/^Email/ s/Email: //p' "$playground/^info")"
	GIT_AUTHOR_DATE="$(sed -n '/^Date/ s/Date: //p' "$playground/^info")"
	SUBJECT="$(sed -n '/^Subject/ s/Subject: //p' "$playground/^info")"

	test -n "$GIT_AUTHOR_NAME" && export GIT_AUTHOR_NAME
	test -n "$GIT_AUTHOR_EMAIL" && export GIT_AUTHOR_EMAIL
	test -n "$GIT_AUTHOR_DATE" && export GIT_AUTHOR_DATE

	# Determine parent
	parent="$(cut -f 1 "$playground/$name^parents")"
	if [ "$(cat "$playground/$name^parents" | wc -l)" -gt 1 ]; then
		# Produce a merge commit first
		parent="$({
			echo "TopGit-driven merge of branches:"
			echo
			cut -f 2 "$playground/$name^parents"
		} | git commit-tree "$(pretty_tree "refs/top-bases/$name")" \
			$(for p in $parent; do echo -p $p; done))"
	fi

	(printf '%s\n\n' "$SUBJECT"; cat "$playground/^msg") |
	git stripspace |
	git commit-tree "$(pretty_tree "$name")" -p "$parent"

	echo "$name" >>"$playground/^ticker"
}

# collapse
# This will collapse a single branch, using information about
# previously collapsed branches stored in $playground.
collapse()
{
	if [ -s "$playground/$_dep" ]; then
		# We've already seen this dep
		commit="$(cat "$playground/$_dep")"

	elif [ -z "$_dep_is_tgish" ]; then
		# This dep is not for rewrite
		commit="$(git rev-parse --verify "$_dep")"

	else
		# First time hitting this dep; the common case
		echo "Collapsing $_dep"
		commit="$(collapsed_commit "$_dep")"
		mkdir -p "$playground/$(dirname "$_dep")"
		echo "$commit" >"$playground/$_dep"
	fi

	# Propagate our work through the dependency chain
	mkdir -p "$playground/$(dirname "$_name")"
	echo "$commit	$_dep" >>"$playground/$_name^parents"
}


## Quilt driver

quilt()
{
	if [ -z "$_dep_is_tgish" ]; then
		# This dep is not for rewrite
		return
	fi

	filename="$output/$_dep.diff"
	if [ -e "$filename" ]; then
		# We've already seen this dep
		return
	fi

	echo "Exporting $_dep"
	mkdir -p "$(dirname "$filename")"
	$tg patch "$_dep" >"$filename"
	echo "$_dep.diff -p1" >>"$output/series"
}


## Machinery

if [ "$driver" = "collapse" ]; then
	[ -n "$output" ] ||
		die "no target branch specified"
	! ref_exists "$output"  ||
		die "target branch '$output' already exists; first run: git branch -D $output"

elif [ "$driver" = "quilt" ]; then
	[ -n "$output" ] ||
		die "no target directory specified"
	[ ! -e "$output" ] ||
		die "target directory already exists: $output"

	mkdir -p "$output"
fi


driver()
{
	case $_dep in refs/remotes/*) return;; esac
	branch_needs_update >/dev/null
	[ "$_ret" -eq 0 ] ||
		die "cancelling export of $_dep (-> $_name): branch not up-to-date"

	$driver
}

# Call driver on all the branches - this will happen
# in topological order.
if [ -z "$branches" ]; then
	recurse_deps driver "$name"
	(_ret=0; _dep="$name"; _name=""; _dep_is_tgish=1; driver)
else
	echo "$branches" | tr ',' '\n' | while read _dep; do
		_dep_is_tgish=1
		$driver
	done
	name="$(echo "$branches" | sed 's/.*,//')"
fi


if [ "$driver" = "collapse" ]; then
	git update-ref "refs/heads/$output" "$(cat "$playground/$name")" ""

	depcount="$(cat "$playground/^ticker" | wc -l)"
	echo "Exported topic branch $name (total $depcount topics) to branch $output"

elif [ "$driver" = "quilt" ]; then
	depcount="$(cat "$output/series" | wc -l)"
	echo "Exported topic branch $name (total $depcount topics) to directory $output"
fi
