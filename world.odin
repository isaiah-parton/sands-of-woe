package game

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:math"
import "core:math/rand"
import "core:math/linalg"
import "base:runtime"
import "core:time"
import "core:fmt"

CHUNK_SIZE :: 128
CHUNK_CELLS :: CHUNK_SIZE * CHUNK_SIZE

Traversal_Result :: struct{
	blocked: bool,
	hit: [2]int,
	end: [2]int,
}

World :: struct {
	width,
	height: int,
	width_in_chunks,
	height_in_chunks: int,

	cells: []Cell,
	queue: [dynamic]int,

	chunks: []Chunk,
	chunk_list: [dynamic]^Chunk,

	gravity: f32,									// General magnitude of gravitational force
	wind: f32,										// Wind affects cells and entities

	last_tick: time.Time,					// When the world updated last
	cells_processed: int,					// Stats from the last tick
	chunks_processed: int,
}

Chunk :: struct {
	which: [2]int,

	next_work_bounds,
	work_bounds: Bounds(int),
	image: rl.Image,
	texture: rl.Texture,

	awake,
	modified,
	ready,
	dead: bool,
}

Explosion :: struct {
	center: [2]f32,
	force: f32,
}

init_world :: proc(world: ^World, width, height: int) {
	world.cells = make([]Cell, width * height)
	
	world.width = width
	world.height = height

	world.width_in_chunks = width / CHUNK_SIZE
	if width & CHUNK_SIZE > 0 do world.width_in_chunks += 1
	world.height_in_chunks = height / CHUNK_SIZE
	if height & CHUNK_SIZE > 0 do world.height_in_chunks += 1

	world.chunks = make([]Chunk, world.width_in_chunks * world.height_in_chunks)
}

destroy_world :: proc(world: ^World) {
	delete(world.cells)
	delete(world.chunks)
	delete(world.queue)
	delete(world.chunk_list)
}

tick_world :: proc(world: ^World) {
	world.last_tick = time.now()
	world.cells_processed = 0
	world.chunks_processed = 0

	for chunk, i in world.chunk_list {
		if chunk.dead {
			destroy_chunk(chunk)
			ordered_remove(&world.chunk_list, i)
			fmt.printf("[world] [chunk] %v unloaded\n", chunk.which)
			continue
		}
		if chunk.modified {
			chunk.awake = true
		}
		if chunk.awake {
			chunk.awake = false
			update_chunk_cells(world, chunk)
			world.chunks_processed += 1
		}
	}

	world.cells_processed = len(world.queue)

	for len(world.queue) > 0 {
		queue_index := rand.int_max(len(world.queue))
		update_cell(world, world.queue[queue_index])
		unordered_remove(&world.queue, queue_index)
	}
}

init_chunk :: proc(chunk: ^Chunk, which: [2]int) {
	chunk.which = which
	chunk.image = rl.GenImageColor(CHUNK_SIZE, CHUNK_SIZE, {})
	chunk.texture = rl.LoadTextureFromImage(chunk.image)
	rl.SetTextureWrap(chunk.texture, rl.TextureWrap.MIRROR_CLAMP)
	chunk.ready = true
}

destroy_chunk :: proc(chunk: ^Chunk) {
	rl.UnloadTexture(chunk.texture)
	rl.UnloadImage(chunk.image)
}

update_chunk_cells :: proc(world: ^World, chunk: ^Chunk) {
	top_left := chunk.which * CHUNK_SIZE
	chunk.next_work_bounds.low = linalg.clamp(chunk.next_work_bounds.low, top_left, linalg.min(top_left + CHUNK_SIZE, [2]int{world.width, world.height}))
	chunk.next_work_bounds.high = linalg.clamp(chunk.next_work_bounds.high, top_left, linalg.min(top_left + CHUNK_SIZE, [2]int{world.width, world.height}))
	chunk.work_bounds = {
		chunk.next_work_bounds.low,
		chunk.next_work_bounds.high,
	}
	chunk.next_work_bounds.low = top_left + CHUNK_SIZE
	chunk.next_work_bounds.high = top_left
	// Queue cells in working bounds for processing
	for y in chunk.work_bounds.low.y ..< chunk.work_bounds.high.y {
		for x in chunk.work_bounds.low.x ..< chunk.work_bounds.high.x {
			index := x + y * world.width
			if world.cells[index].kind != .Empty {
				append(&world.queue, index)
			}
		}
	}
}

