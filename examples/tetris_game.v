module main

import gg
import time
import webgpu

const win_w = 980
const win_h = 760
const board_w = 10
const board_h = 20
const cell_size = 30
const board_px_w = board_w * cell_size
const board_px_h = board_h * cell_size
const board_x = 110
const board_y = 80

const tetromino_masks = [
	[u16(0x0F00), u16(0x2222), u16(0x00F0), u16(0x4444)],
	[u16(0x8E00), u16(0x6440), u16(0x0E20), u16(0x44C0)],
	[u16(0x2E00), u16(0x4460), u16(0x0E80), u16(0xC440)],
	[u16(0x6600), u16(0x6600), u16(0x6600), u16(0x6600)],
	[u16(0x6C00), u16(0x4620), u16(0x06C0), u16(0x8C40)],
	[u16(0x4E00), u16(0x4640), u16(0x0E40), u16(0x4C40)],
	[u16(0xC600), u16(0x2640), u16(0x0C60), u16(0x4C80)],
]

struct Piece {
mut:
	kind int
	rot  int
	x    int
	y    int
}

struct App {
mut:
	gg             &gg.Context = unsafe { nil }
	last_tick      i64
	board          []int
	current        Piece
	next_kind      int
	drop_timer     f32
	drop_interval  f32
	score          int
	lines          int
	level          int
	game_over      bool
	paused         bool
	seed           u32
	key_down       map[gg.KeyCode]bool
	move_left_req  bool
	move_right_req bool
	rotate_req     bool
	hard_drop_req  bool
	restart_req    bool
	pause_req      bool
}

fn main() {
	mut app := &App{}
	app.init_game()
	app.gg = gg.new_context(
		width: win_w
		height: win_h
		create_window: true
		window_title: 'v-webgpu visual test: tetris game'
		bg_color: gg.rgb(8, 12, 22)
		event_fn: on_event
		frame_fn: on_frame
		user_data: app
	)
	app.gg.run()
}

fn (mut app App) init_game() {
	app.last_tick = time.ticks()
	app.board = []int{len: board_w * board_h, init: 0}
	app.drop_timer = 0
	app.drop_interval = 0.68
	app.score = 0
	app.lines = 0
	app.level = 1
	app.game_over = false
	app.paused = false
	app.key_down = map[gg.KeyCode]bool{}
	app.move_left_req = false
	app.move_right_req = false
	app.rotate_req = false
	app.hard_drop_req = false
	app.restart_req = false
	app.pause_req = false
	app.seed = u32(time.ticks()) ^ u32(time.now().unix())
	app.next_kind = app.rand_kind()
	app.spawn_piece()
}

fn on_event(e &gg.Event, mut app App) {
	if e.typ == .key_down {
		app.key_down[e.key_code] = true
		match e.key_code {
			.left, .a { app.move_left_req = true }
			.right, .d { app.move_right_req = true }
			.up, .w, .x { app.rotate_req = true }
			.space { app.hard_drop_req = true }
			.r { app.restart_req = true }
			.p { app.pause_req = true }
			.escape { app.gg.quit() }
			else {}
		}
	}
	if e.typ == .key_up {
		app.key_down[e.key_code] = false
	}
}

fn on_frame(mut app App) {
	now := time.ticks()
	dt := f32(now - app.last_tick) / 1000.0
	app.last_tick = now
	app.update(dt)
	app.draw()
}

fn (app &App) is_key_down(code gg.KeyCode) bool {
	return app.key_down[code] or { false }
}

fn (mut app App) update(dt f32) {
	if app.restart_req {
		app.init_game()
		return
	}
	if app.pause_req && !app.game_over {
		app.paused = !app.paused
	}
	app.pause_req = false

	if app.game_over || app.paused {
		app.consume_inputs()
		return
	}

	if app.move_left_req {
		app.try_move(-1, 0)
	}
	if app.move_right_req {
		app.try_move(1, 0)
	}
	if app.rotate_req {
		app.try_rotate()
	}
	if app.hard_drop_req {
		app.hard_drop()
	}

	soft_drop := app.is_key_down(.down) || app.is_key_down(.s)
	current_interval := if soft_drop { app.drop_interval * 0.14 } else { app.drop_interval }
	app.drop_timer += dt
	for app.drop_timer >= current_interval {
		app.drop_timer -= current_interval
		if !app.try_move(0, 1) {
			app.lock_piece()
			break
		}
	}

	app.consume_inputs()
}

fn (mut app App) consume_inputs() {
	app.move_left_req = false
	app.move_right_req = false
	app.rotate_req = false
	app.hard_drop_req = false
	app.restart_req = false
}

fn (mut app App) try_move(dx int, dy int) bool {
	mut moved := app.current
	moved.x += dx
	moved.y += dy
	if app.can_place(moved) {
		app.current = moved
		return true
	}
	return false
}

fn (mut app App) try_rotate() {
	mut rotated := app.current
	rotated.rot = (rotated.rot + 1) % 4
	if app.can_place(rotated) {
		app.current = rotated
		return
	}
	for kick in [-1, 1, -2, 2] {
		mut shifted := rotated
		shifted.x += kick
		if app.can_place(shifted) {
			app.current = shifted
			return
		}
	}
}

