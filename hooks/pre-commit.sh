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
git rev-parse --verify "$(git symbolic-ref HEAD | sed 's/heads/top-bases/')" >/dev/null 2>&1 ||
	exit 0

[ -s "$root_dir/.topdeps" ] ||
	die ".topdeps is missing"
[ -s "$root_dir/.topmsg" ] ||
	die ".topmsg is missing"

# TODO: Verify .topdeps for valid branch names and against cycles
