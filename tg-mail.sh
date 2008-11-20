#!/bin/sh
# TopGit - A different patch queue manager
# GPLv2

name=
send_email_args=
in_reply_to=


## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-s)
		send_email_args="$1"; shift;;
	-r)
		in_reply_to="$1"; shift;;
	-*)
		echo "Usage: tg [...] mail [-s SEND_EMAIL_ARGS] [-r REFERENCE_MSGID] [NAME]" >&2
		exit 1;;
	*)
		[ -z "$name" ] || die "name already specified ($name)"
		name="$arg";;
	esac
done

[ -n "$name" ] || name="$(git symbolic-ref HEAD | sed 's#^refs/heads/##')"
base_rev="$(git rev-parse --short --verify "refs/top-bases/$name" 2>/dev/null)" ||
	die "not a TopGit-controlled branch"

if [ -n "$in_reply_to" ]; then
	send_email_args="$send_email_args --in-reply-to=$in_reply_to"
fi


patchfile="$(mktemp -t tg-mail.XXXXXX)"

$tg patch "$name" >"$patchfile"

header="$(sed -e '/^$/,$d' "$patchfile")"



from="$(echo "$header" | grep '^From:' | sed 's/From:\s*//')"
to="$(echo "$header" | grep '^To:' | sed 's/To:\s*//')"


people=
[ -n "$from" ] && people="$people --from '$from'"
# FIXME: there could be multimple To
[ -n "$to" ] && people="$people --to '$to'"

# NOTE: git-send-email handles cc itself
eval git send-email $send_email_args "$people" "$patchfile"

rm "$patchfile"

# vim:noet
