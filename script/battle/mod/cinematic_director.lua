--------------------------------------------------------------------------------
-- Cinematic Director  v7
-- Automatic action camera for Total War: WARHAMMER III battles.
--
-- Press the camera Tracking key (Options > Controls, "toggle_tracking") to toggle.
-- (The Unit Camera / context_camera key is not reported to script, so it can't be used.)
-- Esc also turns it off.
--
-- While active the camera picks interesting units/clashes, frames them with a
-- mix of shot types, follows them and cuts between them:
--  * imminent charges and fresh contacts interrupt the current shot
--  * several collisions close together are covered by one wide shot, glided to
--    rather than cut to
--  * units taking missile fire are filmed looking toward the incoming volley,
--    swinging onto the target with a zoom punch as it lands
--  * thick melee, heroes and monsters are framed closer, with zoom punches on hits
--  * your general is the narrative anchor: the camera comes back to them between
--    action shots; Regiments of Renown get extra screen time
--  * a subject with nothing going on is dropped early for one that is fighting;
--    with nothing engaged anywhere, shots hold longer and wider
--  * once one side is breaking, the finale films the rout and the victors
--  * a cinematic HUD (cinematic_director_hud.lua) names the unit on camera, keeps
--    a battle report and shows the tide of battle across the top
--
-- Diagnostic log: cinematic_director_log.txt in the game's install folder.
--------------------------------------------------------------------------------

local CFG = {
	toggle_shortcuts = {
		toggle_tracking = true,		-- Insert (camera tracking key)
		context_camera = true,		-- Delete (unit camera key)
	},
	mark_shortcut = nil,		-- optional shortcut name that writes a JITTER MARK line to the log
	cinematic_camera = true,	-- let the camera pass near/through terrain (stops the engine pushing it up when low)
	free_camera = true,			-- lift height limits, disable camera shake and army anchoring while active
	deselect_on_start = true,	-- clear selection so vanilla tracking/unit camera have nothing to follow
	hide_ui = true,				-- hide the battle UI while the director runs
	show_minimap = true,		-- ...but keep the minimap (radar) visible
	show_unit_cards = true,		-- ...and the unit cards at the bottom (the units' state, for paradigm shifts)
	show_panel = false,			-- show the strategy panel (cinematic_director_panel.lua)
	ai_commander = false,		-- old group AI (retired; regiments now follow their tactics, cinematic_director_tactics.lua)
	film_spells = true,			-- cut to lords/heroes casting spells
	hud = true,					-- cinematic HUD: caption, battle report, tide-of-battle bar
	lord_anchor = 0,			-- seconds: come back to your general this often between action shots (0 = off; off: it
								-- was nearly always just the general walking somewhere)
	renown_bonus = 1.35,		-- interest multiplier for Regiments of Renown
	idle_cut_after = 3.5,		-- seconds: drop a subject with nothing going on, when something else is fighting
	finale = true,				-- once one side is breaking, film the rout and the victors
	finale_share = 0.25,		-- ...when the losing side holds less than this share of the fighting strength
	cinematic_bars = false,		-- letterbox bars while hidden
	auto_start = true,			-- start filming as soon as deployment ends (the hotkeys still toggle it)
	stop_on_escape = true,		-- Esc turns the director off (so menus get their UI back)
	hide_banners = true,		-- hide the floating unit banners while the director runs (the HUD's Banners button toggles)

	zoom = true,				-- use field-of-view zooms
	base_fov = 45,				-- resting FOV in degrees while filming (the game default is restored when the director stops)
	min_zoom_factor = 0.4,		-- never zoom tighter than base_fov * this

	tick_ms = 100,				-- camera update interval (real time)
	survey_every = 4,			-- re-scan the battlefield every N ticks
	move_lead = 0.3,			-- seconds: each move_to aims where the camera will be this far ahead and takes this long,
								-- so a late tick never lets the camera run out of motion and stop (stutter)
	max_dt = 0.25,				-- longest real tick we smooth over (a hitch longer than this is treated as this)

	-- smoothing time constants (seconds); larger = floatier, steadier
	anchor_tau = 1.2,			-- how lazily shot anchors follow unit centroids (kills formation jiggle)
	cam_pos_tau = 0.8,
	cam_targ_tau = 0.7,
	blend_tau = 0.4,			-- camera smoothing while gliding between shots
	blend_time = 2.2,			-- seconds the shortest glide lasts
	glide_per_m = 0.006,		-- ...plus this many seconds per metre travelled
	glide_max = 16,				-- ...up to this (a glide takes as long as the speed limits need)
	swoop_lift = 0.15,			-- long glides rise this many metres per metre still to go (pull back to see the field)
	swoop_max = 40,				-- ...up to this high above the shot
	glide_max_pitch = 40,		-- degrees: a glide never looks down more steeply than this
	glide_turn_mult = 3,		-- glides pan this much faster than shots turn (60 deg/s): onto the new subject, then locked on it
	blend_radius = 160,			-- new collisions this close to the current action are blended in, not cut to

	-- the player's view: every shot is bent toward the angle you started the battle looking from
	-- (behind your army, facing the enemy), so the camera doesn't swing round the field
	home_bias = true,
	home_max_dev = 55,			-- degrees: the camera stays within about this much of that angle (soft limit)
	min_pitch = 24,				-- degrees: the camera always looks down on its subject at least this steeply
	max_lift = 85,				-- metres above the subject that min_pitch may raise the camera to
	fov_tau = 0.5,

	-- hard speed limits within a shot (cuts are not limited): whatever a shot asks for,
	-- the camera never moves, turns or zooms faster than this, and eases into and out of motion
	max_cam_speed = 17.5,		-- m/s
	max_cam_accel = 5,			-- m/s^2
	max_turn_rate = 20,			-- degrees/s the view direction can swing
	max_turn_accel = 22.5,		-- degrees/s^2
	max_zoom_rate = 3,			-- FOV degrees/s
	max_zoom_accel = 5,			-- FOV degrees/s^2
	blend_speed_mult = 2,		-- glides between shots go this much faster (a hard cap: long glides just take longer)
	blend_accel_mult = 6,		-- ...and accelerate this much harder (quick to get going and to settle, still no faster)
	axis_blend = 0.15,			-- per second; how quickly a shot's reference axis re-aligns
	axis_min_dist = 25,			-- ...not at all while the two units are closer than this (their bearing is noise)

	-- terrain handling (low cameras)
	min_ground_clearance = 3.0,
	ground_blur = 12,			-- metres; terrain height is averaged over this radius so the camera doesn't trace every bump
	clear_rise_tau = 0.6,		-- obstruction lift: how quickly the camera rises over terrain in the way
	clear_fall_tau = 1.5,		-- ...and how slowly it settles back down

	overview = true,			-- nothing worth showing: hold a high view of the whole field until something happens
	overview_hold = 3,			-- seconds of nothing happening before a shot gives way to the overview

	min_focus_hold = 7,			-- seconds: the camera stays on a subject at least this long before anything can take it away
								-- (events that happen meanwhile wait their turn, see event_ttl)
	shot_min = 5,				-- normal shots, seconds
	shot_max = 9,
	event_interrupt_after = 1.0,	-- a normal shot can be cut for a contact event after this long
	event_min_hold = 3.0,		-- an event shot can only be cut by another event after this long
	widen_after_impact = 1.0,	-- a single-impact shot holds this long past impact before widening for neighbours

	-- close-up framing for thick melee, heroes and monsters
	close_scale = 0.7,			-- distance multiplier
	close_zoom = 0.85,			-- resting FOV multiplier
	close_crowd = 3,			-- melee units within 50 m that count as "thick of it"
	melee_pulse_min = 5,		-- seconds between rhythmic zoom punches in melee close-ups
	melee_pulse_max = 8,
	pulse_scale = 0.5,			-- depth of all zoom punches (impacts, hits, volleys, rhythm); 0 = none, 1 = the old v7 punches
	pulse_gap = 4,				-- seconds: at most one zoom punch this often per shot
	hit_threshold = 0.012,		-- unary hp lost over 0.3 s that counts as a visible hit
	hit_threshold_big = 0.02,
	hit_cooldown = 3,

	-- contact detection
	charge_min_speed = 2.5,		-- m/s
	charge_min_closing = 2.0,	-- m/s
	charge_ttc = 3.5,			-- seconds before impact we cut to a charge
	contact_radius = 14,		-- centroid distance considered "touching"
	recontact_gap = 15,			-- seconds out of melee before a contact counts as fresh again
	pair_cooldown = 25,			-- seconds before the same pair can trigger again
	unit_cooldown = 10,			-- seconds before the same unit can trigger again
	event_ttl = 14,				-- unfilmed events expire after this long (they wait out min_focus_hold)
	cluster_radius = 85,		-- events within this distance are filmed together
	multi_event_radius = 260,	-- ...and the next most important one up to this far away is panned to as well
	event_gather = 0.5,			-- wait this long after the first event so simultaneous ones can group up
	event_urgent_ttc = 1.5,		-- ...unless an impact is this close

	-- the close charge cam, the one exception to the limits above: cavalry about to hit an enemy weak to their
	-- charge are filmed from right behind the riders, low and level, with no speed limit, no bend toward the
	-- player's view and no minimum pitch
	close_charge = true,
	close_charge_ttc = 1.8,		-- seconds before impact it cuts in
	close_charge_min_ttc = 0.6,	-- ...not when the impact is closer than this (too late to see the run-in)
	close_charge_after = 2.0,	-- seconds it watches the hit land
	close_charge_cooldown = 20,	-- seconds between two of them
	close_charge_fov = 52,		-- a little wider than base_fov while riding in

	-- highlights: moments clearly good or bad for the player (a charge into troops weak to it, a hit in the
	-- rear, shooters or artillery caught in melee, a unit breaking, a general badly hurt). Filmed alone and
	-- close, they cut in sooner than other events, and the HUD shows a big green (good) or red (bad) box
	highlights = true,
	highlight_bonus = 4,		-- added to the event's score
	highlight_scale = 0.6,		-- camera distance multiplier for the shot
	highlight_min_hold = 2.5,	-- seconds: a highlight can take the camera off a shot this soon (not off another highlight)
	highlight_repeat = 40,		-- seconds before the same highlight line is filmed again
	hurt_hp = 0.35,				-- a general in melee below this much health is "badly hurt"

	-- action shots: a unit hit hard out of melee (a spell, artillery, a strong volley) is filmed very close and
	-- low, as a highlight that cuts in at once; charges into troops weak to them get the close charge cam (from
	-- behind the riders) or, when your troops are charged, the brace cam (from behind them)
	action_shots = true,
	action_hit = 0.06,			-- unary hp a regiment loses within action_window, out of melee, to count as hit hard
	action_hit_big = 0.08,		-- ...a monster, character or war machine
	action_window = 1.5,		-- seconds
	action_cooldown = 20,		-- seconds per unit
	action_ttl = 5,				-- an unfilmed hit is stale after this long
	action_hold = 1,			-- seconds: a hit can take the camera off another shot this soon (not off a highlight)
	action_pitch = 7,
	action_hl_hold = 3.5,		-- seconds: a hit can take the camera off a highlight this soon			-- degrees: the least an action shot looks down (min_pitch elsewhere)

	-- slow motion for the first contact or damage of an action shot (not in multiplayer, not when paused or
	-- already slowed); the speed goes back to what it was unless the player changed it meanwhile
	slow_mo = true,
	slow_mo_speed = 0.3,
	slow_mo_len = 2,			-- real seconds
	slow_mo_cooldown = 10,

	-- missile fire
	shooter_range = 400,
	shooter_fired_recently = 4,	-- seconds since a unit's ammo last dropped
	volley_cooldown = 20,		-- per target
	volley_ttl = 9,				-- unfilmed volleys expire after this long
	volley_interrupt_after = 2.5,	-- a normal shot can be cut for a volley after this long

	-- what is interesting (see interest())
	use_targets = true,			-- ask units who they are fighting (duels, the right partner in two-shots)
	pick_top = 5,				-- the subject is picked among the N most interesting units...
	pick_sharpness = 2,			-- ...weighted by score ^ this (higher = more predictable)
	hot_cut_after = 2.5,		-- a normal shot can be cut for something much hotter elsewhere after this long
	hot_cut_ratio = 2.5,		-- ...when it scores this many times the current subject
	hot_cut_min = 10,			-- ...and at least this much
	break_cooldown = 12,		-- seconds between "unit breaks" event shots
	log_scores = true,			-- log the top candidates and why, whenever a subject is picked

	diagnostics = true,			-- log how far the real camera strays from what we ask for
	log_shortcuts = 40,
};

local LOG_PATH = "cinematic_director_log.txt";

-- the log only grows: start it afresh at a battle's load once it passes 4 MB (this script loads before
-- the HUD's and the tactics engine's, which append to the same file)
pcall(function()
	local f = io.open(LOG_PATH, "r");
	if not f then return end;
	local size = f:seek("end");
	f:close();
	if size and size > 4 * 1024 * 1024 then
		f = io.open(LOG_PATH, "w");
		if f then f:write("(log started afresh: it had grown past 4 MB)\n"); f:close() end;
	end;
end);

local battle = {
	tide0 = nil,		-- your share of the fighting strength when first measured
	finale = nil,		-- { player_winning, t } once one side is breaking
	uval = {},			-- unit key -> strength value
};

local function log(s)
	local ok, f = pcall(io.open, LOG_PATH, "a");
	if ok and f then
		local t = "";
		pcall(function() t = os.date("%H:%M:%S ") end);
		f:write(t .. tostring(s) .. "\n");
		f:close();
	end;
end;

local cd = {
	active = false,
	toggle_lock = false,
	shortcuts_logged = 0,
	errors = 0,

	now = 0,			-- seconds of director run time
	ticks = 0,
	list = {},			-- latest survey
	by_key = {},		-- key -> survey entry
	prev = {},			-- key -> {x, z, t}
	vel = {},			-- key -> {vx, vz}
	hist = {},			-- key -> {melee, last_melee}
	ammo = {},			-- key -> last ammo count
	last_fired = {},	-- key -> time ammo last dropped
	stat = {},			-- key -> {kills, hp, t, kill_rate, loss_rate}
	filmed_at = {},		-- key -> time it was last the subject of a shot
	pair_seen = {},
	unit_seen = {},
	volley_seen = {},
	events = {},		-- pending contact events
	volleys = {},		-- pending volley events
	recent = {},
	shot = nil,
	cam = nil,
	clear_s = 0,		-- smoothed obstruction lift
};

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

local function rnd(a, b) return a + math.random() * (b - a) end;
local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end;
local function chance(p) return math.random() < p end;
local function lerp(a, b, f) return a + (b - a) * f end;

local function safe(fn, default)
	local ok, r = pcall(fn);
	if ok then return r end;
	return default;
end;

local function ground(x, z)
	local ok, h = pcall(function() return bm:get_terrain_height(x, z) end);
	if ok and type(h) == "number" then return h end;
	return 0;
end;

-- terrain height averaged over a small area
local function gs(x, z)
	local r, d = CFG.ground_blur, CFG.ground_blur * 0.7;
	return (ground(x, z) * 2 + ground(x + r, z) + ground(x - r, z) + ground(x, z + r) + ground(x, z - r)
		+ ground(x + d, z + d) + ground(x - d, z + d) + ground(x + d, z - d) + ground(x - d, z - d)) / 10;
end;

local function dist2(ax, az, bx, bz)
	local dx, dz = bx - ax, bz - az;
	return math.sqrt(dx * dx + dz * dz);
end;

local function norm2(x, z)
	local l = math.sqrt(x * x + z * z);
	if l < 0.0001 then return 0, 1 end;
	return x / l, z / l;
end;

-- exponential smoothing factor for a time constant
local function k(tau) return 1 - math.exp(-(cd.dt or CFG.tick_ms / 1000) / tau) end;

local function smoothstep(x)
	x = clamp(x, 0, 1);
	return x * x * (3 - 2 * x);
end;

local function upos(u)
	local p = u:position();
	return p:get_x(), p:get_y(), p:get_z();
end;

-- battle report lines for the HUD; tone is from the player's point of view
-- icon: a symbol for the HUD; lines with one pop up briefly (things that happen off camera)
local function report(text, tone, icon)
	if CFG.hud and CD_HUD and cd.active then pcall(CD_HUD.report, text, tone, icon) end;
end;

local function uname(c)
	if CD_HUD then return safe(function() return CD_HUD.name(c) end, "A unit") end;
	return "A unit";
end;

local function good_for(c) return c.friendly and "good" or "bad" end;

--------------------------------------------------------------------------------
-- battlefield survey
--------------------------------------------------------------------------------

local function player_alliance_num()
	return safe(function() return bm:get_player_alliance_num() end, 1);
end;

local function is_alive(u)
	return safe(function() return u:number_of_men_alive() > 0 and not u:is_shattered() end, false);
end;

-- the unit this one is attacking (nil if none or unknown)
local function target_key(u)
	if not CFG.use_targets then return nil end;
	local t = safe(function() return u:current_target() end, nil);
	if type(t) ~= "userdata" and type(t) ~= "table" then return nil end;
	local id = safe(function() return t:unique_ui_id() end, nil);
	return id and tostring(id) or nil;
end;

local function survey()
	local list, by_key = {}, {};
	local pa_num = player_alliance_num();
	local pa = safe(function() return bm:alliances():item(pa_num) end, nil);
	local alliances = bm:alliances();
	local now = cd.now;

	for a = 1, alliances:count() do
		local armies = alliances:item(a):armies();
		for r = 1, armies:count() do
			local units = armies:item(r):units();
			for i = 1, units:count() do
				local u = units:item(i);
				if is_alive(u) then
					local friendly = (a == pa_num);
					local visible = friendly or safe(function() return u:is_visible_to_alliance(pa) end, true);
					if visible then
						local x, y, z = upos(u);
						local c = {
							u = u, x = x, y = y, z = z,
							alliance = a,
							friendly = friendly,
							melee = safe(function() return u:is_in_melee() end, false),
							missile = safe(function() return u:is_under_missile_attack() end, false),
							fast = safe(function() return u:is_moving_fast() end, false),
							routing = safe(function() return u:is_routing() end, false),
							general = safe(function() return u:is_commanding_unit() end, false),
							flying = safe(function() return u:can_fly() end, false),
							cavalry = safe(function() return u:is_cavalry() end, false),
							men = safe(function() return u:initial_number_of_men() end, 100),
							start_ammo = safe(function() return u:starting_ammo() end, 0),
							ammo_left = safe(function() return u:ammo_left() end, 0),
							bearing = safe(function() return u:bearing() end, 0),
							hp = tonumber(safe(function() return u:unary_hitpoints() end, 1)) or 1,
							kills = tonumber(safe(function() return u:number_of_enemies_killed() end, 0)) or 0,
							wavering = safe(function() return u:is_wavering() end, false),
							class = tostring(safe(function() return u:unit_class() end, "") or ""),
						};
						c.big = c.men <= 8;	-- monsters, heroes, lords, chariots, war machines
						c.ror = tostring(safe(function() return u:type() end, "")):find("_ror") ~= nil;	-- Regiment of Renown
						c.key = tostring(safe(function() return u:unique_ui_id() end, tostring(u)));
						c.ranged = (c.start_ammo or 0) > 0 and (c.ammo_left or 0) > 0;
						-- flanks and the unit being fought only matter in a fight
						if c.melee then
							c.rear = safe(function() return u:is_rear_flank_threatened() end, false) and true or false;
							c.flanked = c.rear or (safe(function() return u:is_left_flank_threatened() or u:is_right_flank_threatened() end, false) and true or false);
						end;
						if c.melee or c.ranged then c.target_key = target_key(u) end;

						-- velocity
						local pv = cd.prev[c.key];
						local vel = cd.vel[c.key] or { vx = 0, vz = 0 };
						if pv and now - pv.t > 0.05 then
							local dt = now - pv.t;
							vel.vx = vel.vx * 0.4 + 0.6 * (x - pv.x) / dt;
							vel.vz = vel.vz * 0.4 + 0.6 * (z - pv.z) / dt;
						end;
						cd.vel[c.key] = vel;
						cd.prev[c.key] = { x = x, z = z, t = now };
						c.vx, c.vz = vel.vx, vel.vz;
						c.speed = math.sqrt(c.vx * c.vx + c.vz * c.vz);

						-- firing: ammo went down since the last survey
						local pa_ammo = cd.ammo[c.key];
						if pa_ammo and c.ammo_left < pa_ammo then cd.last_fired[c.key] = now end;
						cd.ammo[c.key] = c.ammo_left;

						-- kill and loss rates per second, smoothed over ~2 s
						local st = cd.stat[c.key];
						if not st then
							st = { kills = c.kills, hp = c.hp, t = now, kill_rate = 0, loss_rate = 0 };
							cd.stat[c.key] = st;
						elseif now - st.t > 0.05 then
							local dt = now - st.t;
							local f = 1 - math.exp(-dt / 2);
							st.kill_rate = st.kill_rate + (math.max(c.kills - st.kills, 0) / dt - st.kill_rate) * f;
							st.loss_rate = st.loss_rate + (math.max(st.hp - c.hp, 0) / dt - st.loss_rate) * f;
							st.kills, st.hp, st.t = c.kills, c.hp, now;
						end;
						c.kill_rate, c.loss_rate = st.kill_rate, st.loss_rate;

						list[#list + 1] = c;
						by_key[c.key] = c;
					end;
				end;
			end;
		end;
	end;

	-- how crowded the melee around each unit is, and how much is going on nearby
	for _, c in ipairs(list) do
		local n, heat = 0, 0;
		for _, o in ipairs(list) do
			if o ~= c then
				local d = dist2(c.x, c.z, o.x, o.z);
				if o.melee and d < 50 then n = n + 1 end;
				if d < 70 then heat = heat + (o.melee and 1 or 0) + math.min(o.kill_rate or 0, 4) * 0.25 end;
			end;
		end;
		c.crowd, c.heat = n, heat;
	end;

	cd.by_key = by_key;
	return list;
end;

local function pair_key(a, b)
	if a.key < b.key then return a.key .. "|" .. b.key end;
	return b.key .. "|" .. a.key;
end;

local function nearest_enemy(c, list, max_d)
	local best, bd = nil, max_d or 1e9;
	for _, o in ipairs(list) do
		if o.alliance ~= c.alliance and not o.routing then
			local d = dist2(c.x, c.z, o.x, o.z);
			if d < bd then best, bd = o, d end;
		end;
	end;
	return best, bd;
end;

-- the enemy unit most likely to be shooting at c
local function find_shooter(c, list)
	local best, best_s = nil, -1e9;
	for _, e in ipairs(list) do
		if e.alliance ~= c.alliance and e.start_ammo > 0 and not e.melee and not e.routing then
			local d = dist2(e.x, e.z, c.x, c.z);
			local fired = cd.last_fired[e.key] and (cd.now - cd.last_fired[e.key]) < CFG.shooter_fired_recently;
			if d < CFG.shooter_range and d > 20 and fired then
				local b = d_to_r(e.bearing or 0);
				local fx, fz = math.sin(b), math.cos(b);
				local dx, dz = norm2(c.x - e.x, c.z - e.z);
				local align = fx * dx + fz * dz;
				if align > 0.5 then
					local s = align * 2 - d / CFG.shooter_range;
					if s > best_s then best, best_s = e, s end;
				end;
			end;
		end;
	end;
	return best;
end;

local function unit_weight(c)
	local w = 1;
	if c.general then w = w + 2 end;
	if c.big then w = w + 1.5 end;
	if c.cavalry then w = w + 1 end;
	if c.flying then w = w + 0.5 end;
	if c.ror then w = w + 1 end;
	return w;
end;

--------------------------------------------------------------------------------
-- tide of battle: each side's share of the fighting strength left on the field
-- (every unit, seen or not, as the game's own balance-of-power bar does)
--------------------------------------------------------------------------------

local function unit_value(u)
	local men = safe(function() return u:initial_number_of_men() end, 100) or 100;
	local v = 1;
	if men <= 1 then v = 3
	elseif men <= 8 then v = 2.5
	elseif safe(function() return u:is_cavalry() end, false) then v = 1.4 end;
	if safe(function() return u:is_commanding_unit() end, false) then v = v * 1.3 end;
	return v;
end;

local function compute_tide()
	local pa = player_alliance_num();
	local sp, se, rp, re = 0, 0, 0, 0;
	local alliances = bm:alliances();
	for a = 1, alliances:count() do
		local armies = alliances:item(a):armies();
		for r = 1, armies:count() do
			local units = armies:item(r):units();
			for i = 1, units:count() do
				local u = units:item(i);
				if is_alive(u) then
					local key = tostring(safe(function() return u:unique_ui_id() end, tostring(u)));
					local val = battle.uval[key];
					if not val then val = unit_value(u); battle.uval[key] = val end;
					local hp = clamp(safe(function() return u:unary_hitpoints() end, 1) or 1, 0, 1);
					local s = val * hp;
					if safe(function() return u:is_routing() end, false) then
						s = s * 0.3;
						if a == pa then rp = rp + 1 else re = re + 1 end;
					end;
					if a == pa then sp = sp + s else se = se + s end;
				end;
			end;
		end;
	end;
	local share = (sp + se) > 0 and sp / (sp + se) or 0.5;
	if not battle.tide0 then battle.tide0 = share end;

	-- trend over the last ~20 s
	cd.tide_hist = cd.tide_hist or {};
	local h = cd.tide_hist;
	h[#h + 1] = { t = cd.now, s = share };
	while #h > 2 and cd.now - h[2].t >= 20 do table.remove(h, 1) end;
	local trend = (cd.now - h[1].t >= 8) and (share - h[1].s) or 0;

	-- decided: the losing side holds little of what it started with, and is running
	local lose = math.min(share, 1 - share);
	local lose0 = share < 0.5 and battle.tide0 or (1 - battle.tide0);
	local runners = share < 0.5 and rp or re;
	local decided = lose < CFG.finale_share and lose < lose0 * 0.6 and (runners > 0 or lose < 0.12);
	cd.tide = { share = share, trend = trend, routing_p = rp, routing_e = re, decided = decided or battle.finale ~= nil };

	if CFG.finale and decided and not battle.finale then
		battle.finale = { player_winning = share >= 0.5, t = cd.now };
		log(string.format("FINALE: %s is breaking (your share %.2f, started %.2f)", share >= 0.5 and "the enemy" or "your army", share, battle.tide0));
		if share >= 0.5 then report("The enemy army is breaking!", "good", "rout") else report("Your army is breaking!", "bad", "rout") end;
	end;
end;

--------------------------------------------------------------------------------
-- event detection
--------------------------------------------------------------------------------

-- the enemy most likely hitting c from behind or the side
local function attacker_behind(c, list)
	local b = d_to_r(c.bearing or 0);
	local fx, fz = math.sin(b), math.cos(b);
	local best, bs = nil, 1e9;
	for _, e in ipairs(list) do
		if e.alliance ~= c.alliance and not e.routing then
			local d = dist2(c.x, c.z, e.x, e.z);
			if d < 45 then
				local dx, dz = norm2(e.x - c.x, e.z - c.z);
				local s = (fx * dx + fz * dz) + d / 45 - (e.target_key == c.key and 1 or 0);
				if s < bs then best, bs = e, s end;
			end;
		end;
	end;
	return best;
end;

local EVENT_BONUS = { charge = 1.5, rear = 3, flank = 2, duel = 3, ["break"] = 2 };
local EVENT_TEXT = {
	contact = "%s clash with %s",
	charge = "%s charge %s",
	rear = "%s hit %s in the rear!",
	flank = "%s hit %s in the side",
	duel = "%s and %s square off",
};

local highlight_of;		-- (kind, a, b) -> nil or { tone, text, icon, unit, a, b }: defined with the banner lines below
local hit_line;			-- (kind, c, src) -> text, icon: defined with the banner lines below

local function add_event(kind, a, b, ttc)
	local pk = pair_key(a, b);
	local now = cd.now;
	if cd.pair_seen[pk] and now - cd.pair_seen[pk] < CFG.pair_cooldown then return false end;
	if cd.unit_seen[a.key] and now - cd.unit_seen[a.key] < CFG.unit_cooldown then return false end;
	cd.pair_seen[pk] = now;
	cd.unit_seen[a.key] = now;
	cd.unit_seen[b.key] = now;

	local e = {
		kind = kind, a = a, b = b, t = now, ttc = ttc or 0,
		x = (a.x + b.x) * 0.5, z = (a.z + b.z) * 0.5,
		score = 6 + unit_weight(a) + unit_weight(b) + (EVENT_BONUS[kind] or 0),
	};
	e.hl = highlight_of(kind, a, b);
	-- the same line as the highlight on screen (e.g. a second unit of the same name): an ordinary event
	local cur = cd.shot and cd.shot.highlight;
	local seen = e.hl and cd.hl_seen and cd.hl_seen[e.hl.text];
	if e.hl and ((cur and cur.text == e.hl.text) or (seen and now - seen < CFG.highlight_repeat)) then e.hl = nil end;
	if e.hl then
		e.score = e.score + CFG.highlight_bonus;
		log(string.format("highlight (%s): %s", e.hl.tone, e.hl.text));
	end;
	cd.events[#cd.events + 1] = e;
	if EVENT_TEXT[kind] then report(string.format(EVENT_TEXT[kind], uname(a), uname(b)), good_for(a)) end;
	log(string.format("event %-7s ttc=%.1f a(men=%d gen=%s cav=%s) b(men=%d gen=%s)",
		kind, e.ttc, a.men, tostring(a.general), tostring(a.cavalry), b.men, tostring(b.general)));
	return true;
end;

-- cavalry, chariots or monsters charging something weak to it: infantry, shooters and artillery, but not
-- monsters, cavalry or characters; spears and pikes only when they can't brace (already fighting, or hit from
-- the side or behind)
local function charges_well(a, b)
	local ca, cb = a.class or "", b.class or "";
	local charger = a.cavalry or ca:find("^cav") or ca:find("chariot") or (a.big and ca:find("^mon"));
	if not charger or ca == "cav_mis" or a.routing then return false end;
	if b.big or b.cavalry or b.general or cb:find("^cav") or cb:find("^mon") or cb == "com" or b.routing then return false end;
	if not (cb:find("spr") or cb:find("pik")) then return true end;
	if b.melee then return true end;
	local bb = d_to_r(b.bearing or 0);
	local dx, dz = norm2(a.x - b.x, a.z - b.z);
	return dx * math.sin(bb) + dz * math.cos(bb) < -0.2;
end;

-- a charge that could get the close charge cam: the best one this survey (ours first, shooters and artillery
-- before infantry, the sooner the better)
local function note_close_charge(a, b, ttc)
	if not CFG.close_charge or not charges_well(a, b) then return end;
	local cb = b.class or "";
	local score = (a.friendly and 2 or 0) + (b.friendly and 1.5 or 0) + ((cb:find("mis") or cb:find("^art")) and 1 or 0) - ttc * 0.3;
	local cc = cd.close_cand;
	if cc and cc.t == cd.now and cc.score >= score then return end;
	cd.close_cand = { a = a, b = b, ttc = ttc, t = cd.now, score = score };
end;

-- archers, gunners, artillery and other shooters on foot (cavalry that shoot get away on their own)
local function is_shooter(c)
	local k = c.class or "";
	if c.cavalry or k:find("^cav") then return false end;
	return k:find("^art") ~= nil or k:find("mis") ~= nil or (c.ranged and not c.big and not c.general);
end;

-- c hit hard out of melee (CFG.action_hit): who did it, and an action shot queued (always a highlight, it
-- skips the pair and unit cooldowns and goes stale fast)
local function add_hit(c, drop, list)
	local now = cd.now;
	local src, kind;
	local cast = cd.cast_on and cd.cast_on[c.key];
	if cast and now - cast.t < 4 and cd.by_key[cast.caster] then src, kind = cd.by_key[cast.caster], "spell" end;
	if not src then
		local s = find_shooter(c, list);
		if s then src, kind = s, ((s.class or ""):find("^art") and "bombard" or "riddle") end;
	end;
	if not src then
		-- nobody seen shooting at it: an enemy lord or hero out of the fight is the likely caster
		local bd = 260;
		for _, e in ipairs(list) do
			if e.alliance ~= c.alliance and (e.general or (e.class or ""):find("^com")) and not e.melee and not e.routing then
				local d = dist2(c.x, c.z, e.x, e.z);
				if d < bd then src, bd, kind = e, d, "magic" end;
			end;
		end;
	end;
	if not src then src, kind = nearest_enemy(c, list, 400), "hit" end;
	if not src then return end;
	local text, icon = hit_line(kind, c, src);
	local t = c.friendly and "bad" or "good";
	local e = {
		kind = "hit", how = kind, a = c, b = src, t = now, ttc = 0, ttl = CFG.action_ttl, urgent = true, drop = drop,
		x = c.x, z = c.z,
		score = 8 + unit_weight(c) + (c.friendly and 1 or 0) + math.min(drop, 0.3) * 20 + CFG.highlight_bonus,
	};
	e.hl = { tone = t, text = text, icon = icon, unit = c, a = c, b = src };
	cd.events[#cd.events + 1] = e;
	report(text, t, icon);
	log(string.format("event hit     %s: %.3f hp in %.1fs (%s) -> highlight (%s): %s", tostring(safe(function() return c.u:type() end, "?")), drop, CFG.action_window, kind, t, text));
end;

local function detect_events(list)
	local now = cd.now;

	for _, c in ipairs(list) do
		local h = cd.hist[c.key];
		if not h then
			-- first sight: just record, never fire (avoids a burst of "fresh" contacts on toggle-on)
			cd.hist[c.key] = { melee = c.melee, last_melee = c.melee and now or -1e9, routing = c.routing };
		else
			local long_out = (now - h.last_melee) > CFG.recontact_gap;

			if c.melee and not h.melee and long_out and not c.routing then
				local e = c.target_key and cd.by_key[c.target_key];
				if not (e and e.alliance ~= c.alliance) then e = nearest_enemy(c, list, 45) end;
				if e then
					local duel = (c.big or c.general) and (e.big or e.general);
					if add_event(duel and "duel" or "contact", c, e) and duel then h.duel = e.key end;
				end;
			end;

			-- hit in the rear or the flank while fighting
			if c.melee and not c.routing and ((c.rear and not h.rear) or (c.flanked and not h.flanked)) then
				local att = attacker_behind(c, list);
				if att then add_event(c.rear and "rear" or "flank", att, c) end;
			end;
			h.rear, h.flanked = c.rear, c.flanked;

			-- monsters, heroes and lords locked in combat with each other
			if c.melee and (c.big or c.general) and not c.routing then
				local foe = c.target_key and cd.by_key[c.target_key];
				if not c.target_key then
					local e = nearest_enemy(c, list, 15);
					if e and e.melee then foe = e end;
				end;
				if foe and (foe.big or foe.general) and foe.alliance ~= c.alliance and not foe.routing then
					-- (retried until the pair is off cooldown, e.g. after the charge that started it)
					if foe.key ~= h.duel and add_event("duel", c, foe) then h.duel = foe.key end;
				end;
			elseif not c.melee then
				h.duel = nil;
			end;

			-- a general badly hurt in a fight
			if c.general and c.melee and not c.routing and (c.hp or 1) < CFG.hurt_hp and not h.hurt then
				local foe = c.target_key and cd.by_key[c.target_key];
				if not (foe and foe.alliance ~= c.alliance) then foe = nearest_enemy(c, list, 30) end;
				if foe then h.hurt = true; add_event("hurt", c, foe) end;
			elseif (c.hp or 1) > CFG.hurt_hp + 0.15 then
				h.hurt = nil;
			end;

			if not c.melee and not c.routing and long_out and c.speed > CFG.charge_min_speed then
				local best, best_ttc = nil, CFG.charge_ttc;
				for _, e in ipairs(list) do
					if e.alliance ~= c.alliance and not e.routing then
						local d = dist2(c.x, c.z, e.x, e.z);
						if d < 90 then
							local dx, dz = norm2(e.x - c.x, e.z - c.z);
							local closing = (c.vx - e.vx) * dx + (c.vz - e.vz) * dz;
							if closing > CFG.charge_min_closing then
								local gap = d - CFG.contact_radius - (c.big and 4 or 0) - (e.big and 4 or 0);
								local ttc = gap / closing;
								if ttc > -0.5 and ttc < best_ttc then best, best_ttc = e, ttc end;
							end;
						end;
					end;
				end;
				if best then
					add_event("charge", c, best, math.max(best_ttc, 0));
					note_close_charge(c, best, math.max(best_ttc, 0));
				end;
			end;

			-- hit hard out of melee: an action shot
			if CFG.action_shots then
				local w = h.hpw or {};
				h.hpw = w;
				w[#w + 1] = { t = now, hp = c.hp or 1 };
				while #w > 1 and now - w[1].t > CFG.action_window do table.remove(w, 1) end;
				local drop = w[1].hp - (c.hp or 1);
				cd.hit_seen = cd.hit_seen or {};
				if drop >= (c.big and CFG.action_hit_big or CFG.action_hit) and not c.melee and not c.routing
					and now - h.last_melee > 3 and now - (cd.hit_seen[c.key] or -1e9) >= CFG.action_cooldown
					and not nearest_enemy(c, list, 20) then
					cd.hit_seen[c.key] = now;
					for n = 1, #w do w[n].hp = c.hp or 1 end;
					add_hit(c, drop, list);
				end;
			end;

			h.melee = c.melee;
			if c.melee then h.last_melee = now end;

			-- routs and rallies, for the battle report
			if c.routing and not h.routing then
				report((c.friendly and "Your " or "Enemy ") .. uname(c) .. " routing", c.friendly and "bad" or "good", "rout");
				log(string.format("rout: men=%d friendly=%s", c.men, tostring(c.friendly)));
				-- a unit breaking in the fight (or a big one): film it from the victor's side
				if (now - h.last_melee < 5 or c.big or c.general) and now - (cd.last_break or -1e9) >= CFG.break_cooldown then
					local victor = nearest_enemy(c, list, 60);
					if victor then
						cd.last_break = now;
						add_event("break", victor, c);
					end;
				end;
			elseif h.routing and not c.routing then
				report((c.friendly and "Your " or "Enemy ") .. uname(c) .. " rallying", c.friendly and "good" or "bad", "hold");
			end;
			h.routing = c.routing;
		end;

		-- units coming under missile fire from an identifiable shooter
		if c.missile and not c.melee and not c.routing
			and not (cd.volley_seen[c.key] and now - cd.volley_seen[c.key] < CFG.volley_cooldown) then
			local s = find_shooter(c, list);
			if s then
				cd.volley_seen[c.key] = now;
				report(string.format("%s shoot at %s", uname(s), uname(c)), good_for(s));
				cd.volleys[#cd.volleys + 1] = {
					target = c, shooter = s, t = now,
					score = 3 + unit_weight(c) + (c.friendly and 1 or 0) + (s.big and 1 or 0),
				};
				log(string.format("event volley  target(men=%d friendly=%s) shooter(men=%d) dist=%.0f",
					c.men, tostring(c.friendly), s.men, dist2(c.x, c.z, s.x, s.z)));
			end;
		end;
	end;

	local keep = {};
	for _, e in ipairs(cd.events) do
		local ttl = e.ttl or CFG.event_ttl;
		if now - e.t < ttl and is_alive(e.a.u) and is_alive(e.b.u) then keep[#keep + 1] = e
		elseif e.hl then log(string.format("highlight not filmed (%s): %s", now - e.t < ttl and "a unit is gone" or "too late", e.hl.text)) end;
	end;
	cd.events = keep;

	keep = {};
	for _, e in ipairs(cd.volleys) do
		if now - e.t < CFG.volley_ttl and is_alive(e.target.u) and is_alive(e.shooter.u) then keep[#keep + 1] = e end;
	end;
	cd.volleys = keep;
end;

--------------------------------------------------------------------------------
-- anchors
--------------------------------------------------------------------------------

local function make_anchor(x, y, z) return { x = x, y = y, z = z } end;

local function follow_anchor(a, x, y, z)
	local f = k(CFG.anchor_tau);
	a.x = a.x + (x - a.x) * f;
	a.y = a.y + (y - a.y) * f;
	a.z = a.z + (z - a.z) * f;
end;

local function centroid(units)
	local sx, sy, sz, n = 0, 0, 0, 0;
	local pts = {};
	for _, c in ipairs(units) do
		if is_alive(c.u) then
			local x, y, z = upos(c.u);
			sx, sy, sz, n = sx + x, sy + y, sz + z, n + 1;
			pts[#pts + 1] = { x, z };
		end;
	end;
	if n == 0 then return nil end;
	local cx, cy, cz = sx / n, sy / n, sz / n;
	local spread = 0;
	for _, p in ipairs(pts) do spread = math.max(spread, dist2(cx, cz, p[1], p[2])) end;
	return cx, cy, cz, spread;
end;

--------------------------------------------------------------------------------
-- zoom
--------------------------------------------------------------------------------

-- quick punch-in at shot time t0: ramp in, hold, ease back out
local function punch(t, t0, amount)
	amount = amount * CFG.pulse_scale;
	if t < t0 then return 1 end;
	local d = t - t0;
	if d < 0.4 then return 1 - amount * smoothstep(d / 0.4) end;
	if d < 1.4 then return 1 - amount end;
	return 1 - amount * (1 - smoothstep((d - 1.4) / 1.5));
end;

local function push(sh, t, amount)
	return 1 - amount * smoothstep(t / sh.duration);
end;

-- pulses: short zoom punches triggered by hits / rhythm
local function add_pulse(sh, amount, t_in, hold, t_out)
	if CFG.pulse_scale <= 0 then return end;
	if sh.last_pulse and sh.elapsed - sh.last_pulse < CFG.pulse_gap then return end;
	sh.last_pulse = sh.elapsed;
	sh.pulses = sh.pulses or {};
	sh.pulses[#sh.pulses + 1] = { t0 = sh.elapsed, a = amount * CFG.pulse_scale, i = t_in or 0.2, h = hold or 0.6, o = t_out or 1.1 };
end;

local function pulse_factor(sh)
	if not sh.pulses then return 1 end;
	local f, keep = 1, {};
	for _, p in ipairs(sh.pulses) do
		local d = sh.elapsed - p.t0;
		local env;
		if d < p.i then env = smoothstep(d / p.i)
		elseif d < p.i + p.h then env = 1
		elseif d < p.i + p.h + p.o then env = 1 - smoothstep((d - p.i - p.h) / p.o)
		else env = nil end;
		if env then
			f = f * (1 - p.a * env);
			keep[#keep + 1] = p;
		end;
	end;
	sh.pulses = keep;
	return f;
end;

--------------------------------------------------------------------------------
-- shot types: frame(sh, P, Q, C, t) -> cam x,y,z, target x,y,z
-- P = primary anchor, Q = partner anchor (may be nil), C = group anchor
-- sh.fx/fz = reference axis (P toward Q / direction of travel), changes slowly
-- sh.sc = distance scale (closer for thick melee / heroes / monsters)
--------------------------------------------------------------------------------

local SHOTS = {};
local slow_mo;		-- (why) -> true if the battle was slowed: see slow motion below

-- the angle the camera sits at, around its subject, for the player's starting view (nil before it is known)
local function home_angle()
	local hm = battle.home;
	if not (CFG.home_bias and hm) then return nil end;
	return math.atan2(-hm.fx, -hm.fz);
end;

SHOTS.tracking = {
	setup = function(sh)
		sh.side = chance(0.5) and 1 or -1;
		sh.dist = (sh.big and rnd(26, 38) or rnd(18, 28)) * sh.sc;
		sh.h = sh.big and rnd(6, 10) or rnd(4, 7);
		sh.dolly = rnd(-1.5, 1.5);
	end,
	frame = function(sh, P, Q, C, t)
		local px, pz = -sh.fz * sh.side, sh.fx * sh.side;
		local x = P.x + px * sh.dist + sh.fx * sh.dolly * t;
		local z = P.z + pz * sh.dist + sh.fz * sh.dolly * t;
		return x, gs(x, z) + sh.h, z, P.x, P.y + sh.look_h, P.z;
	end,
	zoom = function(sh, t) return sh.push_amt and push(sh, t, sh.push_amt) or 1 end,
};

SHOTS.over_shoulder = {
	needs_partner = true,
	setup = function(sh)
		sh.back = (sh.big and rnd(20, 30) or rnd(12, 20)) * sh.sc;
		sh.h = sh.big and rnd(7, 11) or rnd(4.5, 7);
		sh.off = rnd(-7, 7);
	end,
	frame = function(sh, P, Q, C, t)
		local x = P.x - sh.fx * sh.back - sh.fz * sh.off;
		local z = P.z - sh.fz * sh.back + sh.fx * sh.off;
		local tx, tz = P.x + (Q.x - P.x) * 0.7, P.z + (Q.z - P.z) * 0.7;
		return x, gs(x, z) + sh.h, z, tx, gs(tx, tz) + sh.look_h, tz;
	end,
	zoom = function(sh, t)
		if sh.event then return punch(t, sh.impact_t or 0.4, 0.3) end;
		return 1;
	end,
};

-- low angle looking up: lords, monsters, heroes (kept above the engine's minimum height;
-- the low feel comes from looking up at a high target rather than sitting in the dirt)
SHOTS.heroic = {
	setup = function(sh)
		sh.ang = rnd(-0.9, 0.9);
		sh.dist = (sh.big and rnd(18, 26) or rnd(12, 17)) * sh.sc;
		sh.h = rnd(3.2, 4.2);
		sh.look_h = sh.look_h * 1.8;
	end,
	frame = function(sh, P, Q, C, t)
		local ca, sa = math.cos(sh.ang), math.sin(sh.ang);
		local fx, fz = sh.fx * ca - sh.fz * sa, sh.fx * sa + sh.fz * ca;
		local x, z = P.x + fx * sh.dist, P.z + fz * sh.dist;
		return x, gs(x, z) + sh.h, z, P.x, P.y + sh.look_h, P.z;
	end,
	zoom = function(sh, t) return push(sh, t, 0.3) end,
};

SHOTS.orbit = {
	setup = function(sh)
		sh.a0 = math.random() * 2 * math.pi;
		sh.speed = rnd(0.10, 0.18) * (chance(0.5) and 1 or -1);
		local home = home_angle();
		if home then
			-- a slow drift across the player's side of the subject
			local off = rnd(-0.7, 0.7);
			sh.a0 = home + off;
			sh.speed = rnd(0.04, 0.08) * (off > 0 and -1 or 1);
		end;
		sh.dist = (sh.big and rnd(30, 42) or rnd(24, 34)) * sh.sc;
		sh.h = rnd(9, 15);
	end,
	frame = function(sh, P, Q, C, t)
		local a = sh.a0 + sh.speed * t;
		local x, z = P.x + math.sin(a) * sh.dist, P.z + math.cos(a) * sh.dist;
		return x, gs(x, z) + sh.h, z, P.x, P.y + sh.look_h, P.z;
	end,
	zoom = function(sh, t) return sh.push_amt and push(sh, t, sh.push_amt) or 1 end,
};

SHOTS.wide = {
	setup = function(sh)
		sh.ang = home_angle() and (home_angle() + rnd(-0.5, 0.5)) or math.random() * 2 * math.pi;
		sh.dist = rnd(70, 105);
		sh.h = rnd(35, 55);
		sh.drift = rnd(-0.04, 0.04);
	end,
	frame = function(sh, P, Q, C, t)
		local cx, cz = P.x, P.z;
		if Q then cx, cz = (cx + Q.x) * 0.5, (cz + Q.z) * 0.5 end;
		local a = sh.ang + sh.drift * t;
		local x, z = cx + math.sin(a) * sh.dist, cz + math.cos(a) * sh.dist;
		return x, gs(x, z) + sh.h, z, cx, gs(cx, cz) + 2, cz;
	end,
};

SHOTS.chase = {
	follow_velocity = true,
	setup = function(sh)
		sh.back = sh.big and rnd(22, 30) or rnd(16, 24);
		sh.h = sh.flying and rnd(3.5, 6) or rnd(5, 8);
	end,
	frame = function(sh, P, Q, C, t)
		local x, z = P.x - sh.fx * sh.back, P.z - sh.fz * sh.back;
		local y = math.max(gs(x, z), P.y) + sh.h;
		return x, y, z, P.x + sh.fx * 15, P.y + sh.look_h, P.z + sh.fz * 15;
	end,
};

-- EVENT: side-on view of the collision point
SHOTS.impact = {
	needs_partner = true,
	setup = function(sh)
		sh.side = chance(0.5) and 1 or -1;
		sh.dist = (sh.big or sh.partner_big) and rnd(32, 42) or rnd(24, 34);
		sh.h = rnd(4.5, 8);
		sh.pull = rnd(-6, 6);
	end,
	frame = function(sh, P, Q, C, t)
		local mx, mz = (P.x + Q.x) * 0.5, (P.z + Q.z) * 0.5;
		local px, pz = -sh.fz * sh.side, sh.fx * sh.side;
		local x = mx + px * sh.dist - sh.fx * sh.pull;
		local z = mz + pz * sh.dist - sh.fz * sh.pull;
		return x, gs(x, z) + sh.h, z, mx, gs(mx, mz) + 2.5, mz;
	end,
	zoom = function(sh, t) return punch(t, sh.impact_t or 0.4, 0.45) end,
};

-- EVENT: behind and to the side of the charger, looking at the point of impact
SHOTS.charge_follow = {
	needs_partner = true,
	setup = function(sh)
		sh.back = sh.big and rnd(20, 28) or rnd(14, 22);
		sh.off = rnd(6, 12) * (chance(0.5) and 1 or -1);
		sh.h = rnd(3.5, 5.5);
	end,
	frame = function(sh, P, Q, C, t)
		local x = P.x - sh.fx * sh.back - sh.fz * sh.off;
		local z = P.z - sh.fz * sh.back + sh.fx * sh.off;
		local tx, tz = P.x + (Q.x - P.x) * 0.75, P.z + (Q.z - P.z) * 0.75;
		return x, gs(x, z) + sh.h, z, tx, gs(tx, tz) + sh.look_h, tz;
	end,
	zoom = function(sh, t) return punch(t, sh.impact_t or 0.4, 0.38) end,
};

-- EVENT, the exception to the camera limits: riding in with cavalry the last moments before they hit an enemy
-- weak to their charge. Close behind and beside the riders, low and nearly level, looking at the enemy; it
-- follows the unit without the smoothing and speed limits (they would leave it far behind at a gallop), stops
-- dead at the impact and watches the hit land. Driven by close_camera(), not frame().
SHOTS.charge_close = {
	needs_partner = true,
	direct = true,
	cut_in = true,
	setup = function(sh)
		sh.back = sh.big and rnd(13, 16) or rnd(9, 12);
		sh.off = (sh.big and rnd(5, 7) or rnd(3.5, 6)) * (chance(0.5) and 1 or -1);
		sh.h = sh.big and rnd(3.2, 4) or rnd(2.3, 3.0);
	end,
	frame = function(sh, P, Q, C, t)
		local x, z = P.x - sh.fx * sh.back - sh.fz * sh.off, P.z - sh.fz * sh.back + sh.fx * sh.off;
		return x, gs(x, z) + sh.h, z, Q.x, gs(Q.x, Q.z) + 1.5, Q.z;
	end,
};

-- EVENT, the close charge cam's twin for your troops on the receiving end: low behind them, looking over their
-- heads at the cavalry or monsters coming in; it stops and turns to the hit like the close charge cam.
-- sh.c = your unit, sh.partner = the charger. Driven by close_camera(), not frame().
SHOTS.charge_brace = {
	needs_partner = true,
	direct = true,
	cut_in = true,
	setup = function(sh)
		sh.back = sh.big and rnd(12, 15) or rnd(8, 11);
		sh.off = rnd(3, 6) * (chance(0.5) and 1 or -1);
		sh.h = rnd(2.0, 2.6);
	end,
	frame = function(sh, P, Q, C, t)
		local x, z = P.x - sh.fx * sh.back - sh.fz * sh.off, P.z - sh.fz * sh.back + sh.fx * sh.off;
		return x, gs(x, z) + sh.h, z, Q.x, gs(Q.x, Q.z) + 2, Q.z;
	end,
};

-- EVENT: a unit hit hard by a spell, artillery or a strong volley - very close and low (min_pitch is
-- action_pitch here). Behind your unit (looking toward the fire), in front of an enemy one (from the side the
-- fire came from), so it is the player's side either way. P = the unit hit, Q = where it came from.
SHOTS.action_hit = {
	needs_partner = true,
	cut_in = true,
	setup = function(sh)
		sh.dist = sh.big and rnd(16, 22) or rnd(12, 16);
		sh.ang = rnd(0.45, 0.85) * (chance(0.5) and 1 or -1);
		sh.drift = rnd(0.03, 0.06) * (sh.ang > 0 and -1 or 1);
		sh.toward = sh.c.friendly and -1 or 1;
		sh.h = sh.big and rnd(3.5, 5) or rnd(2.4, 3.4);
		sh.min_pitch = CFG.action_pitch;
	end,
	frame = function(sh, P, Q, C, t)
		local a = sh.ang + sh.drift * t;
		local ca, sa = math.cos(a), math.sin(a);
		local dx, dz = sh.fx * sh.toward, sh.fz * sh.toward;
		local fx, fz = dx * ca - dz * sa, dx * sa + dz * ca;
		local x, z = P.x + fx * sh.dist, P.z + fz * sh.dist;
		return x, gs(x, z) + sh.h, z, P.x, math.max(P.y, gs(P.x, P.z)) + sh.look_h, P.z;
	end,
	zoom = function(sh, t) return punch(t, sh.impact_t or 0.3, 0.25) end,
	on_hit = function(sh) add_pulse(sh, 0.3, 0.15, 0.6, 1.0) end,
};

-- EVENT: several collisions close together - side-on to the battle line, wide enough for all
SHOTS.clash_wide = {
	needs_group = true,
	setup = function(sh)
		sh.side = chance(0.5) and 1 or -1;
		sh.dolly = rnd(-2, 2);
		sh.back_ratio = rnd(0.15, 0.4);
	end,
	frame = function(sh, P, Q, C, t)
		local spread = sh.spread_s;
		local dist = clamp(spread * 1.15 + 35, 45, 200);
		local h = clamp(10 + spread * 0.3, 12, 45);
		local px, pz = -sh.fz * sh.side, sh.fx * sh.side;
		local x = C.x + px * dist - sh.fx * dist * sh.back_ratio + sh.fx * sh.dolly * t;
		local z = C.z + pz * dist - sh.fz * dist * sh.back_ratio + sh.fz * sh.dolly * t;
		return x, math.max(gs(x, z), gs(C.x, C.z)) + h, z, C.x, gs(C.x, C.z) + 2.5, C.z;
	end,
	zoom = function(sh, t)
		if sh.blended then return 1 end;
		return 0.75 + 0.25 * smoothstep(t / 2.5);
	end,
};

-- VOLLEY: behind the target, looking up the line of fire at the incoming volley;
-- when the volley lands the aim swings onto the target with a zoom punch
SHOTS.volley_target = {
	needs_partner = true,
	setup = function(sh)
		sh.back = (sh.big and rnd(24, 32) or rnd(16, 24));
		sh.off = rnd(5, 9) * (chance(0.5) and 1 or -1);
		sh.h = rnd(4.5, 7);
		sh.aim, sh.aim_goal = 0.3, 0.3;
	end,
	frame = function(sh, P, Q, C, t)
		-- fx,fz points from the target (P) toward the shooter (Q)
		local d = dist2(P.x, P.z, Q.x, Q.z);
		local ahead = clamp(d * 0.4, 25, 70);
		local x = P.x - sh.fx * sh.back - sh.fz * sh.off;
		local z = P.z - sh.fz * sh.back + sh.fx * sh.off;
		-- incoming point: up the line of fire, raised to where arrows arc in
		local ix, iz = P.x + sh.fx * ahead, P.z + sh.fz * ahead;
		local iy = gs(ix, iz) + 6 + ahead * 0.15;
		sh.aim = sh.aim + (sh.aim_goal - sh.aim) * k(0.25);
		if sh.aim_hold and sh.elapsed > sh.aim_hold then sh.aim_goal, sh.aim_hold = 0.3, nil end;
		local tx, ty, tz = lerp(ix, P.x, sh.aim), lerp(iy, P.y + sh.look_h, sh.aim), lerp(iz, P.z, sh.aim);
		return x, gs(x, z) + sh.h, z, tx, ty, tz;
	end,
	zoom = function(sh, t) return 0.92 end,
	on_hit = function(sh)
		sh.aim_goal, sh.aim_hold = 0.95, sh.elapsed + 1.3;
		add_pulse(sh, 0.38, 0.18, 0.7, 1.2);
	end,
};

-- VOLLEY: behind the shooters, telephoto on the target, punch in as the volley lands
SHOTS.volley_shooter = {
	needs_partner = true,
	setup = function(sh)
		sh.back = sh.big and rnd(18, 26) or rnd(12, 18);
		sh.off = rnd(5, 9) * (chance(0.5) and 1 or -1);
		sh.h = rnd(4, 6.5);
	end,
	frame = function(sh, P, Q, C, t)
		-- P = shooter, Q = target
		local x = P.x - sh.fx * sh.back - sh.fz * sh.off;
		local z = P.z - sh.fz * sh.back + sh.fx * sh.off;
		return x, gs(x, z) + sh.h, z, Q.x, Q.y + 2, Q.z;
	end,
	zoom = function(sh, t)
		-- telephoto: tighter for distant targets
		local d = dist2(sh.P.x, sh.P.z, sh.Q.x, sh.Q.z);
		return clamp(1.1 - d / 300, 0.6, 0.95);
	end,
	on_hit = function(sh) add_pulse(sh, 0.35, 0.18, 0.7, 1.2) end,
};

-- OVERVIEW: nothing worth showing - a high view of the whole field from behind your army,
-- hovering gently, held until something happens
SHOTS.overview = {
	needs_group = true,
	setup = function(sh)
		sh.a0 = rnd(-0.35, 0.35);
		sh.hover = chance(0.5) and 1 or -1;
	end,
	frame = function(sh, P, Q, C, t)
		local spread = sh.spread_s;
		local back = clamp(spread * 0.9 + 60, 110, 320);
		local h = clamp(back * 0.45, 45, 90);	-- the camera height range is 0-100 above ground while we film
		local a = sh.a0 + sh.hover * 0.14 * math.sin(t * 0.035);
		local ca, sa = math.cos(a), math.sin(a);
		local fx, fz = sh.fx * ca - sh.fz * sa, sh.fx * sa + sh.fz * ca;
		local side = math.sin(t * 0.05) * back * 0.06;
		local x = C.x - fx * back - fz * side;
		local z = C.z - fz * back + fx * side;
		local tx, tz = C.x + fx * back * 0.1, C.z + fz * back * 0.1;
		return x, math.max(gs(x, z), gs(C.x, C.z)) + h, z, tx, gs(tx, tz), tz;
	end,
	zoom = function(sh, t) return 1.15 end,
};

--------------------------------------------------------------------------------
-- shot construction
--------------------------------------------------------------------------------

local function uref(c) return tostring(safe(function() return c.u:type() end, "?")) end;

-- how interesting a unit is right now, regardless of what is on screen;
-- returns the score and the reasons (for the log)
local function interest(c, list, want_why)
	local why = want_why and {} or nil;
	local function note(t) if why then why[#why + 1] = t end end;

	-- what is happening to it
	local a = 1;
	if c.melee then a = a + 3; note("melee") end;
	if c.missile then a = a + 1.5; note("under fire") end;
	if c.fast then a = a + 1.5 end;
	local fired = cd.last_fired[c.key] and cd.now - cd.last_fired[c.key] < CFG.shooter_fired_recently;
	if fired then a = a + 1; note("shooting") end;
	local kr = math.min(c.kill_rate or 0, 8);
	if kr > 0.2 then a = a + 0.6 * kr; note(string.format("kills %.1f/s", kr)) end;
	local lr = math.min((c.loss_rate or 0) * 60, 3);
	if lr > 0.2 then a = a + lr; note(string.format("losing %.1f%%/s", (c.loss_rate or 0) * 100)) end;

	-- drama
	if c.melee and c.rear then a = a + 3; note("hit in the rear")
	elseif c.melee and c.flanked then a = a + 2; note("flanked") end;
	if c.wavering and not c.routing then a = a + 2; note("wavering") end;
	local foe = c.target_key and cd.by_key[c.target_key];
	if c.melee and foe and (c.big or c.general) and (foe.big or foe.general) then a = a + 3; note("duel") end;
	if c.general and c.friendly and c.melee and (c.hp or 1) < 0.5 then a = a + 2; note("general in danger") end;
	if (c.big or c.general) and c.melee and (c.hp or 1) < 0.35 then a = a + 1.5; note("last stand") end;

	-- who it is
	local s = a;
	if c.general and (c.melee or fired or c.missile) then s = s * 1.8 end;	-- not for just walking about
	if c.big then s = s * 1.6 end;
	if c.flying then s = s * ((c.airborne and 1.4) or 1.25) end;
	if c.cavalry then s = s * 1.15 end;
	if c.ror then s = s * CFG.renown_bonus end;

	-- the story of the battle
	local fin = battle.finale;
	if c.routing then
		-- finale: the rout is the story
		local loser = fin and (c.friendly ~= fin.player_winning);
		s = s * (loser and 1.6 or 0.3);
	elseif fin and c.friendly == fin.player_winning and (c.fast or c.melee) then
		s = s * 1.3;	-- the pursuit
	end;
	-- nothing near it and not shooting: a dull subject
	if not c.melee and not c.routing then
		local _, d = nearest_enemy(c, list, 1e9);
		if d > 250 and not fired then s = s * 0.5 end;
	end;
	if not c.friendly then s = s * 0.85 end;
	-- the fight around it
	local heat = math.min(c.heat or 0, 10);
	s = s + 0.5 * heat;
	if heat >= 3 then note(string.format("heat %.0f", heat)) end;
	return s, why;
end;

-- interest, less what we have just been watching
local function pick_score(c, raw)
	local s = raw;
	local sh = cd.shot;
	if sh and sh.c.key == c.key then
		s = s * 0.3;
	elseif sh and sh.P and dist2(c.x, c.z, sh.P.x, sh.P.z) < 40 then
		s = s * 0.85;	-- mostly on screen already
	end;
	local since = cd.now - (cd.filmed_at[c.key] or -1e9);
	s = s * (1 - 0.6 * math.exp(-since / 30)) / (1 + 0.15 * (cd.recent[c.key] or 0));
	return s;
end;

local function pick_subject(list)
	local scored = {};
	for _, c in ipairs(list) do
		local raw, why = interest(c, list, CFG.log_scores);
		scored[#scored + 1] = { c = c, raw = raw, s = pick_score(c, raw), why = why };
	end;
	table.sort(scored, function(a, b) return a.s > b.s end);
	local top = math.min(CFG.pick_top, #scored);
	local total = 0;
	for i = 1, top do scored[i].w = math.max(scored[i].s, 0) ^ CFG.pick_sharpness; total = total + scored[i].w end;
	local pick = scored[1];
	local r = math.random() * total;
	for i = 1, top do
		r = r - scored[i].w;
		if r <= 0 then pick = scored[i]; break end;
	end;
	if CFG.log_scores and pick then
		local parts = {};
		for i = 1, math.min(3, top) do
			local e = scored[i];
			parts[#parts + 1] = string.format("%s%s %.1f/%.1f [%s]", e == pick and "*" or "", uref(e.c), e.s, e.raw, table.concat(e.why or {}, ", "));
		end;
		log("  pick: " .. table.concat(parts, " | "));
	end;
	return pick and pick.c;
end;

local function weighted_pick(w)
	local total = 0;
	for _, v in pairs(w) do total = total + v end;
	if total <= 0 then return nil end;
	local r = math.random() * total;
	for kname, v in pairs(w) do
		r = r - v;
		if v > 0 and r <= 0 then return kname end;
	end;
	for kname, v in pairs(w) do if v > 0 then return kname end end;
end;

local function is_close(c)
	return c.big or c.general or (c.melee and (c.crowd or 0) >= CFG.close_crowd);
end;

local function base_shot(type_name, c, partner)
	local sh = {
		type = type_name,
		c = c,
		partner = partner,
		big = c.big,
		partner_big = partner and partner.big,
		flying = c.flying,
		elapsed = 0,
		look_h = c.big and 4 or 1.8,
		P = make_anchor(c.x, c.y, c.z),
		Q = partner and make_anchor(partner.x, partner.y, partner.z) or nil,
		close = is_close(c),
		hits = {},
	};
	sh.sc = sh.close and CFG.close_scale or 1;
	if partner then
		sh.fx, sh.fz = norm2(partner.x - c.x, partner.z - c.z);
	elseif c.speed and c.speed > 1 then
		sh.fx, sh.fz = norm2(c.vx, c.vz);
	else
		local b = d_to_r(c.bearing or 0);
		sh.fx, sh.fz = math.sin(b), math.cos(b);
	end;
	return sh;
end;

local function shot_units(sh)
	if sh.group then return sh.group end;
	local u = { sh.c };
	if sh.partner then u[2] = sh.partner end;
	return u;
end;

local function shot_centre(sh)
	if sh.C then return sh.C.x, sh.C.z end;
	if sh.Q then return (sh.P.x + sh.Q.x) * 0.5, (sh.P.z + sh.Q.z) * 0.5 end;
	return sh.P.x, sh.P.z;
end;

local apply_camera;

local function log_diag(sh)
	if sh and sh.ticks_n and sh.ticks_n > 0 then
		log(string.format("   end of shot #%d %s: speed limits held the camera back %d%% of the time; real tick mean %.0f ms, max %.0f ms",
			sh.n or 0, sh.type, math.floor(100 * (sh.capped_n or 0) / sh.ticks_n),
			1000 * (cd.dt_sum or 0) / math.max(cd.dt_n or 1, 1), 1000 * (cd.dt_max or 0)));
		cd.dt_sum, cd.dt_n, cd.dt_max = 0, 0, 0;
	end;
	if sh and sh.jit_n and sh.jit_n > 2 then
		log(string.format("   end of shot #%d %s: real camera speed %.1f m/s, tick-to-tick speed change %.0f%% (jitter)",
			sh.n or 0, sh.type, sh.jit_sp / sh.jit_n, 100 * sh.jit_dv / math.max(sh.jit_sp, 0.01)));
	end;
	if not CFG.diagnostics or not sh or not sh.diag_n or sh.diag_n == 0 then return end;
	log(string.format("   end of shot #%d %s: cam vs asked max|dy|=%.2f mean|dy|=%.2f max|dxz|=%.2f, wobble reversals=%d (max %.2f m), lowest clearance=%.1f, marks=%d",
		sh.n or 0, sh.type, sh.diag_dy_max, sh.diag_dy_sum / sh.diag_n, sh.diag_dxz_max,
		sh.diag_rev or 0, sh.diag_rev_max or 0, sh.diag_clear_min, sh.marks or 0));
end;

-- mode: "cut" (default) or "blend" (glide from the current camera instead of cutting)
local function start_shot(sh, mode)
	log_diag(cd.shot);
	SHOTS[sh.type].setup(sh);
	if sh.highlight and (sh.type == "impact" or sh.type == "charge_follow") then
		if sh.dist then sh.dist = sh.dist * CFG.highlight_scale end;
		if sh.back then sh.back = sh.back * CFG.highlight_scale end;
	end;
	if (sh.type == "tracking" or sh.type == "orbit") and chance(sh.close and 0.6 or 0.3) then
		sh.push_amt = sh.close and rnd(0.2, 0.32) or rnd(0.12, 0.22);
	end;
	if sh.close and sh.c.melee then sh.next_pulse = rnd(0.8, 1.8) end;
	cd.shot_n = (cd.shot_n or 0) + 1;
	sh.n = cd.shot_n;
	cd.shot = sh;
	if not sh.overview then
		cd.recent[sh.c.key] = (cd.recent[sh.c.key] or 0) + 1;
		cd.filmed_at[sh.c.key] = cd.now;
		if sh.c.general and sh.c.friendly then cd.last_lord = cd.now end;
	end;
	-- no jump cuts (they make the battle hard to follow): every new shot is a glide from where the camera is,
	-- as fast as it needs to be to cover the distance; only the very first shot cuts
	local blend = cd.cam ~= nil and cd.lim ~= nil and not SHOTS[sh.type].cut_in;
	if blend then
		local cx, cz = shot_centre(sh);
		local d = dist2(cd.lim.x, cd.lim.z, cx, cz);
		-- capped speed: a long glide takes longer (roughly the time the limits need to cover it)
		local vmax, amax = CFG.max_cam_speed * CFG.blend_speed_mult, CFG.max_cam_accel * CFG.blend_accel_mult;
		local need = (d > vmax * vmax / amax) and (d / vmax + vmax / amax) or 2 * math.sqrt(d / amax);
		local T = clamp(math.max(CFG.blend_time + d * CFG.glide_per_m, need), CFG.blend_time, CFG.glide_max);
		sh.glide = { t = T, m = CFG.blend_speed_mult, am = CFG.blend_accel_mult };
		sh.glide_d = d;
		sh.blended = true;
		-- the shot's own clock runs during the glide: give it the time back
		sh.duration = sh.duration + T * 0.8;
		if sh.impact_t then sh.impact_t = math.max(sh.impact_t, T * 0.7) end;
		if sh.next_pulse then sh.next_pulse = sh.next_pulse + T end;
	end;
	log(string.format("shot #%d %-14s %s %s men=%d general=%s big=%s melee=%s crowd=%d close=%s friendly=%s dur=%.1f",
		sh.n, sh.type, sh.event and "EVENT" or "     ", blend and string.format("glide %.1fs", sh.glide.t) or "cut  ", sh.c.men, tostring(sh.c.general),
		tostring(sh.c.big), tostring(sh.c.melee), sh.c.crowd or 0, tostring(sh.close), tostring(sh.c.friendly), sh.duration));
	if blend then
		apply_camera(sh, false, true);
	else
		cd.last_cut = cd.now;
		apply_camera(sh, true, true);
	end;
end;

local function normal_shot_type(c, partner, shooter, quiet)
	local melee = c.melee;
	local w = {
		tracking = 3,
		over_shoulder = partner and 3 or 0,
		heroic = (c.big or c.general) and 1.5 or 0.3,
		orbit = 2,
		wide = melee and 0.5 or 0.8,
		chase = (c.flying or (c.cavalry and c.fast)) and 3 or 0,
		volley_target = shooter and 6 or 0,
		volley_shooter = shooter and 2 or 0,
	};
	if quiet then w.wide, w.orbit = w.wide + 2, w.orbit + 1 end;	-- nothing engaged: hold a composition
	if cd.shot and w[cd.shot.type] then w[cd.shot.type] = w[cd.shot.type] * 0.3 end;
	return weighted_pick(w) or "tracking";
end;

--------------------------------------------------------------------------------
-- why the camera is where it is: a line for the HUD's banner, e.g. "Your Knights charging Orc Boyz"
--------------------------------------------------------------------------------

-- lead: first words of the line ("Your X" / "Enemy X"), else "your X" / "X"
local function side_name(c, lead)
	local n = uname(c);
	if c.friendly then
		if c.general then return n end;
		return (lead and "Your " or "your ") .. n;
	end;
	return lead and ("Enemy " .. n) or n;
end;

-- good news for the player? (c doing well = good when c is friendly)
local function tone(c, doing_well)
	if doing_well then return c.friendly and "good" or "bad" end;
	return c.friendly and "bad" or "good";
end;

local EVENT_REASON = {
	charge = { "charge", "%s charging %s" },
	contact = { "clash", "%s clashing with %s" },
	rear = { "rear", "%s hitting %s in the rear" },
	flank = { "flank", "%s attacking %s from the side" },
	duel = { "duel", "%s duelling %s" },
};

-- unit: who the line is about; the HUD puts its callout box over that unit
local function reason(icon, text, t, unit) return { icon = icon, text = text, tone = t, unit = unit } end;

local function event_reason(kind, a, b)
	if kind == "break" then return reason("rout", side_name(b, true) .. " breaking", tone(b, false), b) end;
	local r = EVENT_REASON[kind] or EVENT_REASON.contact;
	return reason(r[1], string.format(r[2], side_name(a, true), side_name(b)), tone(a, true), a);
end;

-- highlights (see CFG.highlight_*): the line, its tone for the player, the unit its box hangs over, and the
-- shot's two units (subject first)
highlight_of = function(kind, a, b)
	if not CFG.highlights then return nil end;
	local function hl(t, text, icon, unit, s1, s2) return { tone = t, text = text, icon = icon, unit = unit, a = s1, b = s2 } end;
	if kind == "charge" and charges_well(a, b) then
		return hl(tone(a, true), side_name(a, true) .. " crashing into " .. side_name(b), "charge", a, a, b);
	elseif kind == "rear" then
		return hl(tone(a, true), side_name(a, true) .. " hitting " .. side_name(b) .. " in the rear", "rear", a, a, b);
	elseif kind == "flank" and (a.cavalry or a.big) then
		return hl(tone(a, true), side_name(a, true) .. " hitting " .. side_name(b) .. " in the side", "flank", a, a, b);
	elseif kind == "contact" or kind == "charge" then
		-- shooters caught in melee by troops that aren't: filmed from behind the attackers
		local sa, sb = is_shooter(a), is_shooter(b);
		if sb and not sa then return hl(tone(b, false), side_name(b, true) .. " caught in melee by " .. side_name(a), "clash", b, a, b) end;
		if sa and not sb then return hl(tone(a, false), side_name(a, true) .. " caught in melee by " .. side_name(b), "clash", a, b, a) end;
	elseif kind == "break" then
		return hl(tone(b, false), side_name(b, true) .. " breaking", "rout", b, a, b);
	elseif kind == "hurt" then
		return hl(tone(a, false), side_name(a, true) .. " badly hurt", "general", a, a, b);
	end;
	return nil;
end;

local function highlight_reason(h)
	local r = reason(h.icon, h.text, h.tone, h.unit);
	r.highlight = true;
	return r;
end;

-- a unit hit hard (add_hit): how = spell (a cast we saw), magic (a caster guessed), bombard, riddle or hit
hit_line = function(how, c, src)
	local n = side_name(c, true);
	if how == "spell" then return n .. " hit by a spell from " .. side_name(src), "spell"
	elseif how == "magic" then return n .. " hit by a spell", "spell"
	elseif how == "bombard" then return n .. " bombarded by " .. side_name(src), "volley"
	elseif how == "riddle" then return n .. " riddled by " .. side_name(src), "volley" end;
	return n .. " hit hard", "down";
end;

-- what the subject of an ordinary shot is doing now
local function state_reason(sh)
	local c = cd.by_key[sh.c.key] or sh.c;
	if sh.anchor then return reason("general", side_name(c, true) .. (c.friendly and ", your general" or ", the enemy general"), nil, c) end;
	if c.routing then return reason("rout", side_name(c, true) .. " retreating", tone(c, false), c) end;
	-- one of ours running a play (hammer and anvil, cycle charge, ...): say which step of it
	local eng, TC = CD_TACTICS_ENGINE, CD_TACTICS;
	if c.friendly and eng and TC and TC.doing and eng.running() then
		local e = eng.find(c.u);
		local st = e and eng.state(e);
		if st and st.act and TC.PLAYS[st.act] then
			local tc = st.target_unit and cd.by_key[tostring(safe(function() return st.target_unit:unique_ui_id() end, "?"))];
			local text = TC.doing(st.act, st.phase, tc and tc ~= c and side_name(tc) or nil);
			if text then return reason(TC.icon(st.act, st.phase), side_name(c, true) .. " " .. text, tone(c, true), c) end;
		end;
	end;
	local foe = c.target_key and cd.by_key[c.target_key];
	if not (foe and foe.alliance ~= c.alliance) then foe = sh.partner end;
	if c.melee then
		if foe then return reason("clash", side_name(c, true) .. " fighting " .. side_name(foe), tone(c, true), c) end;
		return reason("clash", side_name(c, true) .. " fighting", tone(c, true), c);
	end;
	local fired = cd.last_fired[c.key] and cd.now - cd.last_fired[c.key] < CFG.shooter_fired_recently;
	if fired then
		return reason("volley", side_name(c, true) .. (foe and (" shooting at " .. side_name(foe)) or " shooting"), tone(c, true), c);
	end;
	if c.missile then return reason("volley", side_name(c, true) .. " under fire", tone(c, false), c) end;
	if (c.speed or 0) > 1 then
		local en = nearest_enemy(c, cd.list, 200);
		return reason("charge", side_name(c, true) .. (en and (" advancing on " .. side_name(en)) or " on the move"), tone(c, true), c);
	end;
	return reason("hold", side_name(c, true) .. " holding", nil, c);
end;

local function overview_reason(sh)
	local fin = battle.finale;
	if fin then return reason("eye", fin.player_winning and "The enemy army is breaking" or "Your army is breaking", fin.player_winning and "good" or "bad") end;
	if (sh.gap or 0) > 260 then return reason("eye", "The armies manoeuvre", nil) end;
	return reason("eye", "The battle lines close", nil);
end;

-- anything worth showing going on: fighting, shooting, spells
local function action_now(list)
	for _, c in ipairs(list) do
		if c.melee and not c.routing then return true end;
		if cd.last_fired[c.key] and cd.now - cd.last_fired[c.key] < CFG.shooter_fired_recently then return true end;
	end;
	return cd.casts ~= nil and #cd.casts > 0;
end;

-- everyone still fighting; sets sh.gap (distance between the armies) and, once, sh.fx/fz (your army -> theirs)
local function overview_units(sh)
	local units = {};
	local fx, fz, nf, ex, ez, ne = 0, 0, 0, 0, 0, 0;
	for _, c in ipairs(cd.list) do
		if not c.routing then
			units[#units + 1] = c;
			if c.friendly then fx, fz, nf = fx + c.x, fz + c.z, nf + 1 else ex, ez, ne = ex + c.x, ez + c.z, ne + 1 end;
		end;
	end;
	if nf > 0 and ne > 0 then
		sh.gap = dist2(fx / nf, fz / nf, ex / ne, ez / ne);
		if not sh.fx_set then
			sh.fx, sh.fz = norm2(ex / ne - fx / nf, ez / ne - fz / nf);
			sh.fx_set = true;
		end;
	end;
	return units;
end;

local function new_overview_shot()
	local probe = {};
	local units = overview_units(probe);
	if #units == 0 then return false end;
	local sh = base_shot("overview", units[1], nil);
	if probe.fx then sh.fx, sh.fz = probe.fx, probe.fz end;
	sh.gap, sh.fx_set = probe.gap, true;
	sh.group = units;
	local cx, cy, cz, spread = centroid(units);
	sh.C = make_anchor(cx, cy, cz);
	sh.spread_s = spread;
	sh.duration = 1e9;
	sh.overview = true;
	sh.reason = overview_reason(sh);
	log("  -> nothing happening: overview of the field");
	start_shot(sh);
	return true;
end;

local function new_volley_shot(vt)
	local t = weighted_pick({ volley_target = 3, volley_shooter = 1 });
	-- from the player's side: behind your shooters, or behind your regiment under fire
	if home_angle() then t = vt.shooter.friendly and "volley_shooter" or "volley_target" end;
	local sh;
	if t == "volley_target" then
		sh = base_shot(t, vt.target, vt.shooter);
		sh.hit_units = { vt.target };
	else
		sh = base_shot(t, vt.shooter, vt.target);
		sh.hit_units = { vt.target };
	end;
	sh.volley = true;
	sh.duration = rnd(5, 7);
	sh.reason = reason("volley", side_name(vt.shooter, true) .. " shooting at " .. side_name(vt.target), tone(vt.shooter, true), vt.shooter);
	start_shot(sh);
end;

-- your general, when it's time to come back to them
local function lord_due()
	if not CFG.lord_anchor or CFG.lord_anchor <= 0 then return nil end;
	local every = battle.finale and CFG.lord_anchor * 0.5 or CFG.lord_anchor;
	if cd.now - (cd.last_lord or -1e9) < every then return nil end;
	for _, c in ipairs(cd.list) do
		if c.friendly and c.general and not c.routing then return c end;
	end;
	return nil;
end;

local function quiet_field(list)
	for _, c in ipairs(list) do
		if c.melee or (c.fast and not c.routing) then return false end;
	end;
	return true;
end;

local function new_normal_shot()
	local list = cd.list;
	if #list == 0 then return false end;
	local forced = cd.force_subject and cd.by_key[cd.force_subject.key];
	cd.force_subject = nil;
	if CFG.overview and not forced and not action_now(list) then
		if new_overview_shot() then return true end;
	end;
	local lord = not forced and lord_due() or nil;
	if lord and not lord.melee and cd.now - (cd.last_lord or -1e9) < CFG.lord_anchor * 2 then
		-- don't leave a big fight for a general with nothing going on (for a while)
		local ls, top = interest(lord, list), 0;
		for _, o in ipairs(list) do top = math.max(top, (interest(o, list))) end;
		if ls < top * 0.35 then
			log(string.format("  (general can wait: %.1f vs %.1f)", ls, top));
			lord = nil;
		end;
	end;
	local c = lord or forced or pick_subject(list);
	if not c then return false end;
	-- two-shots: the unit it is fighting or shooting at, else the nearest enemy
	local partner = c.target_key and cd.by_key[c.target_key];
	if not (partner and partner.alliance ~= c.alliance and dist2(c.x, c.z, partner.x, partner.z) <= 90) then
		partner = nearest_enemy(c, list, 90);
	end;
	local shooter = (c.missile and not c.melee) and find_shooter(c, list) or nil;
	local quiet = quiet_field(list);

	if lord and not c.melee then
		-- the narrative anchor: a slow heroic look at the general (a victory orbit in the finale)
		local t = weighted_pick({ heroic = 3, orbit = battle.finale and 5 or 2, tracking = 1, over_shoulder = partner and 2 or 0 });
		local sh = base_shot(t, c, partner);
		sh.duration = rnd(6, 8.5);
		sh.hit_units = { c };
		sh.anchor = true;
		sh.reason = state_reason(sh);
		log("  -> back to the general");
		start_shot(sh);
		return true;
	end;

	local tname = normal_shot_type(c, partner, shooter, quiet);

	if tname == "volley_target" or tname == "volley_shooter" then
		new_volley_shot({ target = c, shooter = shooter });
		return true;
	end;

	local sh = base_shot(tname, c, partner);
	sh.duration = rnd(CFG.shot_min, CFG.shot_max) * (quiet and 1.35 or 1);
	sh.hit_units = { c };
	sh.reason = state_reason(sh);
	start_shot(sh);
	return true;
end;

-- the lines for several events: one per pair of units (up to MAX_LINES), each with its own box over its
-- own unit; the first carries the others in .extra. prev: the reason of the shot being widened, whose lines
-- stay (what is already on screen keeps its box). The log joins them: "Your Knights charging Orc Boyz; Giant duelling Karl Franz"
local MAX_LINES = 4;		-- the HUD's callout boxes (CO_N)
local function reason_lines(r)
	local out = {};
	if r and r.unit then
		out[1] = r;
		for _, x in ipairs(r.extra or {}) do out[#out + 1] = x end;
	end;
	return out;
end;
local function join_reasons(lines)
	local first = lines[1];
	local r = reason(first.icon, first.text, first.tone, first.unit);
	r.highlight = first.highlight;
	if #lines > 1 then
		r.extra = {};
		local parts = { first.text };
		for k = 2, math.min(#lines, MAX_LINES) do r.extra[#r.extra + 1] = lines[k]; parts[#parts + 1] = lines[k].text end;
		r.log = table.concat(parts, ";  ");
	end;
	return r;
end;
local function group_reason(heads, group, prev)
	local lines, seen, seen_text = {}, {}, {};
	local function push(x)
		if #lines < MAX_LINES and not seen_text[x.text] then seen_text[x.text] = true; lines[#lines + 1] = x end;
	end;
	local function add(e)
		-- one line per pair (two regiments charging each other are one story)
		local ka, kb = tostring(e.a.key), tostring(e.b.key);
		local pair = ka < kb and (ka .. "|" .. kb) or (kb .. "|" .. ka);
		if not seen[pair] then seen[pair] = true; push(event_reason(e.kind, e.a, e.b)) end;
	end;
	for _, e in ipairs(heads) do add(e) end;
	for _, x in ipairs(reason_lines(prev)) do
		local x2 = reason(x.icon, x.text, x.tone, x.unit);
		push(x2);
	end;
	for _, e in ipairs(group) do add(e) end;
	return join_reasons(lines);
end;

--------------------------------------------------------------------------------
-- slow motion (CFG.slow_mo): the battle at slow_mo_speed for slow_mo_len real seconds, then back to the speed
-- it was at, unless the player changed it meanwhile. Not in multiplayer, not paused or already slowed.
--------------------------------------------------------------------------------

slow_mo = function(why)
	if not CFG.slow_mo or cd.slow then return false end;
	if cd.now - (cd.last_slow or -1e9) < CFG.slow_mo_cooldown then return false end;
	if safe(function() return bm:is_multiplayer() end, true) then return false end;
	local cur = tonumber(safe(function() return bm:current_battle_speed() end, nil));
	if not cur or cur < 0.99 then return false end;
	local ok, err = pcall(function() bm:modify_battle_speed(CFG.slow_mo_speed, true) end);
	if not ok then log("slow motion failed: " .. tostring(err)); return false end;
	cd.slow, cd.last_slow = { t = cd.now, prev = cur }, cd.now;
	log(string.format("   slow motion (%s): speed %.1f -> %.1f for %.1fs", why, cur, CFG.slow_mo_speed, CFG.slow_mo_len));
	return true;
end;

-- now_anyway: the director is stopping
local function slow_mo_end(now_anyway)
	local s = cd.slow;
	if not s or (not now_anyway and cd.now - s.t < CFG.slow_mo_len) then return end;
	local cur = tonumber(safe(function() return bm:current_battle_speed() end, nil));
	if cur and cur <= 0 and not now_anyway then return end;		-- paused: wait for the battle to run again
	cd.slow = nil;
	if cur and math.abs(cur - CFG.slow_mo_speed) < 0.05 then
		pcall(function() bm:modify_battle_speed(s.prev, true) end);
		log(string.format("   slow motion over after %.1fs: speed back to %.1f", cd.now - s.t, s.prev));
	else
		log("   slow motion over (the speed was changed meanwhile: left at " .. tostring(cur) .. ")");
	end;
end;

-- extra_units: units already on screen that must stay in frame (forces a group shot)
local function new_event_shot(mode, extra_units)
	-- (a highlight that has waited gains on the newer ones, so they are filmed in turn rather than the
	-- oldest running out of time)
	local function rank(e) return e.score + (e.hl and (cd.now - e.t) * 0.8 or 0) end;
	table.sort(cd.events, function(a, b) return rank(a) > rank(b) end);
	-- a charge that waited for the camera has landed by now: it's a clash
	for _, e in ipairs(cd.events) do
		if e.kind == "charge" and cd.now - e.t > (e.ttc or 0) + 1.5 then e.kind = "contact" end;
	end;
	local best = cd.events[1];

	-- a highlight is filmed on its own, close
	if best.hl and not extra_units then
		table.remove(cd.events, 1);
		local h = best.hl;
		-- others saying the same thing are this shot
		for k = #cd.events, 1, -1 do
			if cd.events[k].hl and cd.events[k].hl.text == h.text then table.remove(cd.events, k) end;
		end;
		local t;
		if best.kind == "hurt" then t = "heroic"
		elseif best.kind == "hit" then t = "action_hit"
		elseif best.kind == "charge" then t = weighted_pick({ charge_follow = 2, impact = 1 })
		else t = weighted_pick({ over_shoulder = 2, impact = 1 }) end;
		local sh = base_shot(t, h.a, h.b);
		sh.sc = CFG.highlight_scale;
		sh.highlight = h;
		if best.kind == "charge" then
			sh.impact_t = math.max(0.3, best.ttc - (cd.now - best.t));
			sh.duration = clamp(sh.impact_t + 4, 5, 8);
		elseif best.kind == "hit" then
			sh.impact_t = 0.3;
			sh.duration = rnd(4.5, 5.5);
		else
			sh.impact_t = 0.4;
			sh.duration = rnd(5, 6.5);
		end;
		sh.hit_units = best.kind == "hit" and { h.a } or { h.a, h.b };
		sh.reason = highlight_reason(h);
		sh.event = true;
		cd.hl_seen = cd.hl_seen or {};
		cd.hl_seen[h.text] = cd.now;
		log(string.format("  -> highlight shot (%s, %s): %s", best.kind, h.tone, h.text));
		start_shot(sh, mode);
		-- a hit: slow motion now while the damage is still landing, else at the next big one
		if best.kind == "hit" then
			if cd.now - best.t > 1.0 or not slow_mo("hit") then sh.slow_on_hit = true end;
		elseif best.kind == "charge" or best.kind == "rear" or best.kind == "flank" then
			-- a charge or a hit from behind/the side: slow motion at the first hit it lands (around the impact)
			sh.slow_on_hit, sh.slow_hit_mult, sh.slow_until = true, 1, sh.impact_t + 2.5;
		end;
		return;
	end;
	-- (widening the shot on screen: highlights stay queued for their own shot)
	if best.hl then
		best = nil;
		for _, e in ipairs(cd.events) do if not e.hl then best = e; break end end;
		if not best then return end;
	end;

	local group, rest = {}, {};
	for _, e in ipairs(cd.events) do
		if not e.hl and dist2(best.x, best.z, e.x, e.z) <= CFG.cluster_radius then
			group[#group + 1] = e;
		else
			rest[#rest + 1] = e;
		end;
	end;
	-- more queued up elsewhere: pan wide enough to take in the next most important one too
	local heads = { best };
	if not extra_units and #rest > 0 then
		local second;
		for _, e in ipairs(rest) do
			if not e.hl and dist2(best.x, best.z, e.x, e.z) <= CFG.multi_event_radius then second = e; break end;
		end;
		if second then
			heads[2] = second;
			local left = {};
			for _, e in ipairs(rest) do
				if not e.hl and dist2(second.x, second.z, e.x, e.z) <= CFG.cluster_radius then group[#group + 1] = e else left[#left + 1] = e end;
			end;
			rest = left;
			log(string.format("  -> two places at once: %s and %s, %.0f m apart", best.kind, second.kind, dist2(best.x, best.z, second.x, second.z)));
		end;
	end;
	cd.events = rest;

	local sh;
	if #group >= 2 or extra_units then
		local units, seen = {}, {};
		local ax, az = 0, 0;
		for _, c in ipairs(extra_units or {}) do
			if not seen[c.key] then seen[c.key] = true; units[#units + 1] = c end;
		end;
		for _, e in ipairs(group) do
			for _, c in ipairs({ e.a, e.b }) do
				if not seen[c.key] then seen[c.key] = true; units[#units + 1] = c end;
			end;
			local dx, dz = norm2(e.b.x - e.a.x, e.b.z - e.a.z);
			if e.a.alliance ~= best.a.alliance then dx, dz = -dx, -dz end;
			ax, az = ax + dx, az + dz;
		end;
		sh = base_shot("clash_wide", best.a, best.b);
		sh.fx, sh.fz = norm2(ax, az);
		sh.group = units;
		local cx, cy, cz, spread = centroid(units);
		sh.C = make_anchor(cx, cy, cz);
		sh.spread_s = spread;
		sh.duration = rnd(5.5, 7.5) + (heads[2] and 2 or 0);
		sh.reason = group_reason(heads, group, extra_units and cd.shot and cd.shot.reason or nil);
	else
		local kind = best.kind;
		local t;
		if kind == "charge" then
			t = weighted_pick({ impact = 3, charge_follow = 2 });
		elseif kind == "duel" then
			t = weighted_pick({ heroic = 1, over_shoulder = 2, impact = 2, orbit = 1 });
		elseif kind == "break" then
			t = weighted_pick({ over_shoulder = 3, heroic = (best.a.big or best.a.general) and 1.5 or 0, tracking = 1 });
		elseif kind == "rear" or kind == "flank" then
			t = weighted_pick({ impact = 2, over_shoulder = 2 });
		else
			t = weighted_pick({ impact = 3, over_shoulder = 1, heroic = (best.a.big or best.a.general) and 1 or 0 });
		end;
		sh = base_shot(t, best.a, best.b);
		if kind == "charge" then
			sh.impact_t = math.max(0.3, best.ttc - (cd.now - best.t));
			sh.duration = clamp(sh.impact_t + 3.5, 4, 7);
		else
			sh.impact_t = 0.4;
			sh.duration = (kind == "duel") and rnd(5.5, 7.5) or rnd(4, 5.5);
		end;
		sh.hit_units = { best.a, best.b };
		sh.reason = event_reason(kind, best.a, best.b);
	end;
	sh.event = true;
	log(string.format("  -> filming %d event(s) together%s (%s): %s", #group, extra_units and " (+ current action)" or "", best.kind, sh.reason and (sh.reason.log or sh.reason.text) or ""));
	start_shot(sh, mode);
end;

--------------------------------------------------------------------------------
-- hits: watch hitpoints of the units on screen, trigger zoom punches
--------------------------------------------------------------------------------

local function check_hits(sh)
	if not sh.hit_units then return end;
	for _, c in ipairs(sh.hit_units) do
		local hp = safe(function() return c.u:unary_hitpoints() end, nil);
		if hp then
			local hist = sh.hits[c.key] or {};
			sh.hits[c.key] = hist;
			hist[#hist + 1] = hp;
			if #hist > 4 then table.remove(hist, 1) end;
			local drop = hist[1] - hp;	-- over the last ~0.3 s
			local thr = c.big and CFG.hit_threshold_big or CFG.hit_threshold;
			if drop >= thr and (not sh.last_hit or sh.elapsed - sh.last_hit > CFG.hit_cooldown) then
				sh.last_hit = sh.elapsed;
				for i = 1, #hist do hist[i] = hp end;
				if sh.slow_on_hit and drop >= thr * (sh.slow_hit_mult or 2) and sh.elapsed <= (sh.slow_until or 1e9)
					and slow_mo("hit on screen") then sh.slow_on_hit = nil end;
				local on_hit = SHOTS[sh.type].on_hit;
				if on_hit then
					on_hit(sh);
					log(string.format("   hit on %s (%.3f hp) -> %s", sh.type, drop, "volley punch"));
				elseif sh.close or sh.event then
					add_pulse(sh, c.big and 0.3 or 0.22, 0.15, 0.5, 0.9);
				end;
			end;
		end;
	end;
end;

--------------------------------------------------------------------------------
-- camera driving
--------------------------------------------------------------------------------

-- how far the camera must be raised so terrain doesn't block the line to the target
local function obstruction_lift(x, y, z, tx, ty, tz)
	local min_c = CFG.min_ground_clearance;
	local need = gs(x, z) + min_c - y;
	for _, f in ipairs({ 0.2, 0.4, 0.6, 0.8 }) do
		local sx, sz = x + (tx - x) * f, z + (tz - z) * f;
		local line_y = y + (ty - y) * f;
		local deficit = gs(sx, sz) + 1.0 - line_y;
		if deficit > 0 then need = math.max(need, deficit / (1 - f)) end;
	end;
	return math.max(need, 0);
end;

local function update_anchors(sh, snap)
	if not is_alive(sh.c.u) then return false end;
	local x, y, z = upos(sh.c.u);
	if snap then sh.P = make_anchor(x, y, z) else follow_anchor(sh.P, x, y, z) end;

	if sh.partner then
		if is_alive(sh.partner.u) then
			local qx, qy, qz = upos(sh.partner.u);
			if snap or not sh.Q then sh.Q = make_anchor(qx, qy, qz) else follow_anchor(sh.Q, qx, qy, qz) end;
		elseif SHOTS[sh.type].needs_partner then
			return false;
		end;
	end;

	if sh.group then
		local cx, cy, cz, spread = centroid(sh.group);
		if not cx then return false end;
		if snap then
			sh.C = make_anchor(cx, cy, cz);
			sh.spread_s = spread;
		else
			follow_anchor(sh.C, cx, cy, cz);
			sh.spread_s = sh.spread_s + (spread - sh.spread_s) * k(1.5);
		end;
	end;

	local tx, tz;
	local axis_w = 1;
	if SHOTS[sh.type].follow_velocity then
		local vel = cd.vel[sh.c.key];
		if vel and (vel.vx * vel.vx + vel.vz * vel.vz) > 1 then tx, tz = norm2(vel.vx, vel.vz) end;
	elseif sh.Q and not sh.group then
		local d = dist2(sh.P.x, sh.P.z, sh.Q.x, sh.Q.z);
		axis_w = clamp((d - CFG.axis_min_dist) / CFG.axis_min_dist, 0, 1);
		tx, tz = norm2(sh.Q.x - sh.P.x, sh.Q.z - sh.P.z);
	end;
	if tx and not snap and axis_w > 0 then
		local b = k(1 / CFG.axis_blend) * axis_w;
		sh.fx, sh.fz = norm2(sh.fx * (1 - b) + tx * b, sh.fz * (1 - b) + tz * b);
	end;
	return true;
end;

local FIELDS = { "x", "y", "z", "tx", "ty", "tz", "fov" };

-- move cur toward goal with capped speed and acceleration, braking in time to stop on it;
-- returns the new value and velocity, and whether a limit held it back noticeably (more than tol)
local function approach(cur, vel, goal, vmax, amax, dt, tol)
	local e = goal - cur;
	local want = math.min(vmax, math.sqrt(2 * amax * math.abs(e)), math.abs(e) / dt);
	if e < 0 then want = -want end;
	local dv = clamp(want - vel, -amax * dt, amax * dt);
	local capped = math.abs(e) > tol and (math.abs(dv - (want - vel)) > 1e-6 or math.abs(want) >= vmax);
	vel = vel + dv;
	return cur + vel * dt, vel, capped;
end;

local function wrap_pi(a)
	while a > math.pi do a = a - 2 * math.pi end;
	while a < -math.pi do a = a + 2 * math.pi end;
	return a;
end;

local function limiter_reset(x, y, z, tx, ty, tz, fov)
	local dx, dy, dz = tx - x, ty - y, tz - z;
	cd.lim = {
		x = x, y = y, z = z, vx = 0, vy = 0, vz = 0,
		yaw = math.atan2(dx, dz), pitch = math.atan2(dy, math.sqrt(dx * dx + dz * dz)), vyaw = 0, vpitch = 0,
		fov = fov, vfov = 0,
	};
end;

-- the speed limits: the smoothed camera s is the goal, cd.lim follows it no faster than allowed
-- glide: nil, or { m = speed multiplier, am = acceleration multiplier } while travelling between shots
local function limit_camera(s, glide)
	local L = cd.lim;
	local dt = cd.dt or CFG.tick_ms / 1000;
	local m = glide and glide.m or 1;
	local am = glide and glide.am or 1;
	local capped = false;

	-- position, as a vector (so diagonal moves aren't faster)
	local ex, ey, ez = s.x - L.x, s.y - L.y, s.z - L.z;
	local e = math.sqrt(ex * ex + ey * ey + ez * ez);
	local vmax, amax = CFG.max_cam_speed * m, CFG.max_cam_accel * am;
	local wx, wy, wz = 0, 0, 0;
	if e > 1e-4 then
		local sp = math.min(vmax, math.sqrt(2 * amax * e), e / dt);
		if sp >= vmax and e > 1 then capped = true end;
		wx, wy, wz = ex / e * sp, ey / e * sp, ez / e * sp;
	end;
	local dx, dy, dz = wx - L.vx, wy - L.vy, wz - L.vz;
	local dl = math.sqrt(dx * dx + dy * dy + dz * dz);
	if dl > amax * dt then
		if e > 1 then capped = true end;
		dx, dy, dz = dx / dl * amax * dt, dy / dl * amax * dt, dz / dl * amax * dt;
	end;
	L.vx, L.vy, L.vz = L.vx + dx, L.vy + dy, L.vz + dz;
	L.x, L.y, L.z = L.x + L.vx * dt, L.y + L.vy * dt, L.z + L.vz * dt;

	local gmin = gs(L.x, L.z) + CFG.min_ground_clearance * 0.8;
	if L.y < gmin then L.y = gmin; L.vy = math.max(L.vy, 0) end;

	-- view direction, aimed from where the camera really is at what the shot looks at. On a glide that means
	-- panning straight to the new subject and staying locked on it while the camera travels into position (so
	-- it is seen as soon as possible), but never tipping down at the ground beneath the camera
	local lx, ly, lz = s.tx, s.ty, s.tz;
	if glide and glide.look then lx, ly, lz = glide.look[1], glide.look[2], glide.look[3] end;	-- unsmoothed: no lag
	local ax, ay, az = lx - L.x, ly - L.y, lz - L.z;
	local ah = math.sqrt(ax * ax + az * az);
	local dist = math.max(math.sqrt(ah * ah + ay * ay), 1);
	local yaw_abs, pitch_goal = math.atan2(ax, az), math.atan2(ay, ah);
	if glide then pitch_goal = math.max(pitch_goal, -math.rad(CFG.glide_max_pitch)) end;
	local yaw_goal = L.yaw + wrap_pi(yaw_abs - L.yaw);
	-- glides pan faster: the subject comes into view at the start of the move, not at the end
	local tm = glide and CFG.glide_turn_mult or 1;
	local tr, ta = math.rad(CFG.max_turn_rate) * tm, math.rad(CFG.max_turn_accel) * tm;
	local c1, c2, c3;
	L.yaw, L.vyaw, c1 = approach(L.yaw, L.vyaw, yaw_goal, tr, ta, dt, 0.035);
	L.yaw = wrap_pi(L.yaw);
	L.pitch, L.vpitch, c2 = approach(L.pitch, L.vpitch, pitch_goal, tr, ta, dt, 0.035);
	L.dist = dist;
	local cp = math.cos(L.pitch);
	local tx = L.x + math.sin(L.yaw) * cp * dist;
	local ty = L.y + math.sin(L.pitch) * dist;
	local tz = L.z + math.cos(L.yaw) * cp * dist;

	-- zoom
	L.fov, L.vfov, c3 = approach(L.fov, L.vfov, s.fov, CFG.max_zoom_rate * tm, CFG.max_zoom_accel * tm, dt, 0.5);

	return L.x, L.y, L.z, tx, ty, tz, L.fov, capped or c1 or c2 or c3, e;
end;

-- where the engine camera is at clock time t: it glides in a straight line from where it was to each
-- move_to's goal over the move's duration (the HUD hangs its callouts on units with this)
local function cam_model_at(t)
	local m = cd.cam_model;
	if not m then return nil end;
	local f = m.dur > 0 and math.max(0, math.min(1, (t - m.t0) / m.dur)) or 1;
	local function lerp(a, b) return { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f } end;
	return lerp(m.p0, m.p1), lerp(m.q0, m.q1), m.f0 + (m.f1 - m.f0) * f;
end;

-- every move_to while filming goes through here, so the model above follows the camera
local function cam_move(x, y, z, tx, ty, tz, dur, fov)
	local now = CD_REAL_CLOCK and CD_REAL_CLOCK() or os.clock();
	local p, q, f = cam_model_at(now);
	if dur <= 0 or not p then p, q, f = { x, y, z }, { tx, ty, tz }, fov end;
	cd.cam_model = { p0 = p, q0 = q, f0 = f, p1 = { x, y, z }, q1 = { tx, ty, tz }, f1 = fov, t0 = now, dur = dur };
	bm:camera():move_to(v(x, y, z), v(tx, ty, tz), dur, false, fov);
end;

-- always an explicit FOV while filming: 0 means "game default", whose real value we don't know,
-- so switching between 0 and our own resting FOV could snap the zoom back and forth
local function fov_arg(f)
	return math.max(f, 5);
end;

local function record_diag(sh)
	if not CFG.diagnostics or not cd.last_cmd then return end;
	if cd.last_cut and cd.now - cd.last_cut < 0.5 then sh.prev_ay = nil; return end;	-- camera still settling after a cut
	local p = safe(function() return bm:camera():position() end, nil);
	if not p then return end;
	local ax, ay, az = p:get_x(), p:get_y(), p:get_z();
	local lc = cd.last_cmd;
	local dy = math.abs(ay - lc.y);
	local dxz = dist2(ax, az, lc.x, lc.z);
	sh.diag_n = (sh.diag_n or 0) + 1;
	sh.diag_dy_max = math.max(sh.diag_dy_max or 0, dy);
	sh.diag_dy_sum = (sh.diag_dy_sum or 0) + dy;
	sh.diag_dxz_max = math.max(sh.diag_dxz_max or 0, dxz);
	sh.diag_clear_min = math.min(sh.diag_clear_min or 1e9, ay - ground(ax, az));
	-- wobble: actual height changing direction (up/down/up) by noticeable amounts
	if sh.prev_ay then
		local vy = ay - sh.prev_ay;
		if math.abs(vy) > 0.03 then
			if sh.prev_vy and (vy > 0) ~= (sh.prev_vy > 0) then
				sh.diag_rev = (sh.diag_rev or 0) + 1;
				sh.diag_rev_max = math.max(sh.diag_rev_max or 0, math.abs(vy));
			end;
			sh.prev_vy = vy;
		end;
	end;
	sh.prev_ay = ay;
	-- jitter: how much the camera's real speed changes from one tick to the next
	local la = sh.last_actual;
	if la and cd.dt then
		local sp = math.sqrt((ax - la.x) ^ 2 + (ay - la.y) ^ 2 + (az - la.z) ^ 2) / cd.dt;
		if sh.prev_sp then
			sh.jit_n = (sh.jit_n or 0) + 1;
			sh.jit_sp = (sh.jit_sp or 0) + sp;
			sh.jit_dv = (sh.jit_dv or 0) + math.abs(sp - sh.prev_sp);
		end;
		sh.prev_sp = sp;
	end;
	sh.last_actual = { x = ax, y = ay, z = az };
end;

-- every shot, bent toward the player's view: the camera swung round its target to within home_max_dev of the
-- starting angle (softly, so shots that drift still move), then raised until it looks down at least min_pitch
local function home_view(sh, x, y, z, tx, ty, tz)
	local rx, rz = x - tx, z - tz;
	local r = math.sqrt(rx * rx + rz * rz);
	if r < 1 then return x, y, z end;
	local home = home_angle();
	if home then
		local hy = y - gs(x, z);
		local dev = wrap_pi(math.atan2(rx, rz) - home);
		-- directly opposite: keep to the side the shot was already on (no flip across the back)
		if math.abs(dev) > math.rad(150) then
			dev = (sh.home_side or (dev >= 0 and 1 or -1)) * math.abs(dev);
		else
			sh.home_side = dev >= 0 and 1 or -1;
		end;
		local M = math.rad(CFG.home_max_dev);
		local a = home + M * math.tanh(dev / M);
		x, z = tx + math.sin(a) * r, tz + math.cos(a) * r;
		y = gs(x, z) + hy;
		rx, rz = x - tx, z - tz;
	end;
	local p = math.rad(sh.min_pitch or CFG.min_pitch);
	local dy = y - ty;
	if dy < r * math.tan(p) then
		-- same distance from the subject, higher up (closer in if that would go too high)
		local D = math.sqrt(r * r + dy * dy);
		local ndy = math.min(D * math.sin(p), CFG.max_lift);
		local nr = ndy / math.tan(p);
		x, z = tx + rx / r * nr, tz + rz / r * nr;
		y = math.max(ty + ndy, gs(x, z) + CFG.min_ground_clearance);
	end;
	return x, y, z;
end;

-- the close charge cam (SHOTS.charge_close) and the brace cam (SHOTS.charge_brace): follow the charger's raw
-- position with a lag-free tracking filter (position and velocity, so a steady gallop is followed exactly and
-- formation jiggle is damped), outside the smoothing, the speed limits, home_view and min_pitch; at the impact
-- it brakes to a stop, turns to the hit and slows the battle (slow_mo).
-- Leaves cd.cam and cd.lim where the camera really is, so the next shot glides on from there.
local function close_camera(sh, cut)
	if not is_alive(sh.c.u) or not (sh.partner and is_alive(sh.partner.u)) then return false end;
	local dt = cd.dt or CFG.tick_ms / 1000;
	-- the charger (followed by the filter) and the unit charged
	local brace = sh.type == "charge_brace";
	local rider, other = sh.c, sh.partner;
	if brace then rider, other = sh.partner, sh.c end;
	local px, py, pz = upos(rider.u);
	local qx, qy, qz = upos(other.u);
	local R = sh.ride;
	if not R or cut then
		local vel = cd.vel[rider.key] or { vx = 0, vz = 0 };
		R = { x = px, z = pz, vx = vel.vx, vz = vel.vz };
		sh.ride = R;
		sh.stand = { x = qx, z = qz };
		local d = dist2(px, pz, qx, qz);
		if d > 1 then sh.fx, sh.fz = norm2(qx - px, qz - pz) end;
	else
		local ex, ez = R.x + R.vx * dt, R.z + R.vz * dt;
		local rx, rz = px - ex, pz - ez;
		R.x, R.z = ex + rx * 0.5, ez + rz * 0.5;
		R.vx, R.vz = R.vx + rx * 0.15 / dt, R.vz + rz * 0.15 / dt;
		local S = sh.stand;
		S.x, S.z = S.x + (qx - S.x) * k(0.4), S.z + (qz - S.z) * k(0.4);
	end;
	local live = cd.by_key[rider.key];
	local gap = dist2(R.x, R.z, qx, qz);
	-- the hit: they touch (or are fighting); the estimate of when is only a backstop (it is often early)
	if not sh.hit_t and (gap < CFG.contact_radius + 4 + (rider.big and 4 or 0) or (live and live.melee and sh.elapsed > 0.3)
		or sh.elapsed >= (sh.impact_t or 0) + 1.5) then
		sh.hit_t = sh.elapsed;
		log(string.format("   %s: impact at %.1fs (gap %.0f m)", brace and "brace cam" or "close charge", sh.elapsed, gap));
		slow_mo(brace and "charged" or "charge");
	end;
	local x, y, z, tx, ty, tz, vx, vz;
	local cam = sh.ccam;
	if not sh.hit_t then
		-- the charge direction, steady once the two are too close for their bearing to mean much
		if gap > CFG.axis_min_dist then
			local nx, nz = norm2(qx - R.x, qz - R.z);
			sh.fx, sh.fz = norm2(sh.fx * 0.8 + nx * 0.2, sh.fz * 0.8 + nz * 0.2);
		end;
		if brace then
			-- behind the unit charged (fx,fz runs from the charger to it), looking at the charger
			local S = sh.stand;
			local vel = cd.vel[other.key] or { vx = 0, vz = 0 };
			x = S.x + sh.fx * sh.back - sh.fz * sh.off;
			z = S.z + sh.fz * sh.back + sh.fx * sh.off;
			vx, vz = vel.vx, vel.vz;
			tx, tz = R.x, R.z;
		else
			x = R.x - sh.fx * sh.back - sh.fz * sh.off;
			z = R.z - sh.fz * sh.back + sh.fx * sh.off;
			vx, vz = R.vx, R.vz;
			tx, tz = qx, qz;
		end;
	else
		-- stop dead (a quick brake, not a jolt) and look at where they hit
		local f = math.exp(-dt / 0.25);
		cam.vx, cam.vz = cam.vx * f, cam.vz * f;
		x, z, vx, vz = cam.x + cam.vx * dt, cam.z + cam.vz * dt, cam.vx, cam.vz;
		local mx, mz = (px + qx) * 0.5, (pz + qz) * 0.5;
		tx, tz = cam.tx + (mx - cam.tx) * k(0.6), cam.tz + (mz - cam.tz) * k(0.6);
	end;
	y = math.max(gs(x, z) + sh.h, ground(x, z) + 1.6);
	ty = gs(tx, tz) + ((brace and not sh.hit_t) and (rider.big and 4 or 1.8) or 1.5);
	-- a crest between the camera and the enemy: rise over it (quickly), settle back once past
	local need = obstruction_lift(x, y, z, tx, ty, tz);
	sh.clr = cut and need or ((sh.clr or 0) + (need - (sh.clr or 0)) * k(need > (sh.clr or 0) and 0.25 or 0.8));
	y = y + sh.clr;
	local fov = sh.hit_t and (CFG.close_charge_fov - 6) or CFG.close_charge_fov;
	if cam and not cut then fov = cam.fov + (fov - cam.fov) * k(0.4) end;
	sh.ccam = { x = x, z = z, vx = vx, vz = vz, tx = tx, tz = tz, fov = fov };

	-- what the next shot glides on from
	local s = { m = {} };
	local want = { x = x, y = y, z = z, tx = tx, ty = ty, tz = tz, fov = fov };
	for _, f in ipairs(FIELDS) do s[f] = want[f]; s.m[f] = want[f] end;
	cd.cam = s;
	limiter_reset(x, y, z, tx, ty, tz, fov);
	cd.lim.vx, cd.lim.vz = vx, vz;
	cd.lim.dist = math.sqrt((tx - x) ^ 2 + (ty - y) ^ 2 + (tz - z) ^ 2);
	cd.last_cmd = { x = x, y = y, z = z };
	if cut then
		cd.last_cut = cd.now;
		cd.clear_s = 0;
		cam_move(x, y, z, tx, ty, tz, 0, fov_arg(fov));
	else
		local lead = CFG.move_lead;
		cam_move(x + vx * lead, y, z + vz * lead, tx + (sh.hit_t and 0 or vx * lead), ty, tz + (sh.hit_t and 0 or vz * lead), lead, fov_arg(fov));
	end;
	return true;
end;

-- cut: jump the camera; snap: reset the shot's anchors to live positions
apply_camera = function(sh, cut, snap)
	if SHOTS[sh.type].direct then return close_camera(sh, cut) end;
	if not update_anchors(sh, snap or cut) then return false end;
	if not cut then record_diag(sh) end;

	local x, y, z, tx, ty, tz = SHOTS[sh.type].frame(sh, sh.P, sh.Q, sh.C, sh.elapsed);
	x, y, z = home_view(sh, x, y, z, tx, ty, tz);

	-- obstruction lift, smoothed: rises quickly, settles slowly
	local need = obstruction_lift(x, y, z, tx, ty, tz);
	if cut then
		cd.clear_s = need;
	else
		local kk = (need > cd.clear_s) and k(CFG.clear_rise_tau) or k(CFG.clear_fall_tau);
		cd.clear_s = cd.clear_s + (need - cd.clear_s) * kk;
	end;
	y = y + cd.clear_s;

	local zf = 1;
	if CFG.zoom then
		local zfn = SHOTS[sh.type].zoom;
		zf = (zfn and zfn(sh, sh.elapsed) or 1) * pulse_factor(sh);
		if sh.close and not sh.event and not sh.volley then zf = zf * CFG.close_zoom end;
		zf = math.max(zf, CFG.min_zoom_factor);
	end;
	local fov = CFG.base_fov * zf;

	-- long glides pull up and back on the way, then settle onto the new shot
	if sh.glide and cd.lim and not cut then
		local togo = dist2(cd.lim.x, cd.lim.z, x, z);
		local lift = clamp((togo - 40) * CFG.swoop_lift, 0, CFG.swoop_max);
		if lift > 0 then
			y = y + lift;
			fov = math.max(fov, CFG.base_fov);
		end;
	end;

	if sh.glide then sh.glide.look = { tx, ty, tz } end;
	local want = { x = x, y = y, z = z, tx = tx, ty = ty, tz = tz, fov = fov };
	local s = cd.cam;
	if cut or not s then
		s = { m = {} };
		for _, f in ipairs(FIELDS) do s[f] = want[f]; s.m[f] = want[f] end;
		cd.cam = s;
		cd.last_cmd = { x = x, y = y, z = z };
		limiter_reset(x, y, z, tx, ty, tz, fov);
		cam_move(x, y, z, tx, ty, tz, 0, fov_arg(fov));
		return true;
	end;

	local blending = sh.glide ~= nil;
	local tp = blending and CFG.blend_tau or CFG.cam_pos_tau;
	local tt = blending and CFG.blend_tau or CFG.cam_targ_tau;
	local tf = blending and CFG.blend_tau or CFG.fov_tau;
	local taus = { x = tp, y = tp, z = tp, tx = tt, ty = tt, tz = tt, fov = tf };

	-- two-stage smoothing: m chases the goal, s chases m (eased starts and stops)
	for _, f in ipairs(FIELDS) do
		local kk = k(taus[f] * 0.5);
		s.m[f] = s.m[f] + (want[f] - s.m[f]) * kk;
		s[f] = s[f] + (s.m[f] - s[f]) * kk;
	end;

	local gmin = gs(s.x, s.z) + CFG.min_ground_clearance * 0.8;
	if s.y < gmin then s.y = gmin; s.m.y = math.max(s.m.y, gmin) end;

	if not cd.lim then limiter_reset(s.x, s.y, s.z, s.tx, s.ty, s.tz, s.fov) end;
	local cx, cy, cz, ctx, cty, ctz, cfov, capped, err = limit_camera(s, sh.glide);
	if sh.glide then
		-- the glide ends once its time is up and the camera has caught up with the shot
		local L = cd.lim;
		local sp = math.sqrt(L.vx * L.vx + L.vy * L.vy + L.vz * L.vz);
		if sh.elapsed >= sh.glide.t and err < 3 and sp <= CFG.max_cam_speed then
			sh.glide = nil;
			log(string.format("   glide done after %.1fs (%.0f m)", sh.elapsed, sh.glide_d or 0));
		end;
	else
		sh.ticks_n = (sh.ticks_n or 0) + 1;
		if capped then sh.capped_n = (sh.capped_n or 0) + 1 end;
	end;

	-- aim where the camera will be move_lead from now and take that long to get there: the engine keeps the
	-- camera moving at our speed between ticks, however late the next one is
	local L = cd.lim;
	local lead = CFG.move_lead;
	local px, py, pz = cx + L.vx * lead, cy + L.vy * lead, cz + L.vz * lead;
	local yaw, pitch = L.yaw + L.vyaw * lead, clamp(L.pitch + L.vpitch * lead, -1.5, 1.5);
	local d, cp = L.dist or 50, math.cos(pitch);
	cd.last_cmd = { x = cx, y = cy, z = cz };
	cam_move(px, py, pz, px + math.sin(yaw) * cp * d, py + math.sin(pitch) * d, pz + math.cos(yaw) * cp * d,
		lead, fov_arg(cfov + L.vfov * lead));
	return true;
end;

--------------------------------------------------------------------------------
-- main loop
--------------------------------------------------------------------------------

local set_banners;

-- real seconds (os.clock is wall time on Windows); the harness supplies its own clock
local function real_clock()
	if CD_REAL_CLOCK then return CD_REAL_CLOCK() end;
	return os.clock();
end;

-- has the camera been on this shot long enough to move on? (min_focus_hold; never mid-glide)
local function focus_ok(sh)
	if not sh then return true end;
	if SHOTS[sh.type].direct then return true end;		-- the close charge and brace cams end when the hit has landed
	return sh.elapsed >= CFG.min_focus_hold and not sh.glide;
end;

-- the close charge cam, cutting in on the best candidate the last survey found, if it is due now
local function try_close_charge(sh)
	local cc = cd.close_cand;
	if not cc or not CFG.close_charge then return false end;
	local left = cc.ttc - (cd.now - cc.t);
	if cd.now - cc.t > 0.6 or left < CFG.close_charge_min_ttc then cd.close_cand = nil; return false end;
	if left > CFG.close_charge_ttc then return false end;
	if cd.now - (cd.last_close or -1e9) < CFG.close_charge_cooldown then return false end;
	if not (is_alive(cc.a.u) and is_alive(cc.b.u)) then return false end;
	-- not straight off a fresh shot, unless that shot is already on one of the two
	local on_it = sh and (sh.c == cc.a or sh.c == cc.b or sh.partner == cc.a or sh.partner == cc.b
		or (sh.c and (sh.c.key == cc.a.key or sh.c.key == cc.b.key)));
	if sh and not sh.overview and not on_it and (sh.held or 0) < 1.5 and not sh.glide then return false end;
	-- an action shot plays out its hit first
	if sh and sh.type == "action_hit" and (sh.held or 0) < 2.5 then return false end;
	cd.close_cand, cd.last_close = nil, cd.now;
	-- the same charge isn't queued to be filmed again
	local rest = {};
	for _, e in ipairs(cd.events) do
		if not ((e.a.key == cc.a.key or e.b.key == cc.a.key) and (e.a.key == cc.b.key or e.b.key == cc.b.key)) then rest[#rest + 1] = e end;
	end;
	cd.events = rest;
	-- your troops charged: from behind them (the brace cam), else from behind the riders
	local brace = cc.b.friendly and not cc.a.friendly;
	local ns = brace and base_shot("charge_brace", cc.b, cc.a) or base_shot("charge_close", cc.a, cc.b);
	ns.event = true;
	ns.impact_t = math.max(0.2, left);
	ns.duration = ns.impact_t + 1.5 + CFG.close_charge_after;	-- at most; it ends close_charge_after past the hit
	ns.hit_units = { cc.a, cc.b };
	local hl = highlight_of("charge", cc.a, cc.b);
	ns.highlight = hl;
	if hl then cd.hl_seen = cd.hl_seen or {}; cd.hl_seen[hl.text] = cd.now end;
	ns.reason = hl and highlight_reason(hl) or event_reason("charge", cc.a, cc.b);
	log(string.format("  -> %s: %s (%s) into %s (%s), %.1fs to impact", brace and "brace cam" or "close charge cam", uref(cc.a), cc.a.class or "?", uref(cc.b), cc.b.class or "?", left));
	start_shot(ns);
	return true;
end;

local function tick()
	if not cd.active then return end;
	-- the real time since the last tick: the timer fires irregularly, and smoothing with a fixed step
	-- makes the camera speed up and slow down with it
	local t = real_clock();
	local dt = CFG.tick_ms / 1000;
	if cd.clock and t > cd.clock then dt = clamp(t - cd.clock, 0.02, CFG.max_dt) end;
	cd.clock = t;
	cd.dt = dt;
	cd.dt_sum, cd.dt_n = (cd.dt_sum or 0) + dt, (cd.dt_n or 0) + 1;
	cd.dt_max = math.max(cd.dt_max or 0, dt);
	cd.now = cd.now + dt;
	cd.ticks = cd.ticks + 1;

	local surveyed = false;
	if cd.ticks % CFG.survey_every == 1 or #cd.list == 0 then
		local before = cd.by_key;
		cd.list = survey();
		detect_events(cd.list);
		surveyed = true;
		-- the player's view, once per battle: from your army toward the enemy's
		if not battle.home then
			local probe = {};
			overview_units(probe);
			if probe.fx then
				battle.home = { fx = probe.fx, fz = probe.fz };
				log(string.format("home view: facing %.0f degrees", math.deg(math.atan2(probe.fx, probe.fz))));
			end;
		end;
		if action_now(cd.list) then cd.calm_since = nil else cd.calm_since = cd.calm_since or cd.now end;
		-- keep the banner line current: the overview's armies and an ordinary shot's subject change what they do
		local cur = cd.shot;
		if cur and cur.overview then
			cur.group = overview_units(cur);
			if #cur.group == 0 then cur.group = { cur.c } end;
			cur.reason = overview_reason(cur);
		elseif cur and not cur.event and not cur.volley and not cur.spell then
			cur.reason = state_reason(cur);
		end;
		-- units gone from the field (not just out of sight)
		for key, old in pairs(before or {}) do
			if not cd.by_key[key] and not is_alive(old.u) then
				local dead = safe(function() return old.u:number_of_men_alive() <= 0 end, true);
				report((old.friendly and "Your " or "Enemy ") .. uname(old) .. (dead and " destroyed" or " shattered"), old.friendly and "bad" or "good", "skull");
			end;
		end;
	end;
	if cd.ticks % 10 == 1 then
		local ok, err = pcall(compute_tide);
		if not ok and (cd.tide_err or 0) < 3 then cd.tide_err = (cd.tide_err or 0) + 1; log("tide error: " .. tostring(err)) end;
	end;

	local sh = cd.shot;
	if sh then
		sh.elapsed = sh.elapsed + dt;
		if not sh.glide then sh.held = (sh.held or 0) + dt end;	-- time on the shot since the camera got there
		check_hits(sh);
		-- rhythmic zoom punches in melee close-ups
		if sh.next_pulse and sh.elapsed >= sh.next_pulse then
			if not sh.pulses or #sh.pulses == 0 then add_pulse(sh, rnd(0.15, 0.28), 0.2, rnd(0.4, 0.8), 1.0) end;
			sh.next_pulse = sh.elapsed + rnd(CFG.melee_pulse_min, CFG.melee_pulse_max);
		end;
	end;

	slow_mo_end();

	if not (sh and SHOTS[sh.type].direct) and try_close_charge(sh) then return end;

	-- after the close charge (or brace) cam: pull back to the side of the fight
	if sh and SHOTS[sh.type].direct and (sh.elapsed >= sh.duration or (sh.hit_t and sh.elapsed >= sh.hit_t + CFG.close_charge_after)) then
		if is_alive(sh.c.u) and is_alive(sh.partner.u) then
			local f = base_shot("impact", sh.c, sh.partner);
			f.event, f.impact_t = true, 0;
			f.duration = rnd(4, 5.5);
			f.hit_units = { sh.c, sh.partner };
			f.reason = event_reason("contact", sh.c, sh.partner);
			start_shot(f);
		else
			new_normal_shot();
		end;
		return;
	end;

	-- contact events near an ongoing event shot join it (or widen it) instead of cutting away
	-- (not while a highlight plays out: it stays close on its own moment)
	if sh and sh.event and not SHOTS[sh.type].direct and not (sh.highlight and sh.elapsed < CFG.min_focus_hold) and #cd.events > 0 then
		local cx, cz = shot_centre(sh);
		local rest, widen = {}, false;
		local impact_done = sh.elapsed >= (sh.impact_t or 0) + CFG.widen_after_impact;
		for _, e in ipairs(cd.events) do
			if e.hl then
				rest[#rest + 1] = e;	-- highlights get their own shot
			elseif dist2(cx, cz, e.x, e.z) <= CFG.blend_radius then
				if not sh.group and sh.partner then
					if impact_done then widen = true end;
					rest[#rest + 1] = e;	-- keep it pending until we widen
				elseif sh.group then
					local have = {};
					for _, c in ipairs(sh.group) do have[c.key] = true end;
					if not have[e.a.key] then sh.group[#sh.group + 1] = e.a end;
					if not have[e.b.key] then sh.group[#sh.group + 1] = e.b end;
					sh.duration = math.max(sh.duration, sh.elapsed + 3);
					-- its own box too
					local lines = reason_lines(sh.reason);
					local line = event_reason(e.kind, e.a, e.b);
					local dup = false;
					for _, x in ipairs(lines) do if x.text == line.text then dup = true end end;
					if not dup and #lines > 0 and #lines < MAX_LINES then
						lines[#lines + 1] = line;
						sh.reason = join_reasons(lines);
					end;
					log("  -> joined ongoing clash shot");
				end;
			else
				rest[#rest + 1] = e;
			end;
		end;
		cd.events = rest;
		if widen then
			log("  -> widening smoothly to cover neighbouring collisions");
			new_event_shot("blend", shot_units(sh));
			return;
		end;
	end;

	local events_ready, hl_ready, hit_ready = false, false, false;
	local near_pending = false;
	for _, e in ipairs(cd.events) do
		if e.urgent or cd.now - e.t >= CFG.event_gather or (e.kind == "charge" and e.ttc - (cd.now - e.t) <= CFG.event_urgent_ttc) then
			events_ready = true;
			if e.hl then hl_ready = true end;
			if e.urgent then hit_ready = true end;
		end;
		if not e.hl and sh and sh.event and not sh.group and dist2(e.x, e.z, shot_centre(sh)) <= CFG.blend_radius then
			near_pending = true;
		end;
	end;

	-- the close charge cam ends by itself; a highlight plays out before another event takes the camera
	local protected = sh and (SHOTS[sh.type].direct
		or (sh.highlight and sh.elapsed < (hit_ready and CFG.action_hl_hold or CFG.min_focus_hold)));
	if events_ready and (not near_pending or hl_ready) and not protected then
		local can_cut = not sh
			or (sh.overview and sh.elapsed >= 2)
			or (focus_ok(sh) and ((not sh.event and (sh.held or 0) >= CFG.event_interrupt_after)
				or (sh.event and (sh.held or 0) >= CFG.event_min_hold)))
			-- a highlight: sooner, but never off another highlight before it has played out
			or (hl_ready and not sh.glide and (sh.held or 0) >= CFG.highlight_min_hold)
			-- a unit hit hard: at once (even mid-glide)
			or (hit_ready and (sh.glide ~= nil or (sh.held or 0) >= CFG.action_hold));
		if can_cut then
			new_event_shot();
			return;
		end;
	end;

	-- spells: film the caster and the target (like a volley from the shooter's side)
	if cd.casts and #cd.casts > 0 then
		local c = table.remove(cd.casts, 1);
		local caster, target = cd.by_key[c.caster], cd.by_key[c.target];
		if caster and target and cd.now - c.t < 1.5 and sh and not sh.event and not sh.spell and (sh.held or 0) >= 2 and focus_ok(sh)
			and cd.now - (cd.last_spell_shot or -100) >= 15 then
			cd.casts = {};
			cd.last_spell_shot = cd.now;
			local vs = base_shot("volley_shooter", caster, target);
			vs.hit_units = { target };
			vs.volley, vs.spell = true, true;
			vs.duration = rnd(4.5, 6);
			vs.reason = reason("spell", side_name(caster, true) .. " casting at " .. side_name(target), tone(caster, true), caster);
			log("  -> filming a spell");
			start_shot(vs);
			return;
		end;
	end;

	-- volleys: interrupt ordinary shots (not contact events, not other volleys)
	if #cd.volleys > 0 and sh and not sh.event and not sh.volley and (sh.held or 0) >= CFG.volley_interrupt_after
		and (sh.overview or focus_ok(sh)) then
		table.sort(cd.volleys, function(a, b) return a.score > b.score end);
		local vt = table.remove(cd.volleys, 1);
		new_volley_shot(vt);
		return;
	end;

	local need_new = not sh or (sh.elapsed >= sh.duration and focus_ok(sh));
	-- overview: leave it as soon as there is something to show
	if sh and sh.overview and not need_new and surveyed and sh.elapsed > 1.5 and action_now(cd.list) then
		need_new = true;
		log("  -> action: leaving the overview");
	end;
	-- nothing has happened for a while: back to the overview
	if CFG.overview and sh and not need_new and not sh.overview and not sh.event and not sh.volley and not sh.spell
		and focus_ok(sh) and not sh.glide and cd.calm_since and cd.now - cd.calm_since >= CFG.overview_hold then
		need_new = true;
		log("  -> all quiet: back to the overview");
	end;
	-- cut away from a routing subject, except in the finale when the rout is the story
	if sh and not need_new and (sh.held or 0) > 2 and focus_ok(sh) and not sh.event and not battle.finale
		and safe(function() return sh.c.u:is_routing() end, false) then
		need_new = true;
	end;
	-- lost-target recovery: the subject went out of sight, or has nothing going on while others fight
	if sh and not need_new and not sh.event and not sh.volley and not sh.overview and cd.ticks % CFG.survey_every == 1 then
		local live = cd.by_key[sh.c.key];
		if not live and sh.elapsed > 1 then
			need_new = true;
			log("  -> subject lost from sight, cutting away");
		elseif live and (sh.held or 0) > CFG.idle_cut_after * (sh.anchor and 2 or 1) and focus_ok(sh) and not live.melee and not live.missile
			and not live.routing and (live.speed or 0) < 1 then
			local fired = cd.last_fired[live.key] and cd.now - cd.last_fired[live.key] < CFG.shooter_fired_recently;
			local _, d = nearest_enemy(live, cd.list, 1e9);
			if not fired and d > 120 and not quiet_field(cd.list) then
				need_new = true;
				log("  -> nothing happening around the subject, cutting to the action");
			end;
		end;
	end;

	-- something much hotter elsewhere: cut to it
	if sh and not need_new and not sh.event and not sh.volley and not sh.spell and not sh.overview
		and (sh.held or 0) >= CFG.hot_cut_after and focus_ok(sh) and cd.ticks % CFG.survey_every == 1 then
		local live = cd.by_key[sh.c.key];
		local cur = live and interest(live, cd.list) or 0;
		local cx, cz = shot_centre(sh);
		local best, bs = nil, 0;
		for _, c in ipairs(cd.list) do
			if c.key ~= sh.c.key and dist2(c.x, c.z, cx, cz) > 30 then
				local s2 = interest(c, cd.list);
				if s2 > bs then best, bs = c, s2 end;
			end;
		end;
		if best and bs >= CFG.hot_cut_min and bs > cur * CFG.hot_cut_ratio then
			need_new = true;
			cd.force_subject = best;
			log(string.format("  -> much more going on elsewhere (%.1f vs %.1f): %s", bs, cur, uref(best)));
		end;
	end;

	if need_new or not apply_camera(sh, false) then
		new_normal_shot();
	end;

	-- some UI changes bring the banners back; hide them again once things have settled
	if cd.ticks == 5 and cd.banners_hidden then set_banners(true) end;
end;

local function safe_tick()
	if CFG.ai_commander and CD_COMMANDER and cd.active then
		local ok, err = pcall(CD_COMMANDER.tick, CFG.tick_ms / 1000);
		if not ok then log("ERROR in commander: " .. tostring(err)) end;
	end;
	local ok, err = pcall(tick);
	if ok and CFG.hud and CD_HUD and cd.active and cd.ticks % 3 == 0 then pcall(CD_HUD.update, cd) end;
	if not ok then
		cd.errors = cd.errors + 1;
		log("ERROR in tick: " .. tostring(err));
		if cd.errors > 20 then
			log("too many errors, disabling director");
			cd.active = false;
			bm:remove_real_callback("cinematic_director_tick");
		end;
	end;
end;

local UI_PARTS = { "show_army_panel", "show_winds_of_magic_panel", "show_portrait_panel", "show_top_bar", "show_army_abilities" };

local function hide_ui(hide)
	if not CFG.hide_ui then return end;
	if CFG.show_minimap then
		for _, fn in ipairs(UI_PARTS) do
			if not (fn == "show_army_panel" and CFG.show_unit_cards) then
				local ok, err = pcall(function() bm[fn](bm, not hide) end);
				if not ok then log(fn .. " failed: " .. tostring(err)) end;
			end;
		end;
		pcall(function() bm:show_radar_frame(true) end);
	else
		local ok, err = pcall(function()
			if hide then bm:enable_cinematic_ui(true, false, CFG.cinematic_bars) else bm:enable_cinematic_ui(false, true, false) end;
			if hide and CFG.show_unit_cards then bm:show_army_panel(true) end;
		end);
		if not ok then log("hide ui failed: " .. tostring(err)) end;
	end;
end;

-- the floating unit banners
set_banners = function(hidden)
	cd.banners_hidden = hidden;
	local ok, err = pcall(function() bm:enable_unit_ids(not hidden) end);
	if not ok then log("enable_unit_ids failed: " .. tostring(err)) end;
end;

-- the commander reports casts so we can film them
CD_DIRECTOR_NOTIFY = function(kind, caster, target)
	if not cd.active or not CFG.film_spells or kind ~= "cast" then return end;
	cd.casts = cd.casts or {};
	local ck = tostring(safe(function() return caster:unique_ui_id() end, ""));
	local tk = tostring(safe(function() return target:unique_ui_id() end, ""));
	local cc, tc = cd.by_key[ck], cd.by_key[tk];
	if cc then
		report(string.format("%s casts a spell%s", uname(cc), tc and tc ~= cc and (" at " .. uname(tc)) or ""), good_for(cc));
	end;
	-- (a heavy hit on the target soon after is this spell)
	cd.cast_on = cd.cast_on or {};
	if tk ~= "" then cd.cast_on[tk] = { caster = ck, t = cd.now } end;
	cd.casts[#cd.casts + 1] = {
		caster = tostring(safe(function() return caster:unique_ui_id() end, "")),
		target = tostring(safe(function() return target:unique_ui_id() end, "")),
		t = cd.now,
	};
end;

local function set_active(on)
	if on == cd.active then return end;
	cd.active = on;
	if on then
		log("director ON");
		cd.shot, cd.cam, cd.lim, cd.list, cd.events, cd.volleys = nil, nil, nil, {}, {}, {};
		cd.hist, cd.prev, cd.vel, cd.ammo = {}, {}, {}, {};
		cd.errors, cd.last_cut, cd.clear_s, cd.last_cmd = 0, 0, 0, nil;
		cd.by_key, cd.last_fired, cd.recent, cd.tide, cd.tide_hist = {}, {}, {}, nil, {};
		cd.hl_seen, cd.hit_seen, cd.cast_on, cd.slow = {}, {}, {}, nil;
		cd.last_lord = -1e9;	-- open on your general
		cd.stat, cd.filmed_at, cd.force_subject, cd.last_break = {}, {}, nil, nil;
		if cd.banner_pref == nil then cd.banner_pref = CFG.hide_banners and true or false end;
		if cd.banner_pref then set_banners(true) end;
		if CFG.deselect_on_start then pcall(function() bm:clear_selection() end) end;
		if CFG.free_camera then
			local ok, err = pcall(function()
				local cam = bm:camera();
				cam:change_height_range(0, 100);
				cam:disable_shake();
				cam:disable_anchor_to_army();
			end);
			if not ok then log("free camera failed: " .. tostring(err)) end;
		end;
		if CFG.cinematic_camera then
			local ok, err = pcall(function() bm:enable_cinematic_camera(true) end);
			if not ok then log("cinematic camera failed: " .. tostring(err)) end;
		end;
		hide_ui(true);
		if CFG.hud and CD_HUD then
			local ok, err = pcall(CD_HUD.on, true);
			if not ok then log("hud failed: " .. tostring(err)) end;
		end;
		cd.casts, cd.last_spell_shot = {}, nil;
		if CFG.show_panel and CD_PANEL then pcall(CD_PANEL.show) end;
		if CFG.ai_commander and CD_COMMANDER then pcall(CD_COMMANDER.start) end;
		if CD_PROBE then pcall(CD_PROBE.on, true) end;
		bm:repeat_real_callback(safe_tick, CFG.tick_ms, "cinematic_director_tick");
		safe_tick();
	else
		log_diag(cd.shot);
		slow_mo_end(true);
		log("director OFF");
		bm:remove_real_callback("cinematic_director_tick");
		-- come to rest where the camera really is (the smoothed goal can be far ahead mid-glide)
		local L, s = cd.lim, cd.cam;
		if L then
			local d, cp = L.dist or 50, math.cos(L.pitch);
			pcall(function() bm:camera():move_to(v(L.x, L.y, L.z),
				v(L.x + math.sin(L.yaw) * cp * d, L.y + math.sin(L.pitch) * d, L.z + math.cos(L.yaw) * cp * d), 0.6, false, 0) end);
		elseif s then
			pcall(function() bm:camera():move_to(v(s.x, s.y, s.z), v(s.tx, s.ty, s.tz), 0.6, false, 0) end);
		end;
		if CFG.cinematic_camera then pcall(function() bm:enable_cinematic_camera(false) end) end;
		if CFG.free_camera then
			pcall(function()
				local cam = bm:camera();
				cam:enable_anchor_to_army();
				cam:change_height_range(-1, -1);
				cam:enable_shake();
			end);
		end;
		hide_ui(false);
		if cd.banners_hidden then set_banners(false) end;
		if CD_HUD then pcall(CD_HUD.on, false) end;
		if CD_COMMANDER then
			local ok, err = pcall(CD_COMMANDER.stop);
			if not ok then log("commander stop failed: " .. tostring(err)) end;
		end;
		if CD_PANEL then pcall(CD_PANEL.hide) end;
		if CD_PROBE then pcall(CD_PROBE.on, false) end;
		cd.shot, cd.cam = nil, nil;
	end;
end;

-- for the HUD's Banners button
CD_DIRECTOR = {
	active = function() return cd.active end,
	-- the camera now: position {x,y,z}, look point {x,y,z}, vertical fov (nil when not filming); the HUD
	-- projects units onto the screen with it
	camera = function() if not cd.active then return nil end return cam_model_at(real_clock()) end,
	clock = function() return real_clock() end,
	shot = function() return cd.shot end,
	charges_well = charges_well,	-- (harness)
	-- the unit cards stay on screen while filming (the HUD keeps its lines above them)
	unit_cards = function() return CFG.show_unit_cards or not CFG.hide_ui end,
	slow = function() return cd.slow end,
	highlight_of = function(...) return highlight_of(...) end,	-- (harness)
	banners_hidden = function() return cd.banner_pref == true end,
	toggle_banners = function()
		if cd.banner_pref == nil then cd.banner_pref = CFG.hide_banners and true or false end;
		cd.banner_pref = not cd.banner_pref;
		log("banners " .. (cd.banner_pref and "hidden" or "shown") .. " while filming");
		if cd.active then
			if cd.banner_pref then set_banners(true) elseif cd.banners_hidden then set_banners(false) end;
		end;
	end,
};

--------------------------------------------------------------------------------
-- hotkey
--------------------------------------------------------------------------------

local function on_shortcut(context, event_name)
	local name = context.string;
	if cd.shortcuts_logged < CFG.log_shortcuts then
		cd.shortcuts_logged = cd.shortcuts_logged + 1;
		log(event_name .. ": " .. tostring(name));
	end;
	if name == "escape_menu" and CFG.stop_on_escape and cd.active then
		set_active(false);
		return;
	end;
	if CFG.mark_shortcut and name == CFG.mark_shortcut then
		if cd.active and cd.shot then
			local sh = cd.shot;
			sh.marks = (sh.marks or 0) + 1;
			local a = sh.last_actual;
			local c = cd.cam;
			log(string.format("JITTER MARK during shot #%d %s (%.1fs in): cam y=%.1f asked y=%.1f ground=%.1f clearance=%.1f lift=%.1f fov=%.1f",
				sh.n or 0, sh.type, sh.elapsed, a and a.y or -1, c and c.y or -1,
				c and ground(c.x, c.z) or -1, a and (a.y - ground(a.x, a.z)) or -1, cd.clear_s or 0, c and c.fov or 0));
		end;
		return;
	end;
	if not CFG.toggle_shortcuts[name] then return end;

	-- debounce: some keys raise both ShortcutPressed and ShortcutTriggered
	if cd.toggle_lock then return end;
	cd.toggle_lock = true;
	core:get_tm():real_callback(function() cd.toggle_lock = false end, 300);

	set_active(not cd.active);
end;

core:add_listener("cinematic_director_shortcut_pressed", "ShortcutPressed", true,
	function(context) on_shortcut(context, "ShortcutPressed") end, true);
core:add_listener("cinematic_director_shortcut_triggered", "ShortcutTriggered", true,
	function(context) on_shortcut(context, "ShortcutTriggered") end, true);

core:add_listener("cinematic_director_end", "BattleConflictFinished", true,
	function() set_active(false) end, true);

-- start filming when deployment ends (once: after that only the hotkeys turn it on or off)
local function auto_start_watch()
	local ok, err = pcall(function()
		if cd.auto_started then return end;
		if not bm:is_conflict_phase() then return end;
		cd.auto_started = true;
		bm:remove_real_callback("cinematic_director_autostart");
		if not cd.active then log("battle started: director on"); set_active(true) end;
	end);
	if not ok then
		log("auto start failed: " .. tostring(err));
		cd.auto_started = true;
		pcall(function() bm:remove_real_callback("cinematic_director_autostart") end);
	end;
end;
if CFG.auto_start then bm:repeat_real_callback(auto_start_watch, 500, "cinematic_director_autostart") end;

math.randomseed(os.time and os.time() or 1);
log("---- cinematic_director v7 loaded ----");