draw_chunk :: proc(chunk: ^Chunk) {
	rl.DrawTexture(chunk.texture, i32(chunk.which.x * CHUNK_SIZE), i32(chunk.which.y * CHUNK_SIZE), rl.WHITE)
}

draw_chunk_debug :: proc(chunk: ^Chunk) {
	line_thickness := 1.0 / game.camera.scale
	rl.DrawRectangleLinesEx({f32(chunk.which.x * CHUNK_SIZE), f32(chunk.which.y * CHUNK_SIZE), f32(CHUNK_SIZE), f32(CHUNK_SIZE)}, line_thickness, {255, 255, 255, 50})
	if chunk.awake {
		rl.DrawRectangleLinesEx({
			f32(chunk.work_bounds.low.x), 
			f32(chunk.work_bounds.low.y), 
			f32(chunk.work_bounds.high.x - chunk.work_bounds.low.x), 
			f32(chunk.work_bounds.high.y - chunk.work_bounds.low.y),
		}, line_thickness, {255, 0, 255, 255})
	}
}

add_chunk_work :: proc(chunk: ^Chunk, which_cell: [2]int) {
	chunk.next_work_bounds.low = linalg.min(chunk.next_work_bounds.low, which_cell - 2)
	chunk.next_work_bounds.high = linalg.max(chunk.next_work_bounds.high, which_cell + 2)
}

update_chunk_texture :: proc(world: ^World, chunk: ^Chunk) {
	rl.ImageClearBackground(&chunk.image, {})
	bounds := get_chunk_bounds(chunk.which)
	for y in bounds.low.y..<bounds.high.y {
		for x in bounds.low.x..<bounds.high.x {
			if !is_valid_cell(world, {x, y}) {
				continue
			}
			index := x + y * world.width
			cell := world.cells[index]
			if cell.kind != .Empty {
				rl.ImageDrawPixel(&chunk.image, i32(x - bounds.low.x), i32(y - bounds.low.y), cell.color)
			}
		}
	}
	rl.UpdateTexture(chunk.texture, chunk.image.data)
}

// Spawn a new chunk
load_chunk :: proc(world: ^World, which: [2]int) -> Maybe(^Chunk) {
	chunk := get_chunk(world, which).?
	init_chunk(chunk, which)
	append(&world.chunk_list, chunk)
	fmt.printf("[world] [chunk] %v loaded\n", chunk.which)
	return chunk
}

// Get the top left cell of a chunk
get_chunk_top_left :: proc(which: [2]int) -> [2]int {
	return which * CHUNK_SIZE
}

// Get a chunk's overall bounds
get_chunk_bounds :: proc(which: [2]int) -> Bounds(int) {
	top_left := which * CHUNK_SIZE
	return {
		low = top_left,
		high = top_left + CHUNK_SIZE,
	}
}

// Which chunk does a cell occupy
get_cell_chunk :: proc(cell: [2]int) -> [2]int {
	return {
		(cell.x / CHUNK_SIZE) if cell.x >= 0 else ((cell.x + 1) / CHUNK_SIZE - 1),
		(cell.y / CHUNK_SIZE) if cell.y >= 0 else ((cell.y + 1) / CHUNK_SIZE - 1),
	}
}

// Get a cell's home chunk and it's index within it
get_cell_lookup :: proc(cell: [2]int) -> (chunk: [2]int, index: int) {
	chunk = get_cell_chunk(cell)
	local := cell - chunk * CHUNK_SIZE
	index = local.x + local.y * CHUNK_SIZE
	return
}

is_valid_chunk :: proc(world: ^World, which: [2]int) -> bool {
	return which.x >= 0 && which.x < world.width_in_chunks && which.y >= 0 && which.y < world.height_in_chunks
}

// Get a chunk from a world
get_chunk :: proc(world: ^World, which: [2]int) -> Maybe(^Chunk) {
	if !is_valid_chunk(world, which) {
		return nil
	}
	return &world.chunks[which.x + which.y * world.width_in_chunks]
}

