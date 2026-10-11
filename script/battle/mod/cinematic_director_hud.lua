--------------------------------------------------------------------------------
-- Cinematic Director: cinematic HUD
--
-- Shown only while the director is filming (the battle UI is hidden then):
--   * tide of battle  - a bar across the top: your army's share of the
--                       fighting strength left on the field, with its trend
--   * caption         - bottom centre: the unit on camera, its side and type,
--                       what it is doing, men/health and (your units) its tactic
--   * battle report   - top left: the last few charges, clashes, volleys,
--                       spells, routs and losses
--   * letterbox bars  - optional; the small "HUD" button top right cycles
--                       full HUD -> letterbox (caption + tide) -> off
--
-- Everything is created visible the first time the director starts and only
-- shown/hidden afterwards (components created hidden never appeared in game).
-- The director (cinematic_director.lua) drives it through CD_HUD.
--------------------------------------------------------------------------------

local K = CD_UI;
local LOG_PATH = "cinematic_director_log.txt";

local function log(s)
	local ok, f = pcall(io.open, LOG_PATH, "a");
	if ok and f then
		local t = "";
		pcall(function() t = os.date("%H:%M:%S ") end);
		f:write(t .. "[hud] " .. tostring(s) .. "\n");
		f:close();
	end;
end;

local function safe(fn, default)
	local ok, r = pcall(fn);
	if ok then return r end;
	return default;
end;

if not K then
	log("UI kit missing - cinematic HUD disabled");
	return;
end;

local MODES = { "full", "film", "clean" };
local MODE_TIP = {
	full = "Cinematic HUD: full (click for letterbox)",
	film = "Cinematic HUD: letterbox (click to hide)",
	clean = "Cinematic HUD: hidden (click for full)",
};

local BANNER_W = 120;		-- "Banners: off" button, left of the HUD button

local TIDE_W, TIDE_H = 620, 62;
local BAR_X, BAR_Y, BAR_H = 16, 24, 12;
local CAP_W, CAP_H = 580, 92;
local FEED_W, FEED_ROWS, FEED_STEP = 470, 6, 22;
local FEED_CHARS = 58;		-- longer lines are cut short (a wrapped line would overlap the next)
local FEED_LIFE = 30;		-- seconds a report line stays
local FEED_FRESH = 8;		-- ...and stays bright

local H = {
	built = false,
	on = false,
	mode = "full",
	feed = {},			-- { text, tone, t }
	now = 0,
	logged = 0,
};

local function C(id) return K.get(id) end;

local function screen_size()
	local sw, sh = 1920, 1080;
	pcall(function()
		local w, h = core:get_screen_resolution();
		if w and h and w > 0 and h > 0 then sw, sh = w, h end;
	end);
	return sw, sh;
end;

local function move(c, x, y) if c then pcall(function() c:MoveTo(math.floor(x), math.floor(y)) end) end end;

--------------------------------------------------------------------------------
-- build
--------------------------------------------------------------------------------

local function lbl(id, parent, style, x, y, w, h)
	local c = K.make(id, "cd_label", parent);
	K.place(c, x, y, w, h);
	K.text(c, "", style);
	K.click_through(c);
	return c;
end;

local function fill(id, parent, colour, x, y, w, h)
	local c = K.make(id, "cd_fill", parent);
	if parent then K.place(c, x, y, w, h) else K.size(c, w, h) end;
	K.fill(c, colour);
	K.click_through(c);
	return c;
end;

