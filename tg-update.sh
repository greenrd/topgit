#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

name=


## Parse options

if [ -n "$1" ]; then
	echo "Usage: tg update" >&2
	exit 1
fi


name="$(git symbolic-ref HEAD | sed 's#^refs/\(heads\|top-bases\)/##')"
base_rev="$(git rev-parse --short --verify "refs/top-bases/$name" 2>/dev/null)" ||
	die "not a TopGit-controlled branch"


## First, take care of our base

depcheck="$(mktemp)"
missing_deps=
needs_update "$name" >"$depcheck" || :
[ -z "$missing_deps" ] || die "some dependencies are missing: $missing_deps"
if [ -s "$depcheck" ]; then
	# We need to switch to the base branch
	# ...but only if we aren't there yet (from failed previous merge)
	HEAD="$(git symbolic-ref HEAD)"
	if [ "$HEAD" = "${HEAD#refs/top-bases/}" ]; then
		switch_to_base "$name"
	fi

	cat "$depcheck" |
		sed 's/ [^ ]* *$//' | # last is $name
		sed 's/.* \([^ ]*\)$/+\1/' | # only immediate dependencies
		sed 's/^\([^+]\)/-\1/' | # now each line is +branch or -branch (+ == recurse)
		uniq -s 1 | # fold branch lines; + always comes before - and thus wins within uniq
		while read depline; do
			action="${depline:0:1}"
			dep="${depline:1}"

			# We do not distinguish between dependencies out-of-date
			# and base out-of-date cases for $dep here, but thanks
			# to needs_update returning : for the latter, we do
			# correctly recurse here in both cases.

			if [ x"$action" = x+ ]; then
				info "Recursing to $dep..."
				git checkout -q "$dep"
				(
				export TG_RECURSIVE="[$dep] $TG_RECURSIVE"
				export PS1="[$dep] $PS1"
				while ! tg update; do
					# The merge got stuck! Let the user fix it up.
					info "You are in a subshell. If you abort the merge,"
					info "use \`exit 1\` to abort the recursive update altogether."
					if ! sh -i </dev/tty; then
						info "Ok, you aborated the merge. Now, you just need to"
						info "switch back to some sane branch using \`git checkout\`."
						exit 3
					fi
				done
				)
				switch_to_base "$name"
			fi

			info "Updating base with $dep changes..."
			if ! git merge "$dep"; then
				if [ -z "$TG_RECURSIVE" ]; then
					resume='`tg update` again'
				else # subshell
					resume='exit'
				fi
				info "Please commit merge resolution and call $resume."
				info "It is also safe to abort this operation using \`git reset --hard\`,"
				info "but please remember that you are on the base branch now;"
				info "you will want to switch to some normal branch afterwards."
				rm "$depcheck"
				exit 2
			fi
		done

	# Home, sweet home...
	git checkout -q "$name"
else
	info "The base is up-to-date."
fi
rm "$depcheck"


## Second, update our head with the base

if branch_contains "$name" "refs/top-bases/$name"; then
	info "The $name head is up-to-date wrt. the base."
	exit 0
fi
info "Updating $name against new base..."
if ! git merge "refs/top-bases/$name"; then
	if [ -z "$TG_RECURSIVE" ]; then
		info "Please commit merge resolution. No need to do anything else"
		info "You can abort this operation using \`git reset --hard\` now"
		info "and retry this merge later using \`tg update\`."
	else # subshell
		info "Please commit merge resolution and call exit."
		info "You can abort this operation using \`git reset --hard\`."
	fi
	exit 3
fi
