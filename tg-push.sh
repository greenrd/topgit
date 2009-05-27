#!/bin/sh
# TopGit - A different patch queue manager
# GPLv2

## Parse options

recurse_deps=true
tgish_deps_only=false
dry_run=

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	--no-deps)
		recurse_deps=false;;
	--dry-run)
		dry_run=--dry-run;;
	--tgish-only)
		tgish_deps_only=true;;
	-h|--help)
		echo "Usage: tg push [--dry-run] [--no-deps] [--tgish-only] [-r remote] branch*"
		exit 0;;
	-r)
		remote="$1"
		shift
		;;
	*)
		branches="$branches $arg";;
	esac
done

if [ -z "$remote" ]; then
	remote="$base_remote"
fi

if [ -z "$remote" ]; then
	die "no remote location given. Either use -r remote argument or set topgit.remote"
fi

if [ -z "$branches" ]; then
	branches="$(git symbolic-ref HEAD | sed 's#^refs/heads/##')"
fi

for name in $branches; do
	ref_exists "$name" || die "detached HEAD? Can't push $name"
done

_listfile="$(mktemp -t tg-push-listfile.XXXXXX)"
trap "rm -f \"$_listfile\"" 0

push_branch()
{
	# if so desired omit non tgish deps
	$tgish_deps_only && [ -z "$_dep_is_tgish" ] && return 0

	echo "$_dep" >> "$_listfile"
	[ -z "$_dep_is_tgish" ] ||
		echo "top-bases/$_dep" >> "$_listfile"
}

for name in $branches; do
	# current branch
	# re-use push_branch, which expects some pre-defined variables
	_dep="$name"
	_dep_is_tgish=1
	ref_exists "top-bases/$_dep" ||
		_dep_is_tgish=
	push_branch "$name"

	# deps but only if branch is tgish
	$recurse_deps && [ -n "$_dep_is_tgish" ] &&
		no_remotes=1 recurse_deps push_branch "$name"

	# remove multiple occurrences of the same branch
	sort -u "$_listfile" | xargs git push $dry_run "$remote"
done
