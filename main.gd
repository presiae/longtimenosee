extends Node2D

const W := 1280
const H := 720

const PLAYER_SPEED := 175.0
const PLAYER_R := 9.0
const GUARD_R := 11.0
const INMATE_R := 8.0

const GUARD_PATROL_SPEED := 85.0
const GUARD_CHASE_SPEED := 135.0
const VIEW_DIST := 190.0
const VIEW_HALF_FOV := 0.55 
const NEAR_SENSE := 42.0    
const CATCH_DIST := 19.0
const CONFUSE_TIME := 3.5  

const INMATE_VIEW := 140.0

const RECORD_STEP := 0.05  
const MAX_ECHOES := 5
const ECHO_LINGER := 4.0    



class Guard:
	var points: Array[Vector2] = []
	var wp := 1
	var pos := Vector2.ZERO
	var facing := 0.0
	var mode := "patrol" 
	var target := Vector2.ZERO
	var wait := 0.0
	var confused := 0.0
	var stuck := 0.0


class Inmate:
	var home := Vector2.ZERO
	var pos := Vector2.ZERO
	var target := Vector2.ZERO
	var wait := 1.0
	var gawking := false  
	var snitching := false 
	var cooldown := 0.0


class Echo:
	var path: Array[Vector2] = []
	var pos := Vector2.ZERO
	var alive := true
	var linger := ECHO_LINGER


class Poof:
	var pos := Vector2.ZERO
	var t := 0.0



var walls: Array[Rect2] = []
var exit_rect := Rect2(1190, 60, 50, 90)
var key_pos := Vector2(510, 100)
var start_pos := Vector2(150, 600)

var guard_routes: Array = [
	[Vector2(230, 150), Vector2(230, 450)],
	[Vector2(360, 400), Vector2(660, 400), Vector2(660, 110), Vector2(360, 110)],
	[Vector2(760, 100), Vector2(940, 100), Vector2(940, 620), Vector2(760, 620)],
	[Vector2(1030, 260), Vector2(1220, 260), Vector2(1220, 430), Vector2(1030, 430)],
]
var inmate_homes: Array = [
	Vector2(540, 560), Vector2(540, 300), Vector2(850, 450),
	Vector2(1120, 520), Vector2(150, 330),
]


var player_pos := Vector2.ZERO
var has_key := false
var run_time := 0.0
var record_timer := 0.0
var run_path: Array[Vector2] = []

var echoes: Array[Echo] = []
var guards: Array[Guard] = []
var inmates: Array[Inmate] = []
var poofs: Array[Poof] = []

var state := "play" 
var state_timer := 0.0
var attempt := 1


func _ready() -> void:
	randomize()
	RenderingServer.set_default_clear_color(Color(0.05, 0.05, 0.06))
	_build_level()
	_full_reset()


func _build_level() -> void:
	walls.assign([
		 outer border
		Rect2(0, 0, W, 20), Rect2(0, H - 20, W, 20),
		Rect2(0, 0, 20, H), Rect2(W - 20, 0, 20, H),
		 cell block wall (door gap y 260..340)
		Rect2(300, 20, 20, 240), Rect2(300, 340, 20, 360),
		 middle room cover
		Rect2(420, 180, 180, 20), Rect2(420, 480, 20, 160),
		 wall to yard (gap y 440..520)
		Rect2(700, 20, 20, 420), Rect2(700, 520, 20, 180),
		 yard cover
		Rect2(820, 300, 80, 20),
		 wall to exit room (gap y 200..280)
		Rect2(980, 20, 20, 180), Rect2(980, 280, 20, 420),
		 exit room cover
		Rect2(1090, 320, 110, 20),
	])



func _full_reset() -> void:
	echoes.clear()
	attempt = 1
	_start_run()


