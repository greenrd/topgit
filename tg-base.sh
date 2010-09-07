#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# (c) Per Cederqvist <ceder@lysator.liu.se>  2010
# GPLv2

## Parse options

case "$1" in
	-h|--help)
		echo "Usage: tg [...] base [ branch... ]" >&2
		exit 0;;
	*)
		break;;
esac

if [ "$#" -eq 0 ]; then
	set -- HEAD
fi

rv=0
for rev in "$@"; do
	name="$( { git symbolic-ref -q "$rev" || echo "$rev"; } | sed 's#^refs/\(heads\|top-bases\)/##')"
	base_rev="$(git rev-parse --short --verify "refs/top-bases/$name" 2>/dev/null)" || {
		rv=1
		echo $rev is not a TopGit branch >&2
	}
	echo $base_rev
done
exit $rv
