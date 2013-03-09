#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

deps= # List of dependent branches
restarted= # Set to 1 if we are picking up in the middle of base setup
merge= # List of branches to be merged; subset of $deps
name=
rname= # Remote branch to base this one on


## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-r)
		rname="$1"; shift;;
	-*)
		echo "Usage: tg [...] create [<name> [<dep>...|-r <rname>] ]" >&2
		exit 1;;
	*)
		if [ -z "$name" ]; then
			name="$arg"
		else
			deps="$deps $arg"
		fi;;
	esac
done


## Fast-track creating branches based on remote ones

if [ -n "$rname" ]; then
	[ -n "$name" ] || die "no branch name given"
	! ref_exists "$name" || die "branch '$name' already exists"
	has_remote "$rname" || die "no branch $rname in remote $base_remote"

	git update-ref "refs/top-bases/$name" "refs/remotes/$base_remote/top-bases/$rname"
	git update-ref "refs/heads/$name" "refs/remotes/$base_remote/$rname"
	info "Topic branch $name based on $base_remote : $rname set up."
	exit 0
fi


## Auto-guess dependencies

deps="${deps# }"
if [ -z "$deps" ]; then
	if [ -z "$name" -a -s "$git_dir/top-name" -a -s "$git_dir/top-deps" -a -s "$git_dir/top-merge" ]; then
		# We are setting up the base branch now; resume merge!
		name="$(cat "$git_dir/top-name")"
		deps="$(cat "$git_dir/top-deps")"
		merge="$(cat "$git_dir/top-merge")"
		restarted=1
		info "Resuming $name setup..."
	else
		# The common case
		[ -z "$name" ] && die "no branch name given"
		head="$(git symbolic-ref HEAD)"
		deps="${head#refs/heads/}"
		[ "$deps" != "$head" ] || die "refusing to auto-depend on non-head ref ($head)"
		info "Automatically marking dependency on $deps"
	fi
fi

[ -n "$merge" -o -n "$restarted" ] || merge="$deps "

for d in $deps; do
	ref_exists "$d"  ||
		die "unknown branch dependency '$d'"
done
! ref_exists "$name"  ||
	die "branch '$name' already exists"

# Clean up any stale stuff
rm -f "$git_dir/top-name" "$git_dir/top-deps" "$git_dir/top-merge"


## Find starting commit to create the base

if [ -n "$merge" -a -z "$restarted" ]; then
	# Unshift the first item from the to-merge list
	branch="${merge%% *}"
	merge="${merge#* }"
	info "Creating $name base from $branch..."
	# We create a detached head so that we can abort this operation
	git checkout -q "$(git rev-parse "$branch")"
fi


## Merge other dependencies into the base

while [ -n "$merge" ]; do
	# Unshift the first item from the to-merge list
	branch="${merge%% *}"
	merge="${merge#* }"
	info "Merging $name base with $branch..."

	if ! git merge "$branch"; then
		info "Please commit merge resolution and call: $tg create"
		info "It is also safe to abort this operation using:"
		info "git reset --hard some_branch"
		info "(You are on a detached HEAD now.)"
		echo "$name" >"$git_dir/top-name"
		echo "$deps" >"$git_dir/top-deps"
		echo "$merge" >"$git_dir/top-merge"
		exit 2
	fi
done


## Set up the topic branch

git update-ref "refs/top-bases/$name" "HEAD" ""
git checkout -b "$name"

echo "$deps" | sed 's/ /\n/g' >"$root_dir/.topdeps"
git add -f "$root_dir/.topdeps"

author="$(git var GIT_AUTHOR_IDENT)"
author_addr="${author%> *}>"
{
	echo "From: $author_addr"
	! header="$(git config topgit.to)" || echo "To: $header"
	! header="$(git config topgit.cc)" || echo "Cc: $header"
	! header="$(git config topgit.bcc)" || echo "Bcc: $header"
	! subject_prefix="$(git config topgit.subjectprefix)" || subject_prefix="$subject_prefix "
	echo "Subject: [${subject_prefix}PATCH] $name"
	echo
	echo '<patch description>'
	echo
	[ "$(git config --bool format.signoff)" = true ] && echo "Signed-off-by: $author_addr"
} >"$root_dir/.topmsg"
git add -f "$root_dir/.topmsg"



info "Topic branch $name set up. Please fill .topmsg now and make initial commit."
info "To abort: git rm -f .top* && git checkout ${deps%% *} && $tg delete $name"

# vim:noet
