module main

import gg
import time
import webgpu

const win_w = 960
const win_h = 640
const ground_h = 96
const bird_x = f32(260)
const bird_r = f32(18)
const gravity = f32(1300)
const flap_impulse = f32(-420)
const pipe_w = f32(96)
const pipe_gap_h = f32(170)
const pipe_speed = f32(230)
const pipe_spawn_interval = f32(1.35)

enum GameState {
	ready
	playing
	game_over
}

struct Bird {
mut:
	y   f32
	vy  f32
	rot f32
}

struct Pipe {
mut:
	x      f32
	gap_y  f32
	passed bool
}

struct App {
mut:
	gg            &gg.Context = unsafe { nil }
	last_tick     i64
	state         GameState
	bird          Bird
	pipes         []Pipe
	spawn_timer   f32
	score         int
	best_score    int
	seed          u32
	key_down      map[gg.KeyCode]bool
	flap_req      bool
	restart_req   bool
	pulse         f32
}

fn main() {
	mut app := &App{}
	app.init_game()
	app.gg = gg.new_context(
		width: win_w
		height: win_h
		create_window: true
		window_title: 'v-webgpu visual test: flappy-style game'
		bg_color: gg.rgb(10, 16, 28)
		event_fn: on_event
		frame_fn: on_frame
		user_data: app
	)
	app.gg.run()
}

fn (mut app App) init_game() {
	app.last_tick = time.ticks()
	app.seed = u32(time.now().unix()) ^ u32(time.ticks())
	app.key_down = map[gg.KeyCode]bool{}
	app.reset_round()
	app.best_score = 0
}

fn (mut app App) reset_round() {
	app.state = .ready
	app.bird = Bird{
		y: (win_h - ground_h) * 0.5
		vy: 0
		rot: 0
	}
	app.pipes = []Pipe{}
	app.spawn_timer = 0
	app.score = 0
	app.flap_req = false
	app.restart_req = false
	app.pulse = 0
}

fn on_event(e &gg.Event, mut app App) {
	if e.typ == .key_down {
		app.key_down[e.key_code] = true
		match e.key_code {
			.space, .up, .w {
				app.flap_req = true
			}
			.r {
				app.restart_req = true
			}
			.escape {
				app.gg.quit()
			}
			else {}
		}
	}
	if e.typ == .key_up {
		app.key_down[e.key_code] = false
	}
}

fn on_frame(mut app App) {
	now := time.ticks()
	mut dt := f32(now - app.last_tick) / 1000.0
	app.last_tick = now
	if dt > 0.05 {
		dt = 0.05
	}
	app.update(dt)
	app.draw()
}

fn (mut app App) update(dt f32) {
	app.pulse += dt
	if app.restart_req {
		app.reset_round()
		return
	}

	if app.state == .ready {
		app.bird.y += f32((time.ticks() % 800) - 400) * 0.00002
		if app.flap_req {
			app.state = .playing
			app.bird.vy = flap_impulse
		}
		app.flap_req = false
		return
	}

	if app.state == .game_over {
		app.flap_req = false
		return
	}

	if app.flap_req {
		app.bird.vy = flap_impulse
	}
	app.flap_req = false

	app.bird.vy += gravity * dt
	app.bird.y += app.bird.vy * dt
	app.bird.rot = clamp(app.bird.vy * 0.0024, -0.7, 1.2)

	app.spawn_timer += dt
	if app.spawn_timer >= pipe_spawn_interval {
		app.spawn_timer -= pipe_spawn_interval
		app.spawn_pipe()
	}

	for i in 0 .. app.pipes.len {
		app.pipes[i].x -= pipe_speed * dt
		if !app.pipes[i].passed && app.pipes[i].x + pipe_w < bird_x {
			app.pipes[i].passed = true
			app.score++
			if app.score > app.best_score {
				app.best_score = app.score
			}
		}
	}

	app.trim_pipes()
	app.check_collisions()
}