local function build()
	if H.built then return true end;
	local sw, sh = screen_size();

	-- letterbox first, so everything else draws over it
	local bh = math.floor(sh * 0.085);
	fill("cd_hud_lb_top", nil, "black", 0, 0, sw, bh);
	fill("cd_hud_lb_bot", nil, "black", 0, 0, sw, bh);

	-- tide of battle
	local tide = K.make("cd_hud_tide", "cd_card");
	if not tide then return false end;
	K.size(tide, TIDE_W, TIDE_H);
	K.click_through(tide);
	lbl("cd_hud_tide_cap", tide, "caps_c", 0, 5, TIDE_W, 16);
	lbl("cd_hud_tide_l", tide, "tide_l", BAR_X, 5, 220, 16);
	lbl("cd_hud_tide_r", tide, "tide_r", TIDE_W - BAR_X - 220, 5, 220, 16);
	fill("cd_hud_tide_bg", tide, "black", BAR_X - 1, BAR_Y - 1, TIDE_W - 2 * BAR_X + 2, BAR_H + 2);
	fill("cd_hud_tide_a", tide, "blue", BAR_X, BAR_Y, (TIDE_W - 2 * BAR_X) / 2, BAR_H);
	fill("cd_hud_tide_b", tide, "red", TIDE_W / 2, BAR_Y, (TIDE_W - 2 * BAR_X) / 2, BAR_H);
	fill("cd_hud_tide_mid", tide, "gold", TIDE_W / 2 - 1, BAR_Y - 4, 2, BAR_H + 8);
	lbl("cd_hud_tide_trend", tide, "hud_dim_c", 0, BAR_Y + BAR_H + 4, TIDE_W, 18);

	-- caption
	local cap = K.make("cd_hud_cap", "cd_card");
	K.size(cap, CAP_W, CAP_H);
	K.click_through(cap);
	lbl("cd_hud_cap_badge", cap, "caps_c", 0, 7, CAP_W, 14);
	lbl("cd_hud_cap_name", cap, "hud_name", 0, 21, CAP_W, 26);
	lbl("cd_hud_cap_doing", cap, "hud_c", 12, 47, CAP_W - 24, 20);
	lbl("cd_hud_cap_info", cap, "hud_dim_c", 12, 67, CAP_W - 24, 18);
	fill("cd_hud_cap_hpbg", cap, "line", 40, CAP_H - 5, CAP_W - 80, 2);
	fill("cd_hud_cap_hp", cap, "gold", 40, CAP_H - 5, CAP_W - 80, 2);

	-- battle report
	local feed = K.make("cd_hud_feed", "cd_card");
	K.size(feed, FEED_W, 30 + FEED_ROWS * FEED_STEP);
	K.click_through(feed);
	lbl("cd_hud_feed_title", feed, "caps_gold", 14, 7, FEED_W - 28, 16);
	for i = 1, FEED_ROWS do
		lbl("cd_hud_feed_" .. i, feed, "feed", 14, 26 + (i - 1) * FEED_STEP, FEED_W - 28, FEED_STEP);
	end;

	-- mode button
	local b = K.make("cd_hud_mode", "cd_button");
	K.size(b, 64, 26);
	K.text(b, "HUD", "body_c");

	-- unit banners button (the director hides them while filming)
	local bb = K.make("cd_hud_banners", "cd_button");
	K.size(bb, BANNER_W, 26);
	K.text(bb, "Banners", "body_c");

	for _, id in ipairs({ "cd_hud_lb_top", "cd_hud_lb_bot", "cd_hud_tide", "cd_hud_cap", "cd_hud_feed", "cd_hud_mode", "cd_hud_banners" }) do
		pcall(function() C(id):PropagatePriority(1400) end);
	end;
	K.top(b, true);
	K.top(bb, true);
	H.built = true;
	log("cinematic HUD built");
	return true;
end;

--------------------------------------------------------------------------------
-- layout
--------------------------------------------------------------------------------

local TOP_LEVEL = { "cd_hud_lb_top", "cd_hud_lb_bot", "cd_hud_tide", "cd_hud_cap", "cd_hud_feed", "cd_hud_mode", "cd_hud_banners" };

