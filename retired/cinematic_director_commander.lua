--------------------------------------------------------------------------------
-- Cinematic Director: AI commander
-- While the director runs, the player's army is handed to the game's own battle
-- AI (script_ai_planner, the system behind the enemy army) and lords, heroes and
-- monsters cast their abilities automatically.
-- Settings are driven from the panel (cinematic_director_panel.lua) via CD_SETTINGS.
--------------------------------------------------------------------------------

local LOG_PATH = "cinematic_director_log.txt";
local function log(s)
	local ok, f = pcall(io.open, LOG_PATH, "a");
	if ok and f then
		local t = "";
		pcall(function() t = os.date("%H:%M:%S ") end);
		f:write(t .. "[ai] " .. tostring(s) .. "\n");
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

-- default settings; the panel overwrites these
CD_SETTINGS = CD_SETTINGS or {};
local DEFAULTS = {
	ai_control = "on",			-- on / off
	army = "balanced",			-- aggressive / balanced / defensive / hold
	missiles = "support",		-- support / skirmish / hold
	cavalry = "flank",			-- flank / with_army / reserve
	heroes = "fight",			-- fight / stay_back
	spells = "all",				-- all / attack / support / off
};
for k, v in pairs(DEFAULTS) do if CD_SETTINGS[k] == nil then CD_SETTINGS[k] = v end end;

local CFG = {
	reorder_every = 10,			-- seconds between re-issuing planner orders (targets die and move)
	cast_every = 1.0,			-- seconds between spell decisions
	caster_cooldown = 7,		-- seconds between casts by one unit
	ability_rescan = 30,		-- seconds between re-checking which abilities a unit has
	scan_per_tick = 250,		-- ability checks per tick (spreads the scan out)
	ranges = { X = 200, D = 180, H = 180, B = 40, A = 120, R = 120, S = 80 },
	friendly_clear = 30,		-- area damage is only aimed where no friendly unit is this close to the target
	defend_radius = 120,
	hold_radius = 60,
	stay_back_radius = 50,
};

local cm = {
	running = false,
	groups = {},			-- role -> script_ai_planner
	sunits = {},			-- key -> {sunit, role}
	enemy = {},				-- list of enemy script_units
	casters = {},			-- key -> {sunit, abilities = {key -> cat}, next_cast, scanned}
	scan_queue = {},
	next_reorder = 0,
	next_cast = 0,
	now = 0,
	hold_pos = nil,
	waiting_logged = false,
};

--------------------------------------------------------------------------------
-- units
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

local function unit_key(u) return tostring(safe(function() return u:unique_ui_id() end, tostring(u))) end;

local function role_of(u)
	local class = safe(function() return u:unit_class() end, "") or "";
	local men = safe(function() return u:initial_number_of_men() end, 100);
	local general = safe(function() return u:is_commanding_unit() end, false);
	local ammo = safe(function() return u:starting_ammo() end, 0) or 0;
	local cav = safe(function() return u:is_cavalry() end, false);
	local fly = safe(function() return u:can_fly() end, false);
	if general or (men <= 1 and not class:find("^art")) then return "hero" end;
	if class:find("^art") then return "missile" end;
	if ammo > 0 and not cav and men > 8 then return "missile" end;
	if cav or fly or class:find("^cav") or class:find("chariot") then return "cavalry" end;
	return "main";
end;

local function make_sunit(u, ref)
	return safe(function() return script_unit:new(u, ref) end, nil);
end;

