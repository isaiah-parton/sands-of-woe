package game

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:strings"
import "core:time"
import "vendor:miniaudio"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

MAX_PLAYERS :: 4

Input_Method :: enum {
	Keyboard,
	Controller_1,
	Controller_2,
	Controller_3,
	Controller_4,
}

Bounds :: struct($T: typeid) where intrinsics.type_is_numeric(T) {
	low, high: [2]T,
}

Camera :: struct {
	point, motion: [2]f32,
	scale:         f32,
}

Game_Mode :: enum {
	Play,
	Edit,
}



Cell_Swap :: struct {
	chunks:  [2]^Chunk,
	indices: [2]int,
}

game: ^Game

Game :: struct {
	run:                    bool,
	debug:                  bool,
	// Video
	size:                   [2]f32,
	// Time
	dt:                     f32,
	// Input
	mouse_point:            [2]f32,
	last_world_mouse_point: [2]f32,
	world_mouse_point:      [2]f32,
	/*
		Media
	*/
	audio:                  miniaudio.engine,
	audio_config:           miniaudio.engine_config,
	audio_listener:         miniaudio.spatializer_listener,
	audio_spatial:          miniaudio.spatializer,
	audio_node_splitter:    miniaudio.splitter_node,
	audio_node_LPF:         miniaudio.lpf_node,
	audio_node_delay:       miniaudio.delay_node,
	sound_group_ambient:    miniaudio.sound_group,
	sound_group_spatial:    miniaudio.sound_group,
	ambient_source:         Audio_Source,
	master_source:          Audio_Source,
	master_volume:          f32,
	muffler:                f32,
	/*
		World
	*/
	camera:                 Camera,
	world:                  World,
	editor:					Editor,
	mode:                   Game_Mode,

	id_stack:               Stack(Widget_ID, 16),
	widget_hovered:         bool,
	target_scale:           f32,

	font:                   rl.Font,
}

init :: proc() {
	game.run = true
	game.target_scale = 3
	rl.SetTraceLogLevel(.NONE)
	rl.SetConfigFlags({.FULLSCREEN_MODE, .VSYNC_HINT})
	rl.InitWindow(0, 0, "LUDUS")
	// rl.SetExitKey(.KEY_NULL)
	game.font = rl.LoadFont("Pixellari.ttf")

	init_world(&game.world, 1000, 1000)
}
update :: proc() {
	game.dt = rl.GetFrameTime()
	game.size = {f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
	game.mouse_point = {f32(rl.GetMouseX()), f32(rl.GetMouseY())}
	game.last_world_mouse_point = game.world_mouse_point
	game.world_mouse_point =
		(game.mouse_point - game.size / 2) / game.camera.scale + game.camera.point
	game.camera.scale += (game.target_scale - game.camera.scale) * 7.5 * game.dt

	if rl.IsKeyPressed(.GRAVE) {
		game.debug = !game.debug
	}

	switch game.mode {
	case .Edit:
		update_editor(&game.editor)

	case .Play:

	}

	// Update chunks
	if game.mode == .Play && time.duration_milliseconds(time.since(game.world.last_tick)) >= 10 {
		tick_world(&game.world)
	}

	// Draw the game
	rl.BeginDrawing()
	rl.ClearBackground({})

	// Draw world
	rlgl.PushMatrix()
	rlgl.Translatef(game.size.x / 2, game.size.y / 2, 0.0)
	rlgl.Scalef(game.camera.scale, game.camera.scale, 1.0) // Scaling first
	rlgl.Translatef(-game.camera.point.x, -game.camera.point.y, 0.0) // Then translation

	rl.DrawRectangleRec({0, 0, f32(game.world.width), f32(game.world.height)}, {15, 15, 15, 255})

	// Draw chunks
	chunks_drawn: int = 0
	for chunk in game.world.chunk_list {
		top_left := get_chunk_top_left(chunk.which)
		chunk_bounds: Bounds(f32) = {
			{f32(top_left.x), f32(top_left.y)},
			{f32(top_left.x + CHUNK_SIZE), f32(top_left.y + CHUNK_SIZE)},
		}
		camera_bounds: Bounds(f32) = {
			game.camera.point - (game.size * 0.5) / game.camera.scale,
			game.camera.point + (game.size * 0.5) / game.camera.scale,
		}
		if chunk.modified {
			chunk.modified = false
			chunk.awake = true
			update_chunk_texture(&game.world, chunk)
		}
		if bounds_touch(chunk_bounds, camera_bounds) {
			draw_chunk(chunk)
			if game.debug {
				draw_chunk_debug(chunk)
			}
			chunks_drawn += 1
		}
	}

	// World border
	if game.debug {
		rl.DrawRectangleLinesEx({0, 0, f32(game.world.width), f32(game.world.height)}, 1, rl.RED)
	}

	if game.mode == .Edit {
		draw_editor_gadgets(&game.editor)
	}

	rlgl.PopMatrix()

	game.widget_hovered = false

	// Widgets
	rlgl.PushMatrix()
	next_mode := Game_Mode((int(game.mode) + 1) % len(Game_Mode))
	if button({0, game.size.y - 48}, {120, 48}, ctprintf("%v", next_mode)) {
		game.mode = next_mode
	}

	if game.mode == .Edit {
		next_mode := Editor_Mode((int(game.editor.mode) + 1) % len(Editor_Mode))
		if button({121, game.size.y - 48}, {120, 48}, ctprintf("%v", game.editor.mode)) {
			game.editor.mode = next_mode
		}
		for kind, k in Cell_Kind {
			if color_button(
				{game.size.x - 30 * f32(k + 1), game.size.y - 30},
				{28, 28},
				get_cell_start_color(kind),
				game.editor.cell_kind == kind,
			) {
				game.editor.cell_kind = kind
			}
		}
	}

	rlgl.PopMatrix()

	// Debug text
	rl.DrawFPS(0, 0)
	rl.DrawText(ctprintf("mouse: {:v}", game.world_mouse_point), 0, 20, 20, rl.WHITE)

	rl.DrawText(ctprintf("chunk count: %i", len(game.world.chunk_list)), 0, 60, 20, rl.WHITE)
	rl.DrawText(ctprintf("chunks drawn: %i", chunks_drawn), 0, 80, 20, rl.WHITE)
	rl.DrawText(
		ctprintf("chunks processed: %i", game.world.chunks_processed),
		0,
		100,
		20,
		rl.WHITE,
	)

	rl.DrawText(ctprintf("cells processed: %i", game.world.cells_processed), 0, 140, 20, rl.WHITE)

	rl.EndDrawing()

	if rl.WindowShouldClose() {
		game.run = false
	}
}
quit :: proc() {
	rl.CloseWindow()
}

MAX_FMT_BUFFERS :: 100
FMT_BUFFER_LENGTH :: 100
__fmt_buffers: [MAX_FMT_BUFFERS][FMT_BUFFER_LENGTH]u8
__fmt_buffer_index: int

get_fmt_buffer :: proc() -> (res: strings.Builder) {
	res = strings.builder_from_bytes(__fmt_buffers[__fmt_buffer_index][:])
	__fmt_buffer_index = (__fmt_buffer_index + 1) % MAX_FMT_BUFFERS
	return
}
ctprintf :: proc(format: string, args: ..any) -> cstring {
	b := get_fmt_buffer()
	fmt.sbprintf(&b, format, ..args)
	strings.write_byte(&b, 0)
	return cstring(raw_data(b.buf))
}