func _start_run() -> void:
	state = "play"
	player_pos = start_pos
	has_key = false
	run_time = 0.0
	record_timer = 0.0
	run_path.clear()
	run_path.append(start_pos)
	poofs.clear()

	for e in echoes:
		e.alive = true
		e.linger = ECHO_LINGER
		e.pos = e.path[0]

	guards.clear()
	for route in guard_routes:
		var g := Guard.new()
		g.points.assign(route)
		g.pos = g.points[0]
		g.wp = 1
		g.facing = (g.points[1] - g.points[0]).angle()
		guards.append(g)

	inmates.clear()
	for h in inmate_homes:
		var m := Inmate.new()
		m.home = h
		m.pos = h
		m.target = h
		m.wait = randf_range(0.5, 2.5)
		inmates.append(m)


func _on_caught() -> void:
	state = "caught"
	state_timer = 1.4
	attempt += 1
	if run_path.size() > 8:
		var e := Echo.new()
		e.path.assign(run_path)
		e.pos = e.path[0]
		echoes.append(e)
		while echoes.size() > MAX_ECHOES:
			echoes.pop_front()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_full_reset()



func _process(delta: float) -> void:
	if state == "play":
		_update_play(delta)
	elif state == "caught":
		state_timer -= delta
		if state_timer <= 0.0:
			_start_run()
	_update_poofs(delta)
	queue_redraw()


func _update_play(delta: float) -> void:
	run_time += delta

	
	var dir := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))
		- float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))
		- float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	if dir.length() > 0.0:
		dir = dir.normalized()
	player_pos = _try_move(player_pos, dir * PLAYER_SPEED * delta, PLAYER_R)

	
	record_timer += delta
	while record_timer >= RECORD_STEP:
		record_timer -= RECORD_STEP
		run_path.append(player_pos)

	_update_echoes(delta)
	for g in guards:
		_update_guard(g, delta)
	for m in inmates:
		_update_inmate(m, delta)

	
	for g in guards:
		if g.confused > 0.0:
			continue
		if g.pos.distance_to(player_pos) < CATCH_DIST:
			_on_caught()
			return
		for e in echoes:
			if e.alive and g.pos.distance_to(e.pos) < CATCH_DIST:
				e.alive = false
				g.confused = CONFUSE_TIME
				g.mode = "confused"
				var p := Poof.new()
				p.pos = e.pos
				poofs.append(p)

#saaravi #kumars single hit him up +61 416 233 710
	if not has_key and player_pos.distance_to(key_pos) < 18.0:
		has_key = true
	if has_key and exit_rect.grow(PLAYER_R).has_point(player_pos):
		state = "won"


func _update_echoes(delta: float) -> void:
	var f := run_time / RECORD_STEP
	var i := int(f)
	for e in echoes:
		if not e.alive:
			continue
		if i >= e.path.size() - 1:
			e.pos = e.path[e.path.size() - 1]
			e.linger -= delta
			if e.linger <= 0.0:
				e.alive = false
		else:
			e.pos = e.path[i].lerp(e.path[i + 1], f - float(i))


func _update_poofs(delta: float) -> void:
	for i in range(poofs.size() - 1, -1, -1):
		poofs[i].t += delta
		if poofs[i].t > 0.7:
			poofs.remove_at(i)


 
func _update_guard(g: Guard, delta: float) -> void:
	if g.confused > 0.0:
		g.confused -= delta
		g.mode = "confused"
		if g.confused <= 0.0:
			g.mode = "patrol"
			_recover_patrol(g)
		return

	 Perception: player and echoes look identical to a guard. Nearest wins.
	var found := false
	var best := INF
	if _guard_sees(g, player_pos):
		found = true
		best = g.pos.distance_to(player_pos)
		g.target = player_pos
	for e in echoes:
		if e.alive and _guard_sees(g, e.pos):
			var d := g.pos.distance_to(e.pos)
			if d < best:
				found = true
				best = d
				g.target = e.pos
	if found:
		g.mode = "chase"

	match g.mode:
		"chase":
			var arrived := _move_guard(g, g.target, GUARD_CHASE_SPEED, delta)
			if arrived and not found:
				g.mode = "investigate"
				g.wait = 2.0
			elif g.stuck > 1.0:
				g.mode = "patrol"
				_recover_patrol(g)
		"investigate":
			var there := _move_guard(g, g.target, GUARD_PATROL_SPEED * 1.2, delta)
			if there or g.stuck > 1.0:
				g.wait -= delta
				g.facing += delta * 2.0  look around
				if g.wait <= 0.0:
					g.mode = "patrol"
					_recover_patrol(g)
		_:
			if _move_guard(g, g.points[g.wp], GUARD_PATROL_SPEED, delta):
				g.wp = (g.wp + 1) % g.points.size()
			elif g.stuck > 1.0:
				_recover_patrol(g)