fn (mut app App) spawn_pipe() {
	play_h := f32(win_h - ground_h)
	top_margin := f32(80)
	bottom_margin := f32(80)
	min_gap_y := top_margin + pipe_gap_h * 0.5
	max_gap_y := play_h - bottom_margin - pipe_gap_h * 0.5
	gap_y := min_gap_y + app.rand_f32() * (max_gap_y - min_gap_y)
	app.pipes << Pipe{
		x: win_w + 30
		gap_y: gap_y
		passed: false
	}
}

fn (mut app App) trim_pipes() {
	mut kept := []Pipe{cap: app.pipes.len}
	for p in app.pipes {
		if p.x + pipe_w >= -10 {
			kept << p
		}
	}
	app.pipes = kept
}

fn (mut app App) check_collisions() {
	play_h := f32(win_h - ground_h)
	if app.bird.y - bird_r <= 0 || app.bird.y + bird_r >= play_h {
		app.state = .game_over
		return
	}

	for p in app.pipes {
		top_h := p.gap_y - pipe_gap_h * 0.5
		bottom_y := p.gap_y + pipe_gap_h * 0.5
		if circle_rect_overlap(bird_x, app.bird.y, bird_r, p.x, 0, pipe_w, top_h) {
			app.state = .game_over
			return
		}
		if circle_rect_overlap(bird_x, app.bird.y, bird_r, p.x, bottom_y, pipe_w, play_h - bottom_y) {
			app.state = .game_over
			return
		}
	}
}

fn (mut app App) draw() {
	app.gg.begin()
	draw_background(mut app.gg)
	draw_pipes(mut app.gg, app.pipes)
	draw_ground(mut app.gg, app.pulse)
	draw_bird(mut app.gg, app.bird)
	draw_hud(mut app.gg, app.state, app.score, app.best_score)
	app.gg.end()
}

fn draw_background(mut g gg.Context) {
	for y in 0 .. win_h {
		t := f32(y) / f32(win_h)
		r := u8(16 + int(70.0 * t))
		gr := u8(38 + int(90.0 * t))
		b := u8(74 + int(90.0 * t))
		g.draw_line(0, y, win_w, y, gg.rgb(r, gr, b))
	}
	for i in 0 .. 6 {
		x := (i * 170 + 40) % win_w
		y := 60 + (i % 3) * 44
		g.draw_circle_filled(x, y, 22, gg.rgba(234, 246, 255, 72))
		g.draw_circle_filled(x + 16, y + 4, 18, gg.rgba(234, 246, 255, 72))
		g.draw_circle_filled(x - 18, y + 6, 16, gg.rgba(234, 246, 255, 72))
	}
}

fn draw_pipes(mut g gg.Context, pipes []Pipe) {
	play_h := f32(win_h - ground_h)
	for p in pipes {
		top_h := p.gap_y - pipe_gap_h * 0.5
		bottom_y := p.gap_y + pipe_gap_h * 0.5
		pipe_col := gg.rgb(66, 194, 84)
		edge_col := gg.rgb(44, 132, 57)
		g.draw_rect_filled(int(p.x), 0, int(pipe_w), int(top_h), pipe_col)
		g.draw_rect_filled(int(p.x - 6), int(top_h - 24), int(pipe_w + 12), 24, pipe_col)
		g.draw_rect_empty(int(p.x), 0, int(pipe_w), int(top_h), edge_col)

		g.draw_rect_filled(int(p.x), int(bottom_y), int(pipe_w), int(play_h - bottom_y), pipe_col)
		g.draw_rect_filled(int(p.x - 6), int(bottom_y), int(pipe_w + 12), 24, pipe_col)
		g.draw_rect_empty(int(p.x), int(bottom_y), int(pipe_w), int(play_h - bottom_y), edge_col)
	}
}

