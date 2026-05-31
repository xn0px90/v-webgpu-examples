module main

import gg
import math
import time
import webgpu

const win_w = 1280
const win_h = 720
const move_speed = f32(2.6)
const turn_speed = f32(1.9)
const fov = f32(1.02)
const max_dist = f32(18.0)
const map_data = [
	'1111111111111111',
	'1000000000000001',
	'1011110111110101',
	'1010000100010101',
	'1010111101010101',
	'1010100001010101',
	'1010101111010101',
	'1000101000010001',
	'1110101011111101',
	'1000001000000001',
	'1011111011111101',
	'1000000000000001',
	'1111111111111111',
]

struct Vec2 {
mut:
	x f32
	y f32
}

struct Player {
mut:
	pos   Vec2
	angle f32
}

struct App {
mut:
	gg        &gg.Context = unsafe { nil }
	last_tick i64
	player    Player
	key_down  map[gg.KeyCode]bool
}

fn main() {
	mut app := &App{
		last_tick: time.ticks()
		player: Player{
			pos: Vec2{ x: 3.5, y: 3.5 }
			angle: 0.2
		}
		key_down: map[gg.KeyCode]bool{}
	}
	app.gg = gg.new_context(
		width: win_w
		height: win_h
		create_window: true
		window_title: 'v-webgpu visual test: doom raycaster'
		bg_color: gg.rgb(10, 12, 18)
		event_fn: on_event
		frame_fn: on_frame
		user_data: app
	)
	app.gg.run()
}

