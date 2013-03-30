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
git commit -m"TopGit branch $name annihilated."

info 'If you have shared your work, you might want to run `tg push` now.'
info 'Then you probably want to switch to another branch.'
info "You are still on $name"

# vim:noet
