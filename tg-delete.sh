#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

force= # Whether to delete non-empty branch, or branch where only the base is left.
name= # Branch to delete
to_update= # Branches that depend on $name and need dependencies adjusted
deps_to_push= # Dependencies from deleted brach
current= # Branch we are currently on


## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-f)
		force=1;;
	-*)
		echo "Usage: tg [...] delete [-f] <name>" >&2
		exit 1;;
	*)
		[ -z "$name" ] || die "name already specified ($name)"
		name="$arg";;
	esac
done


## Sanity checks

[ -n "$name" ] || die "no branch name specified"
branchrev="$(git rev-parse --verify "$name" 2>/dev/null)" ||
	if [ -n "$force" ]; then
		info "invalid branch name: $name; assuming it has been deleted already"
	else
		die "invalid branch name: $name"
	fi
baserev="$(git rev-parse --verify "refs/top-bases/$name" 2>/dev/null)" ||
	die "not a TopGit topic branch: $name"

! git symbolic-ref HEAD >/dev/null || [ "$(git symbolic-ref HEAD)" != "refs/heads/$name" ] ||
	die "cannot delete your current branch"

current="$(git symbolic-ref HEAD 2>/dev/null | sed 's#^refs/\(heads\|top-bases\)/##')"
[ -n "$current" ] || die "cannot return to detached tree; switch to another branch"

## Make sure our tree is clean

git update-index --ignore-submodules --refresh || die "the working tree is not clean"
git diff-index --quiet --cached -r --ignore-submodules HEAD -- || die "the index is not clean"

[ -z "$force" ] && { branch_empty "$name" || die "branch is non-empty: $name"; }

depsfile="$(get_temp tg-delete-deps)"
tg summary --deps > "$depsfile" 2>/dev/null

while read branch dep; do
	[ "$dep" = "$name" ]    && to_update="$to_update $branch"
	[ "$branch" = "$name" ] && deps_to_push="$deps_to_push $dep"
done < "$depsfile"
deps_to_push=${deps_to_push# }

[ -n "$to_update" -a -z "$deps_to_push" -a -z "$force" ] &&
	die "branch \`$name\` has no dependencies"

for b in $to_update; do
	info "Updating \`$b\` dependencies..."
	git checkout "$b" || die "cannot checkout \`$b\`."

	deps=
	sed -e "s@^$name\$@$deps_to_push@" -e '/^[[:space:]]*$/d' .topdeps | tr ' ' '\n' | while read dep; do
		case " $deps " in
			*" $dep "* )
				:
			;;
			* )
				deps="$deps $dep"
				echo $dep
			;;
		esac
	done > "$depsfile"
	cat "$depsfile" > .topdeps
	git add .topdeps
	(
	while ! git commit -m "TopGIT: updating dependencies from \`$name\` to \`$deps_to_push\`"; do
		# Commit failed
		info "You are in a subshell. Fix commit problem and"
		info "use \`exit\` to continue updating dependencies."
		info "Use \`exit 1\` to abort updating dependencies altogether."
		info "Use \`exit 2\` to skip branch \`$b\` and continue."
		if sh -i </dev/tty; then
			# assume user fixed it
			break
		else
			ret=$?
			git reset --hard
			if [ $ret -eq 2 ]; then
				info "Ok, I will try to continue without updating this branch."
				continue 2
			else
				info "Aborting update of dependencies. You are now on branch \`$b\`."

				exit 3
			fi
		fi
	done
	)
	info "updated dependecies for \`$b' from \`$name' to \`$deps_to_push'"
	info "use \`tg update $b' to ensure it is up to date"
	#tg update || die "Update of $b failed; fix it manually"
done

git checkout -q "$current" || die "failed to return to $current"

## Wipe out

git update-ref -d "refs/top-bases/$name" "$baserev"
[ -z "$branchrev" ] || git update-ref -d "refs/heads/$name" "$branchrev"

# vim:noet
