package game

import rl "vendor:raylib"

import "core:time"
import "core:math"
import "core:math/rand"

Neighboor :: enum {
	Up_Left,
	Up,
	Up_Right,
	Right,
	Down_Right,
	Down,
	Down_Left,
	Left,
}

Cell_Kind :: enum {
	Empty,
	Sand,
	Rock,
}

Cell :: struct {
	kind: Cell_Kind,
	color: [4]u8,
	stuck: bool,

	update_time: time.Time,
	fall_count: int,
}

update_cell :: proc(world: ^World, index: int) {
	cell := &world.cells[index]
	if cell.update_time._nsec >= world.last_tick._nsec {
		return
	}
	which: [2]int = {
		index % world.width,
		index / world.width,
	}
	// Process the cell
	#partial switch cell.kind {
		case .Sand:
		ray := traverse_world(world, which, which + {0, cell.fall_count})
		cell.fall_count = min(cell.fall_count + 2, 8)
		if ray.blocked {
			cell.fall_count = 2
		}
		if ray.end != which {
			move_cell(world, which, ray.end)
			cell.stuck = false
			return
		}
		if !cell.stuck {
			offset := 1 if rand.int_max(2) > 0 else -1
			for i in 0..<2 {
				other: [2]int = {which.x + offset, which.y + 1}
				if get_empty_cell(world, other) {
					move_cell(world, which, other)
					return
				}
				offset = -offset
			}
		}
		if rand.float32() < 0.1 {
			cell.stuck = true
		}

		case .Rock:

	}
}

get_cell_start_color :: proc(kind: Cell_Kind) -> rl.Color {
	color: rl.Color
 	switch kind {
 		case .Empty:

 		case .Rock:
 		color = {35, 39, 45, 255}
 		case .Sand:
 		color = {180, 210, 40, 255}
 	}
 	return color
}

make_cell_of_kind :: proc(kind: Cell_Kind) -> Cell {
 	return Cell{
 		color =	get_cell_start_color(kind),
 		kind = kind,
 	}
 }