func _guard_sees(g: Guard, p: Vector2) -> bool:
	var d := g.pos.distance_to(p)
	if d > VIEW_DIST:
		return false
	if d > NEAR_SENSE:
		var ang := (p - g.pos).angle()
		if absf(angle_difference(g.facing, ang)) > VIEW_HALF_FOV:
			return false
	return _los_clear(g.pos, p)


 Returns true once the guard has arrived at `to`.
func _move_guard(g: Guard, to: Vector2, speed: float, delta: float) -> bool:
	var to_vec := to - g.pos
	var dist := to_vec.length()
	if dist < 4.0:
		return true
	var step := minf(speed * delta, dist)
	var dir := to_vec / dist
	var before := g.pos
	g.pos = _try_move(g.pos, dir * step, GUARD_R)
	g.facing = lerp_angle(g.facing, dir.angle(), minf(1.0, 8.0 * delta))
	if g.pos.distance_to(before) < step * 0.25:
		g.stuck += delta
	else:
		g.stuck = 0.0
	return false


 After a chase, head back to a patrol point the guard can actually reach.
func _recover_patrol(g: Guard) -> void:
	g.stuck = 0.0
	for i in g.points.size():
		var idx := (g.wp + i) % g.points.size()
		if _los_clear(g.pos, g.points[idx]):
			g.wp = idx
			return
	g.pos = g.points[g.wp]  fallback: walk-back skipped


func _alert_nearest_guard(p: Vector2) -> void:
	var best: Guard = null
	var bd := 450.0
	for g in guards:
		if g.confused > 0.0 or g.mode == "chase":
			continue
		var d := g.pos.distance_to(p)
		if d < bd:
			bd = d
			best = g
	if best != null:
		best.mode = "investigate"
		best.target = p
		best.wait = 2.0



func _update_inmate(m: Inmate, delta: float) -> void:
	m.cooldown = maxf(0.0, m.cooldown - delta)
	m.gawking = false
	m.snitching = false

	
	var see_echo := false
	var echo_pos := Vector2.ZERO
	var best := INF
	for e in echoes:
		if not e.alive:
			continue
		var d := m.pos.distance_to(e.pos)
		if d < INMATE_VIEW and d < best and _los_clear(m.pos, e.pos):
			see_echo = true
			best = d
			echo_pos = e.pos
	if see_echo:
		m.gawking = true
		if best > 45.0:
			m.pos = _try_move(m.pos, (echo_pos - m.pos).normalized() * 70.0 * delta, INMATE_R)
		return

	 
	if m.pos.distance_to(player_pos) < INMATE_VIEW and _los_clear(m.pos, player_pos):
		m.snitching = true
		if m.cooldown <= 0.0:
			m.cooldown = 1.0
			_alert_nearest_guard(player_pos)
		return

	
	if m.wait > 0.0:
		m.wait -= delta
		return
	var to := m.target - m.pos
	if to.length() < 5.0:
		m.wait = randf_range(1.0, 3.0)
		m.target = m.home + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 50.0)
		if _hits_wall(m.target, INMATE_R):
			m.target = m.home
	else:
		m.pos = _try_move(m.pos, to.normalized() * 45.0 * delta, INMATE_R)