local function layout()
	local sw, sh = screen_size();
	local on = H.on;
	local m = H.mode;
	local bars = on and m == "film";
	local bh = math.floor(sh * 0.085);

	local vis = {
		cd_hud_lb_top = bars, cd_hud_lb_bot = bars,
		cd_hud_tide = on and m ~= "clean",
		cd_hud_cap = on and m ~= "clean" and H.has_subject,
		cd_hud_feed = on and m == "full",
		cd_hud_mode = on,
		cd_hud_banners = on and CD_DIRECTOR ~= nil,
	};
	for _, id in ipairs(TOP_LEVEL) do K.show(C(id), vis[id]) end;
	if not on then return end;

	K.size(C("cd_hud_lb_top"), sw, bh);
	K.size(C("cd_hud_lb_bot"), sw, bh);
	move(C("cd_hud_lb_top"), 0, 0);
	move(C("cd_hud_lb_bot"), 0, sh - bh);
	move(C("cd_hud_tide"), (sw - TIDE_W) / 2, bars and math.max(4, (bh - TIDE_H) / 2) or 12);
	move(C("cd_hud_cap"), (sw - CAP_W) / 2, bars and (sh - CAP_H - 6) or (sh - CAP_H - 34));
	move(C("cd_hud_feed"), 24, 96);
	move(C("cd_hud_mode"), sw - 64 - 18, 14);
	K.tip(C("cd_hud_mode"), MODE_TIP[m]);
	if CD_DIRECTOR then
		local hidden = safe(CD_DIRECTOR.banners_hidden, false);
		move(C("cd_hud_banners"), sw - 64 - 18 - BANNER_W - 8, 14);
		if H.banner_state ~= hidden then
			H.banner_state = hidden;
			K.text(C("cd_hud_banners"), hidden and "Banners: off" or "Banners: on", "body_c");
			K.tip(C("cd_hud_banners"), hidden and "Unit banners are hidden while filming (click to show them)"
				or "Unit banners are shown while filming (click to hide them)");
		end;
	end;
end;

--------------------------------------------------------------------------------
-- tide of battle
--------------------------------------------------------------------------------

local function draw_tide(t)
	if not t then return end;
	local share = t.share or 0.5;
	local w = TIDE_W - 2 * BAR_X;
	local aw = math.floor(w * share + 0.5);
	aw = math.max(0, math.min(w, aw));
	K.place(C("cd_hud_tide_a"), BAR_X, BAR_Y, math.max(1, aw), BAR_H);
	K.place(C("cd_hud_tide_b"), BAR_X + aw, BAR_Y, math.max(1, w - aw), BAR_H);
	K.show(C("cd_hud_tide_a"), aw > 0);
	K.show(C("cd_hud_tide_b"), aw < w);
	K.text(C("cd_hud_tide_cap"), "Tide of battle");
	K.text(C("cd_hud_tide_l"), string.format("Your army  %d%%", math.floor(share * 100 + 0.5)));
	K.text(C("cd_hud_tide_r"), string.format("%d%%  Enemy", 100 - math.floor(share * 100 + 0.5)));

	local s;
	if t.decided then
		s = share >= 0.5 and "The enemy is breaking - victory is in sight" or "Your army is breaking";
	elseif t.trend and t.trend > 0.04 then s = "Turning in your favour"
	elseif t.trend and t.trend < -0.04 then s = "Turning against you"
	elseif share > 0.62 then s = "You hold the upper hand"
	elseif share < 0.38 then s = "The enemy holds the upper hand"
	else s = "Evenly matched" end;
	if t.routing_e and t.routing_e > 0 then s = s .. string.format("   |   %d enemy unit%s fleeing", t.routing_e, t.routing_e == 1 and "" or "s") end;
	if t.routing_p and t.routing_p > 0 then s = s .. string.format("   |   %d of yours fleeing", t.routing_p) end;
	K.text(C("cd_hud_tide_trend"), s);
end;

--------------------------------------------------------------------------------
-- caption: the unit on camera
--------------------------------------------------------------------------------

local CLASS = {
	inf = "Infantry", cav = "Cavalry", mon = "Monster", art = "Artillery", chr = "Chariot", com = "Commander",
	elph = "Monster", spcl = "Special",
};

local function name_of(c)
	if not c then return "?" end;
	if not c.name then c.name = K.unit_name(tostring(safe(function() return c.u:type() end, "unit"))) end;
	return c.name;
end;

