module main

import gg
import math
import time
import webgpu

const win_w = 1200
const win_h = 760

struct Vec2 {
	x f32
	y f32
}

struct Gear {
	center       Vec2
	teeth        int
	inner_radius f32
	root_radius  f32
	tip_radius   f32
	thickness    f32
	base_color   gg.Color
	direction    f32
	speed        f32
	phase        f32
}

struct App {
mut:
	gg        &gg.Context = unsafe { nil }
	last_tick i64
	elapsed   f32
	gears     []Gear
}

fn main() {
	mut app := &App{
		last_tick: time.ticks()
		gears: [
			Gear{
				center: Vec2{ x: 420, y: 370 }
				teeth: 28
				inner_radius: 58
				root_radius: 104
				tip_radius: 132
				thickness: 18
				base_color: gg.rgb(227, 95, 57)
				direction: 1.0
				speed: 0.9
				phase: 0.1
			},
			Gear{
				center: Vec2{ x: 620, y: 350 }
				teeth: 20
				inner_radius: 46
				root_radius: 76
				tip_radius: 98
				thickness: 14
				base_color: gg.rgb(61, 172, 223)
				direction: -1.0
				speed: 1.24
				phase: 0.7
			},
			Gear{
				center: Vec2{ x: 740, y: 500 }
				teeth: 16
				inner_radius: 34
				root_radius: 62
				tip_radius: 84
				thickness: 12
				base_color: gg.rgb(88, 211, 149)
				direction: 1.0
				speed: 1.42
				phase: 0.25
			},
		]
	}
	app.gg = gg.new_context(
		width: win_w
		height: win_h
		create_window: true
		window_title: 'v-webgpu visual test: gx gears style'
		bg_color: gg.rgb(9, 15, 25)
		event_fn: event
		frame_fn: frame
		user_data: app
	)
	app.gg.run()
}

fn event(e &gg.Event, mut app App) {
	if e.typ == .key_down && e.key_code == .escape {
		app.gg.quit()
	}
}

fn frame(mut app App) {
	now := time.ticks()
	dt := f32(now - app.last_tick) / 1000.0
	app.last_tick = now
	app.elapsed += dt
	app.draw()
}

fn (mut app App) draw() {
	app.gg.begin()
	draw_background(mut app.gg, app.elapsed)

	for gear in app.gears {
		angle := (app.elapsed * gear.speed * gear.direction) + gear.phase
		draw_gear(mut app.gg, gear, angle)
	}

	app.gg.draw_text(24, 34, 'GX-gears-like visual example', gg.TextCfg{
		color: gg.rgb(231, 239, 252)
		size: 24
	})
	app.gg.draw_text(24, 64, 'module: xn0px90.webgpu | import: webgpu (${webgpu.bindings_tag()})', gg.TextCfg{
		color: gg.rgb(147, 210, 252)
		size: 16
	})
	app.gg.draw_text(24, 90, 'Press ESC to close', gg.TextCfg{
		color: gg.rgb(157, 168, 186)
		size: 15
	})
	app.gg.end()
}

fn draw_background(mut g gg.Context, t f32) {
	for y in 0 .. win_h {
		row_t := f32(y) / f32(win_h)
		r := u8(8 + int(20.0 * row_t))
		gr := u8(14 + int(18.0 * row_t))
		b := u8(24 + int(36.0 * row_t))
		g.draw_line(0, y, win_w, y, gg.rgb(r, gr, b))
	}

	center := Vec2{ x: win_w / 2, y: win_h / 2 }
	for i in 0 .. 8 {
		radius := f32(120 + i * 78)
		alpha := u8(56 - i * 6)
		pulse := f32(i) * 0.2
		offset := f32(math.sin(t * 0.7 + pulse) * 6.0)
		g.draw_circle_empty(center.x, center.y, radius + offset, gg.rgba(160, 188, 225, alpha))
	}
}

