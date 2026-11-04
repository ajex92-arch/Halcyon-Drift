class_name RouteGraphHeap
extends RefCounted
## WHAT THIS IS: the to-do list of RouteGraph's route search, kept so that
## the most promising entry (the smallest number) can always be taken off
## first, quickly. It is a "binary heap".
##
## HOW IT WORKS: the heap is a plain Array of [f, node] pairs (f = a score,
## smaller is better; node = a dot number). Think of the list as a family
## tree: entry i's two children sit at 2i+1 and 2i+2, and its parent at
## (i-1)/2. The rule is that no parent's f is bigger than its children's,
## so the smallest f is always at the front (index 0).
##   - push() adds a pair at the end and lets it climb past bigger parents.
##   - pop() takes the front pair, moves the last pair to the front and
##     lets it sink below smaller children.
## Both only touch one path down the tree, so they stay fast even with
## thousands of entries. Pairs with the same f keep no particular order.
##
## WHO USES IT: only RouteGraph.node_path(). It is a "static library": it
## keeps no data of its own; the caller owns the Array and passes it in.
## (A "static" function belongs to the class itself: it is called as
## RouteGraphHeap.push(...) without making a RouteGraphHeap first.)


## Add dot `node` with score `f` to `heap`.
static func push(heap: Array, f: float, node: int) -> void:
	heap.append([f, node])
	# Climb: swap with the parent while the parent's score is bigger.
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if heap[p][0] <= heap[i][0]:
			break
		var tmp = heap[p]
		heap[p] = heap[i]
		heap[i] = tmp
		i = p


## Take the pair with the smallest score off `heap` and return its dot
## number. The heap must not be empty.
static func pop(heap: Array) -> int:
	var top: int = heap[0][1]
	# Move the last pair to the front (unless it was the only one).
	var last = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	# Sink: swap with the smaller child while that child's score is smaller.
	var i := 0
	var n := heap.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < n and heap[l][0] < heap[m][0]:
			m = l
		if r < n and heap[r][0] < heap[m][0]:
			m = r
		if m == i:
			break
		var tmp = heap[m]
		heap[m] = heap[i]
		heap[i] = tmp
		i = m
	return top
