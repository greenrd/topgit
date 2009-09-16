#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

name=
branches=
output=
driver=collapse
flatten=false
numbered=false


## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-b)
		branches="$1"; shift;;
	--flatten)
		flatten=true;;
	--numbered)
		flatten=true;
		numbered=true;;
	--quilt)
		driver=quilt;;
	--collapse)
		driver=collapse;;
	--linearize)
		driver=linearize;;
	-*)
		echo "Usage: tg [...] export ([--collapse] NEWBRANCH | [-b BRANCH1,BRANCH2...] --quilt DIRECTORY | --linearize NEWBRANCH)" >&2
		exit 1;;
	*)
		[ -z "$output" ] || die "output already specified ($output)"
		output="$arg";;
	esac
done



[ -z "$branches" -o "$driver" = "quilt" ] ||
	die "-b works only with the quilt driver"

[ "$driver" = "quilt" ] || ! "$numbered" ||
	die "--numbered works only with the quilt driver";

[ "$driver" = "quilt" ] || ! "$flatten" ||
	die "--flatten works only with the quilt driver"

if [ -z "$branches" ]; then
	# this check is only needed when no branches have been passed
	name="$(git symbolic-ref HEAD | sed 's#^refs/heads/##')"
	base_rev="$(git rev-parse --short --verify "refs/top-bases/$name" 2>/dev/null)" ||
		die "not on a TopGit-controlled branch"
fi


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

create_tg_commit()
{
	name="$1"
	tree="$2"
	parent="$3"

	# Get commit message and authorship information
	git cat-file blob "$name:.topmsg" | git mailinfo "$playground/^msg" /dev/null > "$playground/^info"

	GIT_AUTHOR_NAME="$(sed -n '/^Author/ s/Author: //p' "$playground/^info")"
	GIT_AUTHOR_EMAIL="$(sed -n '/^Email/ s/Email: //p' "$playground/^info")"
	GIT_AUTHOR_DATE="$(sed -n '/^Date/ s/Date: //p' "$playground/^info")"
	SUBJECT="$(sed -n '/^Subject/ s/Subject: //p' "$playground/^info")"

	test -n "$GIT_AUTHOR_NAME" && export GIT_AUTHOR_NAME
	test -n "$GIT_AUTHOR_EMAIL" && export GIT_AUTHOR_EMAIL
	test -n "$GIT_AUTHOR_DATE" && export GIT_AUTHOR_DATE

	(printf '%s\n\n' "$SUBJECT"; cat "$playground/^msg") |
	git stripspace |
	git commit-tree "$tree" -p "$parent"
}

# collapsed_commit NAME
# Produce a collapsed commit of branch NAME.
collapsed_commit()
{
	name="$1"

	rm -f "$playground/^pre" "$playground/^post"
	>"$playground/^body"

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

	if branch_empty "$name"; then
		echo "$parent";
	else
		create_tg_commit "$name" "$(pretty_tree $name)" "$parent"
	fi;

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

	if "$flatten"; then
		bn="$(echo "$_dep.diff" | sed -e 's#_#__#g' -e 's#/#_#g')";
		dn="";
	else
		bn="$(basename "$_dep.diff")";
		dn="$(dirname "$_dep.diff")/";
		if [ "x$dn" = "x./" ]; then
			dn="";
		fi;
	fi;

	if [ -e "$playground/$_dep" ]; then
		# We've already seen this dep
		return
	fi

	mkdir -p "$playground/$(dirname "$_dep")";
	touch "$playground/$_dep";

	if branch_empty "$_dep"; then
		echo "Skip empty patch $_dep";
	else
		if "$numbered"; then
			number="$(echo $(($(cat "$playground/^number" 2>/dev/null) + 1)))";
			bn="$(printf "%04u-$bn" $number)";
			echo "$number" >"$playground/^number";
		fi;

		echo "Exporting $_dep"
		mkdir -p "$output/$dn";
		$tg patch "$_dep" >"$output/$dn$bn"
		echo "$dn$bn -p1" >>"$output/series"
	fi
}

linearize()
{
	if test ! -f "$playground/^BASE"; then
		head="$(git rev-parse --verify "$_dep")"
		echo "$head" > "$playground/^BASE"
		git checkout -q "$head"
		return;
	fi;

	head=$(git rev-parse --verify HEAD)

	if [ -z "$_dep_is_tgish" ]; then
		# merge in $_dep unless already included
		rev="$(git rev-parse --verify "$_dep")";
		common="$(git merge-base --all HEAD "$_dep")";
		if test "$rev" = "$common"; then
			# already included, just skip
			:;
		else
			retmerge=0;

			git merge -s recursive "$_dep" || retmerge="$?";
			if test "x$retmerge" != "x0"; then
				echo fix up the merge, commit and then exit;
				#todo error handling
				sh -i </dev/tty;
			fi;
		fi;
	else
		retmerge=0;

		git merge-recursive "$(pretty_tree "refs/top-bases/$_dep")" -- HEAD "$(pretty_tree "refs/heads/$_dep")" || retmerge="$?";

		if test "x$retmerge" != "x0"; then
			git rerere;
			echo "fix up the merge and update the index.  Don't commit!"
			#todo error handling
			sh -i </dev/tty;
		fi

		result_tree=$(git write-tree)
		# testing branch_empty might not always give the right answer.
		# It can happen that the patch is non-empty but still after
		# linearizing there is no change.  So compare the trees.
		if test "x$result_tree" = "x$(git rev-parse $head^{tree})"; then
			echo "skip empty commit $_dep";
		else
			newcommit=$(create_tg_commit "$_dep" "$result_tree" HEAD)
			git update-ref HEAD $newcommit $head
			echo "exported commit $_dep";
		fi
	fi
}

## Machinery

if [ "$driver" = "collapse" ] || [ "$driver" = "linearize" ]; then
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

elif [ "$driver" = "linearize" ]; then
	git checkout -q -b $output

	echo $name
	if test $(git rev-parse "$(pretty_tree $name)^{tree}") != $(git rev-parse "HEAD^{tree}"); then
		echo "Warning: Exported result doesn't match";
		echo "tg-head=$(git rev-parse "$name"), exported=$(git rev-parse "HEAD")";
		#git diff $head HEAD;
	fi;

fi

# vim:noet
