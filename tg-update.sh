#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

name= # Branch to update
all= # Update all branches
pattern= # Branch selection filter for -a
current= # Branch we are currently on


## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-a)
		all=1;;
	-*)
		echo "Usage: tg [...] update ([<name>] | -a [<pattern>...])" >&2
		exit 1;;
	*)
		if [ -z "$all" ]; then
			[ -z "$name" ] || die "name already specified ($name)"
			name="$arg"
		else
			pattern="$pattern refs/top-bases/${arg#refs/top-bases/}"
		fi
		;;
	esac
done
[ -z "$pattern" ] && pattern=refs/top-bases

current="$(strip_ref "$(git symbolic-ref HEAD 2>/dev/null)")"
if [ -z "$all" ]; then
	if [ -z "$name" ]; then
		name="$current"
		base_rev="$(git rev-parse --short --verify "refs/top-bases/$name" 2>/dev/null)" ||
			die "not a TopGit-controlled branch"
	fi
else
	[ -n "$current" ] || die "cannot return to detached tree; switch to another branch"
fi

ensure_clean_tree

recursive_update() {
	$tg update
	_ret=$?
	[ $_ret -eq 3 ] && exit 3
	return $_ret
}

update_branch() {
	_update_name="$1"
	## First, take care of our base

	_depcheck="$(get_temp tg-depcheck)"
	missing_deps=
	needs_update "$_update_name" >"$_depcheck" || :
	if [ -n "$missing_deps" ]; then
	   	if [ -z "$all" ]; then
		       	die "some dependencies are missing: $missing_deps"
		else
		       	info "some dependencies are missing: $missing_deps; skipping"
		       	return
		fi
	fi
	if [ -s "$_depcheck" ]; then
		# We need to switch to the base branch
		# ...but only if we aren't there yet (from failed previous merge)
		_HEAD="$(git symbolic-ref HEAD)"
		if [ "$_HEAD" = "${_HEAD#refs/top-bases/}" ]; then
			switch_to_base "$_update_name"
		fi

		cat "$_depcheck" |
			sed 's/ [^ ]* *$//' | # last is $_update_name
			sed 's/.* \([^ ]*\)$/+\1/' | # only immediate dependencies
			sed 's/^\([^+]\)/-\1/' | # now each line is +branch or -branch (+ == recurse)
			uniq -s 1 | # fold branch lines; + always comes before - and thus wins within uniq
			while read depline; do
				action="$(echo "$depline" | cut -c 1)"
				dep="$(echo "$depline" | cut -c 2-)"

				# We do not distinguish between dependencies out-of-date
				# and base/remote out-of-date cases for $dep here,
				# but thanks to needs_update returning : or %
				# for the latter, we do correctly recurse here
				# in both cases.

				if [ x"$action" = x+ ]; then
					info "Recursing to $dep..."
					git checkout -q "$dep"
					(
					export TG_RECURSIVE="[$dep] $TG_RECURSIVE"
					export PS1="[$dep] $PS1"
					while ! recursive_update; do
						# The merge got stuck! Let the user fix it up.
						info "You are in a subshell. If you abort the merge,"
						info "use \`exit 1\` to abort the recursive update altogether."
						info "Use \`exit 2\` to skip updating this branch and continue."
						if sh -i </dev/tty; then
							# assume user fixed it
							continue
						else
							ret=$?
							if [ $ret -eq 2 ]; then
								info "Ok, I will try to continue without updating this branch."
								break
							else
								info "Ok, you aborted the merge. Now, you just need to"
								info "switch back to some sane branch using \`git checkout\`."
								exit 3
							fi
						fi
					done
					)
					switch_to_base "$_update_name"
				fi

				# This will be either a proper topic branch
				# or a remote base.  (branch_needs_update() is called
				# only on the _dependencies_, not our branch itself!)

				info "Updating base with $dep changes..."
				if ! git merge "$dep"; then
					if [ -z "$TG_RECURSIVE" ]; then
						resume="\`git checkout $_update_name && $tg update\` again"
					else # subshell
						resume='exit'
					fi
					info "Please commit merge resolution and call $resume."
					info "It is also safe to abort this operation using \`git reset --hard\`,"
					info "but please remember that you are on the base branch now;"
					info "you will want to switch to some normal branch afterwards."
					rm "$_depcheck"
					exit 2
				fi
			done
	else
		info "The base is up-to-date."
	fi

	# Home, sweet home...
	# (We want to always switch back, in case we were on the base from failed
	# previous merge.)
	git checkout -q "$_update_name"

	merge_with="refs/top-bases/$_update_name"


	## Second, update our head with the remote branch

	if has_remote "$_update_name"; then
		_rname="refs/remotes/$base_remote/$_update_name"
		if branch_contains "$_update_name" "$_rname"; then
			info "The $_update_name head is up-to-date wrt. its remote branch."
		else
			info "Reconciling remote branch updates with $_update_name base..."
			# *DETACH* our HEAD now!
			git checkout -q "refs/top-bases/$_update_name"
			if ! git merge "$_rname"; then
				info "Oops, you will need to help me out here a bit."
				info "Please commit merge resolution and call:"
				info "git checkout $_update_name && git merge <commitid>"
				info "It is also safe to abort this operation using: git reset --hard $_update_name"
				exit 4
			fi
			# Go back but remember we want to merge with this, not base
			merge_with="$(git rev-parse HEAD)"
			git checkout -q "$_update_name"
		fi
	fi


	## Third, update our head with the base

	if branch_contains "$_update_name" "$merge_with"; then
		info "The $_update_name head is up-to-date wrt. the base."
		return 0
	fi
	info "Updating $_update_name against new base..."
	if ! git merge "$merge_with"; then
		if [ -z "$TG_RECURSIVE" ]; then
			info "Please commit merge resolution. No need to do anything else"
			info "You can abort this operation using \`git reset --hard\` now"
			info "and retry this merge later using \`$tg update\`."
		else # subshell
			info "Please commit merge resolution and call exit."
			info "You can abort this operation using \`git reset --hard\`."
		fi
		exit 4
	fi
}

[ -z "$all" ] && { update_branch $name; exit; }

non_annihilated_branches $pattern |
	while read name; do
		info "Proccessing $name..."
		update_branch "$name" || exit
	done

info "Returning to $current..."
git checkout -q "$current"
# vim:noet
