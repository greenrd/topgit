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
			git rev-parse -q --verify "refs/top-bases${head_#refs/heads}" >/dev/null || exit 0;;
		*)
			exit 0;;
	esac

else
	exit 0;
fi

# TODO: check the index, not the working copy
[ -s "$root_dir/.topdeps" ] ||
	die ".topdeps is missing"
[ -s "$root_dir/.topmsg" ] ||
	die ".topmsg is missing"

# TODO: Verify .topdeps for valid branch names and against cycles