get_ready_chunk :: proc(world: ^World, which: [2]int) -> Maybe(^Chunk) {
	if !is_valid_chunk(world, which) {
		return nil
	}
	chunk := &world.chunks[which.x + which.y * world.width_in_chunks]
	if !chunk.ready {
		init_chunk(chunk, which)
		append(&world.chunk_list, chunk)
	}
	return chunk
}

is_valid_cell :: proc(world: ^World, which: [2]int) -> bool {
	return which.x >= 0 && which.x < world.width && which.y >= 0 && which.y < world.height
}

// Get a cell by reference
get_cell :: proc(world: ^World, which: [2]int) -> Cell {
	if !is_valid_cell(world, which) {
		return Cell{
			kind = .Rock,
		}
	}
	return world.cells[which.x + which.y * world.width]
}

// Set a cell's data
set_cell :: proc(world: ^World, which: [2]int, what: Cell) {
	if !is_valid_cell(world, which) {
		return
	}
	world.cells[which.x + which.y * world.width] = what
}

// Fills in a circle around `center`
set_cells_in_circle :: proc(world: ^World, center: [2]f32, radius: f32, what: Cell) {
	bounds: Bounds(int) = {
		low = {int(center.x - radius), int(center.y - radius)},
		high = {int(center.x + radius), int(center.y + radius)},
	}
	for y in bounds.low.y ..< bounds.high.y {
		for x in bounds.low.x ..< bounds.high.x {
			if linalg.distance([2]f32{f32(x), f32(y)}, center) <= radius {
				set_cell(world, {x, y}, what)
			}
		}
	}
	wake_chunks_in_bounds(world, bounds)
}

wake_chunks_in_bounds :: proc(world: ^World, bounds: Bounds($T)) {
	chunk_bounds: Bounds(int) = {
		linalg.array_cast(bounds.low, int) / CHUNK_SIZE,
		linalg.array_cast(bounds.high, int) / CHUNK_SIZE + 1,
	}
	for y in chunk_bounds.low.y ..< chunk_bounds.high.y {
		for x in chunk_bounds.low.x ..< chunk_bounds.high.x {
			if chunk, ok := get_ready_chunk(world, {x, y}).?; ok {
				bounds := get_chunk_bounds({x, y})
				chunk.next_work_bounds.low = linalg.min(chunk.next_work_bounds.low, bounds.low)
				chunk.next_work_bounds.high = linalg.max(chunk.next_work_bounds.high, bounds.high)
				chunk.awake = true
				chunk.modified = true
			}
		}
	}
}

// Fills a rectangular selection within `_bounds`
set_cells_in_bounds :: proc(_bounds: Bounds($T), what: Cell) {
	bounds: Bounds(int) = {
		low = linalg.array_cast(_bounds.low, int),
		high = linalg.array_cast(_bounds.high, int),
	}
	low_chunk := get_cell_chunk(bounds.low)
	high_chunk := get_cell_chunk(bounds.high)
	for chunk_x in low_chunk.x ..= high_chunk.x {
		for chunk_y in low_chunk.y ..= high_chunk.y {
			chunk := game.chunk_map[{chunk_x, chunk_y}] or_else load_chunk({chunk_x, chunk_y})
			top_left := get_chunk_top_left({chunk_x, chunk_y})
			low_cell: [2]int = linalg.clamp(bounds.low, top_left, top_left + CHUNK_SIZE)
			high_cell: [2]int = linalg.clamp(bounds.high, top_left, top_left + CHUNK_SIZE)
			chunk.bounds.low = linalg.min(chunk.bounds.low, low_cell)
			chunk.bounds.high = linalg.max(chunk.bounds.high, high_cell)
			for cell_x in low_cell.x ..< high_cell.x {
				for cell_y in low_cell.y ..< high_cell.y {
					set_cell(world, {cell_x, cell_y}, what)
				}
			}
			chunk.modified = true
		}
	}
}

get_empty_cell :: proc(world: ^World, which: [2]int) -> bool {
	if !is_valid_cell(world, which) {
		return false
	}
	return world.cells[which.x + which.y * world.width].kind == .Empty
}