func _try_move(pos: Vector2, motion: Vector2, r: float) -> Vector2:
	var p := pos
	var nx := Vector2(p.x + motion.x, p.y)
	if not _hits_wall(nx, r):
		p = nx
	var ny := Vector2(p.x, p.y + motion.y)
	if not _hits_wall(ny, r):
		p = ny
	return p


func _hits_wall(p: Vector2, r: float) -> bool:
	for w in walls:
		var cx := clampf(p.x, w.position.x, w.end.x)
		var cy := clampf(p.y, w.position.y, w.end.y)
		if p.distance_squared_to(Vector2(cx, cy)) < r * r:
			return true
	return false


func _los_clear(a: Vector2, b: Vector2) -> bool:
	var d := a.distance_to(b)
	var steps := int(d / 6.0)
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / float(steps))
		for w in walls:
			if w.has_point(p):
				return false
	return true


func _ray_dist(origin: Vector2, ang: float, maxd: float) -> float:
	var dir := Vector2.from_angle(ang)
	var t := 6.0
	while t < maxd:
		var p := origin + dir * t
		for w in walls:
			if w.has_point(p):
				return t
		t += 6.0
	return maxd


 
func _text_c(p: Vector2, s: String, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, p + Vector2(-400, 0), s,
		HORIZONTAL_ALIGNMENT_CENTER, 800, size, col)


