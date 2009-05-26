#
# bash completion support for TopGit.
#
# Copyright (C) 2008 Jonas Fonseca <fonseca@diku.dk>
# Copyright (C) 2006,2007 Shawn O. Pearce <spearce@spearce.org>
# Based git's git-completion.sh: http://repo.or.cz/w/git/fastimport.git
# Conceptually based on gitcompletion (http://gitweb.hawaga.org.uk/).
# Distributed under the GNU General Public License, version 2.0.
#
# To use these routines:
#
#    1) Copy this file to somewhere (e.g. ~/.tg-completion.sh).
#    2) Source it from your ~/.bashrc.
#
# Note: Make sure the tg script is in your PATH before you source this
# script, so it can properly setup cached values.

case "$COMP_WORDBREAKS" in
*:*) : great ;;
*)   COMP_WORDBREAKS="$COMP_WORDBREAKS:"
esac

### {{{ Utilities

__tgdir ()
{
	if [ -z "$1" ]; then
		if [ -n "$__tg_dir" ]; then
			echo "$__tg_dir"
		elif [ -d .git ]; then
			echo .git
		else
			git rev-parse --git-dir 2>/dev/null
		fi
	elif [ -d "$1/.git" ]; then
		echo "$1/.git"
	else
		echo "$1"
	fi
}

__tgcomp_1 ()
{
	local c IFS=' '$'\t'$'\n'
	for c in $1; do
		case "$c$2" in
		--*=*) printf %s$'\n' "$c$2" ;;
		*.)    printf %s$'\n' "$c$2" ;;
		*)     printf %s$'\n' "$c$2 " ;;
		esac
	done
}

__tgcomp ()
{
	local cur="${COMP_WORDS[COMP_CWORD]}"
	if [ $# -gt 2 ]; then
		cur="$3"
	fi
	case "$cur" in
	--*=)
		COMPREPLY=()
		;;
	*)
		local IFS=$'\n'
		COMPREPLY=($(compgen -P "$2" \
			-W "$(__tgcomp_1 "$1" "$4")" \
			-- "$cur"))
		;;
	esac
}

__tg_heads ()
{
	local cmd i is_hash=y dir="$(__tgdir "$1")"
	if [ -d "$dir" ]; then
		git --git-dir="$dir" for-each-ref --format='%(refname:short)' \
			refs/heads
		return
	fi
	for i in $(git ls-remote "$1" 2>/dev/null); do
		case "$is_hash,$i" in
		y,*) is_hash=n ;;
		n,*^{}) is_hash=y ;;
		n,refs/heads/*) is_hash=y; echo "${i#refs/heads/}" ;;
		n,*) is_hash=y; echo "$i" ;;
		esac
	done
}

__tg_refs ()
{
	local cmd i is_hash=y dir="$(__tgdir "$1")"
	if [ -d "$dir" ]; then
		if [ -e "$dir/HEAD" ]; then echo HEAD; fi
		git --git-dir="$dir" for-each-ref --format='%(refname:short)' \
			refs/tags refs/heads refs/remotes
		return
	fi
	for i in $(git ls-remote "$dir" 2>/dev/null); do
		case "$is_hash,$i" in
		y,*) is_hash=n ;;
		n,*^{}) is_hash=y ;;
		n,refs/tags/*) is_hash=y; echo "${i#refs/tags/}" ;;
		n,refs/heads/*) is_hash=y; echo "${i#refs/heads/}" ;;
		n,refs/remotes/*) is_hash=y; echo "${i#refs/remotes/}" ;;
		n,*) is_hash=y; echo "$i" ;;
		esac
	done
}

__tg_refs2 ()
{
	local i
	for i in $(__tg_refs "$1"); do
		echo "$i:$i"
	done
}

__tg_refs_remotes ()
{
	local cmd i is_hash=y
	for i in $(git ls-remote "$1" 2>/dev/null); do
		case "$is_hash,$i" in
		n,refs/heads/*)
			is_hash=y
			echo "$i:refs/remotes/$1/${i#refs/heads/}"
			;;
		y,*) is_hash=n ;;
		n,*^{}) is_hash=y ;;
		n,refs/tags/*) is_hash=y;;
		n,*) is_hash=y; ;;
		esac
	done
}

__tg_remotes ()
{
	local i ngoff IFS=$'\n' d="$(__tgdir)"
	shopt -q nullglob || ngoff=1
	shopt -s nullglob
	for i in "$d/remotes"/*; do
		echo ${i#$d/remotes/}
	done
	[ "$ngoff" ] && shopt -u nullglob
	for i in $(git --git-dir="$d" config --list); do
		case "$i" in
		remote.*.url=*)
			i="${i#remote.}"
			echo "${i/.url=*/}"
			;;
		esac
	done
}