fn (mut app App) hard_drop() {
	for app.try_move(0, 1) {
		app.score += 1
	}
	app.lock_piece()
}

fn (mut app App) lock_piece() {
	mut top_out := false
	mask := tetromino_masks[app.current.kind][app.current.rot]
	for py in 0 .. 4 {
		for px in 0 .. 4 {
			bit_idx := 15 - (py * 4 + px)
			if ((mask >> bit_idx) & 1) == 0 {
				continue
			}
			x := app.current.x + px
			y := app.current.y + py
			if y < 0 {
				top_out = true
				continue
			}
			if x >= 0 && x < board_w && y < board_h {
				app.set_cell(x, y, app.current.kind + 1)
			}
		}
	}
	if top_out {
		app.game_over = true
		return
	}
	cleared := app.clear_lines()
	if cleared > 0 {
		app.lines += cleared
		app.score += score_for_lines(cleared, app.level)
		app.level = 1 + (app.lines / 10)
		app.drop_interval = fast_drop_interval(app.level)
	}
	app.spawn_piece()
}

fn (mut app App) spawn_piece() {
	app.current = Piece{
		kind: app.next_kind
		rot: 0
		x: 3
		y: -1
	}
	app.next_kind = app.rand_kind()
	if !app.can_place(app.current) {
		app.game_over = true
	}
}

fn (app &App) can_place(piece Piece) bool {
	mut ok := true
	app.for_each_cell(piece, fn [app, mut ok] (x int, y int) {
		if !ok {
			return
		}
		if x < 0 || x >= board_w || y >= board_h {
			ok = false
			return
		}
		if y >= 0 && app.get_cell(x, y) != 0 {
			ok = false
		}
	})
	return ok
}

fn (mut app App) clear_lines() int {
	mut cleared := 0
	mut y := board_h - 1
	for y >= 0 {
		mut full := true
		for x in 0 .. board_w {
			if app.get_cell(x, y) == 0 {
				full = false
				break
			}
		}
		if full {
			cleared++
			for ty := y; ty > 0; ty-- {
				for x in 0 .. board_w {
					app.set_cell(x, ty, app.get_cell(x, ty - 1))
				}
			}
			for x in 0 .. board_w {
				app.set_cell(x, 0, 0)
			}
			continue
		}
		y--
	}
	return cleared
}

fn (mut app App) rand_u32() u32 {
	app.seed = app.seed * 1664525 + 1013904223
	return app.seed
}

fn (mut app App) rand_kind() int {
	return int(app.rand_u32() % 7)
}

fn (app &App) for_each_cell(piece Piece, f fn (int, int)) {
	mask := tetromino_masks[piece.kind][piece.rot]
	for py in 0 .. 4 {
		for px in 0 .. 4 {
			bit_idx := 15 - (py * 4 + px)
			if ((mask >> bit_idx) & 1) == 0 {
				continue
			}
			f(piece.x + px, piece.y + py)
		}
	}
}

fn (app &App) cell_index(x int, y int) int {
	return y * board_w + x
}

fn (app &App) get_cell(x int, y int) int {
	return app.board[app.cell_index(x, y)]
}

fn (mut app App) set_cell(x int, y int, value int) {
	idx := app.cell_index(x, y)
	app.board[idx] = value
}

fn score_for_lines(lines int, level int) int {
	base := match lines {
		1 { 100 }
		2 { 300 }
		3 { 500 }
		4 { 800 }
		else { 0 }
	}
	return base * level
}

fn fast_drop_interval(level int) f32 {
	v := f32(0.70) - f32(level - 1) * 0.055
	if v < 0.08 {
		return 0.08
	}
	return v
}

fn (mut app App) draw() {
	app.gg.begin()
	draw_background(mut app.gg)
	draw_board(mut app.gg, app.board)
	draw_piece(mut app.gg, app.current.kind + 1, app.current)
	draw_next_piece(mut app.gg, app.next_kind)
	draw_hud(mut app.gg, app.score, app.lines, app.level)
	if app.paused {
		draw_overlay(mut app.gg, 'PAUSED', gg.rgb(227, 238, 255))
	}
	if app.game_over {
		draw_overlay(mut app.gg, 'GAME OVER', gg.rgb(255, 134, 114))
	}
	app.gg.end()
}

fn draw_background(mut g gg.Context) {
	for y in 0 .. win_h {
		t := f32(y) / f32(win_h)
		r := u8(7 + int(20.0 * t))
		gr := u8(11 + int(18.0 * t))
		b := u8(20 + int(38.0 * t))
		g.draw_line(0, y, win_w, y, gg.rgb(r, gr, b))
	}

	for i in 0 .. 9 {
		x := 40 + i * 108
		g.draw_line(x, 0, x, win_h, gg.rgba(110, 138, 180, 18))
	}
}