func _text_l(p: Vector2, s: String, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw() -> void:
	 floor zones
	draw_rect(Rect2(0, 0, W, H), Color(0.11, 0.11, 0.13))
	draw_rect(Rect2(20, 20, 280, H - 40), Color(0.15, 0.15, 0.19))
	draw_rect(Rect2(720, 20, 260, H - 40), Color(0.13, 0.15, 0.13))
	draw_rect(Rect2(1000, 20, 240, H - 40), Color(0.16, 0.14, 0.13))
	_text_c(Vector2(160, 50), "CELL BLOCK", 14, Color(1, 1, 1, 0.25))
	_text_c(Vector2(510, 50), "CORRIDOR", 14, Color(1, 1, 1, 0.25))
	_text_c(Vector2(850, 50), "YARD", 14, Color(1, 1, 1, 0.25))
	_text_c(Vector2(1120, 50), "GATE", 14, Color(1, 1, 1, 0.25))

	for w in walls:
		draw_rect(w, Color(0.38, 0.38, 0.45))

	 exit door
	var door_col := Color(0.2, 0.9, 0.4) if has_key else Color(0.7, 0.2, 0.2)
	draw_rect(exit_rect, door_col)
	_text_c(exit_rect.position + Vector2(25, -8), "EXIT" if has_key else "LOCKED", 14, door_col)

	 key
	if not has_key:
		draw_circle(key_pos, 7.0, Color(1.0, 0.85, 0.2))
		draw_arc(key_pos, 12.0 + sin(Time.get_ticks_msec() * 0.005) * 2.0, 0, TAU, 20, Color(1, 0.85, 0.2, 0.5), 1.5)
		_text_c(key_pos + Vector2(0, -18), "KEY", 12, Color(1, 0.85, 0.2))

	 echo trails + echoes
	for e in echoes:
		if e.path.size() > 1:
			draw_polyline(PackedVector2Array(e.path), Color(0.4, 0.9, 1.0, 0.12), 2.0)
	for e in echoes:
		if e.alive:
			draw_circle(e.pos, PLAYER_R + 3.0, Color(0.4, 0.9, 1.0, 0.25))
			draw_circle(e.pos, PLAYER_R, Color(0.5, 0.95, 1.0, 0.7))
			var pulse := 15.0 + sin(Time.get_ticks_msec() * 0.006) * 3.0
			draw_arc(e.pos, pulse, 0, TAU, 24, Color(0.5, 0.95, 1.0, 0.45), 1.5)

	 vision cones
	for g in guards:
		_draw_cone(g)

	 inmates
	for m in inmates:
		draw_circle(m.pos, INMATE_R, Color(0.95, 0.6, 0.2))
		if m.snitching:
			_text_c(m.pos + Vector2(0, -14), "!", 18, Color(1, 0.2, 0.2))
		elif m.gawking:
			_text_c(m.pos + Vector2(0, -14), "*", 18, Color(0.5, 0.95, 1.0))

	 guards
	for g in guards:
		var col := Color(0.3, 0.5, 1.0)
		var mark := ""
		match g.mode:
			"chase":
				col = Color(1.0, 0.35, 0.3)
				mark = "!"
			"investigate":
				col = Color(1.0, 0.8, 0.3)
				mark = "?"
			"confused":
				col = Color(0.6, 0.6, 0.75)
				mark = "@"
		draw_circle(g.pos, GUARD_R, col)
		draw_line(g.pos, g.pos + Vector2.from_angle(g.facing) * (GUARD_R + 5.0), Color.WHITE, 2.0)
		if mark != "":
			_text_c(g.pos + Vector2(0, -18), mark, 20, col)

	 poofs
	for p in poofs:
		draw_arc(p.pos, 8.0 + p.t * 60.0, 0, TAU, 20, Color(0.5, 0.95, 1.0, 1.0 - p.t / 0.7), 2.0)

	 player
	draw_circle(player_pos, PLAYER_R, Color.WHITE)
	if has_key:
		draw_circle(player_pos, 4.0, Color(1.0, 0.85, 0.2))

	_draw_hud()


func _draw_cone(g: Guard) -> void:
	if g.confused > 0.0:
		return
	var col := Color(1, 0.2, 0.2, 0.22) if g.mode == "chase" else Color(1, 1, 0.5, 0.13)
	var n := 20
	var prev := g.pos
	for i in range(n + 1):
		var a := g.facing - VIEW_HALF_FOV + (2.0 * VIEW_HALF_FOV) * float(i) / float(n)
		var pt := g.pos + Vector2.from_angle(a) * _ray_dist(g.pos, a, VIEW_DIST)
		if i > 0:
			var cross := (prev - g.pos).cross(pt - g.pos)
			if absf(cross) > 1.0:
				draw_colored_polygon(PackedVector2Array([g.pos, prev, pt]), col)
		prev = pt


func _draw_hud() -> void:
	var live := 0
	for e in echoes:
		if e.alive:
			live += 1
	_text_l(Vector2(30, H - 30),
		"Attempt %d    Echoes: %d/%d    Key: %s    [WASD/Arrows] move   [R] full restart"
		% [attempt, echoes.size(), MAX_ECHOES, "YES" if has_key else "no"],
		16, Color(1, 1, 1, 0.8))
	if attempt == 1 and state == "play" and run_time < 12.0:
		_text_c(Vector2(W / 2.0, H / 2.0 + 150),
			"Grab the key, reach the exit. Get caught and you leave an ECHO that distracts guards next run.",
			18, Color(1, 1, 1, 0.8))

	if state == "caught":
		draw_rect(Rect2(0, 0, W, H), Color(0.6, 0.0, 0.0, 0.35))
		_text_c(Vector2(W / 2.0, H / 2.0), "CAUGHT!", 64, Color(1, 0.9, 0.9))
		_text_c(Vector2(W / 2.0, H / 2.0 + 40), "Your echo will replay this run. Bounce back...", 22, Color(0.5, 0.95, 1.0))
	elif state == "won":
		draw_rect(Rect2(0, 0, W, H), Color(0.0, 0.3, 0.1, 0.55))
		_text_c(Vector2(W / 2.0, H / 2.0), "ESCAPED!", 64, Color(0.8, 1.0, 0.85))
		_text_c(Vector2(W / 2.0, H / 2.0 + 40), "Took %d attempt(s). Press R to play again." % attempt, 22, Color.WHITE)