fn draw_gear(mut g gg.Context, gear Gear, angle f32) {
	step := f32((math.pi * 2.0) / f64(gear.teeth))
	tooth_half := step * 0.28

	mut outer := []Vec2{cap: gear.teeth * 2}
	for i in 0 .. gear.teeth {
		base := angle + f32(i) * step
		outer << polar_to_xy(gear.center, gear.tip_radius, base - tooth_half)
		outer << polar_to_xy(gear.center, gear.root_radius, base + tooth_half)
	}

	shadow_center := gear.center + Vec2{ x: 8, y: 9 }
	draw_ring_mesh(mut g, shadow_center, outer, gear.inner_radius, gg.rgba(4, 8, 12, 135))
	draw_ring_mesh(mut g, gear.center, outer, gear.inner_radius, gear.base_color)

	edge := lighten(gear.base_color, 0.26)
	draw_polyline_closed(mut g, outer, int(gear.thickness * 0.16) + 1, edge)

	center_color := lighten(gear.base_color, 0.34)
	draw_circle_filled(mut g, gear.center, gear.inner_radius, center_color)
	g.draw_circle_empty(gear.center.x, gear.center.y, gear.inner_radius + 2, gg.rgba(232, 242, 255, 120))
	g.draw_circle_filled(gear.center.x, gear.center.y, gear.inner_radius * 0.24, gg.rgb(15, 25, 36))

	for i in 0 .. 4 {
		a0 := angle * 0.8 + f32(i) * (math.pi / 2.0)
		a1 := a0 + (math.pi / 6.5)
		p0 := polar_to_xy(gear.center, gear.inner_radius * 0.36, a0)
		p1 := polar_to_xy(gear.center, gear.inner_radius * 0.9, a0)
		p2 := polar_to_xy(gear.center, gear.inner_radius * 0.88, a1)
		p3 := polar_to_xy(gear.center, gear.inner_radius * 0.34, a1)
		g.draw_triangle_filled(p0.x, p0.y, p1.x, p1.y, p2.x, p2.y, gg.rgba(244, 250, 255, 42))
		g.draw_triangle_filled(p0.x, p0.y, p2.x, p2.y, p3.x, p3.y, gg.rgba(244, 250, 255, 42))
	}
}

fn draw_ring_mesh(mut g gg.Context, center Vec2, outer []Vec2, inner_radius f32, color gg.Color) {
	if outer.len < 3 {
		return
	}
	for i in 0 .. outer.len {
		next := (i + 1) % outer.len
		ia := point_on_circle(center, inner_radius, outer[i])
		ib := point_on_circle(center, inner_radius, outer[next])

		g.draw_triangle_filled(ia.x, ia.y, outer[i].x, outer[i].y, outer[next].x, outer[next].y, color)
		g.draw_triangle_filled(ia.x, ia.y, outer[next].x, outer[next].y, ib.x, ib.y, color)
	}
}

fn draw_circle_filled(mut g gg.Context, center Vec2, radius f32, color gg.Color) {
	g.draw_circle_filled(center.x, center.y, radius, color)
}

fn draw_polyline_closed(mut g gg.Context, points []Vec2, thickness int, color gg.Color) {
	if points.len < 2 {
		return
	}
	for i in 0 .. points.len {
		next := (i + 1) % points.len
		draw_thick_line(mut g, points[i], points[next], thickness, color)
	}
}

fn draw_thick_line(mut g gg.Context, a Vec2, b Vec2, thickness int, color gg.Color) {
	dx := b.x - a.x
	dy := b.y - a.y
	len := math.sqrt(dx * dx + dy * dy)
	if len <= 0.0001 {
		return
	}
	nx := -dy / len
	ny := dx / len
	half := thickness / 2
	for i in -half .. half + 1 {
		off := f32(i)
		g.draw_line(
			int(a.x + nx * off),
			int(a.y + ny * off),
			int(b.x + nx * off),
			int(b.y + ny * off),
			color,
		)
	}
}

fn point_on_circle(center Vec2, radius f32, toward Vec2) Vec2 {
	dx := toward.x - center.x
	dy := toward.y - center.y
	len := math.sqrt(dx * dx + dy * dy)
	if len <= 0.0001 {
		return center
	}
	s := radius / len
	return Vec2{
		x: f32(center.x + dx * s)
		y: f32(center.y + dy * s)
	}
}

fn polar_to_xy(center Vec2, radius f32, angle f32) Vec2 {
	return Vec2{
		x: f32(center.x + radius * math.cos(angle))
		y: f32(center.y + radius * math.sin(angle))
	}
}

fn lighten(c gg.Color, amount f32) gg.Color {
	t := clamp01(amount)
	r := u8(int(f32(c.r) + (255.0 - f32(c.r)) * t))
	g := u8(int(f32(c.g) + (255.0 - f32(c.g)) * t))
	b := u8(int(f32(c.b) + (255.0 - f32(c.b)) * t))
	return gg.rgb(r, g, b)
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

fn (a Vec2) + (b Vec2) Vec2 {
	return Vec2{
		x: a.x + b.x
		y: a.y + b.y
	}
}
