--------------------------------------------------------------------------------
-- Cinematic Director: battle tactics engine (Unicorn Overlord style)
--
-- From the moment the battle starts (after deployment) the player cannot give
-- orders. Every regiment fights on its own using the tactics set for it in the
-- campaign (exported to cinematic_director_tactics.txt before the battle).
-- Each unit walks its tactics top to bottom every couple of seconds and follows
-- the first one whose condition holds and whose target exists.
-- Battles without campaign data (custom battles) use the full role defaults.
--------------------------------------------------------------------------------

local T = CD_TACTICS;
local LOG_PATH = "cinematic_director_log.txt";
local EXPORT_PATH = "cinematic_director_tactics.txt";

local CFG = {
	enabled = true,
	lockout = true,				-- no player orders for the whole battle
	eval_every = 2.0,			-- seconds between decisions per unit (staggered)
	commit = 5.0,				-- seconds a decision sticks unless a higher tactic fires
	refresh_orders = 12.0,		-- re-issue an unchanged order this often (targets move and die)
	cast_every = 1.0,			-- seconds between casting passes
	caster_cooldown = 6,		-- seconds between casts by one unit
	fail_backoff = 20,			-- seconds an ability is skipped after a failed cast
	scan_per_tick = 250,		-- ability checks per tick
	ability_rescan = 30,
	hold_radius = 40,
	guard_radius = 40,
	retreat_dist = 80,
	ranges = { X = 200, D = 180, H = 180, B = 40, A = 120, R = 120, S = 80 },
	friendly_clear = 30,
	log_decisions = true,
	no_data_slots = 5,
	release_after_order = true,	-- hand the unit back after each order (it keeps the order) so its card stays selectable
	idle_after = 8,				-- seconds without moving/fighting/shooting before an attack order is re-issued			-- tactic slots for units with no campaign data (custom battles)
};

local function log(s)
	if CD_LOG then CD_LOG("[tactics] ", s) end;
end;

local function safe(fn, default)
	local ok, r = pcall(fn);
	if ok then return r end;
	return default;
end;

local function rnd(a, b) return a + math.random() * (b - a) end;

local function dist(ax, az, bx, bz)
	local dx, dz = bx - ax, bz - az;
	return math.sqrt(dx * dx + dz * dz);
end;

if not T then
	log("tactics catalogue missing - engine disabled");
	return;
end;

local E = {
	running = false,
	now = 0,
	start_t = 0,
	units = {},			-- list of own entries
	enemy = {},			-- list of enemy sunits
	enemy_keys = {},
	scan_queue = {},
	next_cast = 0,
	next_refresh = 0,
};

--------------------------------------------------------------------------------
-- unit facts
--------------------------------------------------------------------------------

local function alive(u)
	return safe(function() return u:number_of_men_alive() > 0 and not u:is_shattered() and not u:is_routing() end, false);
end;

local function upos(u)
	local p = u:position();
	return p:get_x(), p:get_z();
end;

local function gv(x, z)
	local h = safe(function() return bm:get_terrain_height(x, z) end, 0);
	return v(x, h, z);
end;

local function uid(u) return tostring(safe(function() return u:unique_ui_id() end, tostring(u))) end;
local function men(u) return safe(function() return u:initial_number_of_men() end, 100) or 100 end;
local function hp(u) return safe(function() return u:unary_hitpoints() end, 1) or 1 end;
local function in_melee(u) return safe(function() return u:is_in_melee() end, false) end;
local function is_general(u) return safe(function() return u:is_commanding_unit() end, false) end;
local function class_of(u) return safe(function() return u:unit_class() end, "") or "" end;

local function is_cav(u)
	local c = class_of(u);
	return safe(function() return u:is_cavalry() end, false) or safe(function() return u:can_fly() end, false)
		or c:find("^cav") ~= nil or c:find("chariot") ~= nil;
end;

local function is_missile(u)
	if class_of(u):find("^art") then return true end;
	return (safe(function() return u:starting_ammo() end, 0) or 0) > 0;
end;

local function is_large(u) return men(u) <= 8 or is_general(u) end;

local function battle_role(u)
	return T.role_from_class(class_of(u), men(u), is_general(u),
		safe(function() return u:starting_ammo() end, 0), safe(function() return u:is_cavalry() end, false),
		safe(function() return u:can_fly() end, false));
end;

--------------------------------------------------------------------------------
-- campaign data
--------------------------------------------------------------------------------

