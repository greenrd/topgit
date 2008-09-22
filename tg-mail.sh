#!/bin/sh
# TopGit - A different patch queue manager
# GPLv2

name=


## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-*)
		echo "Usage: tg [...] mail [NAME]" >&2
		exit 1;;
	*)
		[ -z "$name" ] || die "name already specified ($name)"
		name="$arg";;
	esac
done

[ -n "$name" ] || name="$(git symbolic-ref HEAD | sed 's#^refs/heads/##')"
base_rev="$(git rev-parse --short --verify "refs/top-bases/$name" 2>/dev/null)" ||
	die "not a TopGit-controlled branch"


patchfile="$(mktemp -t tg-mail.XXXXXX)"

$tg patch $name >"$patchfile"

hlines=$(grep -n -m 1 '^---' "$patchfile" | sed 's/:---//')
header=$(head -n $(($hlines - 1)) "$patchfile")



from="$(echo "$header" | grep '^From:' | sed 's/From:\s*//')"
to="$(echo "$header" | grep '^To:' | sed 's/To:\s*//')"


# XXX: I can't get quoting right without arrays
people=()
[ -n "$from" ] && people=("${people[@]}" --from "$from")
# FIXME: there could be multimple To
[ -n "$to" ]   && people=("${people[@]}" --to "$to")


# NOTE: git-send-email handles cc itself
git send-email "${people[@]}" "$patchfile"

rm "$patchfile"
