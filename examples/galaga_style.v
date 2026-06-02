module main

import gg
import math
import time
import webgpu

const win_w = 960
const win_h = 720
const ship_w = 42
const ship_h = 20
const enemy_w = 34
const enemy_h = 22
const bullet_w = 4
const bullet_h = 12
const player_speed = f32(420.0)
const bullet_speed = f32(560.0)
const enemy_bullet_speed = f32(250.0)
const ship_fire_cooldown = f32(0.22)
const enemy_fire_cooldown = f32(0.62)

struct Vec2 {
mut:
	x f32
	y f32
}

struct Bullet {
mut:
	pos      Vec2
	velocity Vec2
	friendly bool
	active   bool
}

struct Enemy {
mut:
	origin   Vec2
	pos      Vec2
	alive    bool
	anim_t   f32
	col      int
	row      int
}

struct Star {
mut:
	x     f32
	y     f32
	speed f32
	size  int
}

struct App {
mut:
	gg                &gg.Context = unsafe { nil }
	last_tick         i64
	ship_pos          Vec2
	ship_lives        int
	score             int
	enemies           []Enemy
	bullets           []Bullet
	stars             []Star
	formation_offset  Vec2
	formation_dir     f32
	enemy_fire_timer  f32
	ship_fire_timer   f32
	column_fire_index int
	key_down          map[gg.KeyCode]bool
	game_over         bool
	stage_clear       bool
}

fn main() {
	mut app := &App{}
	app.reset_game()
	app.gg = gg.new_context(
		width: win_w
		height: win_h
		create_window: true
		window_title: 'v-webgpu visual test: galaga style game'
		bg_color: gg.rgb(7, 10, 20)
		event_fn: on_event
		frame_fn: on_frame
		user_data: app
	)
	app.gg.run()
}

fn (mut app App) reset_game() {
	app.last_tick = time.ticks()
	app.ship_pos = Vec2{
		x: win_w * 0.5
		y: win_h - 70
	}
	app.ship_lives = 3
	app.score = 0
	app.formation_offset = Vec2{
		x: 0
		y: 0
	}
	app.formation_dir = 1.0
	app.enemy_fire_timer = 0
	app.ship_fire_timer = 0
	app.column_fire_index = 0
	app.key_down = map[gg.KeyCode]bool{}
	app.game_over = false
	app.stage_clear = false
	app.bullets = []Bullet{}
	app.enemies = create_enemy_wave()
	app.stars = create_stars()
}

fn create_enemy_wave() []Enemy {
	mut enemies := []Enemy{}
	cols := 8
	rows := 4
	spacing_x := f32(72)
	spacing_y := f32(58)
	start_x := f32(150)
	start_y := f32(98)
	for row in 0 .. rows {
		for col in 0 .. cols {
			x := start_x + f32(col) * spacing_x
			y := start_y + f32(row) * spacing_y
			enemies << Enemy{
				origin: Vec2{ x: x, y: y }
				pos: Vec2{ x: x, y: y }
				alive: true
				anim_t: f32(col + row) * 0.2
				col: col
				row: row
			}
		}
	}
	return enemies
}

fn create_stars() []Star {
	mut stars := []Star{cap: 96}
	for i in 0 .. 96 {
		x := f32((i * 73) % win_w)
		y := f32((i * 191) % win_h)
		speed := f32(22 + ((i * 19) % 70))
		size := 1 + ((i * 7) % 3)
		stars << Star{
			x: x
			y: y
			speed: speed
			size: size
		}
	}
	return stars
}