fn on_event(e &gg.Event, mut app App) {
	if e.typ == .key_down {
		app.key_down[e.key_code] = true
		if e.key_code == .escape {
			app.gg.quit()
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
	mut turn := f32(0)
	if app.is_key_down(.left) || app.is_key_down(.a) {
		turn -= 1
	}
	if app.is_key_down(.right) || app.is_key_down(.d) {
		turn += 1
	}
	app.player.angle += turn * turn_speed * dt
	app.player.angle = wrap_angle(app.player.angle)

	mut move := f32(0)
	if app.is_key_down(.w) || app.is_key_down(.up) {
		move += 1
	}
	if app.is_key_down(.s) || app.is_key_down(.down) {
		move -= 1
	}
	if math.abs(move) > 0.001 {
		forward := Vec2{
			x: cosf(app.player.angle)
			y: sinf(app.player.angle)
		}
		target := Vec2{
			x: app.player.pos.x + forward.x * move * move_speed * dt
			y: app.player.pos.y + forward.y * move * move_speed * dt
		}
		app.try_move(target)
	}

	mut strafe := f32(0)
	if app.is_key_down(.q) {
		strafe -= 1
	}
	if app.is_key_down(.e) {
		strafe += 1
	}
	if math.abs(strafe) > 0.001 {
		right := Vec2{
			x: cosf(app.player.angle + f32(math.pi / 2.0))
			y: sinf(app.player.angle + f32(math.pi / 2.0))
		}
		target := Vec2{
			x: app.player.pos.x + right.x * strafe * move_speed * 0.85 * dt
			y: app.player.pos.y + right.y * strafe * move_speed * 0.85 * dt
		}
		app.try_move(target)
	}
}

fn (mut app App) try_move(target Vec2) {
	radius := f32(0.19)
	x_ok := !is_wall(target.x + radius, app.player.pos.y) && !is_wall(target.x - radius, app.player.pos.y)
	y_ok := !is_wall(app.player.pos.x, target.y + radius) && !is_wall(app.player.pos.x, target.y - radius)
	if x_ok {
		app.player.pos.x = target.x
	}
	if y_ok {
		app.player.pos.y = target.y
	}
}

fn (mut app App) draw() {
	app.gg.begin()
	draw_background(mut app.gg)
	draw_world(mut app.gg, app.player)
	draw_hud(mut app.gg, app.player)
	app.gg.end()
}

fn draw_background(mut g gg.Context) {
	half := win_h / 2
	for y in 0 .. half {
		t := f32(y) / f32(half)
		r := u8(20 + int(20.0 * t))
		gr := u8(26 + int(28.0 * t))
		b := u8(38 + int(50.0 * t))
		g.draw_line(0, y, win_w, y, gg.rgb(r, gr, b))
	}
	for y in half .. win_h {
		t := f32(y - half) / f32(half)
		r := u8(24 + int(30.0 * t))
		gr := u8(18 + int(16.0 * t))
		b := u8(14 + int(8.0 * t))
		g.draw_line(0, y, win_w, y, gg.rgb(r, gr, b))
	}
}

fn draw_world(mut g gg.Context, player Player) {
	for x in 0 .. win_w {
		ray_cam := (2.0 * f32(x) / f32(win_w)) - 1.0
		ray_angle := player.angle + ray_cam * (fov * 0.5)
		hit := cast_ray(player.pos, ray_angle)

		corrected_dist := hit.dist * f32(math.cos(ray_angle - player.angle))
		d := clamp_min(corrected_dist, 0.05)
		mut line_h := int(f32(win_h) / d)
		if line_h > win_h {
			line_h = win_h
		}
		start := (win_h - line_h) / 2
		end := start + line_h

		shade := clamp01(1.0 - (hit.dist / max_dist))
		base := if hit.side == 1 { f32(0.75) } else { f32(1.0) }
		wall_tint := if hit.cell == `1` { gg.rgb(210, 114, 86) } else { gg.rgb(123, 188, 240) }
		col := darken(wall_tint, f32(1.0) - (shade * base))

		g.draw_line(x, start, x, end, col)
	}
}

struct RayHit {
	dist f32
	cell u8
	side int
}

fn cast_ray(origin Vec2, angle f32) RayHit {
	step := f32(0.02)
	dx := cosf(angle) * step
	dy := sinf(angle) * step
	mut x := origin.x
	mut y := origin.y
	mut dist := f32(0)
	mut prev_cell_x := int(origin.x)
	mut prev_cell_y := int(origin.y)

	for dist < max_dist {
		x += dx
		y += dy
		dist += step
		cell_x := int(x)
		cell_y := int(y)
		if cell_x != prev_cell_x || cell_y != prev_cell_y {
			if is_wall(x, y) {
				cell := map_cell(cell_x, cell_y)
				side := if cell_x != prev_cell_x { 0 } else { 1 }
				return RayHit{
					dist: dist
					cell: cell
					side: side
				}
			}
			prev_cell_x = cell_x
			prev_cell_y = cell_y
		}
	}

	return RayHit{
		dist: max_dist
		cell: `1`
		side: 0
	}
}

fn draw_hud(mut g gg.Context, player Player) {
	g.draw_text(20, 34, 'Doom-style raycaster demo', gg.TextCfg{
		color: gg.rgb(238, 242, 250)
		size: 24
	})
	g.draw_text(20, 62, 'W/S move  A/D turn  Q/E strafe  ESC quit', gg.TextCfg{
		color: gg.rgb(162, 197, 228)
		size: 16
	})
	g.draw_text(20, 86, 'webgpu import ok (${webgpu.bindings_tag()})', gg.TextCfg{
		color: gg.rgb(154, 168, 186)
		size: 14
	})
	g.draw_text(20, 110, 'pos (${player.pos.x:.2f}, ${player.pos.y:.2f})  angle ${player.angle:.2f}', gg.TextCfg{
		color: gg.rgb(154, 168, 186)
		size: 14
	})

	draw_minimap(mut g, player)
}

fn draw_minimap(mut g gg.Context, player Player) {
	scale := 12
	off_x := 20
	off_y := win_h - (map_data.len * scale) - 20

	for my in 0 .. map_data.len {
		row := map_data[my]
		for mx in 0 .. row.len {
			cell := row[mx]
			color := if cell == `1` {
				gg.rgb(86, 93, 104)
			} else {
				gg.rgb(33, 40, 52)
			}
			g.draw_rect_filled(off_x + mx * scale, off_y + my * scale, scale - 1, scale - 1, color)
		}
	}

	px := off_x + int(player.pos.x * f32(scale))
	py := off_y + int(player.pos.y * f32(scale))
	g.draw_circle_filled(px, py, 4, gg.rgb(253, 120, 72))
	lx := px + int(cosf(player.angle) * 11)
	ly := py + int(sinf(player.angle) * 11)
	g.draw_line(px, py, lx, ly, gg.rgb(255, 228, 176))
}

fn map_cell(x int, y int) u8 {
	if y < 0 || y >= map_data.len {
		return `1`
	}
	row := map_data[y]
	if x < 0 || x >= row.len {
		return `1`
	}
	return row[x]
}

fn is_wall(x f32, y f32) bool {
	return map_cell(int(x), int(y)) != `0`
}

fn wrap_angle(a f32) f32 {
	two_pi := f32(math.pi * 2.0)
	mut out := a
	for out < -math.pi {
		out += two_pi
	}
	for out > math.pi {
		out -= two_pi
	}
	return out
}

fn darken(c gg.Color, amount f32) gg.Color {
	t := clamp01(amount)
	r := u8(int(f32(c.r) * (1.0 - t)))
	g := u8(int(f32(c.g) * (1.0 - t)))
	b := u8(int(f32(c.b) * (1.0 - t)))
	return gg.rgb(r, g, b)
}

fn clamp_min(v f32, min_v f32) f32 {
	if v < min_v {
		return min_v
	}
	return v
}

fn clamp01(v f32) f32 {
	if v < 0 {
		return 0
	}
	if v > 1 {
		return 1
	}
	return v
}

fn sinf(a f32) f32 {
	return f32(math.sin(a))
}

fn cosf(a f32) f32 {
	return f32(math.cos(a))
}
