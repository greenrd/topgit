#!/bin/sh

# Create the tg-foo.txt files which contain help for the tg-foo command.

if [ $# -ne 1 ] ; then
	echo "Usage: $0 <tgcommand>" 1>&2
	exit 1
fi

< README awk '
	BEGIN { incommand = 0; }
	/^tg '"$1"'$/ { incommand = 1; next; }
	/^~/ { next; } # Ignore the title underlines.
	/^[^\t]/ { incommand = 0; next; }
	{ if (incommand) { print $0; } }
'  > tg-"$1".txt

# vim:noet
