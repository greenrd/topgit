dir == "push" && $2 == start { print $1 }
dir == "pop"  && $1 == start { print $2 }
