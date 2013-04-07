function first(A,     i)
{
	for(i in A) {
		delete A[i];
		return i;
	}
	return 0;
}
{
	if (dir == "push")
		tree[$2] = tree[$2] " " $1;
	else
		tree[$1] = tree[$1] " " $2;
}
END {
	queue[start] = 1;
	while(1)
	{
      		candidate = first(queue);
      		if(!candidate)
			break;
		if(candidate in processed)
			continue;
		processed[candidate] = 1;
		if(candidate in tree)
		{
			new_candidates = tree[candidate];
			split(new_candidates, tmp);
			for(c in tmp)
				queue[tmp[c]] = 1;
		}
		else
		{
	  		leaves[candidate] = 1;
		}
	}
	for(leave in leaves)
		print leave;
}