__tg_find_subcommand ()
{
	local word subcommand c=1

	while [ $c -lt $COMP_CWORD ]; do
		word="${COMP_WORDS[c]}"
		for subcommand in $1; do
			if [ "$subcommand" = "$word" ]; then
				echo "$subcommand"
				return
			fi
		done
		c=$((++c))
	done
}

__tg_complete_revlist ()
{
	local pfx cur="${COMP_WORDS[COMP_CWORD]}"
	case "$cur" in
	*...*)
		pfx="${cur%...*}..."
		cur="${cur#*...}"
		__tgcomp "$(__tg_refs)" "$pfx" "$cur"
		;;
	*..*)
		pfx="${cur%..*}.."
		cur="${cur#*..}"
		__tgcomp "$(__tg_refs)" "$pfx" "$cur"
		;;
	*)
		__tgcomp "$(__tg_refs)"
		;;
	esac
}

__tg_topics ()
{
	tg summary -t
}

__tg_commands ()
{
	if [ -n "$__tg_all_commandlist" ]; then
		echo "$__tg_all_commandlist"
		return
	fi
	local i IFS=" "$'\n'
	for i in $(tg help | sed -n 's/^Usage:.*(\(.*\)).*/\1/p' | tr '|' ' ')
	do
		case $i in
		*--*)             : helper pattern;;
		*) echo $i;;
		esac
	done
}
__tg_all_commandlist=
__tg_all_commandlist="$(__tg_commands 2>/dev/null)"

__tg_complete_arg ()
{
	if [ $COMP_CWORD -gt 2 ] && [ "${COMP_WORDS[$COMP_CWORD - 1]}" = "$1" ]; then
		return 0
	fi
	return 1
}

### }}}
### {{{ Commands

_tg_create ()
{
	local cmd="$1"
	local cur="${COMP_WORDS[COMP_CWORD]}"

	# Name must be the first arg after the create command
	if [ $((cmd + 1)) = $COMP_CWORD ]; then
		__tgcomp "$(__tg_topics)"
		return
	fi

	__tg_complete_arg "-r" && {
		__tgcomp "$(__tg_remotes)"
		return
	}

	case "$cur" in
	-*)
		__tgcomp "
			-r
		"
		;;
	*)
		__tgcomp "$(__tg_refs)"
	esac
}

_tg_delete ()
{
	local cur="${COMP_WORDS[COMP_CWORD]}"

	case "$cur" in
	-*)
		__tgcomp "
			-f
		"
		;;
	*)
		__tgcomp "$(__tg_topics)"
	esac
}

_tg_depend ()
{
	local subcommands="add"
	local subcommand="$(__git_find_subcommand "$subcommands")"
	if [ -z "$subcommand" ]; then
		__tgcomp "$subcommands"
		return
	fi

	case "$subcommand" in
	add)
		__tgcomp "$(__tg_refs)"
	esac
}

_tg_export ()
{
	local cur="${COMP_WORDS[COMP_CWORD]}"

	__tg_complete_arg "--collapse" && {
		__tgcomp "$(__tg_heads)"
		return
	}

	__tg_complete_arg "--quilt" && {
		return
	}

	case "$cur" in
	*)
		__tgcomp "
			--collapse
			--quilt
		"
	esac
}

