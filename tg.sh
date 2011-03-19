#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

TG_VERSION=0.8

## Auxiliary functions

info()
{
	echo "${TG_RECURSIVE}tg: $*"
}

die()
{
	info "fatal: $*" >&2
	exit 1
}

# cat_file TOPIC:PATH [FROM]
# cat the file PATH from branch TOPIC when FROM is empty.
# FROM can be -i or -w, than the file will be from the index or worktree,
# respectively. The caller should than ensure that HEAD is TOPIC, to make sense.
cat_file()
{
	path="$1"
	case "${2-}" in
	-w)
		cat "$root_dir/${path#*:}"
		;;
	-i)
		# ':file' means cat from index
		git cat-file blob ":${path#*:}"
		;;
	'')
		git cat-file blob "$path"
		;;
	*)
		die "Wrong argument to cat_file: '$2'"
		;;
	esac
}

# get tree for the committed topic
get_tree_()
{
	echo "$1"
}

# get tree for the base
get_tree_b()
{
	echo "refs/top-bases/$1"
}

# get tree for the index
get_tree_i()
{
	git write-tree
}

# get tree for the worktree
get_tree_w()
{
	i_tree=$(git write-tree)
	(
		# the file for --index-output needs to sit next to the
		# current index file
		: ${GIT_INDEX_FILE:="$git_dir/index"}
		TMP_INDEX="$(mktemp "${GIT_INDEX_FILE}-tg.XXXXXX")"
		git read-tree -m $i_tree --index-output="$TMP_INDEX" &&
		GIT_INDEX_FILE="$TMP_INDEX" &&
		export GIT_INDEX_FILE &&
		git diff --name-only -z HEAD |
			git update-index -z --add --remove --stdin &&
		git write-tree &&
		rm -f "$TMP_INDEX"
	)
}