-- returns list of forces: { cqi = , units = { {key, cqi, rank, role, tactics} } }
local function read_export()
	local ok, f = pcall(io.open, EXPORT_PATH, "r");
	if not ok or not f then return {} end;
	local forces, cur = {}, nil;
	for line in f:lines() do
		local fc = line:match("^force (%-?%d+)");
		if fc then
			cur = { cqi = fc, units = {} };
			forces[#forces + 1] = cur;
		elseif cur then
			local idx, key, cqi, rank, role, tac = line:match("^unit (%d+) (%S+) (%S+) (%d+) (%S+) ?(.*)$");
			if idx then
				cur.units[#cur.units + 1] = { key = key, cqi = cqi, rank = tonumber(rank), role = role, tactics = T.parse(tac) };
			end;
		end;
	end;
	f:close();
	return forces;
end;

-- match a battle army to the exported force with the most unit types in the same order
local function match_force(forces, keys)
	local best, best_s;
	for _, fc in ipairs(forces) do
		local s = 0;
		for i, k in ipairs(keys) do
			if fc.units[i] and fc.units[i].key == k then s = s + 2
			else
				for _, u in ipairs(fc.units) do if u.key == k then s = s + 1; break end end;
			end;
		end;
		if #fc.units == #keys then s = s + 1 end;
		if s > 0 and (not best_s or s > best_s) then best, best_s = fc, s end;
	end;
	-- require at least half of the army to line up
	if best and best_s >= #keys then return best end;
	return nil;
end;

--------------------------------------------------------------------------------
-- world snapshot (rebuilt each evaluation pass)
--------------------------------------------------------------------------------

local W = { own = {}, enemy = {}, lord = nil, strength = 1 };

local function is_char(u) return class_of(u) == "com" or is_general(u) end;

local function snapshot()
	W.own, W.enemy, W.lord = {}, {}, nil;
	local own_v, en_v = 0, 0;
	local cx, cz, n = 0, 0, 0;
	for _, e in ipairs(E.units) do
		local u = e.sunit.unit;
		if alive(u) then
			local x, z = upos(u);
			local r = { e = e, u = u, x = x, z = z, melee = in_melee(u), hp = hp(u), large = is_large(u),
				general = is_general(u), missile = e.role == "missile" or e.role == "missile_cav",
				ammo = safe(function() return u:ammo_left() end, 0) or 0, ammo0 = e.ammo0 or 0 };
			W.own[#W.own + 1] = r;
			if r.general then W.lord = r end;
			own_v = own_v + r.hp * (r.large and 1.5 or 1);
			cx, cz, n = cx + x, cz + z, n + 1;
		end;
	end;
	W.cx, W.cz = n > 0 and cx / n or 0, n > 0 and cz / n or 0;
	for _, s in ipairs(E.enemy) do
		local u = s.unit;
		if alive(u) then
			local x, z = upos(u);
			local cls = class_of(u);
			local r = { s = s, u = u, x = x, z = z, melee = in_melee(u), hp = hp(u),
				cav = is_cav(u), missile = is_missile(u), large = is_large(u), general = is_general(u),
				art = cls:find("^art") ~= nil, flier = safe(function() return u:can_fly() end, false),
				hero = is_char(u) and not is_general(u),
				visible = not E.alliance or safe(function() return u:is_visible_to_alliance(E.alliance) end, true) };
			r.monster = r.large and not is_char(u);
			W.enemy[#W.enemy + 1] = r;
			en_v = en_v + r.hp * (r.large and 1.5 or 1);
		end;
	end;
	W.strength = en_v > 0 and own_v / en_v or 10;
end;

-- nearest match; enemies we can see win over hidden ones (the game's AI won't attack what it can't see)
local function nearest(list, x, z, filter, skip)
	local best, bd, hid, hd;
	for _, r in ipairs(list) do
		if r ~= skip and (not filter or filter(r)) then
			local d = dist(x, z, r.x, r.z);
			if r.visible == false then
				if not hd or d < hd then hid, hd = r, d end;
			elseif not bd or d < bd then
				best, bd = r, d;
			end;
		end;
	end;
	if best then return best, bd end;
	return hid, hd;
end;

-- the visible enemy with the best score (lowest wins); hidden ones only if nothing is visible
local function best_enemy(score)
	local best, bs, hid, hs;
	for _, r in ipairs(W.enemy) do
		local s = score(r);
		if s then
			if r.visible == false then
				if not hs or s < hs then hid, hs = r, s end;
			elseif not bs or s < bs then
				best, bs = r, s;
			end;
		end;
	end;
	return best or hid;
end;

local function count_near(list, x, z, r, filter)
	local n = 0;
	for _, o in ipairs(list) do
		if (not filter or filter(o)) and dist(x, z, o.x, o.z) < r then n = n + 1 end;
	end;
	return n;
end;

local function near(list, me, r, filter, skip)
	local _, d = nearest(list, me.x, me.z, filter, skip);
	return d ~= nil and d < r;
end;

--------------------------------------------------------------------------------
-- conditions and targets
--------------------------------------------------------------------------------

local function lord_other(me) if W.lord and W.lord ~= me then return W.lord end end;

local COND = {
	always = function() return true end,
	early = function() return E.now - E.start_t < 60 end,
	after_60 = function() return E.now - E.start_t >= 60 end,
	after_180 = function() return E.now - E.start_t >= 180 end,

	in_melee = function(me) return me.melee end,
	not_in_melee = function(me) return not me.melee end,
	under_fire = function(me) return safe(function() return me.u:is_under_missile_attack() end, false) end,
	not_under_fire = function(me) return not safe(function() return me.u:is_under_missile_attack() end, false) end,
	hp_gt_75 = function(me) return me.hp > 0.75 end,
	hp_lt_75 = function(me) return me.hp < 0.75 end,
	hp_lt_50 = function(me) return me.hp < 0.5 end,
	hp_lt_25 = function(me) return me.hp < 0.25 end,
	has_ammo = function(me) return me.ammo > 0 end,
	ammo_low = function(me) return me.ammo0 > 0 and me.ammo < me.ammo0 * 0.25 end,
	ammo_out = function(me) return me.ammo0 > 0 and me.ammo <= 0 end,
	isolated = function(me) return not near(W.own, me, 100, nil, me) end,

	-- once a unit is falling back because of this it keeps going until 130 m clear, otherwise it
	-- turns round at 80 m, walks back in, and see-saws between retreating and attacking
	enemy_near = function(me)
		local c = me.e and me.e.cur;
		local limit = (c and c.act == "retreat" and E.now - c.since < 20) and 130 or 80;
		return near(W.enemy, me, limit);
	end,
	enemy_near_40 = function(me) return near(W.enemy, me, 40) end,
	enemy_near_150 = function(me) return near(W.enemy, me, 150) end,
	no_enemy_near = function(me) return not near(W.enemy, me, 150) end,
	enemies_near_3 = function(me) return count_near(W.enemy, me.x, me.z, 120) >= 3 end,

	enemy_cav_near = function(me) return near(W.enemy, me, 120, function(r) return r.cav end) end,
	enemy_large_near = function(me) return near(W.enemy, me, 120, function(r) return r.large end) end,
	enemy_missile_near = function(me) return near(W.enemy, me, 200, function(r) return r.missile end) end,
	enemy_inf_near = function(me) return near(W.enemy, me, 80, function(r) return not r.cav and not r.large end) end,
	enemy_general_near = function(me) return near(W.enemy, me, 150, function(r) return r.general end) end,

	ally_in_melee = function(me) return near(W.own, me, 150, function(r) return r.melee end, me) end,
	ally_hurt_near = function(me) return near(W.own, me, 150, function(r) return r.hp < 0.5 end, me) end,
	missiles_threatened = function()
		for _, o in ipairs(W.own) do
			if o.missile and near(W.enemy, o, 60) then return true end;
		end;
		return false;
	end,
	lord_in_melee = function() return W.lord and W.lord.melee end,
	lord_hurt = function() return W.lord and W.lord.hp < 0.5 end,
	lord_near = function(me) local l = lord_other(me); return l and dist(me.x, me.z, l.x, l.z) < 80 end,
	lord_far = function(me) local l = lord_other(me); return l and dist(me.x, me.z, l.x, l.z) > 150 end,

	winning = function() return W.strength > 1.15 end,
	even = function() return W.strength >= 0.85 and W.strength <= 1.15 end,
	losing = function() return W.strength < 0.85 end,
	outnumbered = function() return #W.enemy > #W.own end,
	few_enemies = function() return #W.enemy <= 3 end,
};

local function nearest_enemy(me, filter) return nearest(W.enemy, me.x, me.z, filter) end;

local TARGET = {
	nearest_enemy = function(me) return nearest_enemy(me) end,
	enemy_near_lord = function(me)
		local l = W.lord;
		if not l then return nil end;
		return nearest(W.enemy, l.x, l.z);
	end,
	enemy_near_missiles = function()
		local best, bd;
		for _, o in ipairs(W.own) do
			if o.missile then
				local r, d = nearest(W.enemy, o.x, o.z);
				if r and r.visible ~= false and (not bd or d < bd) then best, bd = r, d end;
			end;
		end;
		return best;
	end,
	enemy_isolated = function()
		return best_enemy(function(r)
			local _, d = nearest(W.enemy, r.x, r.z, nil, r);
			return -(d or 1000);
		end);
	end,
	enemy_farthest = function(me) return best_enemy(function(r) return -dist(me.x, me.z, r.x, r.z) end) end,

	enemy_infantry = function(me) return nearest_enemy(me, function(r) return not r.cav and not r.large and not r.art end) end,
	enemy_missile = function(me) return nearest_enemy(me, function(r) return r.missile end) end,
	enemy_archers = function(me) return nearest_enemy(me, function(r) return r.missile and not r.art end) end,
	enemy_artillery = function(me) return nearest_enemy(me, function(r) return r.art end) end,
	enemy_cavalry = function(me) return nearest_enemy(me, function(r) return r.cav end) end,
	enemy_flier = function(me) return nearest_enemy(me, function(r) return r.flier end) end,
	enemy_large = function(me) return nearest_enemy(me, function(r) return r.large end) end,
	enemy_monster = function(me) return nearest_enemy(me, function(r) return r.monster end) end,
	enemy_hero = function(me) return nearest_enemy(me, function(r) return r.hero end) end,
	enemy_general = function(me) return nearest_enemy(me, function(r) return r.general end) end,

	enemy_engaged = function(me) return nearest_enemy(me, function(r) return r.melee end) end,
	enemy_free = function(me) return nearest_enemy(me, function(r) return not r.melee end) end,
	enemy_attacking_lord = function()
		local l = W.lord;
		if not l or not l.melee then return nil end;
		local r, d = nearest(W.enemy, l.x, l.z, function(r) return r.melee end);
		if r and d < 40 then return r end;
	end,
	enemy_weakest = function(me) return best_enemy(function(r) return r.hp + dist(me.x, me.z, r.x, r.z) / 1000 end) end,
	enemy_strongest = function(me) return best_enemy(function(r) return -r.hp + dist(me.x, me.z, r.x, r.z) / 1000 end) end,

	ally_lord = function(me) return lord_other(me) end,
	ally_engaged = function(me) return nearest(W.own, me.x, me.z, function(r) return r.melee end, me) end,
	ally_weakest = function(me)
		local best;
		for _, r in ipairs(W.own) do
			if r ~= me and r.hp < 0.9 and (not best or r.hp < best.hp) then best = r end;
		end;
		return best;
	end,
	ally_nearest = function(me) return nearest(W.own, me.x, me.z, nil, me) end,
	ally_missile = function(me) return nearest(W.own, me.x, me.z, function(r) return r.missile end, me) end,
	ally_large = function(me) return nearest(W.own, me.x, me.z, function(r) return r.large and not r.general end, me) end,
	self = function(me) return me end,
};

--------------------------------------------------------------------------------
-- orders
--
-- plan() turns (action, target) into one concrete order for this moment:
--   { k = "attack", u = unit, primary = bool }   direct unit-controller attack
--   { k = "goto", x, z }                           direct unit-controller move (running)
--   { k = "halt" }                                 stop where you are
-- Multi-step actions (flank, skirmish, approach, cover, follow) change their order as
-- the situation changes, so evaluate() re-plans them every pass.
--------------------------------------------------------------------------------

local function shooter(e) return e.role == "missile" or e.role == "missile_cav" end;

local function away(me, from, d)
	local dx, dz = me.x - from.x, me.z - from.z;
	local l = math.max(1, math.sqrt(dx * dx + dz * dz));
	return me.x + dx / l * d, me.z + dz / l * d;
end;

local function toward(a, b, d)
	local dx, dz = b.x - a.x, b.z - a.z;
	local l = math.max(1, math.sqrt(dx * dx + dz * dz));
	return a.x + dx / l * d, a.z + dz / l * d, l;
end;

local function attack_order(e, me, target, melee)
	if target.visible == false then return { k = "goto", x = target.x, z = target.z } end;
	-- primary weapon is the bow/gun for missile units; melee orders and empty quivers mean hand to hand
	local primary = true;
	if shooter(e) and (melee or me.ammo <= 0) then primary = false end;
	return { k = "attack", u = target.u, primary = primary };
end;

local function plan(e, me, act, target)
	if act == "attack" then
		return attack_order(e, me, target, false);
	elseif act == "charge" or act == "melee" then
		return attack_order(e, me, target, true);
	elseif act == "flank" then
		-- a point beside and behind the target, as seen from the middle of our army
		local d = dist(me.x, me.z, target.x, target.z);
		if me.melee or d < 35 or target.visible == false then return attack_order(e, me, target, true) end;
		local l = dist(W.cx, W.cz, target.x, target.z);
		local ux, uz = (target.x - W.cx) / math.max(1, l), (target.z - W.cz) / math.max(1, l);
		local side = ((me.x - target.x) * -uz + (me.z - target.z) * ux) >= 0 and 1 or -1;
		local px, pz = target.x + ux * 30 - uz * 45 * side, target.z + uz * 30 + ux * 45 * side;
		if dist(me.x, me.z, px, pz) < 25 then return attack_order(e, me, target, true) end;
		return { k = "goto", x = px, z = pz };
	elseif act == "skirmish" then
		if not shooter(e) or me.ammo <= 0 then return attack_order(e, me, target, false) end;
		if dist(me.x, me.z, target.x, target.z) < 70 and target.visible ~= false then
			local x, z = away(me, target, 60);
			return { k = "goto", x = x, z = z };
		end;
		return attack_order(e, me, target, false);
	elseif act == "approach" then
		local x, z, l = toward(target, me, 60);
		if l <= 75 then return { k = "halt" } end;
		return { k = "goto", x = x, z = z };
	elseif act == "guard" then
		-- fight anything that comes near the friend, otherwise stay at its side
		local en = nearest(W.enemy, target.x, target.z);
		if en and dist(en.x, en.z, target.x, target.z) < CFG.guard_radius + 20 then return attack_order(e, me, en, false) end;
		if dist(me.x, me.z, target.x, target.z) > 30 then
			local x, z = toward(target, me, 20);
			return { k = "goto", x = x, z = z };
		end;
		return { k = "halt" };
	elseif act == "follow" then
		local x, z, l = toward(target, me, 25);
		if l <= 35 then return { k = "halt" } end;
		return { k = "goto", x = x, z = z };
	elseif act == "cover" then
		local en = nearest(W.enemy, target.x, target.z);
		if not en then return { k = "halt" } end;
		-- an enemy that reaches us gets fought
		if dist(me.x, me.z, en.x, en.z) < 30 then return attack_order(e, me, en, true) end;
		local x, z, l = toward(target, en, 35);
		if l < 50 then x, z = toward(target, en, l / 2) end;
		return { k = "goto", x = x, z = z };
	elseif act == "hold" then
		-- hold the spot where the tactic began: fight enemies that come close (missiles shoot from it)
		if not e.hold_at then e.hold_at = { x = me.x, z = me.z } end;
		local a = e.hold_at;
		local en = nearest(W.enemy, a.x, a.z);
		local r = shooter(e) and me.ammo > 0 and 140 or CFG.hold_radius;
		if en and en.visible ~= false and dist(en.x, en.z, a.x, a.z) < r then return attack_order(e, me, en, false) end;
		if dist(me.x, me.z, a.x, a.z) > 15 then return { k = "goto", x = a.x, z = a.z } end;
		return { k = "halt" };
	elseif act == "retreat" then
		-- away from the nearest enemy; toward the lord instead if he is safely behind us
		local en = nearest(W.enemy, me.x, me.z);
		if not en then return { k = "halt" } end;
		local tx, tz = away(me, en, CFG.retreat_dist);
		local l = dist(me.x, me.z, en.x, en.z);
		local lord = W.lord;
		if lord and lord ~= me and not lord.melee and dist(lord.x, lord.z, en.x, en.z) > l + 30 then
			tx, tz = lord.x, lord.z;
		end;
		return { k = "goto", x = tx, z = tz };
	elseif act == "to_lord" then
		local lord = lord_other(me);
		if not lord then return plan(e, me, "retreat", target) end;
		if dist(me.x, me.z, lord.x, lord.z) < 30 then return { k = "halt" } end;
		local en = nearest(W.enemy, lord.x, lord.z);
		local x, z = lord.x, lord.z;
		if en then x, z = away(lord, en, 20) end;
		return { k = "goto", x = x, z = z };
	elseif act == "regroup" then
		local cx, cz, n = 0, 0, 0;
		for _, o in ipairs(W.own) do if o ~= me then cx, cz, n = cx + o.x, cz + o.z, n + 1 end end;
		if n == 0 then return { k = "halt" } end;
		cx, cz = cx / n, cz / n;
		if dist(me.x, me.z, cx, cz) < 30 then return { k = "halt" } end;
		return { k = "goto", x = cx, z = cz };
	end;
	return nil;
end;

-- two orders that would make the unit do the same thing
local function same_order(a, b)
	if not a or not b or a.k ~= b.k then return false end;
	if a.k == "attack" then return a.u == b.u and a.primary == b.primary end;
	if a.k == "goto" or a.k == "hold" then return dist(a.x, a.z, b.x, b.z) < 15 end;
	if a.k == "guard" then return a.s == b.s end;
	return true;
end;

local function execute(e, me, o)
	local ok, err = pcall(function()
		-- direct orders, the way vanilla's patrol manager does it. Handing a lone unit to an
		-- AI planner (attack_force) left regiments dithering 100 m short of the enemy for minutes.
		local uc = e.sunit.uc;
		uc:take_control();
		if o.k == "attack" then uc:attack_unit(o.u, o.primary, true)
		elseif o.k == "goto" then uc:goto_location(gv(o.x, o.z), true)
		else uc:halt() end;
		-- then hand the unit back, as vanilla's goto_start_location_offset(..., release) does: it keeps
		-- the order, and its unit card stays selectable (player orders are blocked by disable_orders)
		if E.release then
			uc:release_control();
			e.direct = false;
			local far = false;
			if o.k == "goto" then far = dist(me.x, me.z, o.x, o.z) > 15
			elseif o.k == "attack" then
				local okp, tx, tz = pcall(upos, o.u);
				far = okp and tx ~= nil and dist(me.x, me.z, tx, tz) > 25;
			end;
			if far then e.rel_check = { t = E.now + 3, x = me.x, z = me.z, ammo = me.ammo } end;
		else
			e.direct = true;
		end;
	end);
	if not ok then log(e.name .. ": order " .. o.k .. " failed: " .. tostring(err)) end;
	return ok;
end;

local function target_key(t) return t and (uid(t.u) .. (t.visible == false and "h" or "")) or "-" end;

-- keep chasing the current target unless the new pick is clearly closer: flipping between two
-- enemies at similar range re-issued the order every few seconds and the unit marched back and forth
local function sticky(e, me, idx, target)
	local c = e.cur;
	if not c or c.idx ~= idx or not c.target or c.target == target or not target.s then return target end;
	local ad = T.ACTION_BY[c.act];
	if not ad or ad.kind ~= "e" then return target end;
	local old;
	for _, r in ipairs(W.enemy) do if r.u == c.target.u then old = r; break end end;
	if not old or old.visible == false then return target end;
	local d_old, d_new = dist(me.x, me.z, old.x, old.z), dist(me.x, me.z, target.x, target.z);
	if d_old <= d_new * 1.3 + 20 then return old end;
	return target;
end;

-- first movement tactic whose condition holds and whose target exists
local function choose(e, me)
	for i, t in ipairs(e.tactics) do
		local act = t[3];
		if act ~= "cast_attack" and act ~= "cast_buff" and T.validate(t) then
			local c = COND[t[1]];
			if c and c(me) then
				local tf = TARGET[t[2]];
				local target = tf and tf(me);
				if target then return i, act, sticky(e, me, i, target) end;
			end;
		end;
	end;
	-- nothing applies: attack the nearest enemy (DEFAULTS[role][1] is always that). Nothing else from
	-- the role defaults is ever used, so a unit only does what its own slots say or this.
	local target = TARGET.nearest_enemy(me);
	if target then return 101, "attack", sticky(e, me, 101, target) end;
	return nil;
end;

-- a unit with an attack order that hasn't moved, fought or shot for a while gets its order again
local function watchdog(e, me)
	if not e.cur or not e.cur.order or e.cur.order.k ~= "attack" or me.melee then e.watch = nil; return end;
	local ammo = me.ammo;
	local w = e.watch;
	if not w then e.watch = { x = me.x, z = me.z, ammo = ammo, t = E.now }; return end;
	if dist(w.x, w.z, me.x, me.z) > 4 or ammo < w.ammo then e.watch = { x = me.x, z = me.z, ammo = ammo, t = E.now }; return end;
	if E.now - w.t >= CFG.idle_after then
		local t = e.cur.target;
		local d = t and dist(me.x, me.z, t.x, t.z) or -1;
		e.idle_count = (e.idle_count or 0) + 1;
		log(string.format("%s idle %.0f s (order %s, target %.0f m away, %s) - re-ordering", e.name, E.now - w.t, e.cur.act, d,
			t and (t.visible == false and "hidden" or "visible") or "none"));
		e.cur = nil;	-- forces a fresh decision and order
		e.watch = nil;
	end;
end;

-- three seconds after a released order, did the unit start doing it? If released units keep
-- stopping dead, releasing evidently cancels orders here: keep script control from then on.
local function release_check(e, me)
	local r = e.rel_check;
	if not r or E.now < r.t then return end;
	e.rel_check = nil;
	if not E.release then return end;
	local acting = dist(r.x, r.z, me.x, me.z) > 3 or me.melee or (me.ammo or 0) < (r.ammo or 0);
	if acting then E.rel_ok = E.rel_ok + 1 else E.rel_fail = E.rel_fail + 1 end;
	if E.rel_fail >= 4 and E.rel_fail > E.rel_ok then
		E.release = false;
		log(string.format("released units are not carrying out their orders (%d stopped, %d fine) - keeping script control from now on (unit cards stay greyed out)",
			E.rel_fail, E.rel_ok));
		for _, u in ipairs(E.units) do u.cur = nil; u.next_eval = E.now + rnd(0, 0.5) end;
	end;
end;

local function evaluate(e, me)
	local idx, act, target = choose(e, me);
	if not idx then e.cur = nil; return end;
	if act ~= "hold" then e.hold_at = nil end;
	local order = plan(e, me, act, target);
	if not order then e.cur = nil; return end;
	local tk = target_key(target);
	local c = e.cur;
	if c and c.idx == idx and c.tk == tk then
		-- same tactic, same target: only send something when the concrete order changed. A direct
		-- attack lasts until the target dies; re-sending it makes the unit stop and re-form.
		if not same_order(order, c.order) then
			if execute(e, me, order) then c.order, c.refresh = order, E.now + CFG.refresh_orders end;
		elseif (order.k == "guard" or order.k == "hold") and E.now >= c.refresh then
			execute(e, me, order);
			c.refresh = E.now + CFG.refresh_orders;
		end;
		c.target = target;
		return;
	end;
	local target_lost = c and c.target and not alive(c.target.u);
	local higher = not c or idx < c.idx;
	if not higher and not target_lost and c and E.now < c.until_t then return end;
	if execute(e, me, order) then
		if CFG.log_decisions then
			local t = idx < 100 and e.tactics[idx] or (T.DEFAULTS[e.role] or T.DEFAULTS.melee)[idx - 100];
			local tname = target.e and target.e.name or safe(function() return target.u:type() end, "?");
			log(string.format("%s: %s %d -> %s (%s)", e.name, idx < 100 and "tactic" or "default", idx < 100 and idx or idx - 100,
				T.label(t), tname));
		end;
		e.cur = { idx = idx, tk = tk, target = target, act = act, order = order, until_t = E.now + CFG.commit + rnd(-1, 1),
			refresh = E.now + CFG.refresh_orders, since = E.now,
			tkey = target.e and target.e.key or safe(function() return target.u:type() end, nil), hidden = target.visible == false,
			self_target = target.e == e };
	end;
end;

--------------------------------------------------------------------------------
-- spells: driven by cast_attack / cast_buff tactics
--------------------------------------------------------------------------------

local ATTACK_CATS = { X = true, D = true, H = true, B = true, S = true };
local BUFF_CATS = { A = true, R = true };

local function queue_scan(e)
	if not CD_ABILITIES then return end;
	for cat, list in pairs(CD_ABILITIES) do
		E.scan_queue[#E.scan_queue + 1] = { e = e, cat = cat, list = list, i = 1 };
	end;
	e.scanned = E.now;
end;

local function run_scan()
	local budget = CFG.scan_per_tick;
	while budget > 0 and #E.scan_queue > 0 do
		local job = E.scan_queue[1];
		local e = job.e;
		local u = e.sunit.unit;
		if not alive(u) then
			table.remove(E.scan_queue, 1);
		else
			while budget > 0 and job.i <= #job.list do
				local ak = job.list[job.i];
				if not e.abilities[ak] and safe(function() return u:can_perform_special_ability(ak) end, false) then
					e.abilities[ak] = job.cat;
					e.n_abilities = e.n_abilities + 1;
				end;
				job.i = job.i + 1;
				budget = budget - 1;
			end;
			if job.i > #job.list then
				table.remove(E.scan_queue, 1);
				if #E.scan_queue == 0 or E.scan_queue[1].e ~= e then
					if e.n_abilities > 0 and not e.scan_logged then
						log(string.format("%s can cast %d abilities", e.name, e.n_abilities));
						e.scan_logged = true;
					end;
				end;
			end;
		end;
	end;
end;

local function friendlies_near(x, z, r)
	for _, o in ipairs(W.own) do
		if dist(x, z, o.x, o.z) < r then return true end;
	end;
	return false;
end;

local function try_cast(e, me, t)
	local target = TARGET[t[2]](me);
	if not target then return false end;
	local cats = t[3] == "cast_attack" and ATTACK_CATS or BUFF_CATS;
	local d = dist(me.x, me.z, target.x, target.z);
	local keys = {};
	for ak, cat in pairs(e.abilities) do
		if cats[cat] and d <= (CFG.ranges[cat] or 150) and (e.blocked[ak] or 0) <= E.now then
			local ok = true;
			if (cat == "X" or cat == "B") and friendlies_near(target.x, target.z, CFG.friendly_clear) then ok = false end;
			if cat == "R" and target.hp > 0.85 then ok = false end;
			if ok then keys[#keys + 1] = ak end;
		end;
	end;
	for i = #keys, 2, -1 do
		local j = math.random(i);
		keys[i], keys[j] = keys[j], keys[i];
	end;
	for _, ak in ipairs(keys) do
		if safe(function() return me.u:can_perform_special_ability(ak) end, false) then
			local ok, err = pcall(function() e.sunit.uc:perform_special_ability(ak, target.u) end);
			if ok then
				log(string.format("%s casts %s on %s", e.name, ak, target.e and target.e.name or safe(function() return target.u:type() end, "?")));
				e.cast_key, e.cast_tkey = ak, target.e and target.e.key or safe(function() return target.u:type() end, nil);
				if CD_DIRECTOR_NOTIFY then pcall(CD_DIRECTOR_NOTIFY, "cast", me.u, target.u) end;
				return true;
			end;
			e.blocked[ak] = E.now + CFG.fail_backoff;
			if not e.fail_logged then
				log(e.name .. ": cast " .. ak .. " failed (probably not enough winds; skipping it for " .. CFG.fail_backoff .. " s): " .. tostring(err));
				e.fail_logged = true;
			end;
		end;
	end;
	return false;
end;

local function cast_pass()
	for _, me in ipairs(W.own) do
		local e = me.e;
		if e.casts and e.n_abilities > 0 and E.now >= e.next_cast then
			for ri, t in ipairs(e.tactics) do
				if (t[3] == "cast_attack" or t[3] == "cast_buff") and T.validate(t) then
					local c = COND[t[1]];
					if c and c(me) and try_cast(e, me, t) then
						e.cast_row, e.cast_at = ri, E.now;
						e.next_cast = E.now + CFG.caster_cooldown + rnd(0, 2);
						break;
					end;
				end;
			end;
		end;
		if e.casts and E.now - (e.scanned or 0) > CFG.ability_rescan then queue_scan(e) end;
	end;
end;

--------------------------------------------------------------------------------
-- setup
--------------------------------------------------------------------------------

local function make_sunit(u, ref) return safe(function() return script_unit:new(u, ref) end, nil) end;

local function refresh_enemies()
	local pa = safe(function() return bm:get_player_alliance_num() end, 1);
	local alliances = bm:alliances();
	for a = 1, alliances:count() do
		if a ~= pa then
			local armies = alliances:item(a):armies();
			for r = 1, armies:count() do
				local units = armies:item(r):units();
				for i = 1, units:count() do
					local u = units:item(i);
					local k = uid(u);
					if alive(u) and not E.enemy_keys[k] then
						local s = make_sunit(u, "cd_tac_en_" .. k);
						if s then E.enemy[#E.enemy + 1] = s; E.enemy_keys[k] = true end;
					end;
				end;
			end;
		end;
	end;
end;

local function add_entry(u, key, name, sname, role, tactics, data)
	local s = make_sunit(u, sname);
	if not s then return nil end;
	local e = {
		sunit = s, name = name, role = role, tactics = tactics, unit = u, key = key, uid = uid(u),
		rank = data and data.rank, from_campaign = data ~= nil,
		next_eval = E.now + rnd(0, CFG.eval_every), abilities = {}, n_abilities = 0, blocked = {}, next_cast = E.now + rnd(2, 5),
		ammo0 = safe(function() return u:starting_ammo() end, 0) or 0,
	};
	-- no script_ai_planner: creating one hands the unit to the battle AI's planner, which
	-- keeps it under AI control - greyed out and unselectable - for the whole battle
	for _, t in ipairs(tactics) do
		if t[3] == "cast_attack" or t[3] == "cast_buff" then e.casts = true end;
	end;
	if e.casts then queue_scan(e) end;
	E.units[#E.units + 1] = e;
	log(string.format("%s (%s, %d slots%s): %s", name, role, #tactics, data and "" or ", no campaign data",
		T.serialise(tactics)));
	return e;
end;

-- reinforcements (and anything else that joins your army mid-battle): orders are locked for the
-- whole army, so a unit the engine doesn't know about would just stand there. Give it defaults.
local function adopt_newcomers()
	local known = {};
	for _, e in ipairs(E.units) do known[e.uid] = true end;
	local pa = safe(function() return bm:get_player_alliance_num() end, 1);
	local armies = bm:alliances():item(pa):armies();
	local added = 0;
	for r = 1, armies:count() do
		local army = armies:item(r);
		if safe(function() return army:is_player_controlled() end, r == 1) then
			local units = army:units();
			for i = 1, units:count() do
				local u = units:item(i);
				local k = uid(u);
				if not known[k] and safe(function() return u:number_of_men_alive() > 0 end, false) then
					local key = safe(function() return u:type() end, "?");
					local role = battle_role(u);
					E.joined = (E.joined or 0) + 1;
					if add_entry(u, key, key .. "#r" .. E.joined, "cd_tac_new_" .. E.joined, role, T.default_tactics(role, CFG.no_data_slots)) then
						added = added + 1;
					end;
				end;
			end;
		end;
	end;
	if added > 0 then
		log(string.format("%d unit(s) joined your army mid-battle, now on default tactics", added));
		if CD_TACTICS_PANEL and CD_TACTICS_PANEL.rehook then pcall(CD_TACTICS_PANEL.rehook) end;
	end;
end;

local function setup()
	local forces = read_export();
	local pa = safe(function() return bm:get_player_alliance_num() end, 1);
	local armies = bm:alliances():item(pa):armies();
	E.units = {};
	local custom, matched = 0, 0;
	for r = 1, armies:count() do
		local army = armies:item(r);
		if safe(function() return army:is_player_controlled() end, r == 1) then
			local units = army:units();
			local keys = {};
			for i = 1, units:count() do keys[i] = safe(function() return units:item(i):type() end, "?") end;
			local force = match_force(forces, keys);
			local used = {};
			for i = 1, units:count() do
				local u = units:item(i);
				-- campaign entry: same position and type, else the first unused one of that type
				local data;
				if force then
					local d = force.units[i];
					if d and d.key == keys[i] and not used[i] then data, used[i] = d, true
					else
						for j, d2 in ipairs(force.units) do
							if not used[j] and d2.key == keys[i] then data, used[j] = d2, true; break end;
						end;
					end;
				end;
				local role = data and data.role or battle_role(u);
				local tactics;
				if data and #data.tactics == 0 then
					matched = matched + 1;
					tactics = T.default_tactics(role, T.slots_for_rank(data.rank));
				elseif data then
					matched = matched + 1;
					local n = T.slots_for_rank(data.rank);
					tactics = {};
					for k = 1, math.min(n, #data.tactics) do tactics[k] = data.tactics[k] end;
					-- pad (rank went up since the tactics were set) with defaults not already listed
					for _, d in ipairs(T.DEFAULTS[role] or T.DEFAULTS.melee) do
						if #tactics >= n then break end;
						local dup = false;
						for _, t in ipairs(tactics) do if T.serialise({ t }) == T.serialise({ d }) then dup = true end end;
						if not dup then T.insert_padded(tactics, { d[1], d[2], d[3] }) end;
					end;
				else
					custom = custom + 1;
					tactics = T.default_tactics(role, CFG.no_data_slots);
				end;
				add_entry(u, keys[i], keys[i] .. "#" .. i, "cd_tac_own_" .. r .. "_" .. i, role, tactics, data);
			end;
		end;
	end;
	E.alliance = safe(function() return bm:alliances():item(pa) end, nil);
	E.enemy, E.enemy_keys = {}, {};
	refresh_enemies();
	log(string.format("battle started: %d units under tactics (%d from campaign, %d on defaults), %d enemies",
		#E.units, matched, custom, #E.enemy));
end;

local function lockout(on)
	if not CFG.lockout then return end;
	local ok, err = pcall(function() bm:disable_orders(on) end);
	log((on and "orders locked" or "orders unlocked") .. (ok and "" or (" - failed: " .. tostring(err))));
end;

local function stop()
	if not E.running then return end;
	E.running = false;
	pcall(function() bm:remove_real_callback("cd_tactics_tick") end);
	for _, e in ipairs(E.units) do
		if e.direct then pcall(function() e.sunit.uc:release_control() end) end;
	end;
	lockout(false);
	log("battle over, tactics engine stopped");
end;

local TICK = 0.2;

local function tick()
	E.now = E.now + TICK;
	run_scan();
	if E.now >= E.next_refresh then
		E.next_refresh = E.now + 10;
		if E.now < 65 then
			local held = {};
			for _, e in ipairs(E.units) do
				if safe(function() return e.unit:is_script_controlled() end, false) then held[#held + 1] = e.name end;
			end;
			log(string.format("script-controlled (greyed) units at %.0f s: %d of %d%s", E.now, #held, #E.units,
				#held > 0 and (" - " .. table.concat(held, ", ")) or ""));
		end;
		pcall(refresh_enemies);
		local ok, err = pcall(adopt_newcomers);
		if not ok then log("reinforcement check error: " .. tostring(err)) end;
	end;
	snapshot();
	if #W.enemy == 0 then return end;
	for _, me in ipairs(W.own) do
		local e = me.e;
		if E.now >= e.next_eval then
			e.next_eval = E.now + CFG.eval_every;
			pcall(release_check, e, me);
			pcall(watchdog, e, me);
			local ok, err = pcall(evaluate, e, me);
			if not ok then log(e.name .. ": evaluate error " .. tostring(err)) end;
		end;
	end;
	if E.now >= E.next_cast then
		E.next_cast = E.now + CFG.cast_every;
		cast_pass();
	end;
end;

local errors = 0;
local function safe_tick()
	local ok, err = pcall(tick);
	if not ok then
		errors = errors + 1;
		log("ERROR in tick: " .. tostring(err));
		if errors > 30 then
			log("too many errors, giving control back");
			stop();
		end;
	end;
end;

local function start()
	if E.running or not CFG.enabled then return end;
	-- scripted orders would desync a multiplayer battle (and could take over another player's army)
	if safe(function() return bm:is_multiplayer() end, false) then
		log("multiplayer battle: unit tactics disabled, everyone keeps control of their own army");
		return;
	end;
	E.running = true;
	E.now, E.start_t = 0, 0;
	E.release, E.rel_ok, E.rel_fail = CFG.release_after_order, 0, 0;
	local ok, err = pcall(setup);
	if not ok then
		log("setup failed, control stays with the player: " .. tostring(err));
		E.running = false;
		return;
	end;
	if #E.units == 0 then
		log("no player units found, control stays with the player");
		E.running = false;
		return;
	end;
	lockout(true);
	bm:repeat_real_callback(safe_tick, TICK * 1000, "cd_tactics_tick");
end;

-- wait for deployment to end
local function watch()
	if E.running then
		pcall(function() bm:remove_real_callback("cd_tactics_watch") end);
		return;
	end;
	if safe(function() return bm:is_conflict_phase() end, false) then
		pcall(function() bm:remove_real_callback("cd_tactics_watch") end);
		start();
	end;
end;

-- read-only view for the battle tactics panel
local function find(u)
	if not u then return nil end;
	local k = uid(u);
	for _, e in ipairs(E.units) do
		if e.unit == u or e.uid == k then return e end;
	end;
	return nil;
end;

-- what a unit is doing right now: { idx = row (or nil), default = role-default row (when no row applied),
--   act, target_key, hidden, since, cast_row, cast_ago, cast_key, alive }
local function state(e)
	if not e then return nil end;
	local st = { alive = alive(e.unit), now = E.now };
	local c = e.cur;
	if c then
		if c.idx < 100 then st.idx = c.idx else st.default = (T.DEFAULTS[e.role] or T.DEFAULTS.melee)[c.idx - 100] end;
		st.act, st.target_key, st.hidden, st.self_target, st.since = c.act, c.tkey, c.hidden, c.self_target, c.since;
	end;
	if e.cast_at then st.cast_row, st.cast_ago, st.cast_key, st.cast_tkey = e.cast_row, E.now - e.cast_at, e.cast_key, e.cast_tkey end;
	return st;
end;

CD_TACTICS_ENGINE = {
	start = start, stop = stop,
	running = function() return E.running end,
	units = function() return E.units end,
	find = find,
	state = state,
	enemies_left = function() return #W.enemy end,
};

if CFG.enabled then
	bm:repeat_real_callback(watch, 500, "cd_tactics_watch");
	core:add_listener("cd_tactics_end", "BattleConflictFinished", true, function() stop() end, true);
	log("---- tactics engine loaded, waiting for the battle to start ----");
end;
