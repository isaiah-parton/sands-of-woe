package game

import rl "vendor:raylib"

Brush :: struct {
	cell_kind: Cell_Kind,
	size: f32,
}

update_brush :: proc(b: ^Brush, w: ^World) {
	if rl.IsKeyDown(.LEFT_SHIFT) {
		b.size += rl.GetMouseWheelMove()
	}
	b.size = clamp(b.size, 2, 50)
	if rl.IsMouseButtonDown(.LEFT) && !game.widget_hovered {
		set_cells_in_circle(&game.world, game.world_mouse_point, b.size / 2, make_cell_of_kind(b.cell_kind))
	}
}