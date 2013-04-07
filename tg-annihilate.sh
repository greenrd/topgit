#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# (c) Per Cederqvist <ceder@lysator.liu.se>  2010
# GPLv2

force= # Whether to annihilate non-empty branch, or branch where only the base is left.


## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-f)
		force=1;;
	*)
		echo "Usage: tg [...] annihilate [-f]" >&2
		exit 1;;
	esac
done


## Sanity checks

name="$(git symbolic-ref HEAD | sed 's#^refs/heads/##')"
branchrev="$(git rev-parse --verify "$name" 2>/dev/null)" ||
	die "invalid branch name: $name"
baserev="$(git rev-parse --verify "refs/top-bases/$name" 2>/dev/null)" ||
	die "not a TopGit topic branch: $name"

[ -z "$force" ] && { branch_empty "$name" || die "branch is non-empty: $name"; }

## Annihilate
mb="$(git merge-base "refs/top-bases/$name" "$name")"
git read-tree "$mb^{tree}"
# Need to pass --no-verify in order to inhibit TopGit's pre-commit hook to run,
# which would bark upon missing .top* files.
git commit --no-verify -m"TopGit branch $name annihilated."

# Propagate the dependencies through to dependents (if any), if they don't already have them
dependencies="$(tg prev -w)"
tg next | while read dependent; do
	git checkout -f $dependent
	for dependency in $dependencies; do
		tg depend add "$dependency" 2>/dev/null
	done
done

info "If you have shared your work, you might want to run tg push $name now."
git status

# vim:noet
