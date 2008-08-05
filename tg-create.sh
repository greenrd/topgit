#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

deps= # List of dependent branches
restarted= # Set to 1 if we are picking up in the middle of base setup
merge= # List of branches to be merged; subset of $deps
name=


## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-*)
		echo "Usage: tg create NAME [DEPS...]" >&2
		exit 1;;
	*)
		if [ -z "$name" ]; then
			name="$arg"
		else
			deps="$deps $arg"
		fi;;
	esac
done


## Auto-guess dependencies

deps="${deps# }"
if [ -z "$deps" ]; then
	head="$(git symbolic-ref HEAD)"
	bname="${head#refs/top-bases/}"
	if [ "$bname" != "$head" -a -s "$git_dir/top-deps" -a -s "$git_dir/top-merge" ]; then
		# We are on a base branch now; resume merge!
		deps="$(cat "$git_dir/top-deps")"
		merge="$(cat "$git_dir/top-merge")"
		name="$bname"
		restarted=1
		info "Resuming $name setup..."
	else
		# The common case
		[ -z "$name" ] && die "no branch name given"
		deps="${head#refs/heads/}"
		[ "$deps" != "$head" ] || die "refusing to auto-depend on non-head ref ($head)"
		info "Automatically marking dependency on $deps"
	fi
fi

[ -n "$merge" -o -n "$restarted" ] || merge="$deps "

for d in $deps; do
	git rev-parse --verify "$d" >/dev/null 2>&1 ||
		die "unknown branch dependency '$d'"
done
! git rev-parse --verify "$name" >/dev/null 2>&1 ||
	die "branch '$name' already exists"

# Clean up any stale stuff
rm -f "$git_dir/top-deps" "$git_dir/top-merge"


## Create base

if [ -n "$merge" ]; then
	# Unshift the first item from the to-merge list
	branch="${merge%% *}"
	merge="${merge#* }"
	info "Creating $name base from $branch..."
	switch_to_base "$name" "$branch"
fi


## Merge other dependencies into the base

while [ -n "$merge" ]; do
	# Unshift the first item from the to-merge list
	branch="${merge%% *}"
	merge="${merge#* }"
	info "Merging $name base with $branch..."

	if ! git merge "$branch"; then
		info "Please commit merge resolution and call: tg create"
		info "It is also safe to abort this operation using \`git reset --hard\`"
		info "but please remember you are on the base branch now;"
		info "you will want to switch to a different branch."
		echo "$deps" >"$git_dir/top-deps"
		echo "$merge" >"$git_dir/top-merge"
		exit 2
	fi
done


## Set up the topic branch

git checkout -b "$name"

echo "$deps" | sed 's/ /\n/g' >"$root_dir/.topdeps"
git add "$root_dir/.topdeps"

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
	cat <<EOT
<patch description>

Signed-off-by: $author_addr
EOT
} >"$root_dir/.topmsg"
git add "$root_dir/.topmsg"



info "Topic branch $name set up. Please fill .topmsg now and make initial commit."
info "To abort: git rm -f .top* && git checkout ${deps%% *} && tg delete $name"
