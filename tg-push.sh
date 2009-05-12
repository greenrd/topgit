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

push_branch()
{
	# if so desired omit non tgish deps
	$tgish_deps_only && [ -z "$_dep_is_tgish" ] && return 0

	echo "$_dep"
	local base="top-bases/$_dep"
	if ref_exists "$base"; then
		echo "top-bases/$_dep"
	else
		echo "warning, no base found $base" 1>&2
	fi
}

for name in $branches; do
	list="$(
		# deps
		if $recurse_deps; then
			no_remotes=1 recurse_deps push_branch "$name"
		fi
		# current branch
		_dep="$name"
		_dep_is_tgish=1
		push_branch "$name"
	)"
	echo "pushing:"; echo $list
	git push $dry_run "$remote" $list
done