fn draw_board(mut g gg.Context, board []int) {
	g.draw_rect_filled(board_x - 10, board_y - 10, board_px_w + 20, board_px_h + 20, gg.rgba(8, 13, 24, 220))
	g.draw_rect_empty(board_x - 10, board_y - 10, board_px_w + 20, board_px_h + 20, gg.rgba(202, 224, 250, 110))

	for y in 0 .. board_h {
		for x in 0 .. board_w {
			v := board[y * board_w + x]
			px := board_x + x * cell_size
			py := board_y + y * cell_size
			if v == 0 {
				g.draw_rect_filled(px, py, cell_size - 1, cell_size - 1, gg.rgb(13, 20, 33))
				continue
			}
			c := tet_color(v)
			g.draw_rect_filled(px, py, cell_size - 1, cell_size - 1, c)
			g.draw_rect_empty(px + 1, py + 1, cell_size - 3, cell_size - 3, gg.rgba(250, 252, 255, 70))
		}
	}
}

fn draw_piece(mut g gg.Context, color_idx int, piece Piece) {
	c := tet_color(color_idx)
	mask := tetromino_masks[piece.kind][piece.rot]
	for py in 0 .. 4 {
		for px in 0 .. 4 {
			bit_idx := 15 - (py * 4 + px)
			if ((mask >> bit_idx) & 1) == 0 {
				continue
			}
			gx := piece.x + px
			gy := piece.y + py
			if gx < 0 || gx >= board_w || gy < 0 || gy >= board_h {
				continue
			}
			sx := board_x + gx * cell_size
			sy := board_y + gy * cell_size
			g.draw_rect_filled(sx, sy, cell_size - 1, cell_size - 1, c)
			g.draw_rect_empty(sx + 1, sy + 1, cell_size - 3, cell_size - 3, gg.rgba(250, 252, 255, 80))
		}
	}
}

fn draw_next_piece(mut g gg.Context, next_kind int) {
	panel_x := board_x + board_px_w + 70
	panel_y := board_y + 30
	g.draw_rect_filled(panel_x - 18, panel_y - 18, 230, 190, gg.rgba(8, 13, 24, 210))
	g.draw_rect_empty(panel_x - 18, panel_y - 18, 230, 190, gg.rgba(196, 219, 248, 120))
	g.draw_text(panel_x, panel_y + 18, 'Next', gg.TextCfg{
		color: gg.rgb(233, 241, 252)
		size: 26
	})

	preview := Piece{
		kind: next_kind
		rot: 0
		x: 0
		y: 0
	}
	mask := tetromino_masks[next_kind][0]
	for py in 0 .. 4 {
		for px in 0 .. 4 {
			bit_idx := 15 - (py * 4 + px)
			if ((mask >> bit_idx) & 1) == 0 {
				continue
			}
			sx := panel_x + 26 + px * 28
			sy := panel_y + 52 + py * 28
			g.draw_rect_filled(sx, sy, 24, 24, tet_color(preview.kind + 1))
			g.draw_rect_empty(sx + 1, sy + 1, 22, 22, gg.rgba(250, 252, 255, 90))
		}
	}
}

fn draw_hud(mut g gg.Context, score int, lines int, level int) {
	g.draw_text(110, 40, 'Tetris-style demo', gg.TextCfg{
		color: gg.rgb(233, 241, 252)
		size: 30
	})
	g.draw_text(460, 44, 'Score ${score}', gg.TextCfg{
		color: gg.rgb(151, 211, 255)
		size: 20
	})
	g.draw_text(620, 44, 'Lines ${lines}', gg.TextCfg{
		color: gg.rgb(151, 211, 255)
		size: 20
	})
	g.draw_text(760, 44, 'Level ${level}', gg.TextCfg{
		color: gg.rgb(151, 211, 255)
		size: 20
	})
	g.draw_text(110, 700, 'A/D or arrows move | Up rotate | Down soft drop | Space hard drop | P pause | R restart | ESC quit', gg.TextCfg{
		color: gg.rgb(164, 180, 205)
		size: 15
	})
	g.draw_text(110, 724, 'webgpu import ok (${webgpu.bindings_tag()})', gg.TextCfg{
		color: gg.rgb(149, 163, 186)
		size: 14
	})
}

fn draw_overlay(mut g gg.Context, label string, color gg.Color) {
	g.draw_rect_filled(230, 250, 520, 170, gg.rgba(7, 12, 21, 214))
	g.draw_rect_empty(230, 250, 520, 170, gg.rgba(199, 220, 248, 120))
	g.draw_text(390, 322, label, gg.TextCfg{
		color: color
		size: 44
	})
	g.draw_text(354, 366, 'Press R to restart', gg.TextCfg{
		color: gg.rgb(215, 229, 246)
		size: 24
	})
}

fn tet_color(i int) gg.Color {
	return match i {
		1 { gg.rgb(97, 235, 255) }
		2 { gg.rgb(93, 146, 255) }
		3 { gg.rgb(255, 174, 91) }
		4 { gg.rgb(255, 233, 98) }
		5 { gg.rgb(129, 240, 127) }
		6 { gg.rgb(196, 126, 255) }
		7 { gg.rgb(255, 117, 124) }
		else { gg.rgb(53, 67, 90) }
	}
}

