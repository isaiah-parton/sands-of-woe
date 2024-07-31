package game

bounds_touch :: proc(a, b: Bounds($T)) -> bool {
	return a.low.x <= b.high.x && a.high.x >= b.low.x && a.low.y <= b.high.y && a.high.y >= b.low.y
}

point_in_bounds :: proc(p: [2]$T, b: Bounds(T)) -> bool {
	return p.x >= b.low.x && p.x < b.high.x && p.y >= b.low.y && p.y < b.high.y
}