// Wake a cell and its neighboors
wake_cell_and_neighboors :: proc(world: ^World, which: [2]int) {
	which_chunk := which / CHUNK_SIZE
	bounds := get_chunk_bounds(which_chunk)
	// Wake home chunk
	if chunk, ok := get_chunk(world, which_chunk).?; ok {
		add_chunk_work(chunk, which)
		chunk.awake = true
	}
	// Wake neighboring chunks
	if which.x == bounds.low.x {
		wake_cell(world, [2]int{which.x - 1, which.y})
	} else if which.x == bounds.high.x - 1 {
		wake_cell(world, [2]int{which.x + 1, which.y})
	}
	if which.y == bounds.low.y {
		wake_cell(world, [2]int{which.x, which.y - 1})
	} else if which.y == bounds.high.y - 1 {
		wake_cell(world, [2]int{which.x, which.y + 1})
	}
}
// Wake a single cell so it will be processed next frame
wake_cell :: proc(world: ^World, which: [2]int) {
	// Wake home chunk
	if chunk, ok := get_chunk(world, which / CHUNK_SIZE).?; ok {
		add_chunk_work(chunk, which)
		chunk.awake = true
	}
}

swap_cells :: proc(world: ^World, from, to: [2]int) {
	from_index := from.x + from.y * world.width
	to_index := to.x + to.y * world.width

	world.cells[to_index], world.cells[from_index] = world.cells[from_index], world.cells[to_index]

	from_chunk := get_chunk(world, from / CHUNK_SIZE).? or_else load_chunk(world, from / CHUNK_SIZE).?
	to_chunk := get_chunk(world, to / CHUNK_SIZE).? or_else load_chunk(world, to / CHUNK_SIZE).?

	wake_cell_and_neighboors(world, from)
	wake_cell_and_neighboors(world, to)

	from_chunk.modified = true
	to_chunk.modified = true
}

move_cell :: proc(world: ^World, from, to: [2]int) {
	from_index := from.x + from.y * world.width
	to_index := to.x + to.y * world.width

	world.cells[to_index] = world.cells[from_index]
	world.cells[from_index] = {}

	from_chunk := get_chunk(world, from / CHUNK_SIZE).?
	to_chunk := get_ready_chunk(world, to / CHUNK_SIZE).?

	wake_cell_and_neighboors(world, from)
	wake_cell_and_neighboors(world, to)

	if is_valid_cell(world, {to.x - 1, to.y}) {
		world.cells[to.x - 1 + to.y * world.width].stuck = false
	}
	if is_valid_cell(world, {to.x + 1, to.y}) {
		world.cells[to.x + 1 + to.y * world.width].stuck = false
	}
	if is_valid_cell(world, {to.x, to.y + 1}) {
		world.cells[to.x + (to.y + 1) * world.width].stuck = false
	}

	from_chunk.modified = true
	to_chunk.modified = true
}

traverse_world_int :: proc(world: ^World, from, to: [2]int) -> (res: Traversal_Result) {
	res.end = to

	if from == to { 
		return 
	}
	diff := from - to
	diff_x_is_larger := abs(diff.x) > abs(diff.y)
	mod: [2]int = {diff.x < 0 ? 1 : -1, diff.y < 0 ? 1 : -1}
	upper_bound := max(abs(diff.x), abs(diff.y));
	min := min(abs(diff.x), abs(diff.y));
	slope := (min == 0 || upper_bound == 0) ? 0 : (f32(min + 1) / f32(upper_bound + 1))
	smaller_count: int = 0;
	prev := from
	for i: int = 1; i <= upper_bound; i += 1 {
		smaller_count = int(math.floor_f32(f32(i) * slope))
		inc: [2]int
		if diff_x_is_larger {
			inc.x = i
			inc.y = smaller_count
		} else {
			inc.y = i
			inc.x = smaller_count
		}
		next: [2]int = from + inc * mod
		if get_cell(world, next).kind != .Empty {
			res.blocked = true
			res.hit = next
			res.end = prev
			return
		}
		prev = next
	}
	return
}

traverse_world_vec :: proc(world: ^World, from, to: [2]f32) -> Traversal_Result {
	return traverse_world_int(world, {int(from.x), int(from.y)}, {int(to.x), int(to.y)})
}

traverse_world :: proc {
	traverse_world_int, 
	traverse_world_vec,
}