fn on_event(e &gg.Event, mut app App) {
	if e.typ == .key_down {
		app.key_down[e.key_code] = true
		if e.key_code == .escape {
			app.gg.quit()
		}
		if e.key_code == .r && (app.game_over || app.stage_clear) {
			app.reset_game()
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

fn (app &App) is_key_down(key gg.KeyCode) bool {
	return app.key_down[key] or { false }
}

fn (mut app App) update(dt f32) {
	update_stars(mut app.stars, dt)
	if app.game_over || app.stage_clear {
		return
	}

	app.ship_fire_timer -= dt
	app.enemy_fire_timer -= dt

	mut move_x := f32(0)
	if app.is_key_down(.left) || app.is_key_down(.a) {
		move_x -= 1
	}
	if app.is_key_down(.right) || app.is_key_down(.d) {
		move_x += 1
	}
	app.ship_pos.x += move_x * player_speed * dt
	app.ship_pos.x = clamp(app.ship_pos.x, ship_w * 0.5, win_w - ship_w * 0.5)

	if app.is_key_down(.space) && app.ship_fire_timer <= 0 {
		app.spawn_player_bullet()
		app.ship_fire_timer = ship_fire_cooldown
	}

	app.update_enemy_formation(dt)
	if app.enemy_fire_timer <= 0 {
		app.spawn_enemy_bullet()
		app.enemy_fire_timer = enemy_fire_cooldown
	}

	for i in 0 .. app.bullets.len {
		mut b := &app.bullets[i]
		if !b.active {
			continue
		}
		b.pos.x += b.velocity.x * dt
		b.pos.y += b.velocity.y * dt
		if b.pos.y < -20 || b.pos.y > win_h + 20 {
			b.active = false
		}
	}

	app.handle_collisions()
	app.cleanup_entities()

	if app.ship_lives <= 0 {
		app.game_over = true
	}
	if alive_enemy_count(app.enemies) == 0 {
		app.stage_clear = true
	}
}

fn update_stars(mut stars []Star, dt f32) {
	for i in 0 .. stars.len {
		stars[i].y += stars[i].speed * dt
		if stars[i].y > win_h {
			stars[i].y = 0
			stars[i].x = f32((int(stars[i].x) * 37 + 113) % win_w)
		}
	}
}

fn (mut app App) spawn_player_bullet() {
	app.bullets << Bullet{
		pos: Vec2{ x: app.ship_pos.x, y: app.ship_pos.y - ship_h * 0.6 }
		velocity: Vec2{ x: 0, y: -bullet_speed }
		friendly: true
		active: true
	}
}

fn (mut app App) spawn_enemy_bullet() {
	cols := 8
	for _ in 0 .. cols {
		app.column_fire_index = (app.column_fire_index + 1) % cols
		mut selected := -1
		mut best_row := -1
		for i in 0 .. app.enemies.len {
			e := app.enemies[i]
			if !e.alive || e.col != app.column_fire_index {
				continue
			}
			if e.row > best_row {
				best_row = e.row
				selected = i
			}
		}
		if selected >= 0 {
			e := app.enemies[selected]
			app.bullets << Bullet{
				pos: Vec2{ x: e.pos.x, y: e.pos.y + enemy_h * 0.45 }
				velocity: Vec2{ x: 0, y: enemy_bullet_speed }
				friendly: false
				active: true
			}
			return
		}
	}
}

fn (mut app App) update_enemy_formation(dt f32) {
	app.formation_offset.x += app.formation_dir * 85.0 * dt

	mut min_x := f32(1e9)
	mut max_x := f32(-1e9)
	for enemy in app.enemies {
		if !enemy.alive {
			continue
		}
		x := enemy.origin.x + app.formation_offset.x
		if x < min_x {
			min_x = x
		}
		if x > max_x {
			max_x = x
		}
	}

	if min_x < 70 || max_x > win_w - 70 {
		app.formation_dir *= -1
		app.formation_offset.y += 18
	}

	for i in 0 .. app.enemies.len {
		mut e := &app.enemies[i]
		if !e.alive {
			continue
		}
		e.anim_t += dt
		bob := f32(math.sin(e.anim_t * 5.0) * 3.2)
		e.pos.x = e.origin.x + app.formation_offset.x
		e.pos.y = e.origin.y + app.formation_offset.y + bob
		if e.pos.y > app.ship_pos.y - 90 {
			app.game_over = true
		}
	}
}

fn (mut app App) handle_collisions() {
	for bi in 0 .. app.bullets.len {
		mut bullet := &app.bullets[bi]
		if !bullet.active {
			continue
		}
		if bullet.friendly {
			for ei in 0 .. app.enemies.len {
				mut enemy := &app.enemies[ei]
				if !enemy.alive {
					continue
				}
				if rect_overlap(
					bullet.pos.x - bullet_w * 0.5,
					bullet.pos.y - bullet_h * 0.5,
					bullet_w,
					bullet_h,
					enemy.pos.x - enemy_w * 0.5,
					enemy.pos.y - enemy_h * 0.5,
					enemy_w,
					enemy_h,
				) {
					enemy.alive = false
					bullet.active = false
					app.score += 100
					break
				}
			}
		} else {
			if rect_overlap(
				bullet.pos.x - bullet_w * 0.5,
				bullet.pos.y - bullet_h * 0.5,
				bullet_w,
				bullet_h,
				app.ship_pos.x - ship_w * 0.5,
				app.ship_pos.y - ship_h * 0.5,
				ship_w,
				ship_h,
			) {
				bullet.active = false
				app.ship_lives -= 1
			}
		}
	}
}

fn (mut app App) cleanup_entities() {
	mut kept_bullets := []Bullet{cap: app.bullets.len}
	for b in app.bullets {
		if b.active {
			kept_bullets << b
		}
	}
	app.bullets = kept_bullets
}

fn alive_enemy_count(enemies []Enemy) int {
	mut count := 0
	for e in enemies {
		if e.alive {
			count++
		}
	}
	return count
}

fn (mut app App) draw() {
	app.gg.begin()
	draw_background(mut app.gg, app.stars)
	draw_enemies(mut app.gg, app.enemies)
	draw_bullets(mut app.gg, app.bullets)
	draw_ship(mut app.gg, app.ship_pos)
	draw_hud(mut app.gg, app.score, app.ship_lives)
	if app.game_over {
		draw_center_message(mut app.gg, 'GAME OVER', gg.rgb(255, 124, 104))
	}
	if app.stage_clear {
		draw_center_message(mut app.gg, 'STAGE CLEAR', gg.rgb(120, 244, 184))
	}
	if app.game_over || app.stage_clear {
		app.gg.draw_text(330, 436, 'Press R to restart', gg.TextCfg{
			color: gg.rgb(214, 226, 245)
			size: 24
		})
	}
	app.gg.end()
}

fn draw_background(mut g gg.Context, stars []Star) {
	for y in 0 .. win_h {
		t := f32(y) / f32(win_h)
		r := u8(6 + int(12.0 * t))
		gr := u8(10 + int(12.0 * t))
		b := u8(20 + int(34.0 * t))
		g.draw_line(0, y, win_w, y, gg.rgb(r, gr, b))
	}
	for s in stars {
		c := if s.size == 3 { gg.rgb(218, 236, 255) } else { gg.rgb(142, 172, 212) }
		g.draw_rect_filled(int(s.x), int(s.y), s.size, s.size, c)
	}
}

fn draw_ship(mut g gg.Context, pos Vec2) {
	body := gg.rgb(122, 209, 255)
	wing := gg.rgb(72, 151, 236)
	cockpit := gg.rgb(242, 248, 255)
	g.draw_triangle_filled(pos.x, pos.y - ship_h * 0.6, pos.x - ship_w * 0.5, pos.y + ship_h * 0.5, pos.x + ship_w * 0.5, pos.y + ship_h * 0.5, body)
	g.draw_triangle_filled(pos.x - ship_w * 0.5, pos.y + ship_h * 0.5, pos.x - ship_w * 0.16, pos.y + ship_h * 0.08, pos.x - ship_w * 0.36, pos.y + ship_h * 0.56, wing)
	g.draw_triangle_filled(pos.x + ship_w * 0.5, pos.y + ship_h * 0.5, pos.x + ship_w * 0.16, pos.y + ship_h * 0.08, pos.x + ship_w * 0.36, pos.y + ship_h * 0.56, wing)
	g.draw_circle_filled(pos.x, pos.y - ship_h * 0.1, 4, cockpit)
}

fn draw_enemies(mut g gg.Context, enemies []Enemy) {
	for e in enemies {
		if !e.alive {
			continue
		}
		h := enemy_h * 0.5
		w := enemy_w * 0.5
		body := gg.rgb(255, 106, 112)
		detail := gg.rgb(255, 198, 165)
		g.draw_rect_filled(int(e.pos.x - w), int(e.pos.y - h * 0.6), enemy_w, int(enemy_h * 0.9), body)
		g.draw_triangle_filled(
			f32(e.pos.x - w),
			f32(e.pos.y - h * 0.1),
			e.pos.x,
			f32(e.pos.y - h),
			f32(e.pos.x + w),
			f32(e.pos.y - h * 0.1),
			body,
		)
		g.draw_rect_filled(int(e.pos.x - w * 0.75), int(e.pos.y + h * 0.26), int(enemy_w * 0.3), int(enemy_h * 0.2), detail)
		g.draw_rect_filled(int(e.pos.x + w * 0.45), int(e.pos.y + h * 0.26), int(enemy_w * 0.3), int(enemy_h * 0.2), detail)
		g.draw_circle_filled(e.pos.x - 6, e.pos.y - 4, 2.5, gg.rgb(16, 23, 33))
		g.draw_circle_filled(e.pos.x + 6, e.pos.y - 4, 2.5, gg.rgb(16, 23, 33))
	}
}

fn draw_bullets(mut g gg.Context, bullets []Bullet) {
	for b in bullets {
		if !b.active {
			continue
		}
		col := if b.friendly { gg.rgb(115, 229, 255) } else { gg.rgb(255, 164, 102) }
		g.draw_rect_filled(int(b.pos.x - bullet_w * 0.5), int(b.pos.y - bullet_h * 0.5), bullet_w, bullet_h, col)
	}
}

fn draw_hud(mut g gg.Context, score int, lives int) {
	g.draw_text(20, 34, 'Galaga-style demo', gg.TextCfg{
		color: gg.rgb(234, 241, 252)
		size: 24
	})
	g.draw_text(20, 62, 'A/D or Left/Right move  Space shoot  ESC quit', gg.TextCfg{
		color: gg.rgb(166, 195, 228)
		size: 16
	})
	g.draw_text(20, 86, 'webgpu import ok (${webgpu.bindings_tag()})', gg.TextCfg{
		color: gg.rgb(150, 166, 186)
		size: 14
	})
	g.draw_text(20, 110, 'Score ${score}   Lives ${lives}', gg.TextCfg{
		color: gg.rgb(216, 230, 245)
		size: 18
	})
}

fn draw_center_message(mut g gg.Context, message string, color gg.Color) {
	g.draw_rect_filled(258, 304, 448, 126, gg.rgba(8, 12, 20, 188))
	g.draw_rect_empty(258, 304, 448, 126, gg.rgba(202, 222, 252, 150))
	g.draw_text(338, 360, message, gg.TextCfg{
		color: color
		size: 40
	})
}

fn rect_overlap(ax f32, ay f32, aw f32, ah f32, bx f32, by f32, bw f32, bh f32) bool {
	if ax + aw < bx {
		return false
	}
	if bx + bw < ax {
		return false
	}
	if ay + ah < by {
		return false
	}
	if by + bh < ay {
		return false
	}
	return true
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