_tg_help ()
{
	local cur="${COMP_WORDS[COMP_CWORD]}"
	case "$cur" in
	-*)
		COMPREPLY=()
		return
		;;
	esac
	__tgcomp "$(__tg_commands)"
}

_tg_import ()
{
	local cur="${COMP_WORDS[COMP_CWORD]}"

	__tg_complete_arg "-p" && {
		COMPREPLY=()
		return
	}

	case "$cur" in
	-*)
		__tgcomp "
			-p
		"
		;;
	*)
		__tg_complete_revlist
	esac
}

_tg_info ()
{
	local cur="${COMP_WORDS[COMP_CWORD]}"

	case "$cur" in
	*)
		__tgcomp "$(__tg_topics)"
	esac
}

_tg_mail ()
{
	local cur="${COMP_WORDS[COMP_CWORD]}"

	case "$cur" in
	*)
		__tgcomp "$(__tg_topics)"
	esac
}

_tg_patch ()
{
	local cur="${COMP_WORDS[COMP_CWORD]}"

	case "$cur" in
	-*)
		__tgcomp "
			-i
			-w
		"
		;;
	*)
		__tgcomp "$(__tg_topics)"
	esac
}

_tg_push ()
{
	local cur="${COMP_WORDS[COMP_CWORD]}"

	__tg_complete_arg "-r" && {
		__tgcomp "$(__tg_remotes)"
		return
	}

	case "$cur" in
	-*)
		__tgcomp "
			--no-deps
			--dry-run
			--tgish-only
			-r
		"
		;;
	*)
		__tgcomp "$(__tg_topics)"
	esac
}

_tg_remote ()
{
	local cur="${COMP_WORDS[COMP_CWORD]}"

	case "$cur" in
	-*)
		__tgcomp "
			--populate
		"
		;;
	*)
		__tgcomp "$(__tg_remotes)"
	esac
}

_tg_summary ()
{
	local cur="${COMP_WORDS[COMP_CWORD]}"

	case "$cur" in
	*)
		__tgcomp "
			--graphviz
			-t
		"
	esac
}

_tg_update ()
{
	COMPREPLY=()
}

### }}}
### {{{ tg completion

_tg ()
{
	local i c=1 command __tg_dir

	while [ $c -lt $COMP_CWORD ]; do
		i="${COMP_WORDS[c]}"
		case "$i" in
		-r) 
			c=$((++c))
			if [ $c -lt $COMP_CWORD ]; then
				__tgcomp "$(__tg_remotes)"
				return
			fi
			;;
		-h|--help) command="help"; break ;;
		*) command="$i"; break ;;
		esac
		c=$((++c))
	done

	if [ -z "$command" ]; then
		case "${COMP_WORDS[COMP_CWORD]}" in
		-*)	__tgcomp "
				-r
				-h
				--help
			"
			;;
		*)     __tgcomp "$(__tg_commands)" ;;
		esac
		return
	fi

	case "$command" in
	create)      _tg_create "$c" ;;
	delete)      _tg_delete ;;
	depend)      _tg_depend ;;
	export)      _tg_export ;;
	help)        _tg_help ;;
	import)      _tg_import ;;
	info)        _tg_info ;;
	mail)        _tg_mail ;;
	patch)       _tg_patch ;;
	push)        _tg_push ;;
	remote)      _tg_remote ;;
	summary)     _tg_summary ;;
	update)      _tg_update ;;
	*)           COMPREPLY=() ;;
	esac
}

### }}}

complete -o default -o nospace -F _tg tg

# The following are necessary only for Cygwin, and only are needed
# when the user has tab-completed the executable name and consequently
# included the '.exe' suffix.
#
if [ Cygwin = "$(uname -o 2>/dev/null)" ]; then
complete -o default -o nospace -F _tg tg.exe
fi
