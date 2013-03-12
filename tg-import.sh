#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# (c) Aneesh Kumar K.V <aneesh.kumar@linux.vnet.ibm.com>  2008
# GPLv2

branch_prefix=t/
single=
ranges=
basedep=


## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-d)
		basedep="$1"; shift;;
	-p)
		branch_prefix="$1"; shift;;
	-s)
		single="$1"; shift;;
	-*)
		echo "Usage: tg [...] import [-d <base-branch>] ([-p <prefix>] <range>... | -s <name> <commit>)" >&2
		exit 1;;
	*)
		ranges="$ranges $arg";;
	esac
done


## Make sure our tree is clean

git update-index --ignore-submodules --refresh || exit
[ -z "$(git diff-index --cached --name-status -r --ignore-submodules HEAD --)" ] ||
	die "the index is not clean"


## Perform import

get_commit_msg()
{
	commit="$1"
	headers=""
	! header="$(git config topgit.to)" || headers="$headers%nTo: $header"
	! header="$(git config topgit.cc)" || headers="$headers%nCc: $header"
	! header="$(git config topgit.bcc)" || headers="$headers%nBcc: $header"
	git log -1 --pretty=format:"From: %an <%ae>$headers%nSubject: %s%n%n%b" "$commit"
}

get_branch_name()
{
	# nice sed script from git-format-patch.sh
	commit="$1"
	titleScript='
	s/[^-a-z.A-Z_0-9]/-/g
        s/\.\.\.*/\./g
	s/\.*$//
	s/--*/-/g
	s/^-//
	s/-$//
	q
'
	git log -1 --pretty=format:"%s" "$commit" | sed -e "$titleScript"
}

process_commit()
{
	commit="$1"
	branch_name="$2"
	info "---- Importing $commit to $branch_name"
	tg create "$branch_name" $basedep
	basedep=
	get_commit_msg "$commit" > .topmsg
	git add -f .topmsg .topdeps
	if ! git cherry-pick --no-commit "$commit"; then
		info "The commit will also finish the import of this patch."
		exit 2
	fi
	git commit -C "$commit"
	info "++++ Importing $commit finished"
}

if [ -n "$single" ]; then
	process_commit $ranges "$single"
	exit
fi

# nice arg verification stolen from git-format-patch.sh
for revpair in $ranges
do
	case "$revpair" in
	?*..?*)
		rev1=`expr "z$revpair" : 'z\(.*\)\.\.'`
		rev2=`expr "z$revpair" : 'z.*\.\.\(.*\)'`
		;;
	*)
		die "Unknow range spec $revpair"
		;;
	esac
	git rev-parse --verify "$rev1^0" >/dev/null 2>&1 ||
		die "Not a valid rev $rev1 ($revpair)"
	git rev-parse --verify "$rev2^0" >/dev/null 2>&1 ||
		die "Not a valid rev $rev2 ($revpair)"
	git cherry -v "$rev1" "$rev2" |
	while read sign rev comment
	do
		case "$sign" in
		'-')
			info "Merged already: $comment"
			;;
		*)
			process_commit "$rev" "$branch_prefix$(get_branch_name "$rev")"
			;;
		esac
	done
done

# vim:noet
