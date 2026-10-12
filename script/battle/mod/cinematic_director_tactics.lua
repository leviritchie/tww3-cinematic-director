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
	paradigm_cooldown = 20,		-- seconds between paradigm shifts
	play_eval = 0.6,			-- ... for units running a play (cycle charge, kiting, hammer): their timing matters
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
	local ok, f = pcall(io.open, LOG_PATH, "a");
	if ok and f then
		local t = "";
		pcall(function() t = os.date("%H:%M:%S ") end);
		f:write(t .. "[tactics] " .. tostring(s) .. "\n");
		f:close();
	end;
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
	eng = {},			-- enemy key -> time it started fighting our units
	hpt = {},			-- own entry / enemy key -> { hp, t, rate }: health lost per second (smoothed)
	focus = nil,		-- the army's focus-fire target { key, t }
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
		-- "force <cqi> [general's rank]", then "unit <idx> <key> <cqi> <rank> <role> <rows>" lines and
		-- "para <idx> <k> <rows>" lines for paradigms 2-4 that differ from paradigm 1
		local fc, lr = line:match("^force (%-?%d+) ?(%d*)");
		if fc then
			cur = { cqi = fc, units = {}, by_idx = {}, lord_rank = tonumber(lr) };
			forces[#forces + 1] = cur;
		elseif cur then
			local idx, key, cqi, rank, role, tac = line:match("^unit (%d+) (%S+) (%S+) (%d+) (%S+) ?(.*)$");
			if idx then
				local d = { key = key, cqi = cqi, rank = tonumber(rank), role = role, tactics = T.parse(tac), sets = {} };
				cur.units[#cur.units + 1] = d;
				cur.by_idx[idx] = d;
			else
				local pi, k, ptac = line:match("^para (%d+) (%d) ?(.*)$");
				local d = pi and cur.by_idx[pi];
				if d then d.sets[tonumber(k)] = T.parse(ptac) end;
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

local function norm(x, z)
	local l = math.sqrt(x * x + z * z);
	if l < 0.001 then return 0, 0, 0 end;
	return x / l, z / l, l;
end;

local function is_char(u) return class_of(u) == "com" or is_general(u) end;

-- health lost per second (a share of the unit), smoothed over ~6 s
local function loss_rate(r, k)
	local h = E.hpt[k];
	if not h then h = { hp = r.hp, t = E.now, rate = 0 }; E.hpt[k] = h end;
	local dt = E.now - h.t;
	if dt >= 1 then
		local inst = math.max(0, (h.hp - r.hp) / dt);
		h.rate = h.rate + (inst - h.rate) * math.min(1, dt / 6);
		h.hp, h.t = r.hp, E.now;
	end;
	return h.rate;
end;

-- the game's own verdict, read through the UI context of the unit (the unit card tooltip's morale line): its
-- strongest morale effect is "Winning current combat" or "Losing currently". Only the strongest effect is
-- readable, so this is seen only when the fight outweighs everything else on the unit's morale.
local NATIVE = { win = nil, lose = nil, ready = false, next_log = 0 };
local function plain(t) return t and (tostring(t):gsub("%[%[[^%]]*%]%]", ""):gsub("^%s+", ""):gsub("%s+$", "")) or nil end;
local function ccv(u, expr)
	local ok, v = pcall(function() return common.get_context_value("CcoBattleUnit", tostring(u:unique_ui_id()), expr) end);
	if ok then return v end;
	return nil;
end;
local function native_fight(r, h)
	if not NATIVE.ready then
		NATIVE.ready = true;
		local function loc(k) local ok, t = pcall(function() return common.get_localised_string(k) end); return ok and plain(t) or nil end;
		NATIVE.win = loc("random_localisation_strings_string_unit_encouraged_winning");
		NATIVE.lose = loc("random_localisation_strings_string_unit_concerned_losing");
		if NATIVE.win == "" then NATIVE.win = nil end;
		if NATIVE.lose == "" then NATIVE.lose = nil end;
		log(string.format("fight states: the game's morale lines are '%s' / '%s'", tostring(NATIVE.win), tostring(NATIVE.lose)));
	end;
	-- read at most once a second per unit
	if h.nat_t and E.now - h.nat_t < 1 then return h.nat end;
	h.nat_t = E.now;
	local top = plain(ccv(r.u, "MoraleGreatestEffect"));
	h.nat_top = top;
	h.nat = (top and NATIVE.win and top == NATIVE.win and "win") or (top and NATIVE.lose and top == NATIVE.lose and "lose") or nil;
	return h.nat;
end;

-- who is winning each melee: a unit's health loss against the average of the enemies in melee around it,
-- and the game's verdict where it can be read (native_fight).
-- r.fight = "win_big" / "win" / "lose" / "lose_bad" (nil: not fighting, or even), r.foe = nearest of them
local FIGHT_R, FIGHT_MIN, FIGHT_BAD = 40, 0.003, 0.006;
local function fight_states(list, foes)
	for _, r in ipairs(list) do
		r.fight, r.foe = nil, nil;
		if r.melee then
			local n, sum, waver, fd = 0, 0, false, nil;
			for _, o in ipairs(foes) do
				if o.melee then
					local d = dist(r.x, r.z, o.x, o.z);
					if d < FIGHT_R then
						n, sum = n + 1, sum + o.loss;
						if o.waver then waver = true end;
						if not fd or d < fd then r.foe, fd = o, d end;
					end;
				end;
			end;
			if n > 0 then
				local mine, theirs = r.loss, sum / n;
				if r.waver or (mine > FIGHT_BAD and mine > theirs * 2.5) then r.fight = "lose_bad"
				elseif waver or (theirs > FIGHT_BAD and theirs > mine * 2.5) then r.fight = "win_big"
				elseif mine > FIGHT_MIN and mine > theirs * 1.5 then r.fight = "lose"
				elseif theirs > FIGHT_MIN and theirs > mine * 1.5 then r.fight = "win" end;
			end;
			-- the game's verdict wins over the estimate (the estimate still says how strongly)
			local nat = r.hk and E.hpt[r.hk] and native_fight(r, E.hpt[r.hk]);
			if nat == "win" and r.fight ~= "win" and r.fight ~= "win_big" then r.fight = "win"
			elseif nat == "lose" and r.fight ~= "lose" and r.fight ~= "lose_bad" then r.fight = "lose" end;
			r.nat = nat;
		end;
	end;
end;

-- for tuning: what the game's unit context says about a few units in melee, next to the estimate
local function fight_probe()
	if E.now < NATIVE.next_log then return end;
	NATIVE.next_log = E.now + 5;
	local n = 0;
	for _, list in ipairs({ W.own, W.enemy }) do
		for _, r in ipairs(list) do
			if r.melee and n < 4 then
				n = n + 1;
				local h = E.hpt[r.hk] or {};
				local function v(expr) local x = ccv(r.u, expr); return x == nil and "-" or tostring(x) end;
				log(string.format("fight probe: %s %s: estimate %s (loses %.2f%%/s), game %s; top morale line '%s', status %s colour %s, hp lost recently %s, damage dealt recently %s, morale %s %s",
					list == W.own and "ours" or "theirs", safe(function() return r.u:type() end, "?"), tostring(r.fight), (r.loss or 0) * 100,
					tostring(r.nat), tostring(h.nat_top), v("StatusMostImportant.Key"), v("StatusColour"),
					v("PercentHpLostRecently"), v("DamageInflictedRecently"), v("MoraleState"), v("MoralePercent")));
			end;
		end;
	end;
end;

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
			r.loss, r.hk = loss_rate(r, e), e;
			if r.melee then r.waver = safe(function() return u:is_wavering() end, false) end;
			W.own[#W.own + 1] = r;
			if r.general then W.lord = r end;
			own_v = own_v + r.hp * (r.large and 1.5 or 1);
			cx, cz, n = cx + x, cz + z, n + 1;
		end;
	end;
	W.cx, W.cz = n > 0 and cx / n or 0, n > 0 and cz / n or 0;
	local ex, ez, ne = 0, 0, 0;
	local engaged = {};
	for _, s in ipairs(E.enemy) do
		local u = s.unit;
		if alive(u) then
			local x, z = upos(u);
			local cls = class_of(u);
			local key = s.cd_key or uid(u);
			local r = { s = s, u = u, x = x, z = z, melee = in_melee(u), hp = hp(u), key = key,
				cav = is_cav(u), missile = is_missile(u), large = is_large(u), general = is_general(u),
				art = cls:find("^art") ~= nil, flier = safe(function() return u:can_fly() end, false),
				hero = is_char(u) and not is_general(u),
				visible = not E.alliance or safe(function() return u:is_visible_to_alliance(E.alliance) end, true) };
			r.monster = r.large and not is_char(u);
			r.loss, r.hk = loss_rate(r, key), key;
			if r.melee then r.waver = safe(function() return u:is_wavering() end, false) end;
			-- how long it has been fighting our units (hammer and anvil waits for the anvil to hold)
			if r.melee then engaged[key] = E.eng[key] or E.now end;
			r.eng_t = r.melee and (E.now - engaged[key]) or 0;
			W.enemy[#W.enemy + 1] = r;
			en_v = en_v + r.hp * (r.large and 1.5 or 1);
			if r.visible ~= false then ex, ez, ne = ex + x, ez + z, ne + 1 end;
		end;
	end;
	E.eng = engaged;
	W.ex, W.ez = ne > 0 and ex / ne or nil, ne > 0 and ez / ne or nil;
	W.strength = en_v > 0 and own_v / en_v or 10;
	fight_states(W.own, W.enemy);
	fight_states(W.enemy, W.own);
	if CFG.log_decisions then pcall(fight_probe) end;
end;

-- direction from (x, z) toward the enemy army
local function front(x, z)
	if not W.ex then return 0, 1 end;
	local fx, fz = norm(W.ex - x, W.ez - z);
	if fx == 0 and fz == 0 then return 0, 1 end;
	return fx, fz;
end;

local function enemy_by_key(k)
	for _, r in ipairs(W.enemy) do if r.key == k then return r end end;
	return nil;
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

-- true and the closest unit found (the WHEN condition's unit), or false
local function near(list, me, r, filter, skip)
	local o, d = nearest(list, me.x, me.z, filter, skip);
	if d ~= nil and d < r then return true, o end;
	return false;
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

	in_melee = function(me)
		if not me.melee then return false end;
		return true, me.foe or nearest(W.enemy, me.x, me.z, function(r) return r.melee end);
	end,
	not_in_melee = function(me) return not me.melee end,
	under_fire = function(me)
		if not safe(function() return me.u:is_under_missile_attack() end, false) then return false end;
		return true, (nearest(W.enemy, me.x, me.z, function(r) return r.missile end));
	end,
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
	enemies_near_3 = function(me)
		if count_near(W.enemy, me.x, me.z, 120) < 3 then return false end;
		return true, (nearest(W.enemy, me.x, me.z));
	end,

	enemy_cav_near = function(me) return near(W.enemy, me, 120, function(r) return r.cav end) end,
	enemy_large_near = function(me) return near(W.enemy, me, 120, function(r) return r.large end) end,
	enemy_missile_near = function(me) return near(W.enemy, me, 200, function(r) return r.missile end) end,
	enemy_inf_near = function(me) return near(W.enemy, me, 80, function(r) return not r.cav and not r.large end) end,
	enemy_general_near = function(me) return near(W.enemy, me, 150, function(r) return r.general end) end,

	ally_in_melee = function(me)
		local ok, a = near(W.own, me, 150, function(r) return r.melee end, me);
		return ok, a, a and a.foe;
	end,
	ally_hurt_near = function(me) return near(W.own, me, 150, function(r) return r.hp < 0.5 end, me) end,
	-- the unit: the threatened missile unit closest to this one, and the enemy near it
	missiles_threatened = function(me)
		local best, foe, bd;
		for _, o in ipairs(W.own) do
			if o.missile then
				local ok, en = near(W.enemy, o, 60);
				local d = ok and dist(me.x, me.z, o.x, o.z);
				if ok and (not bd or d < bd) then best, foe, bd = o, en, d end;
			end;
		end;
		if not best then return false end;
		return true, best, foe;
	end,
	lord_in_melee = function()
		local l = W.lord;
		if not (l and l.melee) then return false end;
		return true, l, l.foe;
	end,
	lord_hurt = function() local l = W.lord; if l and l.hp < 0.5 then return true, l, l.foe end; return false end,
	lord_near = function(me) local l = lord_other(me); if l and dist(me.x, me.z, l.x, l.z) < 80 then return true, l end; return false end,
	lord_far = function(me) local l = lord_other(me); if l and dist(me.x, me.z, l.x, l.z) > 150 then return true, l end; return false end,

	-- fights (see fight_states)
	self_winning = function(me) if me.fight == "win" or me.fight == "win_big" then return true, me.foe end; return false end,
	self_winning_big = function(me) if me.fight == "win_big" then return true, me.foe end; return false end,
	self_losing = function(me) if me.fight == "lose" or me.fight == "lose_bad" then return true, me.foe end; return false end,
	self_losing_bad = function(me) if me.fight == "lose_bad" then return true, me.foe end; return false end,
	ally_winning = function(me)
		local ok, a = near(W.own, me, 150, function(r) return r.fight == "win" or r.fight == "win_big" end, me);
		return ok, a, a and a.foe;
	end,
	ally_losing = function(me)
		local ok, a = near(W.own, me, 150, function(r) return r.fight == "lose" or r.fight == "lose_bad" end, me);
		return ok, a, a and a.foe;
	end,
	ally_losing_bad = function(me)
		local ok, a = near(W.own, me, 150, function(r) return r.fight == "lose_bad" end, me);
		return ok, a, a and a.foe;
	end,

	winning = function() return W.strength > 1.15 end,
	even = function() return W.strength >= 0.85 and W.strength <= 1.15 end,
	losing = function() return W.strength < 0.85 end,
	outnumbered = function() return #W.enemy > #W.own end,
	few_enemies = function(me)
		if #W.enemy > 3 then return false end;
		return true, (nearest(W.enemy, me.x, me.z));
	end,
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
	enemy_winning_fight = function(me) return nearest_enemy(me, function(r) return r.fight == "win" or r.fight == "win_big" end) end,
	enemy_losing_fight = function(me) return nearest_enemy(me, function(r) return r.fight == "lose" or r.fight == "lose_bad" end) end,

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
	ally_losing_fight = function(me) return nearest(W.own, me.x, me.z, function(r) return r.fight == "lose" or r.fight == "lose_bad" end, me) end,
	self = function(me) return me end,

	-- the unit the row's WHEN condition found (t1, t2: what the condition returned after true)
	trigger_enemy = function(me, t1, t2)
		for _, r in ipairs({ t1 or false, t2 or false }) do if r and r.s then return r end end;
		return nil;
	end,
	trigger_ally = function(me, t1, t2)
		for _, r in ipairs({ t1 or false, t2 or false }) do if r and r.e and r ~= me then return r end end;
		return nil;
	end,
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

--------------------------------------------------------------------------------
-- plays: whole battle plans in one tactic row, each with a little state machine in
-- e.st (reset when the unit switches play). PICK[play] chooses the play's target
-- (or declines with nil, handing over to the next row); plan() below runs it.
--------------------------------------------------------------------------------

local PLAYS = { hammer = true, hammer_flank = true, hammer_wide = true, cycle_charge = true, skirmish = true, focus = true, fire_support = true, disrupt = true,
	kill_lord = true, high_ground = true, duelist = true, caster = true };

local function play_state(e, act)
	if not e.st or e.st.act ~= act then e.st = { act = act, t0 = E.now } end;
	return e.st;
end;

local function has_ammo(e, me) return shooter(e) and me.ammo > 0 end;
local function busy_with(o, act) local c = o.e and o.e.cur; return c and c.act == act end;

-- a shooter backs off from enemy melee troops closing in (not ones already locked in a fight
-- with our units), away from them and toward our own lines, until 110 m clear
local function kite(e, me, st)
	if not has_ammo(e, me) or e.art then return nil end;
	local active = st.kite_until and E.now < st.kite_until;
	local th, d = nearest(W.enemy, me.x, me.z, function(o) return not o.missile and o.visible ~= false end);
	if not th or d > (active and 110 or 75) or (th.melee and d > 35) then return nil end;
	if not active then st.kites = (st.kites or 0) + 1 end;
	st.kite_until = E.now + 4;
	local ax, az = norm(me.x - th.x, me.z - th.z);
	local bx, bz = 0, 0;
	if dist(me.x, me.z, W.cx, W.cz) > 30 then bx, bz = norm(W.cx - me.x, W.cz - me.z) end;
	local dx, dz = norm(ax * 0.65 + bx * 0.35, az * 0.65 + bz * 0.35);
	if dx == 0 and dz == 0 then dx, dz = ax, az end;
	return { k = "goto", x = me.x + dx * 70, z = me.z + dz * 70 };
end;

-- out of ammo, or a melee unit on a shooting play: help the nearest fight
local function join_fight(e, me, fallback)
	local en, d = nearest(W.enemy, me.x, me.z, function(o) return o.melee end);
	if en and d < 200 then return attack_order(e, me, en, true) end;
	local n = fallback or nearest(W.enemy, me.x, me.z);
	if n then return attack_order(e, me, n, true) end;
	return { k = "halt" };
end;

-- charge, fight while the charge bonus counts, pull out to (rx, rz), reform, charge again
local CYCLE_HOLD = { cavalry = 9, missile_cav = 6, monster = 14, hero = 10, melee = 10, missile = 8 };
local function cycle(e, me, target, st, rx, rz)
	local ph = st.cy or "charge";
	if ph == "charge" then
		if me.melee then st.cy, st.ct = "contact", E.now end;
		return attack_order(e, me, target, true);
	end;
	if ph == "contact" then
		local hold = e.chariot and 3 or (CYCLE_HOLD[e.role] or 10);
		if not me.melee and E.now - st.ct > 3 then st.cy = "charge"; return attack_order(e, me, target, true) end;
		-- stay in a fight that is nearly won
		if E.now - st.ct < hold or target.hp < 0.35 then return attack_order(e, me, target, true) end;
		st.cy, st.ot = "out", E.now;
		st.n = (st.n or 0) + 1;
		log(string.format("%s: pulling out after %.0f s to charge again (cycle %d)", e.name, E.now - st.ct, st.n));
	end;
	if st.cy == "out" then
		local d = dist(me.x, me.z, target.x, target.z);
		if (dist(me.x, me.z, rx, rz) < 20 and d > 45) or E.now - st.ot > 12 then
			st.cy, st.rt = "reform", E.now;
		else
			return { k = "goto", x = rx, z = rz };
		end;
	end;
	-- reform: a moment to turn round and dress ranks
	if E.now - st.rt < 2 then return { k = "halt" } end;
	st.cy = "charge";
	return attack_order(e, me, target, true);
end;

-- focus fire: one target for every unit on the play
local function focus_value(r)
	local v = 1;
	if r.general then v = 3.2 elseif r.hero then v = 2.6 elseif r.monster then v = 2.4 elseif r.large then v = 2 end;
	if r.art then v = math.max(v, 2.2) elseif r.missile then v = math.max(v, 1.5) end;
	if r.cav then v = math.max(v, 1.3) end;
	return v * (1.4 - 0.6 * r.hp);		-- damaged ones first: finish them
end;

local function focus_target()
	local sx, sz, n = 0, 0, 0;
	for _, o in ipairs(W.own) do if o.missile then sx, sz, n = sx + o.x, sz + o.z, n + 1 end end;
	if n == 0 then sx, sz = W.cx, W.cz else sx, sz = sx / n, sz / n end;
	local function score(r) return focus_value(r) - math.max(0, dist(sx, sz, r.x, r.z) - 180) / 60 end;
	local best, bs;
	for _, r in ipairs(W.enemy) do
		if r.visible ~= false and r.hp > 0.08 then
			local s = score(r);
			if not bs or s > bs then best, bs = r, s end;
		end;
	end;
	local f = E.focus;
	local cur = f and enemy_by_key(f.key);
	if cur and (cur.visible == false or cur.hp <= 0.08) then cur = nil end;
	-- keep the current target for 25 s, and after that unless something clearly better shows up
	if cur and best ~= cur and (E.now - f.t < 25 or bs < score(cur) + 0.8) then best = cur end;
	if best and (not f or f.key ~= best.key) then
		E.focus = { key = best.key, t = E.now };
		log("focus fire: shooters on Focus fire now all target " .. tostring(safe(function() return best.u:type() end, "?")));
	end;
	return best;
end;

-- hammer and anvil variants. arc: how far round from straight behind the unit may start its charge
-- (degrees); berth: extra room it gives the target's side on the way round (metres)
local HAMMER = {
	hammer       = { arc = 50,  berth = 0 },
	hammer_flank = { arc = 100, berth = 0 },
	hammer_wide  = { arc = 50,  berth = 45 },
};
local function hammering(o) local c = o.e and o.e.cur; return c and HAMMER[c.act] ~= nil end;

-- the way t's rear faces: away from the unit of ours fighting it (the nearest one; a centroid of
-- several is skewed sideways at the end of a line), steadied by the way our army faces
local function rear_dir(t, me)
	local o = nearest(W.own, t.x, t.z, function(o) return o ~= me and o.melee end);
	local fx, fz = front(W.cx, W.cz);
	if not o or dist(o.x, o.z, t.x, t.z) > 50 then return fx, fz end;
	local lx, lz = norm(t.x - o.x, t.z - o.z);
	local bx, bz = norm(lx * 0.6 + fx * 0.4, lz * 0.6 + fz * 0.4);
	if bx == 0 and bz == 0 then return fx, fz end;
	return bx, bz;
end;

-- where me is round t: angle from straight behind it (0) to straight in front (+-pi), and distance
local function hammer_geom(me, t, bx, bz)
	local dx, dz = me.x - t.x, me.z - t.z;
	return math.atan2(dx * -bz + dz * bx, dx * bx + dz * bz), math.sqrt(dx * dx + dz * dz);
end;

-- how wide to go round t on one side (side +1/-1): clear of t, and of the enemies standing beside it in its line
local function hammer_radius(e, t, bx, bz, side, V)
	local R = ((e.role == "cavalry" or e.role == "monster") and 45 or 35) + V.berth;
	local px, pz = -bz, bx;
	for _, o in ipairs(W.enemy) do
		if o ~= t then
			local dx, dz = o.x - t.x, o.z - t.z;
			local along, lat = dx * bx + dz * bz, (dx * px + dz * pz) * side;
			if lat > 0 and lat < 110 and math.abs(along) < 50 then R = math.max(R, lat + 40 + V.berth) end;
		end;
	end;
	return math.min(R, 170);
end;

-- length of the way round: straight to the tangent of the circle, then along it until the rear is in reach
local function hammer_route(D, a, R, arc)
	if a <= arc then return D end;
	local al = D > R and math.acos(R / D) or 0;
	if a - al <= arc then return D end;
	return math.sqrt(math.max(D * D - R * R, 0)) + R * (a - al - arc);
end;

-- the way round t on side (+1/-1): how far round it still has to go (radians), the circle's radius,
-- and the route's length
local function hammer_way(e, t, bx, bz, th, D, side, V)
	local a = side * th;
	if a < 0 then a = a + 2 * math.pi end;
	local R = hammer_radius(e, t, bx, bz, side, V);
	return a, R, hammer_route(D, a, R, math.rad(V.arc));
end;

-- the shorter side to go round t, and that route's length
local function hammer_side(e, t, bx, bz, th, D, V)
	local _, _, l1 = hammer_way(e, t, bx, bz, th, D, 1, V);
	local _, _, l2 = hammer_way(e, t, bx, bz, th, D, -1, V);
	if l1 <= l2 then return 1, l1, l2 end;
	return -1, l2, l1;
end;

-- the enemy held by our line that is quickest to get behind (a clear rear, not screened by its friends)
local function hammer_target(e, me, V)
	V = V or HAMMER.hammer;
	local arc = math.rad(V.arc);
	local best, bs;
	for _, r in ipairs(W.enemy) do
		if r.melee and r.visible ~= false and r.eng_t >= 3 then
			local bx, bz = rear_dir(r, me);
			local th, D = hammer_geom(me, r, bx, bz);
			local _, s = hammer_side(e, r, bx, bz, th, D, V);
			s = s + 80 * count_near(W.enemy, r.x + bx * 35, r.z + bz * 35, 35, function(o) return o ~= r end);
			if e.st and HAMMER[e.st.act] and e.st.tk == r.key then s = s - 80 end;
			if not bs or s < bs then best, bs = r, s end;
		end;
	end;
	return best;
end;

-- going round enemy troops in the way (missile hunt). Enemies other than the target and shooters count as
-- circles DETOUR_R wide; when the straight way to the target crosses one, the group of circles touching it
-- (a battle line) is gone round on the shorter side: head just past its edge as seen from here, re-planned
-- every tick, so the unit swings round the end of the line and comes at the target from there.
-- nil: the way is clear.
local DETOUR_R = 40;		-- metres: half a formation's width plus room for ours to pass
local DETOUR_LINK = 90;		-- circles whose centres are closer than this form one wall
local function detour(e, me, target, st)
	local tx, tz = target.x - me.x, target.z - me.z;
	local L = math.sqrt(tx * tx + tz * tz);
	if L < 30 then return nil end;
	local ux, uz = tx / L, tz / L;
	local obs, block = {}, {};
	for _, o in ipairs(W.enemy) do
		if o ~= target and not o.missile and o.visible ~= false and o.hp > 0.05 then
			local d = dist(me.x, me.z, o.x, o.z);
			-- a circle round the target can't be avoided; one we are already inside shrinks to where we are
			-- (going round it then keeps that distance instead of spiralling in)
			local rr = math.min(DETOUR_R, d * 0.98);
			if d >= 15 and dist(o.x, o.z, target.x, target.z) > DETOUR_R then
				local c = { o = o, d = d, r = rr };
				obs[#obs + 1] = c;
				local along = (o.x - me.x) * ux + (o.z - me.z) * uz;
				local lat = math.abs((o.x - me.x) * -uz + (o.z - me.z) * ux);
				if along > 0 and along < L and lat < rr then c.wall = true; block[#block + 1] = c end;
			end;
		end;
	end;
	if #block == 0 then st.dside = nil; return nil end;
	-- the whole wall: every circle linked to the ones in the way
	local k = 1;
	while k <= #block do
		local a = block[k];
		for _, c in ipairs(obs) do
			if not c.wall and dist(a.o.x, a.o.z, c.o.x, c.o.z) < DETOUR_LINK then c.wall = true; block[#block + 1] = c end;
		end;
		k = k + 1;
	end;
	-- its edges as seen from here, as angles off the straight way (+ is to the left of it)
	local base = math.atan2(ux, uz);
	local function wrap(a) while a > math.pi do a = a - 2 * math.pi end; while a < -math.pi do a = a + 2 * math.pi end; return a end;
	local edge = { [1] = { a = -1e9 }, [-1] = { a = -1e9 } };
	for _, c in ipairs(block) do
		local ca = wrap(math.atan2(c.o.x - me.x, c.o.z - me.z) - base);
		local half = math.asin(math.min(1, c.r / c.d));
		for side = -1, 1, 2 do
			local a = side * ca + half;
			if a > edge[side].a then edge[side] = { a = a, l = math.sqrt(math.max(c.d * c.d - c.r * c.r, 0)) } end;
		end;
	end;
	local cost, way = {}, {};
	for side = -1, 1, 2 do
		local g = edge[side];
		local ang = base + side * (g.a + 0.1);
		local l = g.l + 30;
		local wx, wz = me.x + math.sin(ang) * l, me.z + math.cos(ang) * l;
		way[side] = { x = wx, z = wz };
		cost[side] = g.l + dist(wx, wz, target.x, target.z) + (g.a > math.rad(160) and 1e4 or 0);
	end;
	local best = cost[1] <= cost[-1] and 1 or -1;
	if not st.dside then
		st.dside = best;
		log(string.format("%s: going round %d enemy units to reach %s (%s side, about %.0f m)", e.name, #block,
			tostring(safe(function() return target.u:type() end, "?")), best == 1 and "left" or "right", cost[best]));
	elseif st.dside ~= best and cost[best] < cost[st.dside] * 0.7 then
		st.dside = best;
	end;
	local w = way[st.dside];
	return { k = "goto", x = w.x, z = w.z };
end;

local function height(x, z) return safe(function() return bm:get_terrain_height(x, z) end, 0) or 0 end;

-- the highest point within 120 m that isn't toward the enemy (a little nearer wins a tie)
local function pick_high(me)
	local fx, fz = front(me.x, me.z);
	local h0 = height(me.x, me.z);
	local bx, bz, bh = me.x, me.z, h0;
	for _, r in ipairs({ 30, 60, 90, 120 }) do
		for k = 0, 11 do
			local a = k * math.pi / 6;
			local x, z = me.x + math.cos(a) * r, me.z + math.sin(a) * r;
			if (x - me.x) * fx + (z - me.z) * fz < 30 then
				local h = height(x, z) - r * 0.02;
				if h > bh + 0.5 then bx, bz, bh = x, z, h end;
			end;
		end;
	end;
	return bx, bz, height(bx, bz) - h0;
end;

local PICK = {
	hammer = function(e, me) return hammer_target(e, me, HAMMER.hammer) or me end,		-- me: waiting for the anvil
	hammer_flank = function(e, me) return hammer_target(e, me, HAMMER.hammer_flank) or me end,
	hammer_wide = function(e, me) return hammer_target(e, me, HAMMER.hammer_wide) or me end,
	cycle_charge = function(e, me, t)
		if me.hp < 0.3 then return nil end;
		-- pulling out and reforming: stay on the same enemy, whatever is nearest by then
		local st = e.st;
		if st and st.act == "cycle_charge" and (st.cy == "out" or st.cy == "reform") and st.tk then
			local old = enemy_by_key(st.tk);
			if old then return old end;
		end;
		return t;
	end,
	focus = function(e, me)
		local t = focus_target();
		if not t then return nil end;
		-- the army's target is far beyond this unit's reach: something in range instead
		if has_ammo(e, me) and dist(me.x, me.z, t.x, t.z) > 260 then
			local n, d = nearest(W.enemy, me.x, me.z, function(r) return r.visible ~= false end);
			if n and d < 200 then return n end;
		end;
		return t;
	end,
	disrupt = function(e, me)
		if me.hp < 0.25 then return nil end;
		local best, bs;
		for _, r in ipairs(W.enemy) do
			if r.missile and r.visible ~= false and r.hp > 0.12 then
				-- each hunter takes a different one
				local taken = 0;
				for _, o in ipairs(W.own) do
					local c = o.e.cur;
					if o ~= me and c and c.act == "disrupt" and c.target and c.target.u == r.u then taken = taken + 1 end;
				end;
				local s = dist(me.x, me.z, r.x, r.z) + taken * 150;
				local c = e.cur;
				if c and c.act == "disrupt" and c.target and c.target.u == r.u then s = s - 60 end;
				if not bs or s < bs then best, bs = r, s end;
			end;
		end;
		return best;
	end,
	kill_lord = function(e, me)
		if me.hp < 0.3 or (me.general and me.hp < 0.6) then return nil end;
		local g;
		for _, r in ipairs(W.enemy) do if r.general and r.visible ~= false then g = r end end;
		if not g then return nil end;
		if dist(me.x, me.z, g.x, g.z) > ((e.fast or has_ammo(e, me)) and 450 or 220) then return nil end;
		-- guards: enemy melee troops near him that are free to protect him
		local guards = count_near(W.enemy, g.x, g.z, 50, function(o) return o ~= g and not o.missile and not o.melee end);
		if busy_with({ e = e }, "kill_lord") then return guards < 3 and g or nil end;
		if guards <= 1 or g.melee or g.hp < 0.5 then return g end;
		return nil;
	end,
	duelist = function(e, me, t)
		if not t or t.visible == false then return nil end;
		if me.hp < 0.4 or (me.general and me.hp < 0.6) then return nil end;
		local c = e.cur;
		if c and c.act == "duelist" and c.target and c.target.u == t.u and me.melee then return t end;
		-- commit only when it's safe: help is near it, it is already fighting, or it is alone
		if near(W.own, t, 40, nil, me) or t.melee or not near(W.enemy, t, 60, nil, t) then return t end;
		return nil;
	end,
	caster = function(e, me)
		if e.scan_done and e.n_abilities == 0 then return hammer_target(e, me) or me end;
		return me;
	end,
};

local function plan(e, me, act, target)
	if HAMMER[act] then
		local V = HAMMER[act];
		local st = play_state(e, act);
		if target == me then
			-- no anvil yet: wait on the army's flank, a little behind the line
			st.wait = st.wait or E.now;
			st.tk = nil;
			local en, d = nearest(W.enemy, me.x, me.z);
			if en and (d < 50 or E.now - st.wait > 60) then return attack_order(e, me, en, not has_ammo(e, me)) end;
			local fx, fz = front(W.cx, W.cz);
			local px, pz = -fz, fx;
			local side = ((me.x - W.cx) * px + (me.z - W.cz) * pz) >= 0 and 1 or -1;
			local wide = 40;
			for _, o in ipairs(W.own) do
				if o ~= me and not hammering(o) then
					wide = math.max(wide, math.abs((o.x - W.cx) * px + (o.z - W.cz) * pz));
				end;
			end;
			wide = math.min(wide, 200) + 40;
			local x, z = W.cx + px * side * wide - fx * 20, W.cz + pz * side * wide - fz * 20;
			if dist(me.x, me.z, x, z) < 20 then return { k = "halt" } end;
			return { k = "goto", x = x, z = z };
		end;
		st.wait = nil;
		if st.tk ~= target.key then
			st.tk, st.phase, st.t, st.cy, st.side, st.bx, st.bz, st.hit, st.limit = target.key, "swing", E.now, nil, nil, nil, nil, nil, nil;
		end;
		-- its rear, eased so the route doesn't flip when our units fighting it shuffle
		local bx, bz = rear_dir(target, me);
		if st.bx then
			local nx, nz = norm(st.bx * 0.8 + bx * 0.2, st.bz * 0.8 + bz * 0.2);
			if nx ~= 0 or nz ~= 0 then bx, bz = nx, nz end;
		end;
		st.bx, st.bz = bx, bz;
		if not st.hit then
			local th, D = hammer_geom(me, target, bx, bz);
			local arc = math.rad(V.arc);
			-- the side to go round: the shorter way (round the open end of their line, not past all of it);
			-- once picked it sticks unless the other way becomes clearly shorter
			local best, lb, lo = hammer_side(e, target, bx, bz, th, D, V);
			if not st.side then
				st.side = best;
				-- give up going round after the time the route should take, with room to spare
				local speed = (e.role == "cavalry" or e.role == "monster") and 7 or 3.5;
				st.limit = math.max(45, lb / speed * 1.6 + 10);
			elseif st.side ~= best and lb < lo * 0.7 then
				st.side = best;
			end;
			local side = st.side;
			local a, R = hammer_way(e, target, bx, bz, th, D, side, V);		-- how far it still has to go round on that side
			if me.melee or a <= arc or E.now - st.t > (st.limit or 45) then
				st.hit, st.phase = true, V.arc > 80 and "flank_hit" or "hit";
				log(string.format("%s: %s - charging %s from %.0f deg off its rear", e.name, act, tostring(safe(function() return target.u:type() end, "?")), math.deg(a)));
			else
				-- the shortest way round: straight for the tangent point of a circle clear of it, then along the circle
				local w = math.max(a - (D > R + 5 and math.acos(R / D) or 0.6), 0);
				if w <= arc then w = arc * 0.5 end;
				local ang, px, pz = side * w, -bz, bx;
				st.phase = a > math.rad(100) and "swing" or "rear";
				return { k = "goto", x = target.x + R * (bx * math.cos(ang) + px * math.sin(ang)),
					z = target.z + R * (bz * math.cos(ang) + pz * math.sin(ang)) };
			end;
		end;
		if has_ammo(e, me) then return attack_order(e, me, target, false) end;		-- shoot it in the back
		if e.role == "cavalry" or e.role == "monster" then
			return cycle(e, me, target, st, target.x + bx * 80, target.z + bz * 80);
		end;
		return attack_order(e, me, target, true);
	elseif act == "cycle_charge" then
		local st = play_state(e, "cycle_charge");
		if st.tk ~= target.key then st.tk, st.cy = target.key, nil end;
		-- pull out away from it, bending back toward our lines
		local ax, az = norm(me.x - target.x, me.z - target.z);
		local cx, cz = norm(W.cx - target.x, W.cz - target.z);
		local dx, dz = norm(ax + cx, az + cz);
		if dx == 0 and dz == 0 then dx, dz = ax, az end;
		return cycle(e, me, target, st, target.x + dx * 75, target.z + dz * 75);
	elseif act == "skirmish" or act == "focus" then
		local st = play_state(e, act);
		if not shooter(e) then return attack_order(e, me, target, act == "focus") end;
		local k = kite(e, me, st);
		if k then return k end;
		if me.ammo <= 0 then return join_fight(e, me, nil) end;
		return attack_order(e, me, target, false);
	elseif act == "fire_support" then
		local st = play_state(e, act);
		if not shooter(e) then return attack_order(e, me, target, false) end;
		if me.ammo <= 0 then return join_fight(e, me, target) end;
		-- the melee regiment we shelter behind
		local ally = nearest(W.own, me.x, me.z, function(o) return o ~= me and not o.missile and not o.general end);
		if not ally then
			local k = kite(e, me, st);
			return k or attack_order(e, me, target, false);
		end;
		local en = nearest(W.enemy, ally.x, ally.z);
		local fx, fz = norm(en.x - ally.x, en.z - ally.z);
		if fx == 0 and fz == 0 then fx, fz = front(ally.x, ally.z) end;
		-- enemy melee troops got past the line: back behind it
		local th, d = nearest(W.enemy, me.x, me.z, function(o) return not o.missile and o.visible ~= false end);
		if th and d < 45 and not (th.melee and d > 25) then
			local bx, bz = norm(ally.x - th.x, ally.z - th.z);
			return { k = "goto", x = ally.x + bx * 30, z = ally.z + bz * 30 };
		end;
		-- stay 20-40 m behind it; don't walk past it to get the target in range
		local ahead = (me.x - ally.x) * fx + (me.z - ally.z) * fz;
		if ahead > -5 or (st.back and ahead > -20) or dist(me.x, me.z, target.x, target.z) > 165 then
			st.back = ahead > -20;
			local x, z = ally.x - fx * 30, ally.z - fz * 30;
			if dist(me.x, me.z, x, z) < 12 then return { k = "halt" } end;
			return { k = "goto", x = x, z = z };
		end;
		st.back = nil;
		return attack_order(e, me, target, false);
	elseif act == "disrupt" or act == "kill_lord" or act == "duelist" then
		local st = play_state(e, act);
		if act == "kill_lord" then
			local k = kite(e, me, st);
			if k then return k end;
		end;
		if act == "disrupt" then
			if st.tk ~= target.key then st.tk, st.dside = target.key, nil end;
			-- go round enemy troops in the way (shooters only while still out of range)
			local d = dist(me.x, me.z, target.x, target.z);
			local o = (not me.melee and target.visible ~= false and (not has_ammo(e, me) or d > 170)) and detour(e, me, target, st) or nil;
			st.phase = o and "round" or nil;
			if o then return o end;
		end;
		return attack_order(e, me, target, not has_ammo(e, me));
	elseif act == "high_ground" then
		local st = play_state(e, act);
		if not st.hx then
			local gain;
			st.hx, st.hz, gain = pick_high(me);
			log(string.format("%s: taking the high ground %.0f m away, %.1f m higher", e.name, dist(me.x, me.z, st.hx, st.hz), gain));
		end;
		local en, d = nearest(W.enemy, st.hx, st.hz);
		if en and en.visible ~= false and d < (has_ammo(e, me) and 160 or 45) then
			return attack_order(e, me, en, not has_ammo(e, me));
		end;
		if dist(me.x, me.z, st.hx, st.hz) > 12 then return { k = "goto", x = st.hx, z = st.hz } end;
		return { k = "halt" };
	elseif act == "caster" then
		if e.scan_done and e.n_abilities == 0 then return plan(e, me, "hammer", target) end;
		play_state(e, act);
		local en, d = nearest(W.enemy, me.x, me.z);
		if not en then return { k = "halt" } end;
		if d < 45 and en.visible ~= false then
			-- too close: get behind our nearest regiment, else just away
			local fr = nearest(W.own, me.x, me.z, function(o) return o ~= me and not o.missile and not o.large end);
			if fr and dist(fr.x, fr.z, en.x, en.z) > 15 then
				local bx, bz = norm(fr.x - en.x, fr.z - en.z);
				return { k = "goto", x = fr.x + bx * 35, z = fr.z + bz * 35 };
			end;
			local x, z = away(me, en, 70);
			return { k = "goto", x = x, z = z };
		end;
		-- 50 m behind the regiment facing the enemy nearest to us
		local line = nearest(W.own, en.x, en.z, function(o) return o ~= me and not o.missile and not busy_with(o, "caster") end);
		if not line then
			if d < 110 then local x, z = away(me, en, 60); return { k = "goto", x = x, z = z } end;
			return { k = "halt" };
		end;
		local bx, bz = norm(line.x - en.x, line.z - en.z);
		if bx == 0 and bz == 0 then bx, bz = front(line.x, line.z); bx, bz = -bx, -bz end;
		local x, z = line.x + bx * 50, line.z + bz * 50;
		if dist(me.x, me.z, x, z) < 20 then return { k = "halt" } end;
		return { k = "goto", x = x, z = z };
	end;
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

local FALLBACK = { "always", "nearest_enemy", "attack" };

-- first movement tactic whose condition holds and whose target exists (and whose play doesn't decline)
local function choose(e, me)
	for i, t in ipairs(e.tactics) do
		local act = t[3];
		if not T.is_cast(act) and T.validate(t) then
			local c = COND[t[1]];
			local ok, t1, t2;
			if c then ok, t1, t2 = c(me) end;
			if ok then
				local tf = TARGET[t[2]];
				local target = tf and tf(me, t1, t2);
				if target then target = sticky(e, me, i, target) end;
				local pick = PICK[act];
				if target and pick then target = pick(e, me, target) end;
				if target then return i, act, target end;
			end;
		end;
	end;
	-- nothing applies: attack the nearest enemy (FALLBACK). Nothing from the role defaults is ever
	-- used here, so a unit only does what its own slots say or this.
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
	-- a play picks its own targets (with its own stickiness): follow it right away
	local higher = not c or idx < c.idx or (idx == c.idx and PLAYS[act]);
	if not higher and not target_lost and c and E.now < c.until_t then return end;
	if execute(e, me, order) then
		if CFG.log_decisions then
			local t = idx < 100 and e.tactics[idx] or FALLBACK;
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

-- rows a Battle mage casts without being told
local CASTER_ROWS = {
	{ "always", "enemy_engaged", "cast_attack" }, { "always", "nearest_enemy", "cast_attack" },
	{ "ally_hurt_near", "ally_weakest", "cast_buff" }, { "always", "ally_engaged", "cast_buff" },
};

-- what this character can cast, for the campaign editor's spell list (by campaign unit cqi)
local function save_spells(e)
	if not e.cqi or e.n_abilities == 0 or e.saved_n == e.n_abilities then return end;
	e.saved_n = e.n_abilities;
	local keep = {};
	local ok, f = pcall(io.open, T.SPELLS_PATH, "r");
	if ok and f then
		for line in f:lines() do
			if line ~= "" and line:match("^spells (%S+)") ~= tostring(e.cqi) then keep[#keep + 1] = line end;
		end;
		f:close();
	end;
	local keys = {};
	for k in pairs(e.abilities) do keys[#keys + 1] = k end;
	table.sort(keys);
	keep[#keep + 1] = "spells " .. tostring(e.cqi) .. " " .. table.concat(keys, " ");
	local ok2, w = pcall(io.open, T.SPELLS_PATH, "w");
	if ok2 and w then
		w:write(table.concat(keep, "\n") .. "\n");
		w:close();
		log(string.format("%s: saved %d spells for the campaign editor", e.name, #keys));
	end;
end;

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
					e.scan_done = true;
					if e.n_abilities > 0 and not e.scan_logged then
						log(string.format("%s can cast %d abilities", e.name, e.n_abilities));
						e.scan_logged = true;
					end;
					pcall(save_spells, e);
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

local function cast_ok(cat, target)
	if (cat == "X" or cat == "B") and friendlies_near(target.x, target.z, CFG.friendly_clear) then return false end;
	if cat == "R" and target.hp > 0.85 then return false end;
	return true;
end;

local function try_cast(e, me, t, t1, t2)
	local tf = TARGET[t[2]];
	local target = tf and tf(me, t1, t2);
	if not target then return false end;
	local d = dist(me.x, me.z, target.x, target.z);
	local keys = {};
	if T.is_spell_id(t[3]) then
		-- one particular spell
		local ak = t[3]:sub(4);
		local cat = e.abilities[ak] or T.spell_cat(ak);
		if cat and d <= (CFG.ranges[cat] or 150) and (e.blocked[ak] or 0) <= E.now and cast_ok(cat, target) then keys[1] = ak end;
	else
		local cats = t[3] == "cast_attack" and ATTACK_CATS or BUFF_CATS;
		for ak, cat in pairs(e.abilities) do
			if cats[cat] and d <= (CFG.ranges[cat] or 150) and (e.blocked[ak] or 0) <= E.now and cast_ok(cat, target) then
				keys[#keys + 1] = ak;
			end;
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
			for _, row in ipairs(e.cast_rows) do
				local t = row.t;
				local c = COND[t[1]];
				local ok, t1, t2;
				if c then ok, t1, t2 = c(me) end;
				if ok and try_cast(e, me, t, t1, t2) then
					e.cast_row, e.cast_at = row.ri, E.now;
					e.next_cast = E.now + CFG.caster_cooldown + rnd(0, 2);
					break;
				end;
			end;
		end;
		if (e.casts or e.cast_any) and E.now - (e.scanned or 0) > CFG.ability_rescan then queue_scan(e) end;
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
						if s then s.cd_key = k; E.enemy[#E.enemy + 1] = s; E.enemy_keys[k] = true end;
					end;
				end;
			end;
		end;
	end;
end;

-- spell rows of the unit's current tactics (a Battle mage row brings its implicit casting rows)
local function build_casts(e)
	e.cast_rows = {};
	local caster_row;
	for ri, t in ipairs(e.tactics) do
		if T.is_cast(t[3]) and T.validate(t) then e.cast_rows[#e.cast_rows + 1] = { t = t, ri = ri } end;
		if t[3] == "caster" and not caster_row then caster_row = ri end;
	end;
	if caster_row then
		for _, t in ipairs(CASTER_ROWS) do e.cast_rows[#e.cast_rows + 1] = { t = t, ri = caster_row } end;
	end;
	e.casts = #e.cast_rows > 0;
end;

local function casts_any(sets)
	for _, set in ipairs(sets) do
		for _, t in ipairs(set) do if T.is_cast(t[3]) or t[3] == "caster" then return true end end;
	end;
	return false;
end;

local function setup()
	local forces = read_export();
	E.paradigm, E.para_custom, E.para_seen, E.para_t = 1, false, 1, nil;
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
					tactics = T.default_tactics(role, T.slots_for_rank(data.rank, role));
				elseif data then
					matched = matched + 1;
					-- fit() pads with defaults when the rank went up since the tactics were set
					tactics = T.fit(data.tactics, T.slots_for_rank(data.rank, role), role);
				else
					custom = custom + 1;
					tactics = T.default_tactics(role, CFG.no_data_slots);
				end;
				-- paradigms 2-4: the unit's own set where one was saved, else paradigm 1's
				local sets = { tactics };
				for k = 2, T.MAX_PARADIGMS do
					local d = data and data.sets[k];
					if d and #d > 0 then
						sets[k] = T.fit(d, T.slots_for_rank(data.rank, role), role);
						E.para_custom = true;
					else
						sets[k] = tactics;
					end;
				end;
				local name = keys[i] .. "#" .. i;
				local s = make_sunit(u, "cd_tac_own_" .. r .. "_" .. i);
				if s then
					local cls = class_of(u);
					local e = {
						sunit = s, name = name, role = role, tactics = tactics, sets = sets, unit = u, key = keys[i], uid = uid(u),
						general = is_general(u), lord_rank = is_general(u) and (force and force.lord_rank or 1) or nil,
						rank = data and data.rank, from_campaign = data ~= nil, cqi = data and data.cqi,
						next_eval = rnd(0, CFG.eval_every), abilities = {}, n_abilities = 0, blocked = {}, next_cast = rnd(2, 5),
						ammo0 = safe(function() return u:starting_ammo() end, 0) or 0,
						art = cls:find("^art") ~= nil, chariot = cls:find("chariot") ~= nil,
						fast = role == "cavalry" or role == "missile_cav" or safe(function() return u:can_fly() end, false),
					};
					-- no script_ai_planner: creating one hands the unit to the battle AI's planner, which
					-- keeps it under AI control - greyed out and unselectable - for the whole battle
					build_casts(e);
					-- casting in any paradigm needs the ability scan; lords and heroes are always
					-- scanned, so the campaign editor learns their spells
					e.cast_any = casts_any(sets);
					if e.cast_any or role == "hero" then queue_scan(e) end;
					E.units[#E.units + 1] = e;
					log(string.format("%s (%s, %d slots%s): %s", name, role, #tactics, data and "" or ", no campaign data",
						T.serialise(tactics)));
				end;
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
	end;
	snapshot();
	if #W.enemy == 0 then return end;
	for _, me in ipairs(W.own) do
		local e = me.e;
		if E.now >= e.next_eval then
			e.next_eval = E.now + ((e.cur and PLAYS[e.cur.act]) and CFG.play_eval or CFG.eval_every);
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
	E.running = true;
	E.now, E.start_t = 0, 0;
	E.release, E.rel_ok, E.rel_fail = CFG.release_after_order, 0, 0;
	-- the units were set up during deployment (and may have been edited since)
	local ok, err = true, nil;
	if not E.prepared then ok, err = pcall(setup) end;
	E.prepared = false;
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

-- deployment: the units and their tactics are set up as soon as the battle loads, so the player can change
-- them in the battle tactics panel before the fight. Nothing is ordered and nothing locked until it starts.
local function prepare()
	if E.prepared or E.prep_failed or E.running or not CFG.enabled then return end;
	local ok, err = pcall(setup);
	if not ok then
		E.prep_failed = true;
		log("deployment setup failed (tactics are set up when the battle starts): " .. tostring(err));
		return;
	end;
	if #E.units == 0 then return end;
	E.prepared = true;
	log(string.format("deployment: %d units ready, their tactics can be changed in the battle panel", #E.units));
end;

-- deployment edits from the battle panel: paradigm k's rows for one unit. Paradigms II-IV that were never
-- set follow paradigm I. Only before the battle starts; the battle starts in paradigm I.
local function set_rows(e, k, rows)
	k = tonumber(k) or 1;
	if not e or not e.sets or E.running or not E.prepared or k < 1 or k > T.MAX_PARADIGMS then return false end;
	local list = {};
	for i, t in ipairs(rows) do list[i] = { t[1], t[2], t[3] } end;
	if k == 1 then
		local old = e.sets[1];
		for j = 2, T.MAX_PARADIGMS do if e.sets[j] == old then e.sets[j] = list end end;
	else
		E.para_custom = true;
	end;
	e.sets[k] = list;
	e.tactics = e.sets[E.paradigm or 1];
	build_casts(e);
	local any = casts_any(e.sets);
	if any and not e.cast_any and e.role ~= "hero" then queue_scan(e) end;
	e.cast_any = any;
	e.edited = true;
	log(string.format("deployment edit: %s paradigm %s: %s", e.name, T.PARADIGM_NAMES[k], T.serialise(list)));
	return true;
end;

-- wait for deployment to end
local function watch()
	if E.running then
		pcall(function() bm:remove_real_callback("cd_tactics_watch") end);
		return;
	end;
	-- scripted orders would desync a multiplayer battle (and could take over another player's army)
	if safe(function() return bm:is_multiplayer() end, true) then
		pcall(function() bm:remove_real_callback("cd_tactics_watch") end);
		log("multiplayer battle: unit tactics off, everyone keeps control of their own army");
		return;
	end;
	if safe(function() return bm:is_conflict_phase() end, false) then
		pcall(function() bm:remove_real_callback("cd_tactics_watch") end);
		start();
	else
		prepare();
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

--------------------------------------------------------------------------------
-- paradigms: whole-army tactics sets
--------------------------------------------------------------------------------

-- the highest character rank among the player's generals still fighting (nil: none left)
local function lord_rank_up()
	local best;
	for _, e in ipairs(E.units) do
		if e.general and alive(e.unit) then best = math.max(best or 0, e.lord_rank or 1) end;
	end;
	return best;
end;

-- { cur, n = paradigms the generals unlock (0: all down), enabled, rank, seen = most ever available }
local function paradigms()
	local r = lord_rank_up();
	local n = r and T.paradigms_for_rank(r) or 0;
	E.para_seen = math.max(E.para_seen or 1, n);
	-- cooldown: seconds until the next shift is allowed (0 = ready)
	local cd = E.para_t and math.max(0, CFG.paradigm_cooldown - (E.now - E.para_t)) or 0;
	return { cur = E.paradigm or 1, n = n, enabled = n > 1, rank = r, seen = E.para_seen, custom = E.para_custom, cooldown = cd };
end;

-- switch the whole army to paradigm k; false and a reason when it can't
local function set_paradigm(k)
	k = tonumber(k);
	if not E.running or not k or k < 1 or k > T.MAX_PARADIGMS then return false, "no battle" end;
	local p = paradigms();
	if p.n == 0 then return false, "every general is down" end;
	if k > p.n then return false, "locked" end;
	if k == E.paradigm then return true end;
	if p.cooldown > 0 then return false, string.format("cooling down (%.0f s)", p.cooldown) end;
	E.paradigm, E.para_t = k, E.now;
	local changed = 0;
	for _, e in ipairs(E.units) do
		local new = e.sets and e.sets[k] or e.tactics;
		-- a unit whose rows are the same in both paradigms carries on undisturbed (a cycle charge
		-- keeps its timing); the others decide afresh. A play's own state resets when the play changes.
		if T.serialise(new) ~= T.serialise(e.tactics) then
			e.tactics = new;
			build_casts(e);
			e.cur, e.cast_row = nil, nil;
			e.next_eval = E.now + rnd(0, 0.4);
			changed = changed + 1;
		else
			e.tactics = new;
		end;
	end;
	log(string.format("paradigm %s (general's rank %s): %d units change tactics", T.PARADIGM_NAMES[k], tostring(p.rank), changed));
	if CD_HUD and CD_HUD.report then pcall(CD_HUD.report, "Paradigm " .. T.PARADIGM_NAMES[k], "good", "tactic") end;
	return true;
end;

-- what a unit is doing right now: { idx = row (or nil), default = role-default row (when no row applied),
--   act, target_key, hidden, since, cast_row, cast_ago, cast_key, alive }
local function state(e)
	if not e then return nil end;
	local st = { alive = alive(e.unit), now = E.now };
	local c = e.cur;
	if c then
		if c.idx < 100 then st.idx = c.idx else st.default = FALLBACK end;
		st.act, st.target_key, st.hidden, st.self_target, st.since = c.act, c.tkey, c.hidden, c.self_target, c.since;
		-- a play's current step: "wait", "swing", "rear", "hit", "charge", "contact", "out", "reform", "kite"
		local ps = e.st;
		if ps and ps.act == c.act then
			if ps.kite_until and E.now < ps.kite_until then st.phase = "kite"
			elseif ps.wait then st.phase = "wait"
			else st.phase = ps.cy or ps.phase end;
		end;
		st.target_unit = c.target and c.target.u;
	end;
	if e.cast_at then st.cast_row, st.cast_ago, st.cast_key, st.cast_tkey = e.cast_row, E.now - e.cast_at, e.cast_key, e.cast_tkey end;
	return st;
end;

CD_TACTICS_ENGINE = {
	start = start, stop = stop,
	running = function() return E.running end,
	-- deployment: units set up, tactics editable (set_rows), battle not started
	deploying = function() return E.prepared and not E.running end,
	set_rows = set_rows,
	units = function() return E.units end,
	find = find,
	state = state,
	enemies_left = function() return #W.enemy end,
	paradigms = paradigms,
	paradigm = set_paradigm,
	-- for the harness: the world snapshot, and a WHEN condition / target evaluated for one of our units
	world = function() return W end,
	cond = function(id, me) return COND[id](me) end,
	target = function(id, me, t1, t2) return TARGET[id](me, t1, t2) end,
};

if CFG.enabled then
	bm:repeat_real_callback(watch, 500, "cd_tactics_watch");
	core:add_listener("cd_tactics_end", "BattleConflictFinished", true, function() stop() end, true);
	log("---- tactics engine loaded, waiting for the battle to start ----");
end;