local function kind_of(c)
	local cls = tostring(safe(function() return c.u:unit_class() end, "") or "");
	local key = tostring(safe(function() return c.u:type() end, "") or "");
	local parts = { c.friendly and "Your army" or "Enemy" };
	if c.general then
		parts[#parts + 1] = "General";
	elseif cls == "com" or (c.men or 0) == 1 and not cls:find("^mon") then
		parts[#parts + 1] = "Hero";
	else
		local k = CLASS[cls:match("^(%a+)") or ""];
		if c.flying then k = (k and k ~= "Monster") and ("Flying " .. k:lower()) or (k or "Flyer") end;
		if k then parts[#parts + 1] = k end;
	end;
	if key:find("_ror") then parts[#parts + 1] = "Regiment of Renown" end;
	return table.concat(parts, "  -  ");
end;

-- nearest living enemy in the latest survey
local function nearest(cd, c, max_d)
	local best, bd = nil, max_d or 1e9;
	for _, o in ipairs(cd.list or {}) do
		if o.alliance ~= c.alliance and not o.routing then
			local dx, dz = o.x - c.x, o.z - c.z;
			local d = math.sqrt(dx * dx + dz * dz);
			if d < bd then best, bd = o, d end;
		end;
	end;
	return best, bd;
end;

local function doing(cd, sh, c)
	local live = cd.by_key and cd.by_key[c.key] or c;
	if live.routing then return live.friendly and "Routing - fleeing the field!" or "Routing - the enemy flees!" end;
	local en, d = nearest(cd, live, 60);
	if live.melee then
		local n = 0;
		for _, o in ipairs(cd.list or {}) do
			if o.alliance ~= live.alliance and o.melee then
				local dx, dz = o.x - live.x, o.z - live.z;
				if dx * dx + dz * dz < 2500 then n = n + 1 end;
			end;
		end;
		local who = en and name_of(en) or "the enemy";
		if n >= 3 then return "In the thick of the fighting against " .. who .. (n > 1 and string.format(" and %d more", n - 1) or "") end;
		return "Locked in melee with " .. who;
	end;
	if sh.spell and sh.partner then return "Casting a spell at " .. name_of(sh.partner) end;
	local fired = cd.last_fired and cd.last_fired[c.key] and (cd.now - cd.last_fired[c.key]) < 5;
	if fired then
		local tgt = (sh.type == "volley_shooter" and sh.partner) or nearest(cd, live, 450);
		return "Loosing missiles" .. (tgt and (" at " .. name_of(tgt)) or "");
	end;
	if live.missile then
		local from = sh.type == "volley_target" and sh.partner;
		return "Under missile fire" .. (from and (" from " .. name_of(from)) or "");
	end;
	local en2, d2 = nearest(cd, live, 250);
	if live.fast and en2 and d2 < 120 then return "Charging " .. name_of(en2) end;
	if (live.speed or 0) > 0.8 then
		if en2 then return "Advancing on " .. name_of(en2) end;
		return "On the move";
	end;
	if en2 then return string.format("Facing %s, %d m away", name_of(en2), math.floor(d2 / 5 + 0.5) * 5) end;
	return "Holding position";
end;

local function draw_caption(cd)
	local sh = cd.shot;
	local c = sh and sh.c;
	H.has_subject = c ~= nil;
	if not c then return end;

	local alive = safe(function() return c.u:number_of_men_alive() end, 0) or 0;
	local total = c.men or safe(function() return c.u:initial_number_of_men() end, 1) or 1;
	local hp = safe(function() return c.u:unary_hitpoints() end, 1) or 1;
	hp = math.max(0, math.min(1, hp));

	local info = {};
	if total > 1 then info[#info + 1] = string.format("%d / %d men", alive, total) end;
	info[#info + 1] = string.format("%d%% health", math.floor(hp * 100 + 0.5));
	if c.ranged or (c.start_ammo or 0) > 0 then
		local a = safe(function() return c.u:ammo_left() end, 0) or 0;
		local s0 = c.start_ammo or 0;
		if s0 > 0 then info[#info + 1] = string.format("%d%% ammo", math.floor(a / s0 * 100 + 0.5)) end;
	end;
	if c.friendly and CD_TACTICS_ENGINE and CD_TACTICS_PANEL and CD_TACTICS_PANEL.status then
		local e = safe(function() return CD_TACTICS_ENGINE.find(c.u) end, nil);
		if e then
			local s = safe(function() return CD_TACTICS_PANEL.status(e) end, nil);
			if s and s ~= "" then info[#info + 1] = "Tactic: " .. s:gsub("%s%s.*$", ""):gsub("%.$", "") end;
		end;
	end;

	K.text(C("cd_hud_cap_badge"), kind_of(c));
	K.text(C("cd_hud_cap_name"), name_of(c));
	K.text(C("cd_hud_cap_doing"), doing(cd, sh, c));
	K.text(C("cd_hud_cap_info"), table.concat(info, "   |   "));
	local w = CAP_W - 80;
	K.place(C("cd_hud_cap_hp"), 40, CAP_H - 5, math.max(1, math.floor(w * hp)), 2);
	K.fill(C("cd_hud_cap_hp"), hp > 0.3 and "gold" or "red");
end;

--------------------------------------------------------------------------------
-- battle report
--------------------------------------------------------------------------------

local function draw_feed()
	K.text(C("cd_hud_feed_title"), "Battle report");
	local keep = {};
	for _, f in ipairs(H.feed) do
		if H.now - f.t < FEED_LIFE then keep[#keep + 1] = f end;
	end;
	H.feed = keep;
	for i = 1, FEED_ROWS do
		local f = H.feed[#H.feed - i + 1];
		local row = C("cd_hud_feed_" .. i);
		if f then
			local fresh = H.now - f.t < FEED_FRESH;
			local style = not fresh and "feed_old" or (f.tone == "good" and "feed_good" or (f.tone == "bad" and "feed_bad" or "feed"));
			K.text(row, f.text, style);
		else
			K.text(row, "", "feed");
		end;
	end;
	local n = math.min(FEED_ROWS, math.max(1, #H.feed));
	K.size(C("cd_hud_feed"), FEED_W, 30 + n * FEED_STEP + 4);
	if #H.feed == 0 then K.text(C("cd_hud_feed_1"), "Waiting for the first blows...", "feed_old") end;
end;

--------------------------------------------------------------------------------
-- public
--------------------------------------------------------------------------------

local function set_on(on)
	if on and not H.built then
		local ok, err = pcall(build);
		if not ok then log("build error: " .. tostring(err)); return end;
	end;
	if not H.built then return end;
	H.on = on and true or false;
	pcall(layout);
	log(H.on and ("HUD on (" .. H.mode .. ")") or "HUD off");
end;

local function update(cd)
	if not H.on then return end;
	H.now = cd.now or H.now;
	local ok, err = pcall(function()
		draw_tide(cd.tide);
		draw_caption(cd);
		draw_feed();
		layout();
	end);
	if not ok and H.logged < 5 then H.logged = H.logged + 1; log("update error: " .. tostring(err)) end;
end;

-- tone: "good" (for the player), "bad" or nil
local function report(text, tone)
	text = tostring(text);
	if #text > FEED_CHARS then text = text:sub(1, FEED_CHARS - 3):gsub("%s+%S*$", "") .. "..." end;
	H.feed[#H.feed + 1] = { text = text, tone = tone, t = H.now };
	while #H.feed > 20 do table.remove(H.feed, 1) end;
end;

core:add_listener("cd_hud_click", "ComponentLClickUp", true,
	function(context)
		local id = tostring(context.string);
		if id == "cd_hud_banners" then
			if CD_DIRECTOR then pcall(CD_DIRECTOR.toggle_banners) end;
			pcall(layout);
			return;
		end;
		if id ~= "cd_hud_mode" then return end;
		local i = 1;
		for n, m in ipairs(MODES) do if m == H.mode then i = n end end;
		H.mode = MODES[i % #MODES + 1];
		log("HUD mode " .. H.mode);
		pcall(layout);
	end, true);

core:add_listener("cd_hud_end", "BattleConflictFinished", true, function() set_on(false) end, true);

CD_HUD = {
	on = set_on,
	update = update,
	report = report,
	name = name_of,
	state = H,
};
log("cinematic HUD loaded");
