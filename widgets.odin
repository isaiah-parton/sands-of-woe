package game

import "base:intrinsics"
import "base:runtime"
import rl "vendor:raylib"

Widget_ID :: u32

Stack :: struct($T: typeid, $N: int) {
	items: [N]T,
	height: int,
}
push :: proc(stack: ^Stack($T, $N), item: T) {
	stack.items[stack.height] = item
	stack.height += 1
}
pop :: proc(stack: ^Stack($T, $N)) {
	stack.height -= 1
}
top :: proc(stack: ^Stack($T, $N)) -> (item: T, ok: bool) #optional_ok {
	assert(stack.height < len(stack.items))
	if stack.height == 0 {
		return {}, false
	}
	return stack.items[stack.height - 1], true
}

FNV1A32_OFFSET_BASIS :: 0x811c9dc5
FNV1A32_PRIME :: 0x01000193
fnv32a :: proc(data: []byte, seed: u32) -> u32 {
	h: u32 = seed;
	for b in data {
		h = (h ~ u32(b)) * FNV1A32_PRIME;
	}
	return h;
}
/*
	Unique id creation
*/
hash :: proc {
	hash_string,
	hash_rawptr,
	hash_uintptr,
	hash_bytes,
	hash_loc,
	hash_int,
}
hash_int :: #force_inline proc(num: int) -> Widget_ID {
	hash := top(&game.id_stack) or_else FNV1A32_OFFSET_BASIS
	return hash ~ (Widget_ID(num) * FNV1A32_PRIME)
}
hash_string :: #force_inline proc(str: string) -> Widget_ID { 
	return hash_bytes(transmute([]byte)str) 
}
hash_rawptr :: #force_inline proc(data: rawptr, size: int) -> Widget_ID { 
	return hash_bytes(([^]u8)(data)[:size])  
}
hash_uintptr :: #force_inline proc(ptr: uintptr) -> Widget_ID { 
	ptr := ptr
	return hash_bytes(([^]u8)(&ptr)[:size_of(ptr)])  
}
hash_bytes :: proc(bytes: []byte) -> Widget_ID {
	return fnv32a(bytes, top(&game.id_stack) or_else FNV1A32_OFFSET_BASIS)
}
hash_loc :: proc(loc: runtime.Source_Code_Location) -> Widget_ID {
	hash := hash_bytes(transmute([]byte)loc.file_path)
	hash = hash ~ (Widget_ID(loc.line) * FNV1A32_PRIME)
	hash = hash ~ (Widget_ID(loc.column) * FNV1A32_PRIME)
	return hash
}

push_id_int :: proc(num: int) {
	push(&game.id_stack, hash_int(num))
}
push_id_string :: proc(str: string) {
	push(&game.id_stack, hash_string(str))
}
push_id_other :: proc(id: Widget_ID) {
	push(&game.id_stack, id)
}
push_id :: proc {
	push_id_int,
	push_id_string,
	push_id_other,
}

pop_id :: proc() {
	pop(&game.id_stack)
}

/*
	Widgets
*/
button :: proc(origin, size: [2]f32, text: cstring, selected: bool = false) -> bool {
	hovered := point_in_bounds(game.mouse_point, Bounds(f32){origin, origin + size})
	text_size := rl.MeasureText(text, 32)
	if hovered {
		rl.DrawRectangleRec({origin.x, origin.y, size.x, size.y}, rl.GOLD)
		game.widget_hovered = true
	} else {
		rl.DrawRectangleLinesEx({origin.x, origin.y, size.x, size.y}, 2, rl.LIGHTGRAY)
	}
	rl.DrawTextEx(game.font, text, {origin.x + size.x / 2 - f32(text_size) / 2, origin.y + size.y / 2 - 16}, 32, 1, rl.BLACK if hovered else rl.LIGHTGRAY)
	return hovered && rl.IsMouseButtonPressed(.LEFT)
}

color_button :: proc(origin, size: [2]f32, color: rl.Color, selected: bool = false) -> bool {
	hovered := point_in_bounds(game.mouse_point, Bounds(f32){origin, origin + size})
	if hovered || selected {
		rl.DrawRectangleLinesEx({origin.x, origin.y, size.x, size.y}, 2, rl.WHITE if selected else rl.GRAY)
	}
	if hovered {
		game.widget_hovered = true
	}
	rl.DrawRectangleRec({origin.x + 4, origin.y + 4, size.x - 8, size.y - 8}, color)
	return hovered && rl.IsMouseButtonPressed(.LEFT)
}