fn draw_ground(mut g gg.Context, pulse f32) {
	base_y := win_h - ground_h
	g.draw_rect_filled(0, base_y, win_w, ground_h, gg.rgb(185, 147, 84))
	for i in 0 .. 24 {
		x := i * 42
		off := int(pulse * 50.0) % 42
		g.draw_rect_filled(x - off, base_y + 12, 26, 12, gg.rgb(203, 163, 97))
		g.draw_rect_filled(x - off + 10, base_y + 30, 28, 12, gg.rgb(158, 120, 66))
		g.draw_rect_filled(x - off + 2, base_y + 48, 24, 12, gg.rgb(203, 163, 97))
	}
	g.draw_rect_filled(0, base_y - 8, win_w, 8, gg.rgb(215, 190, 116))
}

fn draw_bird(mut g gg.Context, bird Bird) {
	body := gg.rgb(255, 220, 76)
	wing := gg.rgb(248, 164, 52)
	beak := gg.rgb(248, 132, 38)
	eye := gg.rgb(24, 24, 24)
	g.draw_circle_filled(bird_x, bird.y, bird_r, body)
	wing_y := bird.y + f32(5.0 + bird.rot * 8.0)
	g.draw_rounded_rect_filled(int(bird_x - 8), int(wing_y - 7), 18, 12, 4, wing)
	g.draw_triangle_filled(
		bird_x + bird_r - 2,
		bird.y - 2,
		bird_x + bird_r + 18,
		bird.y + 3,
		bird_x + bird_r - 2,
		bird.y + 8,
		beak,
	)
	g.draw_circle_filled(bird_x + 6, bird.y - 6, 3.5, eye)
	g.draw_circle_filled(bird_x + 7, bird.y - 7, 1.4, gg.rgb(255, 255, 255))
}

fn draw_hud(mut g gg.Context, state GameState, score int, best int) {
	g.draw_text(20, 32, 'Flappy-style WebGPU demo', gg.TextCfg{
		color: gg.rgb(244, 249, 255)
		size: 26
	})
	g.draw_text(20, 58, 'Jump: Space/Up/W  Restart: R  Quit: ESC', gg.TextCfg{
		color: gg.rgb(194, 219, 240)
		size: 16
	})
	g.draw_text(20, 82, 'webgpu import ok (${webgpu.bindings_tag()})', gg.TextCfg{
		color: gg.rgb(170, 190, 210)
		size: 14
	})
	g.draw_text(760, 40, 'Score ${score}', gg.TextCfg{
		color: gg.rgb(252, 250, 236)
		size: 28
	})
	g.draw_text(760, 70, 'Best ${best}', gg.TextCfg{
		color: gg.rgb(222, 236, 248)
		size: 20
	})

	if state == .ready {
		draw_overlay(mut g, 'Press Space to Start', gg.rgb(255, 239, 170))
	}
	if state == .game_over {
		draw_overlay(mut g, 'Game Over - Press R', gg.rgb(255, 146, 128))
	}
}

fn draw_overlay(mut g gg.Context, msg string, color gg.Color) {
	g.draw_rect_filled(236, 248, 488, 108, gg.rgba(8, 14, 24, 190))
	g.draw_rect_empty(236, 248, 488, 108, gg.rgba(220, 234, 252, 140))
	g.draw_text(286, 314, msg, gg.TextCfg{
		color: color
		size: 34
	})
}

fn circle_rect_overlap(cx f32, cy f32, cr f32, rx f32, ry f32, rw f32, rh f32) bool {
	closest_x := clamp(cx, rx, rx + rw)
	closest_y := clamp(cy, ry, ry + rh)
	dx := cx - closest_x
	dy := cy - closest_y
	return (dx * dx + dy * dy) <= cr * cr
}

fn clamp(v f32, lo f32, hi f32) f32 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

fn (mut app App) rand_u32() u32 {
	app.seed = app.seed * 1664525 + 1013904223
	return app.seed
}

fn (mut app App) rand_f32() f32 {
	return f32(app.rand_u32() % 10000) / 10000.0
}
