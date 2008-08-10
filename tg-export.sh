#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

name=
output=


## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-*)
		echo "Usage: tg export NEWBRANCH" >&2
		exit 1;;
	*)
		[ -z "$output" ] || die "new branch already specified ($output)"
		output="$arg";;
	esac
done


name="$(git symbolic-ref HEAD | sed 's#^refs/heads/##')"
base_rev="$(git rev-parse --short --verify "refs/top-bases/$name" 2>/dev/null)" ||
	die "not on a TopGit-controlled branch"

[ -n "$output" ] ||
	die "no target branch specified"

! git rev-parse --verify "$output" >/dev/null 2>&1 ||
	die "target branch '$output' already exists; first run: git branch -D $output"


playground="$(mktemp -d)"
trap 'rm -rf "$playground"' EXIT

# Trusty Cogito code:
load_author()
{
	if [ -z "$GIT_AUTHOR_NAME" ] && echo "$1" | grep -q '^[^< ]'; then
		export GIT_AUTHOR_NAME="$(echo "$1" | sed 's/ *<.*//')"
	fi
	if [ -z "$GIT_AUTHOR_EMAIL" ] && echo "$1" | grep -q '<.*>'; then
		export GIT_AUTHOR_EMAIL="$(echo "$1" | sed 's/.*<\(.*\)>.*/\1/')"
	fi
}

# pretty_tree NAME
# Output tree ID of a cleaned-up tree without tg's artifacts.
pretty_tree()
{
	(export GIT_INDEX_FILE="$playground/^index"
	 git read-tree "$1"
	 git update-index --force-remove ".top*"
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
	git cat-file blob "$name:.topmsg" >"$playground/^msg"
	while read line; do
		if [ -z "$line" ]; then
			# end of header
			cat >"$playground/^body"
			break
		fi
		case "$line" in
		From:*) load_author "${line#From: }";;
		Subject:*) echo "${line#Subject: }" >>"$playground/^pre";;
		*) echo "$line" >>"$playground/^post";;
		esac
	done <"$playground/^msg"

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

	{
		if [ -s "$playground/^pre" ]; then
			cat "$playground/^pre"
			echo
		fi
		cat "$playground/^body"
		[ ! -s "$playground/^post" ] || cat "$playground/^post"
	} | git commit-tree "$(pretty_tree "$name")" -p "$parent"

	echo "$name" >>"$playground/^ticker"
}

# collapse_one
# This will collapse a single branch, using information about
# previously collapsed branches stored in $playground.
collapse_one()
{
	branch_needs_update >/dev/null
	[ "$_ret" -eq 0 ] ||
		die "cancelling $_ret export of $_dep (-> $_name): branch not up-to-date"

	if [ -s "$playground/$_dep" ]; then
		# We've already seen this dep
		commit="$(cat "$playground/$_dep")"

	elif [ -z "$_dep_is_tgish" ]; then
		# This dep is not for rewrite
		commit="$(git rev-parse --verify "$_dep")"

	else
		# First time hitting this dep; the common case
		commit="$(collapsed_commit "$_dep")"

		mkdir -p "$playground/$(dirname "$_dep")"
		echo "$commit" >"$playground/$_dep"
		echo "Collapsed $_dep"
	fi

	# Propagate our work through the dependency chain
	mkdir -p "$playground/$(dirname "$_name")"
	echo "$commit	$_dep" >>"$playground/$_name^parents"
}

# Collapse all the branches - this way, collapse_one will be
# called in topological order.
recurse_deps collapse_one "$name"
(_ret=0; _dep="$name"; _name=""; _dep_is_tgish=1; collapse_one)

git update-ref "refs/heads/$output" "$(cat "$playground/$name")"

depcount="$(cat "$playground/^ticker" | wc -l)"
echo "Exported topic branch $name (total $depcount topics) to branch $output"