local function collect()
	local pa_num = safe(function() return bm:get_player_alliance_num() end, 1);
	local alliances = bm:alliances();
	local own, enemy = {}, {};
	for a = 1, alliances:count() do
		local armies = alliances:item(a):armies();
		for r = 1, armies:count() do
			local army = armies:item(r);
			local player_army = (a == pa_num) and safe(function() return army:is_player_controlled() end, r == 1);
			local units = army:units();
			for i = 1, units:count() do
				local u = units:item(i);
				if alive(u) then
					if a == pa_num then
						if player_army then own[#own + 1] = u end;
					else
						enemy[#enemy + 1] = u;
					end;
				end;
			end;
		end;
	end;
	return own, enemy;
end;

--------------------------------------------------------------------------------
-- orders
--------------------------------------------------------------------------------

local function sunit_list_alive(list)
	local out = {};
	for _, s in ipairs(list) do if alive(s.unit) then out[#out + 1] = s end end;
	return out;
end;

local function centre(list)
	local sx, sz, n = 0, 0, 0;
	for _, s in ipairs(list) do
		if alive(s.unit) then
			local x, z = upos(s.unit);
			sx, sz, n = sx + x, sz + z, n + 1;
		end;
	end;
	if n == 0 then return nil end;
	return sx / n, sz / n;
end;

local function group_sunits(role)
	local out = {};
	for _, e in pairs(cm.sunits) do
		if e.role == role and alive(e.sunit.unit) then out[#out + 1] = e.sunit end;
	end;
	return out;
end;

-- enemies the cavalry should go for first: missiles, artillery, then anything not in melee
local function flank_targets(enemies)
	local soft, free = {}, {};
	for _, s in ipairs(enemies) do
		local u = s.unit;
		local class = safe(function() return u:unit_class() end, "") or "";
		local ammo = safe(function() return u:ammo_left() end, 0) or 0;
		if class:find("^art") or (ammo > 0 and not safe(function() return u:is_cavalry() end, false)) then
			soft[#soft + 1] = s;
		elseif not safe(function() return u:is_in_melee() end, false) then
			free[#free + 1] = s;
		end;
	end;
	if #soft > 0 then return soft end;
	if #free > 0 then return free end;
	return enemies;
end;

local function anchor_sunit()
	-- the unit others guard: the lord if alive, else the biggest main-line unit
	local best, best_men;
	for _, e in pairs(cm.sunits) do
		if alive(e.sunit.unit) then
			if safe(function() return e.sunit.unit:is_commanding_unit() end, false) and e.role ~= "hero" then return e.sunit end;
			if e.role == "main" then
				local m = safe(function() return e.sunit.unit:number_of_men_alive() end, 0);
				if not best_men or m > best_men then best, best_men = e.sunit, m end;
			end;
		end;
	end;
	return best;
end;

local function order(role, planner, enemies)
	local S = CD_SETTINGS;
	local ok, err = pcall(function()
		if role == "main" then
			if S.army == "aggressive" then
				planner:rush_force(enemies);
			elseif S.army == "balanced" then
				planner:attack_force(enemies);
			elseif S.army == "defensive" then
				local x, z = centre(group_sunits("main"));
				if x then planner:defend_position(gv(x, z), CFG.defend_radius) end;
			else
				if cm.hold_pos then planner:defend_position(cm.hold_pos, CFG.hold_radius) end;
			end;
		elseif role == "missile" then
			local a = anchor_sunit();
			if S.missiles == "skirmish" then
				planner:attack_force(enemies);
			elseif S.missiles == "hold" or not a then
				local x, z = centre(group_sunits("missile"));
				if x then planner:defend_position(gv(x, z), CFG.hold_radius) end;
			else
				planner:defend_force(a, 60);
			end;
		elseif role == "cavalry" then
			local a = anchor_sunit();
			if S.cavalry == "flank" then
				planner:attack_force(flank_targets(enemies));
			elseif S.cavalry == "reserve" and a then
				planner:defend_force(a, 80);
			else
				if S.army == "aggressive" then planner:rush_force(enemies) else planner:attack_force(enemies) end;
			end;
		elseif role == "hero" then
			local a = anchor_sunit();
			if S.heroes == "stay_back" and a then
				planner:defend_force(a, CFG.stay_back_radius);
			elseif S.army == "hold" and cm.hold_pos then
				planner:defend_position(cm.hold_pos, CFG.hold_radius);
			else
				planner:attack_force(enemies);
			end;
		end;
	end);
	if not ok then log("order " .. role .. " failed: " .. tostring(err)) end;
end;

local function refresh_enemies()
	local _, enemy = collect();
	for _, u in ipairs(enemy) do
		local k = unit_key(u);
		if not cm.enemy_keys[k] then
			local s = make_sunit(u, "cd_enemy_r" .. k);
			if s then cm.enemy[#cm.enemy + 1] = s; cm.enemy_keys[k] = true end;
		end;
	end;
end;

local function reorder()
	pcall(refresh_enemies);
	local enemies = sunit_list_alive(cm.enemy);
	if #enemies == 0 then return end;
	for role, planner in pairs(cm.groups) do
		if #group_sunits(role) > 0 then order(role, planner, enemies) end;
	end;
end;

--------------------------------------------------------------------------------
-- spells
--------------------------------------------------------------------------------

local function spells_allowed(cat)
	local s = CD_SETTINGS.spells;
	if s == "off" then return false end;
	if s == "attack" then return cat == "X" or cat == "D" or cat == "H" or cat == "B" or cat == "S" end;
	if s == "support" then return cat == "A" or cat == "R" end;
	return true;
end;

local function queue_scan(key)
	local c = cm.casters[key];
	if not c or not CD_ABILITIES then return end;
	for cat, list in pairs(CD_ABILITIES) do
		cm.scan_queue[#cm.scan_queue + 1] = { key = key, cat = cat, list = list, i = 1 };
	end;
	c.scanned = cm.now;
end;

local function run_scan()
	local budget = CFG.scan_per_tick;
	while budget > 0 and #cm.scan_queue > 0 do
		local job = cm.scan_queue[1];
		local c = cm.casters[job.key];
		if not c or not alive(c.sunit.unit) then
			table.remove(cm.scan_queue, 1);
		else
			local u = c.sunit.unit;
			while budget > 0 and job.i <= #job.list do
				local ak = job.list[job.i];
				if safe(function() return u:can_perform_special_ability(ak) end, false) then
					if not c.abilities[ak] then
						c.abilities[ak] = job.cat;
						c.count = c.count + 1;
					end;
				end;
				job.i = job.i + 1;
				budget = budget - 1;
			end;
			if job.i > #job.list then
				table.remove(cm.scan_queue, 1);
				if #cm.scan_queue == 0 or cm.scan_queue[1].key ~= job.key then
					log(string.format("caster %s has %d usable abilities", job.key, c.count));
				end;
			end;
		end;
	end;
end;

local function friendlies_near(x, z, r, own)
	for _, u in ipairs(own) do
		local ux, uz = upos(u);
		if dist(x, z, ux, uz) < r then return true end;
	end;
	return false;
end;

-- pick a target for an ability category; returns a battle unit or nil
local function pick_target(cat, caster_u, own, enemies)
	local cx, cz = upos(caster_u);
	local range = CFG.ranges[cat] or 150;
	local best, best_s;

	if cat == "A" or cat == "R" then
		for _, u in ipairs(own) do
			local x, z = upos(u);
			local d = dist(cx, cz, x, z);
			if d <= range then
				local s = 0;
				if safe(function() return u:is_in_melee() end, false) then s = s + 5 end;
				local men = safe(function() return u:initial_number_of_men() end, 100);
				if men <= 8 then s = s + 2 end;	-- elites / monsters
				if cat == "R" then
					local hp = safe(function() return u:unary_hitpoints() end, 1);
					if hp > 0.85 then s = -100 end;
					s = s + (1 - hp) * 10;
				end;
				s = s - d / range;
				if s > 0 and (not best_s or s > best_s) then best, best_s = u, s end;
			end;
		end;
		return best;
	end;

	if cat == "S" then
		-- summon near the fighting: target the nearest enemy that's in range
		for _, u in ipairs(enemies) do
			local x, z = upos(u);
			local d = dist(cx, cz, x, z);
			if d <= range and (not best_s or -d > best_s) then best, best_s = u, -d end;
		end;
		return best;
	end;

	for _, u in ipairs(enemies) do
		local x, z = upos(u);
		local d = dist(cx, cz, x, z);
		if d <= range then
			local melee = safe(function() return u:is_in_melee() end, false);
			local men = safe(function() return u:number_of_men_alive() end, 1);
			local big = safe(function() return u:initial_number_of_men() end, 100) <= 8;
			local s;
			if cat == "X" or cat == "B" then
				if not friendlies_near(x, z, CFG.friendly_clear, own) then
					s = men / 20;
					if safe(function() return u:ammo_left() end, 0) > 0 then s = s + 3 end;
				end;
			elseif cat == "H" then
				s = (melee and 5 or 1) + (big and 3 or 0);
			elseif cat == "D" then
				s = (big and 5 or 1) + (melee and 1 or 0);
			end;
			if s then
				s = s - d / range;
				if not best_s or s > best_s then best, best_s = u, s end;
			end;
		end;
	end;
	return best;
end;

local function cast_spells(own, enemies)
	if CD_SETTINGS.spells == "off" then return end;
	for key, c in pairs(cm.casters) do
		local u = c.sunit.unit;
		if alive(u) and cm.now >= c.next_cast and c.count > 0 then
			-- try abilities in random order, first one that is ready and has a target wins
			local keys = {};
			for ak, cat in pairs(c.abilities) do
				if spells_allowed(cat) then keys[#keys + 1] = ak end;
			end;
			for i = #keys, 2, -1 do
				local j = math.random(i);
				keys[i], keys[j] = keys[j], keys[i];
			end;
			for _, ak in ipairs(keys) do
				if safe(function() return u:can_perform_special_ability(ak) end, false) then
					local cat = c.abilities[ak];
					local target = pick_target(cat, u, own, enemies);
					if target then
						local ok, err = pcall(function() c.sunit.uc:perform_special_ability(ak, target) end);
						if ok then
							log(string.format("cast %s (%s) by %s", ak, cat, key));
							c.next_cast = cm.now + CFG.caster_cooldown + rnd(0, 3);
							if CD_DIRECTOR_NOTIFY then pcall(CD_DIRECTOR_NOTIFY, "cast", u, target) end;
							break;
						else
							log("cast " .. ak .. " failed: " .. tostring(err));
						end;
					end;
				end;
			end;
			if c.next_cast < cm.now then c.next_cast = cm.now + 1.5 end;
		end;
		if cm.now - (c.scanned or 0) > CFG.ability_rescan then queue_scan(key) end;
	end;
end;

--------------------------------------------------------------------------------
-- start / stop
--------------------------------------------------------------------------------

local function own_sunits_all(by_role)
	local out = {};
	for _, list in pairs(by_role) do for _, s in ipairs(list) do out[#out + 1] = s end end;
	return out;
end;

local function begin()
	local own, enemy = collect();
	if #own == 0 or #enemy == 0 then return false end;

	local by_role = { main = {}, missile = {}, cavalry = {}, hero = {} };
	cm.sunits, cm.enemy, cm.casters, cm.scan_queue, cm.enemy_keys = {}, {}, {}, {}, {};
	for i, u in ipairs(own) do
		local s = make_sunit(u, "cd_own_" .. i);
		if s then
			local role = role_of(u);
			local key = unit_key(u);
			cm.sunits[key] = { sunit = s, role = role };
			by_role[role][#by_role[role] + 1] = s;
			local men = safe(function() return u:initial_number_of_men() end, 100);
			if men <= 8 then
				cm.casters[key] = { sunit = s, abilities = {}, count = 0, next_cast = rnd(2, 6) };
				queue_scan(key);
			end;
		end;
	end;
	for i, u in ipairs(enemy) do
		local s = make_sunit(u, "cd_enemy_" .. i);
		if s then cm.enemy[#cm.enemy + 1] = s; cm.enemy_keys[unit_key(u)] = true end;
	end;

	cm.groups = {};
	if CD_SETTINGS.ai_control == "on" then
		for role, list in pairs(by_role) do
			if #list > 0 then
				local p = safe(function() return script_ai_planner:new("cd_" .. role, list) end, nil);
				if p then
					cm.groups[role] = p;
				else
					log("could not create planner for " .. role);
				end;
			end;
		end;
		local x, z = centre(by_role.main[1] and by_role.main or own_sunits_all(by_role));
		if x then cm.hold_pos = gv(x, z) end;
		reorder();
	end;
	log(string.format("AI took command: main=%d missile=%d cavalry=%d heroes=%d, casters=%d, enemies=%d (ai_control=%s)",
		#by_role.main, #by_role.missile, #by_role.cavalry, #by_role.hero,
		(function() local n = 0 for _ in pairs(cm.casters) do n = n + 1 end return n end)(), #cm.enemy, CD_SETTINGS.ai_control));
	cm.next_reorder = cm.now + CFG.reorder_every;
	return true;
end;

local function release_all()
	for role, p in pairs(cm.groups) do
		local ok, err = pcall(function() p:release() end);
		if not ok then log("release " .. role .. " failed: " .. tostring(err)) end;
	end;
	cm.groups = {};
end;

CD_COMMANDER = {};

function CD_COMMANDER.start()
	cm.running = true;
	cm.started = false;
	cm.waiting_logged = false;
	cm.now = 0;
end;

function CD_COMMANDER.stop()
	if not cm.running then return end;
	cm.running = false;
	if cm.started then
		release_all();
		log("control returned to player");
	end;
	cm.started = false;
end;

-- called when a panel setting changes
function CD_COMMANDER.settings_changed(name)
	if not cm.running or not cm.started then return end;
	if name == "ai_control" then
		if CD_SETTINGS.ai_control == "on" then
			release_all();
			cm.started = false;		-- rebuild on next tick
		else
			release_all();
			log("AI control off (camera and spells only)");
		end;
		return;
	end;
	if name == "army" and CD_SETTINGS.army == "hold" then
		local x, z = centre(group_sunits("main"));
		if x then cm.hold_pos = gv(x, z) end;
	end;
	reorder();
	cm.next_reorder = cm.now + CFG.reorder_every;
end;

function CD_COMMANDER.tick(dt)
	if not cm.running then return end;
	cm.now = cm.now + dt;

	if not cm.started then
		local conflict = safe(function() return bm:is_conflict_phase() end, true);
		if not conflict then
			if not cm.waiting_logged then log("waiting for deployment to end"); cm.waiting_logged = true end;
			return;
		end;
		local ok, r = pcall(begin);
		if not ok then
			log("start failed: " .. tostring(r));
			cm.running = false;
			return;
		end;
		cm.started = r;
		if not r then return end;
	end;

	run_scan();

	if CD_SETTINGS.ai_control == "on" and cm.now >= cm.next_reorder then
		cm.next_reorder = cm.now + CFG.reorder_every;
		reorder();
	end;

	if cm.now >= cm.next_cast then
		cm.next_cast = cm.now + CFG.cast_every;
		local own, enemy = {}, {};
		for _, e in pairs(cm.sunits) do if alive(e.sunit.unit) then own[#own + 1] = e.sunit.unit end end;
		for _, s in ipairs(cm.enemy) do if alive(s.unit) then enemy[#enemy + 1] = s.unit end end;
		cast_spells(own, enemy);
	end;
end;
