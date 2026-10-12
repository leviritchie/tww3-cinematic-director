--------------------------------------------------------------------------------
-- Cinematic Director: cinematic HUD (streamlined)
--
-- Shown only while the director is filming (the battle UI is hidden then):
--   * callouts - why the camera is here: a box with a symbol and a line, e.g.
--                [>>] "Your Empire Knights charging Orc Boyz", over the unit it is about,
--                with a leader line down to the unit; one per event when the shot shows
--                several. Line and underline are blue when it is good news for you, red when
--                bad. Placed every CALLOUT_MS by projecting the unit through the director's
--                camera (CD_DIRECTOR.camera; the fov it passes is vertical; +x is screen-right
--                looking along +z).
--   * banner   - bottom centre: the same for lines about no unit ("The battle lines close")
--   * toast    - just above the banner, for a few seconds: things that happen
--                off camera (a unit destroyed, routing, rallying)
--   * tide     - top centre: a thin bar, your share of the fighting strength
--                (blue) against the enemy's (red), with an arrow when it turns
--   * two small symbol buttons top right: HUD mode (full / letterbox / off)
--     and unit banners (shown / hidden while filming)
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
local MODE_ICON = { full = "film", film = "film_gold", clean = "film_dim" };

local BTN = 36;					-- symbol buttons, top right
local TIDE_W, TIDE_H = 300, 8;
local BAN_H = 46;				-- banner height; its width follows the text
local BAN_MIN, BAN_MAX = 280, 1150;
local CHAR_W = 8.4;				-- rough width of a banner character (for sizing the banner to its line)
local TOAST_LIFE = 4;			-- seconds a toast stays
local CO_N = 4;					-- callout boxes
local CO_H = 36;				-- callout box height for one line; the text wraps to 2-3 lines (CO_LINE each)
local CO_LINE = 21;
local CO_MIN, CO_MAX = 150, 380;
local CO_STEM = 60;				-- pixels from the box down to the unit
local CALLOUT_MS = 40;			-- how often callouts follow their units
local CO_DRIFT_X = 160;			-- a box moves once its unit is this far past either side of it,
local CO_DRIFT_Y = 320;			-- or this far below it (or up against it)
local CO_MIN_HOLD = 1;			-- seconds a box stays put at least
local CO_TAU = 0.08;			-- seconds: smoothing of the unit point (formation jiggle)
-- Anchored callouts: a unit's box is made inside its floating banner (unit_id_holder > <unique_ui_id>),
-- which the engine moves with the unit every frame and which stays on screen while the banners are hidden
-- (in game: a box there followed its unit while filming). The box hangs centred on the banner, its bottom
-- at the banner's bottom (above the banner when the banners are shown), and its leader line drops from it
-- to the unit's heads. Units without a banner on screen get the projected boxes.
local CO_ANCHOR = true;
local AB_W, AB_H = 48, 75;		-- a banner's size when it can't be read (as seen in game)
local AB_LOGS = 60;

local TONE_FILL = { good = "blue", bad = "red" };
-- highlights (reason.highlight: a moment clearly good or bad for the player): a bigger box, tinted green
-- or red, with larger text and thicker lines
local HL_FILL = { good = "green", bad = "red" };
local HL_TINT = { good = "green_bg", bad = "red_bg" };
local HL_CHAR_W, HL_H, HL_LINE, HL_MIN, HL_MAX, HL_ICON, HL_UL, HL_LW = 11, 50, 26, 220, 500, 34, 5, 4;
local TONE_ICON = { good = "_good", bad = "_bad" };

