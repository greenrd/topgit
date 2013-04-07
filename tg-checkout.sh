#!/bin/sh
# TopGit - A different patch queue manager
# GPLv2

## Parse options

# Subcommands.
push=
pop=
goto=

# Options of "push" and "pop".
all=

# Arguments of "goto".
pattern=

checkout() {
	_head="$(git rev-parse --abbrev-ref=loose HEAD)"
	ref_exists "refs/top-bases/$_head" && branch_annihilated "$_head" && _checkout_opts="-f"
	git checkout ${_checkout_opts} "$1"
}

while [ $# -gt 0 ]; do
	arg="$1"
	shift

	case "$arg" in
		-a)
			all=1;;
		child|next|push)
			push=1;;
		parent|prev|pop|..)
			pop=1;;
		goto)
			goto=1
			if [ $# -gt 0 ]; then
				pattern="$1"
				shift
			fi;;
		*)
			echo "Usage: tg [...] checkout [ [ push | pop ] [ -a ] | goto <pattern> ]" >&2
			exit 1;;
	esac
done

if [ "$goto$all" = 11 ]; then
	die "goto -a does not make sense."
fi

if [ -z "$push$pop$goto" ]; then
	# Default subcommand is "push".  This was the most reasonable
	# opposite of ".." that I could figure out.  "goto" would also
	# make sense as the default command, I suppose.
	push=1
fi

_depfile="$(mktemp -t tg-co-deps.XXXXXX)"
_altfile="$(mktemp -t tg-co-alt.XXXXXX)"
trap "rm -f \"$_depfile\" \"$_altfile\"" 0

if [ -n "$goto" ]; then
	tg summary -t | grep -e "$pattern" >$_altfile || :
	no_branch_found="No topic branch matches grep pattern '$pattern'"
else
	branch=`git symbolic-ref -q HEAD` || die "Working on a detached head"
	branch=`git rev-parse --abbrev-ref $branch`

	if [ -n "$pop" ]; then
		no_branch_found="$branch does not depend on any topic"
	else
		no_branch_found="No topic depends on $branch"
	fi

	if [ -z "$all" ]; then
		if [ -n "$pop" ]; then
			tg prev -w >$_altfile
		else
			tg next -w >$_altfile
		fi
	else
		tg summary --deps >$_depfile || die "tg summary failed"

		if [ -n "$pop" ]; then
			dir=pop
		else
			dir=push
		fi
		script=@sharedir@/leaves.awk
		awk -f @sharedir@/leaves.awk dir=$dir start=$branch <$_depfile | sort >$_altfile
	fi
fi

_alts=`wc -l < $_altfile`
if [ $_alts = 0 ]; then
	die "$no_branch_found"
elif [ $_alts = 1 ]; then
	checkout `cat $_altfile`
	exit $?
fi

echo Please select one of the following topic branches:
cat -n $_altfile
echo -n "Input the number: "
read n

# Check the input
sane=`echo $n|sed 's/[^0-9]//g'`
if [ -z "$n" ] || [ "$sane" != "$n" ]; then
	die "Bad input"
fi
if [ $n -lt 1 ] || [ $n -gt $_alts ]; then
	die "Input out of range"
fi

new_branch=`sed -n ${n}p $_altfile`
[ -n "$new_branch" ] || die "Bad input"

checkout $new_branch
