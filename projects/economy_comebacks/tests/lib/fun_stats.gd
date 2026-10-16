extends RefCounted
## WHAT THIS IS: a few small maths helpers for the fun probe: the average of
## a list of numbers, its middle value (the "median"), other "percentiles",
## and how well two lists rise and fall together (a "correlation").
##
## HOW IT WORKS: each function takes plain lists of numbers and gives back
## one number. When there is nothing to measure (an empty list, too few
## values, or a list where every value is the same), it gives back null
## instead. FUN_JSON prints null as "null", which means "could not be
## measured in this match".
##   - A percentile q (a 0..1 fraction) is the value that a share q of the
##     list lies at or below: q = 0.5 is the median, q = 0.9 the value that
##     90% of the list stays under. We sort the list; when q falls between
##     two entries we take the point on the straight line between them
##     ("linear interpolation"). tools/fun_lib.py uses the same rule, so
##     both tools give the same answers.
##   - Spearman's rho (a "rank correlation"): replace every value by its
##     rank (1 = smallest; equal values share the average of their ranks),
##     then measure how well the two rank lists line up (Pearson's
##     correlation). +1 = both lists always rise together, 0 = no link,
##     -1 = one always falls when the other rises.
## This is a "static library": plain functions with no memory of their own.
##
## WHO USES IT: tests/fun_probe.gd and its parts in tests/lib/
## (fun_probe_*.gd) load it with
##   const FunStats := preload("res://tests/lib/fun_stats.gd")
## It has no class_name on purpose: test helpers stay out of the game's
## list of global names.


## The average of the numbers in `xs`, or null for an empty list.
static func mean(xs: Array) -> Variant:
	if xs.is_empty():
		return null
	var total := 0.0
	for x in xs:
		total += float(x)
	return total / float(xs.size())


## The `q`-th percentile of `xs` (q is a 0..1 fraction: 0.5 = the median,
## 0.9 = the 90th percentile), with linear interpolation between the two
## neighbouring values (see HOW IT WORKS). Null for an empty list. The
## caller's list is not changed.
static func percentile(xs: Array, q: float) -> Variant:
	if xs.is_empty():
		return null
	# Step 1: a sorted copy of the list.
	var s := xs.duplicate()
	s.sort()
	# Step 2: where q falls in the sorted list, counted from 0 (it may fall
	# between two entries, `lo` and `hi`).
	var pos := clampf(q, 0.0, 1.0) * float(s.size() - 1)
	var lo := int(floor(pos))
	var hi := mini(lo + 1, s.size() - 1)
	# Step 3: the point on the straight line between those two entries.
	var frac := pos - float(lo)
	return float(s[lo]) + (float(s[hi]) - float(s[lo])) * frac


## The middle value of `xs` (the 50th percentile), or null for an empty
## list.
static func median(xs: Array) -> Variant:
	return percentile(xs, 0.5)


## The rank of every value of `xs`, in the same order as `xs`: 1 for the
## smallest, 2 for the next... Equal values all get the average of the
## ranks they cover (two values tied for 3rd and 4th both get 3.5).
static func ranks(xs: Array) -> Array:
	# Step 1: the positions 0, 1, 2 ... of the values, sorted by value.
	var idx: Array = range(xs.size())
	idx.sort_custom(func(a, b) -> bool: return float(xs[a]) < float(xs[b]))
	# Step 2: walk through the sorted values one group of equal values at a
	# time; every member of a group gets the group's average rank.
	var out: Array = []
	out.resize(xs.size())
	var i := 0
	while i < idx.size():
		var j := i
		while j + 1 < idx.size() and float(xs[idx[j + 1]]) == float(xs[idx[i]]):
			j += 1
		var avg := (float(i) + float(j)) * 0.5 + 1.0
		for k in range(i, j + 1):
			out[idx[k]] = avg
		i = j + 1
	return out


## Pearson's correlation of two equally long lists `xs` and `ys` (how well
## they rise and fall together, -1..+1). Null when it can't be measured:
## fewer than 3 pairs, lists of different lengths, or a list whose values
## are all the same.
static func pearson(xs: Array, ys: Array) -> Variant:
	var n := xs.size()
	if n < 3 or ys.size() != n:
		return null
	# Step 1: the two averages.
	var mx: float = mean(xs)
	var my: float = mean(ys)
	# Step 2: how far each pair sits from the averages, multiplied together
	# (sxy) and squared (sxx, syy).
	var sxy := 0.0
	var sxx := 0.0
	var syy := 0.0
	for i in n:
		var dx := float(xs[i]) - mx
		var dy := float(ys[i]) - my
		sxy += dx * dy
		sxx += dx * dx
		syy += dy * dy
	# Step 3: no spread in one list means no correlation can be measured.
	if sxx <= 0.0 or syy <= 0.0:
		return null
	return sxy / sqrt(sxx * syy)


## Spearman's rank correlation of `xs` and `ys` (see HOW IT WORKS): -1..+1,
## or null when it can't be measured (see pearson()).
static func spearman(xs: Array, ys: Array) -> Variant:
	if xs.size() != ys.size():
		return null
	return pearson(ranks(xs), ranks(ys))


## `num` divided by `den`, or null when `den` is 0 or less (nothing to
## divide by, so the share can't be measured).
static func ratio(num: float, den: float) -> Variant:
	return num / den if den > 0.0 else null


## `x` rounded to steps of `step` (0.001 = three decimals), or null when `x`
## is null. Used to keep FUN_JSON short.
static func snap(x: Variant, step: float) -> Variant:
	if typeof(x) == TYPE_NIL:
		return null
	return snappedf(float(x), step)


## Every number of `xs` rounded to steps of `step` (a new list).
static func snap_all(xs: Array, step: float) -> Array:
	var out: Array = []
	for x in xs:
		out.append(snappedf(float(x), step))
	return out
