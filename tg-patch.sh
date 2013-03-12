#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

name=

head_from=


## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-i|-w)
		[ -z "$head_from" ] || die "-i and -w are mutually exclusive"
		head_from="$arg";;
	-*)
		echo "Usage: tg [...] patch [-i | -w] [<name>]" >&2
		exit 1;;
	*)
		[ -z "$name" ] || die "name already specified ($name)"
		name="$arg";;
	esac
done

head="$(git symbolic-ref HEAD)"
head="${head#refs/heads/}"

[ -n "$name" ] ||
	name="$head"
base_rev="$(git rev-parse --short --verify "refs/top-bases/$name" 2>/dev/null)" ||
	die "not a TopGit-controlled branch"

if [ -n "$head_from" ] && [ "$name" != "$head" ]; then
	die "$head_from makes only sense for the current branch"
fi



setup_pager


# put out the commit message
# and put an empty line out, if the last one in the message was not an empty line
# and put out "---" if the commit message does not have one yet
cat_file "$name:.topmsg" $head_from |
	awk '
/^---/ {
    has_3dash=1;
}
       {
    need_empty = 1;
    if ($0 == "")
        need_empty = 0;
    print;
}
END    {
    if (need_empty)
        print "";
    if (!has_3dash)
        print "---";
}
'

b_tree=$(pretty_tree "$name" -b)
t_tree=$(pretty_tree "$name" $head_from)

if [ $b_tree = $t_tree ]; then
	echo "No changes."
else
	git diff-tree -p --stat $b_tree $t_tree
fi

echo '-- '
echo "tg: ($base_rev..) $name (depends on: $(cat_file "$name:.topdeps" $head_from | paste -s -d' '))"
branch_contains "$name" "$base_rev" ||
	echo "tg: The patch is out-of-date wrt. the base! Run \`$tg update\`."

# vim:noet