local H = {
	built = false,
	on = false,
	mode = "film",		-- letterbox by default (the HUD button cycles full / letterbox / hidden)
	toasts = {},		-- { text, icon, tone, t }
	co = {},			-- callouts: { unit, w, wp (smoothed world point), ax/ay (screen), vis, line }
	co_vis = {}, line_vis = {}, hline_vis = {},
	ab = {},			-- anchored boxes by unit id: { uid, bw, bh, key, vis, dy, dy_t }
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

local function icon(id, parent, name, x, y, size)
	local c = K.make(id, "cd_icon", parent);
	if parent then K.place(c, x, y, size, size) else K.size(c, size, size) end;
	K.fill(c, name);
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

	-- tide: a thin bar
	local tide = fill("cd_hud_tide", nil, "dark", 0, 0, TIDE_W + 4, TIDE_H + 4);
	if not tide then return false end;
	fill("cd_hud_tide_a", tide, "blue", 2, 2, TIDE_W / 2, TIDE_H);
	fill("cd_hud_tide_b", tide, "red", 2 + TIDE_W / 2, 2, TIDE_W / 2, TIDE_H);
	fill("cd_hud_tide_mid", tide, "gold", 2 + TIDE_W / 2 - 1, 0, 2, TIDE_H + 4);
	icon("cd_hud_trend", nil, "up", 0, 0, 16);

	-- banner
	local ban = K.make("cd_hud_ban", "cd_card");
	K.size(ban, 600, BAN_H);
	K.click_through(ban);
	icon("cd_hud_ban_icon", ban, "eye", 12, 8, 30);
	lbl("cd_hud_ban_text", ban, "banner", 48, 0, 600 - 60, BAN_H - 3);
	fill("cd_hud_ban_line", ban, "gold", 0, BAN_H - 3, 600, 3);

	-- callouts: a box (the banner's card, mostly opaque) and a leader line each
	for i = 1, CO_N do
		local box = K.make("cd_hud_co" .. i, "cd_card");
		K.size(box, 400, CO_H);
		K.click_through(box);
		fill("cd_hud_co" .. i .. "_tint", box, "clear", 0, 0, 400, CO_H);
		icon("cd_hud_co" .. i .. "_icon", box, "eye", 8, 5, 26);
		lbl("cd_hud_co" .. i .. "_text", box, "banner", 40, 0, 400 - 50, CO_H - 3);
		fill("cd_hud_co" .. i .. "_ul", box, "gold", 0, CO_H - 3, 400, 3);
		fill("cd_hud_co" .. i .. "_line", nil, "gold", 0, 0, 2, CO_STEM);
		fill("cd_hud_co" .. i .. "_hline", nil, "gold", 0, 0, 20, 2);
	end;

	-- toast
	local toast = fill("cd_hud_toast", nil, "dark", 0, 0, 400, 24);
	icon("cd_hud_toast_icon", toast, "skull", 6, 3, 18);
	lbl("cd_hud_toast_text", toast, "toast", 28, 0, 400 - 34, 24);

	-- symbol buttons
	local b = K.make("cd_hud_mode", "cd_button");
	K.size(b, BTN, BTN);
	K.text(b, "", "body_c");
	icon("cd_hud_mode_icon", b, "film", 7, 7, BTN - 14);
	local bb = K.make("cd_hud_banners", "cd_button");
	K.size(bb, BTN, BTN);
	K.text(bb, "", "body_c");
	icon("cd_hud_banners_icon", bb, "flag_dim", 7, 7, BTN - 14);

	for _, id in ipairs({ "cd_hud_lb_top", "cd_hud_lb_bot", "cd_hud_tide", "cd_hud_trend", "cd_hud_ban", "cd_hud_toast", "cd_hud_mode", "cd_hud_banners" }) do
		pcall(function() C(id):PropagatePriority(1400) end);
	end;
	for i = 1, CO_N do
		pcall(function() C("cd_hud_co" .. i .. "_line"):PropagatePriority(1400) end);
		pcall(function() C("cd_hud_co" .. i .. "_hline"):PropagatePriority(1400) end);
		pcall(function() C("cd_hud_co" .. i):PropagatePriority(1401) end);
		K.show(C("cd_hud_co" .. i), false);
		K.show(C("cd_hud_co" .. i .. "_line"), false);
		K.show(C("cd_hud_co" .. i .. "_hline"), false);
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

-- the unit cards, kept on screen while filming (CD_DIRECTOR.unit_cards): drawn over the letterbox bar, and
-- the banner and callouts stay above them
local function cards_shown()
	return CD_DIRECTOR ~= nil and CD_DIRECTOR.unit_cards ~= nil and safe(CD_DIRECTOR.unit_cards, false) and true or false;
end;

-- screen y of the top of the unit cards (nil when they aren't shown); read once a second
local function cards_top(sh)
	if not cards_shown() then return nil end;
	local now = os.clock();
	if H.cards_y and H.cards_t and now - H.cards_t < 1 and now >= H.cards_t then return H.cards_y end;
	H.cards_t = now;
	local y;
	pcall(function()
		local root = core:get_ui_root();
		local c = find_uicomponent(root, "battle_orders", "cards_panel") or find_uicomponent(root, "battle_orders");
		if c and c:Visible() then
			local _, cy = c:Position();
			if cy and cy > sh * 0.5 and cy < sh then y = cy end;
		end;
	end);
	H.cards_y = y or (sh - math.floor(sh * 0.14));
	return H.cards_y;
end;

-- the cards above the letterbox bar while the HUD is on (their own priority back afterwards)
local function raise_cards(on)
	local ok, err = pcall(function()
		if on and not H.cards_raised and cards_shown() then
			local c = find_uicomponent(core:get_ui_root(), "battle_orders");
			if not c then return end;
			H.cards_raised = { c = c, prio = c:Priority() };
			c:PropagatePriority(1402);
		elseif not on and H.cards_raised then
			local r = H.cards_raised;
			H.cards_raised = nil;
			r.c:PropagatePriority(r.prio or 0);
		end;
	end);
	if not ok then log("unit cards priority: " .. tostring(err)) end;
end;

local TOP_LEVEL = { "cd_hud_lb_top", "cd_hud_lb_bot", "cd_hud_tide", "cd_hud_trend", "cd_hud_ban", "cd_hud_toast", "cd_hud_mode", "cd_hud_banners" };

local function layout()
	local sw, sh = screen_size();
	local on = H.on;
	local m = H.mode;
	local bars = on and m == "film";
	local bh = math.floor(sh * 0.085);
	local toast = H.toasts[#H.toasts];

	local vis = {
		cd_hud_lb_top = bars, cd_hud_lb_bot = bars,
		cd_hud_tide = on and m == "full",
		cd_hud_trend = on and m == "full" and H.trend ~= nil,
		cd_hud_ban = on and m ~= "clean" and H.ban_text ~= nil,
		cd_hud_toast = on and m == "full" and toast ~= nil,
		cd_hud_mode = on,
		cd_hud_banners = on and CD_DIRECTOR ~= nil,
	};
	for _, id in ipairs(TOP_LEVEL) do K.show(C(id), vis[id]) end;
	if not on then return end;

	K.size(C("cd_hud_lb_top"), sw, bh);
	K.size(C("cd_hud_lb_bot"), sw, bh);
	move(C("cd_hud_lb_top"), 0, 0);
	move(C("cd_hud_lb_bot"), 0, sh - bh);

	local tx, ty = (sw - TIDE_W - 4) / 2, 16;
	move(C("cd_hud_tide"), tx, ty);
	move(C("cd_hud_trend"), tx + TIDE_W + 12, ty - 4);

	local bw = H.ban_w or 600;
	local by = bars and (sh - bh + (bh - BAN_H) / 2) or (sh - BAN_H - 40);
	local ct = cards_top(sh);
	if ct then
		-- the cards take the bottom: the banner goes in the top bar (film) or above the cards
		by = bars and ((bh - BAN_H) / 2) or math.min(by, ct - BAN_H - 12);
	end;
	move(C("cd_hud_ban"), (sw - bw) / 2, by);
	if toast then
		move(C("cd_hud_toast"), (sw - (H.toast_w or 400)) / 2, by - 32);
	end;

	move(C("cd_hud_mode"), sw - BTN - 16, 12);
	K.tip(C("cd_hud_mode"), MODE_TIP[m]);
	if H.mode_icon ~= MODE_ICON[m] then
		H.mode_icon = MODE_ICON[m];
		K.fill(C("cd_hud_mode_icon"), H.mode_icon);
	end;
	if CD_DIRECTOR then
		local hidden = safe(CD_DIRECTOR.banners_hidden, false);
		move(C("cd_hud_banners"), sw - 2 * BTN - 24, 12);
		if H.banner_state ~= hidden then
			H.banner_state = hidden;
			K.fill(C("cd_hud_banners_icon"), hidden and "flag_dim" or "flag");
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
	local aw = math.floor(TIDE_W * share + 0.5);
	aw = math.max(0, math.min(TIDE_W, aw));
	K.place(C("cd_hud_tide_a"), 2, 2, math.max(1, aw), TIDE_H);
	K.place(C("cd_hud_tide_b"), 2 + aw, 2, math.max(1, TIDE_W - aw), TIDE_H);
	K.show(C("cd_hud_tide_a"), aw > 0);
	K.show(C("cd_hud_tide_b"), aw < TIDE_W);

	-- an arrow only when the battle is turning: blue up = your way, red down = theirs
	local trend = nil;
	if t.trend and t.trend > 0.04 then trend = "up_good"
	elseif t.trend and t.trend < -0.04 then trend = "down_bad" end;
	if trend ~= H.trend then
		H.trend = trend;
		if trend then K.fill(C("cd_hud_trend"), trend) end;
	end;
end;

--------------------------------------------------------------------------------
-- banner: why the camera is here
--------------------------------------------------------------------------------

local function name_of(c)
	if not c then return "?" end;
	if not c.name then c.name = K.unit_name(tostring(safe(function() return c.u:type() end, "unit"))) end;
	return c.name;
end;

--------------------------------------------------------------------------------
-- callouts: boxes over the units the lines are about
--------------------------------------------------------------------------------

-- the point to hang the line from: over the unit's heads (about where its health bar floats)
local function head_height(c)
	if c.co_h then return c.co_h end;
	local cls = tostring(safe(function() return c.u:unit_class() end, ""));
	local h = 2.8;
	if cls:find("^mon") or cls:find("^lrg") then h = 8
	elseif c.cavalry or c.flying or cls:find("^cav") or cls:find("chariot") or cls:find("^chr") then h = 4.2
	elseif c.big then h = 3.5 end;
	c.co_h = h;
	return h;
end;

local function unit_point(c)
	local p = c.u and safe(function() return c.u:position() end, nil);
	if p then return p:get_x(), p:get_y() + head_height(c), p:get_z() end;
	if c.x then return c.x, (c.y or 0) + head_height(c), c.z end;
	return nil;
end;

-- world point -> screen pixels through the director's camera (nil when behind it or not filming)
local function project(sw, sh, wx, wy, wz)
	if not (CD_DIRECTOR and CD_DIRECTOR.camera) then return nil end;
	local p, q, fov = CD_DIRECTOR.camera();
	if not p then return nil end;
	local fx, fy, fz = q[1] - p[1], q[2] - p[2], q[3] - p[3];
	local l = math.sqrt(fx * fx + fy * fy + fz * fz);
	if l < 0.01 then return nil end;
	fx, fy, fz = fx / l, fy / l, fz / l;
	local rx, rz = fz, -fx;								-- right: +x when looking along +z
	local rl = math.sqrt(rx * rx + rz * rz);
	if rl < 0.01 then return nil end;
	rx, rz = rx / rl, rz / rl;
	local ux, uy, uz = fy * rz, fz * rx - fx * rz, -fy * rx;	-- up = forward x right
	local dx, dy, dz = wx - p[1], wy - p[2], wz - p[3];
	local Z = dx * fx + dy * fy + dz * fz;
	if Z < 1 then return nil end;
	local X, Y = dx * rx + dz * rz, dx * ux + dy * uy + dz * uz;
	local th = math.tan(math.rad(math.max(fov or 45, 5)) / 2);
	return sw / 2 + X / (Z * th) * (sh / 2), sh / 2 - Y / (Z * th) * (sh / 2);
end;

-- a callout's size: short lines stay on one line, longer ones wrap to two or three (narrower boxes
-- take less of the picture); lines counted with a greedy word wrap at CHAR_W a character
local function wrap_lines(text, chars)
	local n, len = 1, 0;
	for word in text:gmatch("%S+") do
		if len > 0 and len + 1 + #word > chars then n, len = n + 1, #word
		else len = len + (len > 0 and 1 or 0) + #word end;
	end;
	return n;
end;

local function callout_size(text, big)
	local n = #text;
	local want = n <= 30 and 1 or (n <= 64 and 2 or 3);
	local chars = math.max(16, math.ceil(n / want) + 3);
	local lines = wrap_lines(text, chars);
	while lines > want and chars < 60 do chars = chars + 2; lines = wrap_lines(text, chars) end;
	if big then
		local w = math.floor(math.max(HL_MIN, math.min(HL_MAX, chars * HL_CHAR_W * 1.08 + 70)));
		return w, HL_H + (lines - 1) * HL_LINE;
	end;
	local w = math.floor(math.max(CO_MIN, math.min(CO_MAX, chars * CHAR_W * 1.08 + 56)));
	return w, CO_H + (lines - 1) * CO_LINE;
end;

-- a callout box's look; part(sfx) gives its parts ("" = the box, "_tint", "_icon", "_text", "_ul", "_line")
local function style_box(part, x, w, h, big)
	K.size(part(""), w, h);
	local is, ul = big and HL_ICON or 26, big and HL_UL or 3;
	local col = (big and HL_FILL[x.tone]) or TONE_FILL[x.tone] or "gold";
	K.place(part("_tint"), 0, 0, w, h);
	K.fill(part("_tint"), big and HL_TINT[x.tone] or "clear");
	K.place(part("_icon"), 8, math.floor((h - ul - is) / 2), is, is);
	K.place(part("_text"), is + 14, 0, w - is - 20, h - ul);
	K.text(part("_text"), x.text, big and "hud_name" or "banner");
	K.fill(part("_icon"), x.icon .. (big and "" or (TONE_ICON[x.tone] or "_gold")));	-- (cream on the tint)
	K.place(part("_ul"), 0, h - ul, w, ul);
	K.fill(part("_ul"), col);
	K.fill(part("_line"), col);
end;

-- the shot's lines that are about a unit (the first and its .extra)
local function set_callouts(r)
	local list = {};
	if r and r.unit then
		list[1] = r;
		for _, x in ipairs(r.extra or {}) do
			if x.unit and #list < CO_N then list[#list + 1] = x end;
		end;
	end;
	local key = "";
	for _, x in ipairs(list) do key = key .. x.icon .. "|" .. x.text .. "|" .. tostring(x.tone) .. (x.highlight and "!" or "") .. "#" end;
	if key == H.co_key then return end;
	H.co_key = key;
	local old = H.co or {};
	H.co = {};
	for i, x in ipairs(list) do
		local big = x.highlight and true or false;
		local w, h = callout_size(x.text, big);
		local prev = old[i];
		-- the same unit keeps its smoothed point (no jump when only the words change)
		local keep = prev and prev.unit == x.unit;
		H.co[i] = { unit = x.unit, w = w, h = h, lw = big and HL_LW or 2, wp = keep and prev.wp or nil, box = keep and prev.box or nil, box_t = keep and prev.box_t or nil };
		if keep and prev.box and (prev.box.w ~= w or prev.box.h ~= h) then
			local b = prev.box;
			H.co[i].box = { x = math.max(12, b.x + (b.w - w) / 2), y = b.below and b.y or (b.y + b.h - h), w = w, h = h, below = b.below };		-- same centre and stem
		end;
		H.co[i].src = x;
		style_box(function(sfx) return C("cd_hud_co" .. i .. sfx) end, x, w, h, big);
		K.fill(C("cd_hud_co" .. i .. "_hline"), (big and HL_FILL[x.tone]) or TONE_FILL[x.tone] or "gold");
	end;
end;

local function overlaps(a, b)
	return a.x < b.x + b.w + 8 and b.x < a.x + a.w + 8 and a.y < b.y + b.h + 6 and b.y < a.y + a.h + 6;
end;

-- where a box goes for a unit at screen point ax, ay: centred over it, CO_STEM above (under it when the
-- unit is near the top of the screen), clear of the boxes already placed
local function ideal_box(co, ax, ay, placed, sw, top, bottom)
	local r = { w = co.w, h = co.h };
	r.x = math.max(12, math.min(sw - co.w - 12, ax - co.w / 2));
	r.y = ay - CO_STEM - r.h;
	r.below = r.y < top and ay + 30 + r.h <= bottom;
	if r.below then r.y = ay + 30 end;
	local function hit_by() for _, o in ipairs(placed) do if overlaps(r, o) then return o end end end;
	for _ = 1, CO_N do
		local hit = hit_by();
		if not hit then break end;
		r.y = r.below and (hit.y + hit.h + 8) or (hit.y - r.h - 8);
	end;
	r.y = math.max(top, math.min(bottom - r.h + CO_H, r.y));
	-- no room above (or below): slide along the row instead
	for _ = 1, CO_N do
		local hit = hit_by();
		if not hit then break end;
		if hit.x + hit.w + 8 + co.w <= sw - 12 then r.x = hit.x + hit.w + 10 else r.x = math.max(12, hit.x - co.w - 10) end;
	end;
	return r;
end;

-- has the unit drifted so far from its box that the box should move? (the box stays still otherwise:
-- text that follows a unit at the timer's rate, not the camera's frame rate, jerks and is hard to read)
local function drifted(r, ax, ay)
	if ax < r.x - CO_DRIFT_X or ax > r.x + r.w + CO_DRIFT_X then return true end;
	local gap = r.below and (r.y - ay) or (ay - r.y - r.h);
	return gap < 12 or gap > CO_DRIFT_Y;
end;

local function describe(c)
	if not c then return "nil" end;
	local x, y, w, h;
	pcall(function() x, y = c:Position() end);
	pcall(function() w, h = c:Bounds() end);
	return string.format("%s at %s,%s size %sx%s", tostring(safe(function() return c:Id() end, "?")), tostring(x), tostring(y), tostring(w), tostring(h));
end;

local function ab_log(s)
	if (H.ab_logs or 0) >= AB_LOGS then return end;
	H.ab_logs = (H.ab_logs or 0) + 1;
	log(s);
end;

local function banner_of(uid)
	local hd = safe(function() return find_uicomponent(core:get_ui_root(), "unit_id_holder") end, nil);
	return hd and safe(function() return find_child_uicomponent(hd, uid) end, nil), hd;
end;

-- the unit's banner (looked up each time: the game may remake it) and our box in it (made on first use;
-- the banner's own size is read before our box goes in, since a component's Bounds grow with its children)
local function anchor_of(c)
	if not CO_ANCHOR or not c or not c.u then return nil end;
	local uid = tostring(safe(function() return c.u:unique_ui_id() end, ""));
	if uid == "" then return nil end;
	local banner, hd = banner_of(uid);
	local a = H.ab[uid];
	if not a then a = { uid = uid }; H.ab[uid] = a end;
	if not banner or not safe(function() return banner:VisibleFromRoot() end, false) then
		if not a.no_banner then
			a.no_banner = true;
			ab_log(string.format("callout for %s: no banner on screen (%s), placed by projection", name_of(c), hd and "holder found" or "no unit_id_holder"));
		end;
		return nil;
	end;
	a.no_banner = nil;
	local id = "cd_hud_ab_" .. uid;
	local box = safe(function() return find_child_uicomponent(banner, id) end, nil);
	if not box then
		a.bw, a.bh = AB_W, AB_H;
		pcall(function()
			local w, h = banner:Bounds();
			if w and w > 4 and w < 200 and h and h > 4 and h < 300 then a.bw, a.bh = w, h end;
		end);
		local ok = pcall(function()
			box = UIComponent(banner:CreateComponent(id, "ui/templates/cd_card.twui.xml"));
			for _, p in ipairs({ { "_tint", "cd_fill" }, { "_icon", "cd_icon" }, { "_text", "cd_label" }, { "_ul", "cd_fill" }, { "_line", "cd_fill" } }) do
				local part = UIComponent(box:CreateComponent(id .. p[1], "ui/templates/" .. p[2] .. ".twui.xml"));
				pcall(function() part:SetInteractive(false) end);
			end;
			box:SetInteractive(false);
			box:PropagatePriority(1401);
		end);
		if not ok or not box then ab_log("callout for " .. name_of(c) .. ": could not make a box in banner " .. describe(banner)); return nil end;
		a.key, a.vis, a.line_vis, a.dy, a.made = nil, true, true, 0, (a.made or 0) + 1;
		ab_log(string.format("callout box made in the banner of %s (uid %s, made %d times): banner %s, its size before %dx%d", name_of(c), uid, a.made, describe(banner), a.bw, a.bh));
	end;
	a.banner, a.box = banner, box;
	return a;
end;

local function ab_part(a, sfx)
	if sfx == "" then return a.box end;
	return safe(function() return find_child_uicomponent(a.box, "cd_hud_ab_" .. a.uid .. sfx) end, nil);
end;

-- keep every callout's box still and its leader line on the unit: a drop from the box's edge, then
-- along to the unit when it isn't under the box. A box moves (in one step) only when its unit has
-- drifted well away from it, at most once per CO_MIN_HOLD.
local function place_callouts()
	local list = H.co or {};
	local show = H.on and H.mode ~= "clean" and #list > 0;
	local sw, sh = screen_size();
	local bars = H.mode == "film";
	local bh = bars and math.floor(sh * 0.085) or 0;
	local top, bottom = bh + 40, sh - bh - CO_H - 8;
	local ct = H.on and cards_top(sh);
	if ct then bottom = math.min(bottom, ct - CO_H - 8) end;
	local now = CD_DIRECTOR and CD_DIRECTOR.clock and CD_DIRECTOR.clock() or H.now;
	local dt = math.max(0, math.min(0.5, now - (H.co_t or now)));
	H.co_t = now;
	local f = 1 - math.exp(-dt / CO_TAU);
	for _, co in ipairs(list) do
		co.vis, co.line, co.ax = false, false, nil;
		if show then
			local wx, wy, wz = unit_point(co.unit);
			if wx then
				if not co.wp then co.wp = { wx, wy, wz }
				else
					co.wp[1], co.wp[2], co.wp[3] = co.wp[1] + (wx - co.wp[1]) * f, co.wp[2] + (wy - co.wp[2]) * f, co.wp[3] + (wz - co.wp[3]) * f;
				end;
				co.ax, co.ay = project(sw, sh, co.wp[1], co.wp[2], co.wp[3]);
			end;
		end;
	end;
	-- anchored boxes: they move with their banners; here only their stacking (dy: lifted clear of the
	-- boxes placed before them, kept at least CO_MIN_HOLD unless it overlaps), the screen-edge clamps
	-- and their leader lines are set
	local placed, todo = {}, {};
	local used = {};
	local banners_on = CD_DIRECTOR and CD_DIRECTOR.banners_hidden and not safe(CD_DIRECTOR.banners_hidden, true) or false;
	for _, co in ipairs(list) do
		co.a = nil;
		-- (only while the unit's heads are in the picture; otherwise the projected box keeps its place)
		local a = show and co.ax and co.ax >= 0 and co.ax <= sw and co.ay >= 0 and co.ay <= sh and anchor_of(co.unit);
		local bx, by;
		if a then pcall(function() bx, by = a.banner:Position() end) end;
		if bx and by and bx > -400 and bx < sw + 400 and by > -400 and by < sh + 400 then
			co.a, used[a.uid] = a, true;
			local x = co.src;
			local big = x.highlight and true or false;
			local key = x.icon .. "|" .. x.text .. "|" .. tostring(x.tone) .. (big and "!" or "") .. co.w .. "x" .. co.h;
			if a.key ~= key then
				a.key = key;
				style_box(function(sfx) return ab_part(a, sfx) end, x, co.w, co.h, big);
			end;
			local base_x = bx + a.bw / 2 - co.w / 2;
			local base_y = (banners_on and (by - 4) or (by + a.bh)) - co.h;
			local function rect(dy)
				local r = { w = co.w, h = co.h, x = math.max(12, math.min(sw - co.w - 12, base_x)), y = base_y + dy };
				if r.y < top then r.y = top end;
				return r;
			end;
			local function hit(r) for _, o in ipairs(placed) do if overlaps(r, o) then return o end end end;
			-- the least lift that clears the boxes placed so far
			local need = 0;
			for _ = 1, CO_N do
				local o = hit(rect(need));
				if not o then break end;
				need = need - ((base_y + need + co.h) - o.y + 8);
			end;
			local dy = a.dy or 0;
			if dy ~= need and (hit(rect(dy)) or now - (a.dy_t or -1e9) >= CO_MIN_HOLD) then a.dy, a.dy_t = need, now end;
			local r = rect(a.dy or 0);
			placed[#placed + 1] = r;
			K.place(a.box, r.x - bx, r.y - by);
			-- the leader line: from the box's bottom down to the unit's heads, above the unit
			local lw = co.lw or 2;
			local len = math.floor(co.ay - (r.y + r.h));
			local ln = ab_part(a, "_line");
			if len >= 4 then
				local lx = math.max(10, math.min(co.w - 12, co.ax - r.x));
				K.place(ln, lx - math.floor(lw / 2), co.h, lw, len);
				if not a.line_vis then a.line_vis = true; K.show(ln, true) end;
			elseif a.line_vis then
				a.line_vis = false; K.show(ln, false);
			end;
			if not a.vis then a.vis = true; K.show(a.box, true) end;
			co.vis = true;
			-- for tuning: where the banner sits against the unit's heads as projected
			if now - (a.log_t or -1e9) >= 2 then
				a.log_t = now;
				ab_log(string.format("anchored callout %s: banner %d,%d (%dx%d), heads project to %d,%d, box %d,%d %dx%d lift %d%s",
					name_of(co.unit), math.floor(bx), math.floor(by), a.bw, a.bh, math.floor(co.ax), math.floor(co.ay), math.floor(r.x), math.floor(r.y), r.w, r.h, math.floor(a.dy or 0), banners_on and " (banners on)" or ""));
			end;
		end;
	end;
	-- anchored boxes no longer wanted (the box may have gone with its banner: looked up again)
	for uid, a in pairs(H.ab) do
		if not used[uid] and a.vis then
			a.vis = false;
			local banner = banner_of(uid);
			local box = banner and safe(function() return find_child_uicomponent(banner, "cd_hud_ab_" .. uid) end, nil);
			if box then K.show(box, false) end;
		end;
	end;
	-- boxes that stay put first, then the ones that need a place (left to right), clear of the others
	for i, co in ipairs(list) do
		if co.a then
			-- anchored
		elseif co.ax then
			if co.box and not (drifted(co.box, co.ax, co.ay) and now - (co.box_t or -1e9) >= CO_MIN_HOLD) then
				placed[#placed + 1] = co.box;
			else
				todo[#todo + 1] = i;
			end;
		elseif co.box and now - (co.box_t or -1e9) < CO_MIN_HOLD then
			placed[#placed + 1] = co.box;	-- briefly out of view (a cut): keep it
			co.keep = true;
		end;
	end;
	table.sort(todo, function(a, b) return list[a].ax < list[b].ax end);
	for _, i in ipairs(todo) do
		local co = list[i];
		co.box, co.box_t = ideal_box(co, co.ax, co.ay, placed, sw, top, bottom), now;
		placed[#placed + 1] = co.box;
	end;
	for i, co in ipairs(list) do
		local r = co.box;
		if co.a then
			-- anchored
		elseif r and (co.ax or co.keep) then
			co.vis = true;
			if r.x ~= r.mx or r.y ~= r.my then r.mx, r.my = r.x, r.y; move(C("cd_hud_co" .. i), r.x, r.y) end;
			local ax, ay = co.ax, co.ay;
			if ax and ax >= 0 and ax <= sw and ay >= 0 and ay <= sh then
				-- the drop: from the box's bottom (top, when the box hangs under the unit) to the unit's height
				local lx = math.max(r.x + 10, math.min(r.x + co.w - 12, ax));
				local y1, y2 = r.y + r.h, ay;
				if r.below or ay < r.y then y1, y2 = ay, r.y end;
				if y2 - y1 >= 4 then
					co.line = true;
					local lw = co.lw or 2;
					K.size(C("cd_hud_co" .. i .. "_line"), lw, math.floor(y2 - y1));
					move(C("cd_hud_co" .. i .. "_line"), lx - math.floor(lw / 2), y1);
					-- the run along to the unit
					local hw = math.floor(math.abs(ax - lx));
					co.hline = hw >= 3;
					if co.hline then
						K.size(C("cd_hud_co" .. i .. "_hline"), hw + lw, lw);
						move(C("cd_hud_co" .. i .. "_hline"), math.min(ax, lx) - math.floor(lw / 2), ay - math.floor(lw / 2));
					end;
				end;
			end;
		end;
		co.keep = nil;
	end;
	for i = 1, CO_N do
		local co = list[i];
		local vis = show and co and co.vis and not co.a or false;
		if H.co_vis[i] ~= vis then H.co_vis[i] = vis; K.show(C("cd_hud_co" .. i), vis) end;
		local lv = vis and co.line or false;
		if H.line_vis[i] ~= lv then H.line_vis[i] = lv; K.show(C("cd_hud_co" .. i .. "_line"), lv) end;
		local hv = lv and co.hline or false;
		if H.hline_vis[i] ~= hv then H.hline_vis[i] = hv; K.show(C("cd_hud_co" .. i .. "_hline"), hv) end;
	end;
end;

local function draw_banner(cd)
	local sh = cd.shot;
	local r = sh and sh.reason;
	set_callouts(r);
	if r and r.unit then r = nil end;		-- it is on a callout instead
	if not r then H.ban_text, H.ban_key = nil, nil; return end;
	local key = r.icon .. "|" .. r.text .. "|" .. tostring(r.tone);
	if key == H.ban_key then return end;
	H.ban_key = key;
	H.ban_text = r.text;
	local w = math.floor(math.max(BAN_MIN, math.min(BAN_MAX, #r.text * CHAR_W + 100)));
	H.ban_w = w;
	K.size(C("cd_hud_ban"), w, BAN_H);
	K.place(C("cd_hud_ban_text"), 48, 0, w - 60, BAN_H - 3);
	K.text(C("cd_hud_ban_text"), r.text, "banner");
	K.fill(C("cd_hud_ban_icon"), r.icon .. (TONE_ICON[r.tone] or "_gold"));
	K.place(C("cd_hud_ban_line"), 0, BAN_H - 3, w, 3);
	K.fill(C("cd_hud_ban_line"), TONE_FILL[r.tone] or "gold");
end;

--------------------------------------------------------------------------------
-- toasts: things happening off camera
--------------------------------------------------------------------------------

local function draw_toast()
	local keep = {};
	for _, f in ipairs(H.toasts) do
		if H.now - f.t < TOAST_LIFE then keep[#keep + 1] = f end;
	end;
	H.toasts = keep;
	local f = keep[#keep];
	if not f or f == H.toast_shown then return end;
	H.toast_shown = f;
	local w = math.floor(math.max(160, math.min(560, #f.text * 7 + 50)));
	H.toast_w = w;
	K.size(C("cd_hud_toast"), w, 24);
	K.place(C("cd_hud_toast_text"), 28, 0, w - 34, 24);
	K.text(C("cd_hud_toast_text"), f.text, "toast");
	K.fill(C("cd_hud_toast_icon"), f.icon .. (TONE_ICON[f.tone] or "_gold"));
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
	if not H.on then H.ban_key, H.ban_text, H.toasts, H.co_key, H.co = nil, nil, {}, nil, {} end;
	pcall(layout);
	pcall(place_callouts);
	raise_cards(H.on);
	-- callouts follow their units between director ticks
	pcall(function()
		if H.on and not H.co_timer then
			bm:repeat_real_callback(function()
				local ok, err = pcall(place_callouts);
				if not ok and H.logged < 5 then H.logged = H.logged + 1; log("callout error: " .. tostring(err)) end;
			end, CALLOUT_MS, "cd_hud_callouts");
			H.co_timer = true;
		elseif not H.on and H.co_timer then
			bm:remove_real_callback("cd_hud_callouts");
			H.co_timer = nil;
		end;
	end);
	log(H.on and ("HUD on (" .. H.mode .. ")") or "HUD off");
end;

local function update(cd)
	if not H.on then return end;
	H.now = cd.now or H.now;
	local ok, err = pcall(function()
		draw_tide(cd.tide);
		draw_banner(cd);
		draw_toast();
		layout();
		place_callouts();
	end);
	if not ok and H.logged < 5 then H.logged = H.logged + 1; log("update error: " .. tostring(err)) end;
end;

-- tone: "good" (for the player), "bad" or nil; only lines with a symbol become toasts
-- (charges, clashes and volleys are already on the banner when the camera films them)
local function report(text, tone, icon_name)
	if not icon_name then return end;
	H.toasts[#H.toasts + 1] = { text = tostring(text), tone = tone, icon = icon_name, t = H.now };
	while #H.toasts > 4 do table.remove(H.toasts, 1) end;
end;

core:add_listener("cd_hud_click", "ComponentLClickUp", true,
	function(context)
		local id = tostring(context.string);
		if id == "cd_hud_banners" or id == "cd_hud_banners_icon" then
			if CD_DIRECTOR then pcall(CD_DIRECTOR.toggle_banners) end;
			pcall(layout);
			return;
		end;
		if id ~= "cd_hud_mode" and id ~= "cd_hud_mode_icon" then return end;
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