# pretty_tree NAME [-b | -i | -w]
# Output tree ID of a cleaned-up tree without tg's artifacts.
# NAME will be ignored for -i and -w, but needs to be present
pretty_tree()
{
	name=$1
	source=${2#?}
	git ls-tree --full-tree "$(get_tree_$source "$name")" |
		awk -F '	' '$2 !~ /^.top/' |
		git mktree
}

# setup_hook NAME
setup_hook()
{
	hook_call="\"\$($tg --hooks-path)\"/$1 \"\$@\""
	if [ -f "$git_dir/hooks/$1" ] &&
	   fgrep -q "$hook_call" "$git_dir/hooks/$1"; then
		# Another job well done!
		return
	fi
	# Prepare incantation
	if [ -x "$git_dir/hooks/$1" ]; then
		hook_call="$hook_call"' || exit $?'
	else
		hook_call="exec $hook_call"
	fi
	# Don't call hook if tg is not installed
	hook_call="if which \"$tg\" > /dev/null; then $hook_call; fi"
	# Insert call into the hook
	{
		echo "#!/bin/sh"
		echo "$hook_call"
		[ ! -s "$git_dir/hooks/$1" ] || cat "$git_dir/hooks/$1"
	} >"$git_dir/hooks/$1+"
	chmod a+x "$git_dir/hooks/$1+"
	mv "$git_dir/hooks/$1+" "$git_dir/hooks/$1"
}

# setup_ours (no arguments)
setup_ours()
{
	if [ ! -s "$git_dir/info/attributes" ] || ! grep -q topmsg "$git_dir/info/attributes"; then
		{
			echo ".topmsg	merge=ours"
			echo ".topdeps	merge=ours"
		} >>"$git_dir/info/attributes"
	fi
	if ! git config merge.ours.driver >/dev/null; then
		git config merge.ours.name '"always keep ours" merge driver'
		git config merge.ours.driver 'touch %A'
	fi
}

# measure_branch NAME [BASE]
measure_branch()
{
	_bname="$1"; _base="$2"
	[ -n "$_base" ] || _base="refs/top-bases/$_bname"
	# The caller should've verified $name is valid
	_commits="$(git rev-list "$_bname" ^"$_base" -- | wc -l)"
	_nmcommits="$(git rev-list --no-merges "$_bname" ^"$_base" -- | wc -l)"
	if [ $_commits -gt 1 ]; then
		_suffix="commits"
	else
		_suffix="commit"
	fi
	echo "$_commits/$_nmcommits $_suffix"
}

# branch_contains B1 B2
# Whether B1 is a superset of B2.
branch_contains()
{
	[ -z "$(git rev-list --max-count=1 ^"$1" "$2" --)" ]
}

# ref_exists REF
# Whether REF is a valid ref name
ref_exists()
{
	git rev-parse --verify "$@" >/dev/null 2>&1
}

# has_remote BRANCH
# Whether BRANCH has a remote equivalent (accepts top-bases/ too)
has_remote()
{
	[ -n "$base_remote" ] && ref_exists "remotes/$base_remote/$1"
}

branch_annihilated()
{
	_name="$1";

	# use the merge base in case the base is ahead.
	mb="$(git merge-base "refs/top-bases/$_name" "$_name" 2> /dev/null)";

	test -z "$mb" || test "$(git rev-parse "$mb^{tree}")" = "$(git rev-parse "$_name^{tree}")";
}

# is_sha1 REF
# Whether REF is a SHA1 (compared to a symbolic name).
is_sha1()
{
	[ "$(git rev-parse "$1")" = "$1" ]
}

# recurse_deps CMD NAME [BRANCHPATH...]
# Recursively eval CMD on all dependencies of NAME.
# CMD can refer to $_name for queried branch name,
# $_dep for dependency name,
# $_depchain for space-seperated branch backtrace,
# $_dep_missing boolean to check whether $_dep is present
# and the $_dep_is_tgish boolean.
# It can modify $_ret to affect the return value
# of the whole function.
# If recurse_deps() hits missing dependencies, it will append
# them to space-separated $missing_deps list and skip them
# affter calling CMD with _dep_missing set.
# remote dependencies are processed if no_remotes is unset.
recurse_deps()
{
	_cmd="$1"; shift
	_name="$1"; # no shift
	_depchain="$*"

	_depsfile="$(get_temp tg-depsfile)"
	# If no_remotes is unset check also our base against remote base.
	# Checking our head against remote head has to be done in the helper.
	if test -z "$no_remotes" && has_remote "top-bases/$_name"; then
		echo "refs/remotes/$base_remote/top-bases/$_name" >>"$_depsfile"
	fi

	# if the branch was annihilated, there exists no .topdeps file
	if ! branch_annihilated "$_name"; then
		#TODO: handle nonexisting .topdeps?
		git cat-file blob "$_name:.topdeps" >>"$_depsfile";
	fi;

	_ret=0
	while read _dep; do
		_dep_missing=
		if ! ref_exists "$_dep" ; then
			# All hope is lost. Inform driver and continue
			missing_deps="$missing_deps $_dep"
			_dep_missing=1
			eval "$_cmd"
			continue
		fi

		_dep_is_tgish=1
		ref_exists "refs/top-bases/$_dep"  ||
			_dep_is_tgish=

		# Shoo shoo, keep our environment alone!
		[ -z "$_dep_is_tgish" ] ||
			(recurse_deps "$_cmd" "$_dep" "$@") ||
			_ret=$?

		eval "$_cmd"
	done <"$_depsfile"
	missing_deps="${missing_deps# }"
	return $_ret
}

# branch_needs_update
# This is a helper function for determining whether given branch
# is up-to-date wrt. its dependencies. It expects input as if it
# is called as a recurse_deps() helper.
# In case the branch does need update, it will echo it together
# with the branch backtrace on the output (see needs_update()
# description for details) and set $_ret to non-zero.
branch_needs_update()
{
	if [ -n "$_dep_missing" ]; then
		echo "! $_depchain"
		return 0
	fi

	_dep_base_update=
	if [ -n "$_dep_is_tgish" ]; then
		if has_remote "$_dep"; then
			branch_contains "$_dep" "refs/remotes/$base_remote/$_dep" || _dep_base_update=%
		fi
		# This can possibly override the remote check result;
		# we want to sync with our base first
		branch_contains "$_dep" "refs/top-bases/$_dep" || _dep_base_update=:
	fi

	if [ -n "$_dep_base_update" ]; then
		# _dep needs to be synced with its base/remote
		echo "$_dep_base_update $_dep $_depchain"
		_ret=1
	elif [ -n "$_name" ] && ! branch_contains "refs/top-bases/$_name" "$_dep"; then
		# Some new commits in _dep
		echo "$_dep $_depchain"
		_ret=1
	fi
}

# needs_update NAME
# This function is recursive; it outputs reverse path from NAME
# to the branch (e.g. B_DIRTY B1 B2 NAME), one path per line,
# inner paths first. Innermost name can be ':' if the head is
# not in sync with the base, '%' if the head is not in sync
# with the remote (in this order of priority) or '!' if depednecy
# is missing.
# It will also return non-zero status if NAME needs update.
# If needs_update() hits missing dependencies, it will append
# them to space-separated $missing_deps list and skip them.
needs_update()
{
	recurse_deps branch_needs_update "$@"
}

# branch_empty NAME [-i | -w]
branch_empty()
{
	[ "$(pretty_tree "$1" -b)" = "$(pretty_tree "$1" ${2-})" ]
}

# list_deps [-i | -w]
# -i/-w apply only to HEAD
list_deps()
{
	local head
	local head_from
	local from
	head_from=${1-}
	head="$(git symbolic-ref -q HEAD)" ||
		head="..detached.."

	git for-each-ref refs/top-bases |
		while read rev type ref; do
			name="${ref#refs/top-bases/}"
			if branch_annihilated "$name"; then
				continue;
			fi

			from=$head_from
			[ "refs/heads/$name" = "$head" ] ||
				from=
			cat_file "$name:.topdeps" $from | while read dep; do
				dep_is_tgish=true
				ref_exists "refs/top-bases/$dep"  ||
					dep_is_tgish=false
				if ! "$dep_is_tgish" || ! branch_annihilated $dep; then
					echo "$name $dep"
				fi
			done
		done
}

# switch_to_base NAME [SEED]
switch_to_base()
{
	_base="refs/top-bases/$1"; _seed="$2"
	# We have to do all the hard work ourselves :/
	# This is like git checkout -b "$_base" "$_seed"
	# (or just git checkout "$_base"),
	# but does not create a detached HEAD.
	git read-tree -u -m HEAD "${_seed:-$_base}"
	[ -z "$_seed" ] || git update-ref "$_base" "$_seed"
	git symbolic-ref HEAD "$_base"
}

# Show the help messages.
do_help()
{
	if [ -z "$1" ] ; then
		# This is currently invoked in all kinds of circumstances,
		# including when the user made a usage error. Should we end up
		# providing more than a short help message, then we should
		# differentiate.
		# Petr's comment: http://marc.info/?l=git&m=122718711327376&w=2

		## Build available commands list for help output

		cmds=
		sep=
		for cmd in "@cmddir@"/tg-*; do
			! [ -r "$cmd" ] && continue
			# strip directory part and "tg-" prefix
			cmd="$(basename "$cmd")"
			cmd="${cmd#tg-}"
			cmds="$cmds$sep$cmd"
			sep="|"
		done

		echo "TopGit v$TG_VERSION - A different patch queue manager"
		echo "Usage: tg [-r REMOTE] ($cmds|help) ..."
	elif [ -r "@cmddir@"/tg-$1 ] ; then
		setup_pager
		@cmddir@/tg-$1 -h 2>&1 || :
		echo
		if [ -r "@sharedir@/tg-$1.txt" ] ; then
			cat "@sharedir@/tg-$1.txt"
		fi
	else
		echo "`basename $0`: no help for $1" 1>&2
		do_help
		exit 1
	fi
}

## Pager stuff

# isatty FD
isatty()
{
	test -t $1
}

# setup_pager
# Spawn pager process and redirect the rest of our output to it
setup_pager()
{
	isatty 1 || return 0

	# TG_PAGER = GIT_PAGER | PAGER | less
	# NOTE: GIT_PAGER='' is significant
	TG_PAGER=${GIT_PAGER-${PAGER-less}}

	[ -z "$TG_PAGER"  -o  "$TG_PAGER" = "cat" ]  && return 0


	# now spawn pager
	export LESS="${LESS:-FRSX}"	# as in pager.c:pager_preexec()

	# setup_pager should be called only once per command
	pager_fifo="$tg_tmp_dir/pager"
	mkfifo -m 600 "$pager_fifo"

	"$TG_PAGER" < "$pager_fifo" &
	exec > "$pager_fifo"		# dup2(pager_fifo.in, 1)

	# this is needed so e.g. `git diff` will still colorize it's output if
	# requested in ~/.gitconfig with color.diff=auto
	export GIT_PAGER_IN_USE=1

	# atexit(close(1); wait pager)
	# deliberately overwrites the global EXIT trap
	trap "exec >&-; rm -rf \"$tg_tmp_dir\"; wait" EXIT
}

# get_temp NAME [-d]
# creates a new temporary file (or directory with -d) in the global
# temporary directory $tg_tmp_dir with pattern prefix NAME
get_temp()
{
	mktemp ${2-} "$tg_tmp_dir/$1.XXXXXX"
}

## Startup

[ -d "@cmddir@" ] ||
	die "No command directory: '@cmddir@'"

## Initial setup

set -e
git_dir="$(git rev-parse --git-dir)"
root_dir="$(git rev-parse --show-cdup)"; root_dir="${root_dir:-.}"
# Make sure root_dir doesn't end with a trailing slash.
root_dir="${root_dir%/}"
base_remote="$(git config topgit.remote 2>/dev/null)" || :
tg="tg"
# make sure merging the .top* files will always behave sanely
setup_ours
setup_hook "pre-commit"
# create global temporary directories, inside GIT_DIR
tg_tmp_dir="$(mktemp -d "$git_dir/tg-tmp.XXXXXX")"
trap "rm -rf \"$tg_tmp_dir\"" EXIT

## Dispatch

# We were sourced from another script for our utility functions;
# this is set by hooks.  Skip the rest of the file.  A simple return doesn't
# work as expected in every shell.  See http://bugs.debian.org/516188
if [ -z "$tg__include" ]; then

if [ "$1" = "-r" ]; then
	shift
	if [ -z "$1" ]; then
		echo "Option -r requires an argument." >&2
		do_help
		exit 1
	fi
	base_remote="$1"; shift
	tg="$tg -r $base_remote"
fi

cmd="$1"
[ -n "$cmd" ] || { do_help; exit 1; }
shift

case "$cmd" in
help|--help|-h)
	do_help "$1"
	exit 0;;
--hooks-path)
	# Internal command
	echo "@hooksdir@";;
*)
	[ -r "@cmddir@"/tg-$cmd ] || {
		echo "Unknown subcommand: $cmd" >&2
		do_help
		exit 1
	}
	. "@cmddir@"/tg-$cmd;;
esac

fi

# vim:noet
