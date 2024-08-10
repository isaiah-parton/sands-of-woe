package game

import "core:fmt"
import "core:math"
import "core:math/linalg"

import rl "vendor:raylib"

Editor_Mode :: enum {
	Paint,
	Polygon,
}

Paint_Tool :: struct {
	size: f32,
}

Polygon_Tool :: struct {
	done: bool,
	points: [dynamic][2]f32,
	next_point: [2]f32,
	snap_to: Maybe(int),
}

Editor :: struct {
	mode: Editor_Mode,
	polygon: Polygon_Tool,
	paint: Paint_Tool,
	cell_kind: Cell_Kind,
}

draw_editor_gadgets :: proc(e: ^Editor) {
	switch e.mode {

		case .Paint:

		rl.DrawRing(
			rl.Vector2(game.world_mouse_point),
			e.paint.size / 2,
			e.paint.size / 2 + 1,
			0,
			360,
			60,
			rl.GRAY,
		)

		case .Polygon:

		for i in 0..<len(e.polygon.points) - 1 {
			rl.DrawLineEx(
				rl.Vector2(e.polygon.points[i]), 
				rl.Vector2(e.polygon.points[i + 1]), 
				game.camera.scale / 2, 
				rl.GRAY,
				)
		}
		if index, ok := e.polygon.snap_to.?; ok {
			rl.DrawLineEx(rl.Vector2(e.polygon.points[index]), rl.Vector2(e.polygon.next_point), game.camera.scale / 2, rl.RED)
		}
		if len(e.polygon.points) > 0 {
			last_point := e.polygon.points[len(e.polygon.points) - 1]
			rl.DrawLineEx(rl.Vector2(last_point), rl.Vector2(e.polygon.next_point), game.camera.scale / 2, rl.WHITE)
		}
		for i in 0..<len(e.polygon.points) {
			rl.DrawCircleV(rl.Vector2(e.polygon.points[i]), 3, rl.BLUE)
		}
	}
}

update_editor :: proc(e: ^Editor) {
	// Camera movement
	CAMERA_ACCELERATION :: 5.5
	camera_speed: f32 = 2400.0 / game.camera.scale
	if !rl.IsKeyDown(.LEFT_SHIFT) {
		game.target_scale = clamp(
			game.target_scale + rl.GetMouseWheelMove() * 0.1 * game.target_scale,
			1,
			8,
		)
	}
	if rl.IsKeyDown(.A) {
		game.camera.motion.x +=
			(-camera_speed - game.camera.motion.x) * CAMERA_ACCELERATION * game.dt
	} else if rl.IsKeyDown(.D) {
		game.camera.motion.x +=
			(camera_speed - game.camera.motion.x) * CAMERA_ACCELERATION * game.dt
	} else {
		game.camera.motion.x -= game.camera.motion.x * CAMERA_ACCELERATION * game.dt
	}
	if rl.IsKeyDown(.W) {
		game.camera.motion.y +=
			(-camera_speed - game.camera.motion.y) * CAMERA_ACCELERATION * game.dt
	} else if rl.IsKeyDown(.S) {
		game.camera.motion.y +=
			(camera_speed - game.camera.motion.y) * CAMERA_ACCELERATION * game.dt
	} else {
		game.camera.motion.y -= game.camera.motion.y * CAMERA_ACCELERATION * game.dt
	}
	game.camera.point += game.camera.motion * game.dt

	// World editing
	switch e.mode {

		case .Paint:
		if rl.IsKeyDown(.LEFT_SHIFT) {
			e.paint.size += rl.GetMouseWheelMove()
		}
		e.paint.size = clamp(e.paint.size, 2, 50)
		if rl.IsMouseButtonDown(.LEFT) && !game.widget_hovered {
			set_cells_in_circle(&game.world, game.world_mouse_point, e.paint.size / 2, make_cell_of_kind(e.cell_kind))
		}

		case .Polygon:
		if !e.polygon.done {
			snap_distance := f32(3) * game.camera.scale
			e.polygon.next_point = game.world_mouse_point
			e.polygon.snap_to = nil
			if rl.IsKeyDown(.LEFT_CONTROL) {
				last_point := e.polygon.points[len(e.polygon.points) - 1]
				diff := linalg.abs(last_point - e.polygon.next_point)
				if diff.x > diff.y {
					e.polygon.next_point.y = last_point.y
				} else {
					e.polygon.next_point.x = last_point.x
				}

				if rl.IsKeyDown(.LEFT_SHIFT) {
					for point, p in e.polygon.points {
						if diff.x > diff.y {
							if abs(point.x - e.polygon.next_point.x) < snap_distance {
								e.polygon.next_point.x = point.x
								e.polygon.snap_to = p
							}
						} else {
							if abs(point.y - e.polygon.next_point.y) < snap_distance {
								e.polygon.next_point.y = point.y
								e.polygon.snap_to = p
							}
						}
					}
				}
			}
			if len(e.polygon.points) > 2 {
				first_point := e.polygon.points[0]
				if linalg.distance(e.polygon.next_point, first_point) < snap_distance {
					e.polygon.next_point = first_point
				}
			}
			if !game.widget_hovered && rl.IsMouseButtonPressed(.LEFT) {
				if len(e.polygon.points) > 2 && e.polygon.next_point == e.polygon.points[0] {
					e.polygon.done = true
				}
				append(&e.polygon.points, e.polygon.next_point)
			}
		} else {
			if rl.IsKeyPressed(.B) {
				// Calculate bounds
				bounds: Bounds(f32) = {
					{f32(game.world.width), f32(game.world.height)},
					{0.0, 0.0},
				}
				for point in e.polygon.points {
					bounds.low = linalg.min(bounds.low, point)
					bounds.high = linalg.max(bounds.high, point)
				}

				for y in int(bounds.low.y)..<int(bounds.high.y) {
					for x in int(bounds.low.x)..<int(bounds.high.x) {
						if check_point_vs_poly([2]f32{f32(x), f32(y)}, e.polygon.points[:]) {
							set_cell(&game.world, {x, y}, make_cell_of_kind(e.cell_kind))
						}
					}
				}

				wake_chunks_in_bounds(&game.world, bounds)

				clear(&e.polygon.points)
				e.polygon.done = false
			}
		}
		if rl.IsMouseButtonPressed(.RIGHT) {
			clear(&e.polygon.points)
			e.polygon.done = false
		}
	}
}

check_point_vs_tri :: proc(point, a, b, c: [2]f32) -> bool {
	alpha := ((b.y - c.y) * (point.x - c.x) + (c.x - b.x) * (point.y - c.y)) / ((b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y))
	beta := ((c.y - a.y) * (point.x - c.x) + (a.x - c.x) * (point.y - c.y)) / ((b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y))
	gamma := 1 - alpha - beta
	return alpha > 0 && beta > 0 && gamma > 0
}

check_point_vs_poly :: proc(point: [2]f32, poly: [][2]f32) -> bool {
	inside := false

	if len(poly) > 2 {
		for i in 0..<len(poly) {
			j := i + 1
			if j >= len(poly) {
				j = 0
			}
			if (poly[i].y > point.y) != (poly[j].y > point.y) && (point.x < (poly[j].x - poly[i].x) * (point.y - poly[i].y) / (poly[j].y - poly[i].y) + poly[i].x) {
				inside = !inside
			}
		}
	}

	return inside
}