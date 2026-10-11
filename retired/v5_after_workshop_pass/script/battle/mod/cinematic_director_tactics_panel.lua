--------------------------------------------------------------------------------
-- Cinematic Director: battle tactics panel
--
-- While the tactics engine runs, shows the selected regiment's tactics on the
-- right of the screen: the row it is following right now is highlighted with an
-- arrow, spell rows light up when they cast, and a status line says what the
-- unit is doing. Select a unit (or use < > on the panel) to inspect it; "-"
-- folds the panel down to its title bar, "+" opens it again.
--
-- The panel is created visible and never hidden while the battle runs (folding
-- only shrinks it): components created hidden and shown later never appeared in
-- game, both here and in the campaign editor's old pop-up lists.
--------------------------------------------------------------------------------

local T = CD_TACTICS;
local K = CD_UI;
local LOG_PATH = "cinematic_director_log.txt";

local function log(s)
	if CD_LOG then CD_LOG("[tactics-ui] ", s) end;
end;

local function safe(fn, default)
	local ok, r = pcall(fn);
	if ok then return r end;
	return default;
end;

if not T or not K then
	log("catalogue or UI kit missing - battle tactics panel disabled");
	return;
end;

local W = 440;
local HEAD_H = 64;
local ROW_Y, ROW_STEP, ROW_H = 70, 40, 36;
local CAST_GLOW = 4;		-- seconds a spell row stays lit after casting
local PROBES = false;		-- visibility probes (A/B/C boxes) for diagnosing an unseen panel
local PROBE_SECONDS = 90;

local P = {
	built = false,
	shown = true,		-- expanded (vs folded to the title bar)
	sel = nil,			-- engine entry being shown
	hooked = false,
	logged = 0,
	probes = nil,
	probe_t = nil,
};

local function C(id) return K.get(id) end;
local function engine() return CD_TACTICS_ENGINE end;

local function ability_name(key)
	if not key then return nil end;
	local n = safe(function() return common.get_localised_string("unit_abilities_onscreen_name_" .. key) end, nil);
	if n and n ~= "" then return n end;
	return (tostring(key):gsub("^wh%d?_[%w]+_", ""):gsub("_", " "));
end;

-- screen size in the same space as Position()/MoveTo(). Not the UI root's Bounds():
-- in battle those grow to cover the root's children, so a panel placed from them
-- pushed itself further off-screen on every redraw.
local function screen_size()
	local sw, sh = 1920, 1080;
	pcall(function()
		local w, h = core:get_screen_resolution();
		if w and h and w > 0 and h > 0 then sw, sh = w, h end;
	end);
	return sw, sh;
end;

--------------------------------------------------------------------------------
-- visibility probe (one battle's worth of evidence about what can be seen)
--
-- Three labelled boxes across the top of the screen for the first 90 seconds:
--   A  our panel template, child of the UI root, created visible
--   B  our panel template, created inside the game's own battle HUD
--   C  the game's own scripted-subtitle box with our text
--------------------------------------------------------------------------------

local function probe_box(id, parent, x, y, text)
	local c = K.make(id, "cd_panel", parent);
	if not c then return nil end;
	K.anchor(c, 1, x, y, 300, 56);
	local l = K.make(id .. "_txt", "cd_label", c);
	K.place(l, 12, 8, 276, 40);
	K.text(l, text, "head");
	K.click_through(l);
	K.click_through(c);
	pcall(function() c:PropagatePriority(1600) end);
	K.top(c, true);
	return c;
end;

local function make_probes()
	local rw = screen_size();
	local x0 = math.floor(rw / 2) - 470;
	local out = {};
	out[#out + 1] = probe_box("cd_probe_a", nil, x0, 130, "Tactics probe A");
	local hud = safe(function() return find_uicomponent(K.root(), "hud_battle") end, nil);
	if hud then
		local b = probe_box("cd_probe_b", hud, x0 + 320, 130, "Tactics probe B");
		out[#out + 1] = b;
	else
		log("probe B: hud_battle not found");
	end;
	local ok, err = pcall(function()
		local root = K.root();
		root:CreateComponent("cd_probe_c", "UI/Common UI/scripted_subtitles.twui.xml");
		local c = find_uicomponent(root, "cd_probe_c");
		local t = find_uicomponent(c, "text_child");
		t:SetStateText("Tactics probe C", "");
		t:SetVisible(true);
		t:RegisterTopMost();
		c:SetVisible(true);
		out[#out + 1] = c;
	end);
	if not ok then log("probe C failed: " .. tostring(err)) end;
	P.probes = out;
	P.probe_t = os.clock();
	local sx, sy = safe(function() return core:get_screen_resolution() end, nil);
	local rw2, rh2 = screen_size();
	log(string.format("probes up: screen_resolution=%s,%s root=%s,%s", tostring(sx), tostring(sy), tostring(rw2), tostring(rh2)));
	for _, c in ipairs(out) do
		log("  probe " .. K.describe(c) .. " fromroot=" .. tostring(safe(function() return c:VisibleFromRoot() end, "?")));
	end;
end;

local function end_probes()
	if not P.probes then return end;
	for _, c in ipairs(P.probes) do
		K.top(c, false);
		K.show(c, false);
		local t = safe(function() return find_uicomponent(c, "text_child") end, nil);
		if t then K.top(t, false); K.show(t, false) end;
	end;
	P.probes = nil;
	log("probes removed");
end;

--------------------------------------------------------------------------------
-- build
--------------------------------------------------------------------------------

local function build()
	if P.built then return true end;
	local panel = K.make("cd_bt_panel", "cd_panel");
	if not panel then return false end;
	K.size(panel, W, 300);

	local function lbl(id, style, x, y, w, h)
		local c = K.make(id, "cd_label", panel);
		K.place(c, x, y, w, h);
		K.text(c, "", style);
		K.click_through(c);
		return c;
	end;
	local function btn(id, x, y, w, h, text, tip)
		local c = K.make(id, "cd_button", panel);
		K.place(c, x, y, w, h);
		K.text(c, text, "body_c");
		K.tip(c, tip);
		return c;
	end;

	lbl("cd_bt_name", "head", 16, 10, W - 140, 26);
	lbl("cd_bt_sub", "small", 16, 38, W - 32, 18);
	btn("cd_bt_prev", W - 118, 12, 32, 26, "<", "Previous regiment");
	btn("cd_bt_next", W - 82, 12, 32, 26, ">", "Next regiment");
	btn("cd_bt_close", W - 46, 12, 32, 26, "-", "Fold this panel down to its title bar");
	local line = K.make("cd_bt_line", "cd_fill", panel);
	K.place(line, 12, 62, W - 24, 1);
	K.fill(line, "line");
	K.click_through(line);

	for i = 1, T.MAX_SLOTS + 1 do
		local y = ROW_Y + (i - 1) * ROW_STEP;
		local hl = K.make("cd_bt_hl_" .. i, "cd_fill", panel);
		K.place(hl, 8, y, W - 16, ROW_H);
		K.fill(hl, "active");
		K.click_through(hl);
		local edge = K.make("cd_bt_edge_" .. i, "cd_fill", panel);
		K.place(edge, 8, y, 3, ROW_H);
		K.fill(edge, "gold");
		K.click_through(edge);
		local ar = K.make("cd_bt_arrow_" .. i, "cd_arrow", panel);
		K.place(ar, 14, y + 6, 24, 24);
		K.click_through(ar);
		lbl("cd_bt_num_" .. i, "gold_c", 40, y, 22, ROW_H);
		lbl("cd_bt_txt_" .. i, "body", 68, y, W - 80, ROW_H);
	end;

	local card = K.make("cd_bt_card", "cd_card", panel);
	K.click_through(card);
	lbl("cd_bt_nowcap", "caps_gold", 0, 0, W - 48, 16);
	lbl("cd_bt_now", "para", 0, 0, W - 48, 40);

	pcall(function() panel:PropagatePriority(1500) end);
	K.top(panel, true);
	P.built = true;
	log("battle tactics panel built");
	return true;
end;

--------------------------------------------------------------------------------
-- drawing
--------------------------------------------------------------------------------

local function row_text(t)
	local c, tg, a = T.COND_BY[t[1]], T.TARGET_BY[t[2]], T.ACTION_BY[t[3]];
	if not c or not tg or not a then return "?" end;
	local when = t[1] == "always" and "Always" or c.label;
	local what = a.kind == "-" and a.label or (a.label .. " " .. tg.label:lower());
	return when .. ":  " .. what;
end;

local VERB = {
	attack = "Attacking", charge = "Charging", melee = "Fighting hand to hand with", flank = "Flanking",
	skirmish = "Skirmishing with", approach = "Advancing toward", guard = "Guarding", follow = "Moving to",
	cover = "Shielding", hold = "Holding position", retreat = "Falling back", to_lord = "Falling back to the lord",
	regroup = "Regrouping with the army",
};

local function status_text(e, st)
	if not st.alive then return "This regiment is out of the fight." end;
	local parts = {};
	if st.act then
		local v = VERB[st.act] or st.act;
		local ad = T.ACTION_BY[st.act];
		if (ad and ad.kind == "-") or st.self_target then
			parts[#parts + 1] = v .. ".";
		else
			local who = st.target_key and K.unit_name(st.target_key) or "target";
			parts[#parts + 1] = v .. " " .. who .. (st.hidden and " (not in sight - marching to where it was last seen)." or ".");
		end;
	else
		parts[#parts + 1] = (engine().enemies_left() == 0) and "No enemies left." or "No row applies yet - waiting.";
	end;
	if st.cast_ago and st.cast_ago < 20 then
		parts[#parts + 1] = string.format("Cast %s%s %d s ago.", ability_name(st.cast_key) or "a spell",
			st.cast_tkey and (" on " .. K.unit_name(st.cast_tkey)) or "", math.floor(st.cast_ago));
	end;
	return table.concat(parts, "  ");
end;

local function position(h)
	local sw, sh = screen_size();
	local x = math.max(0, sw - W - 30);
	local y = math.max(60, math.floor(sh * 0.26));
	local panel = C("cd_bt_panel");
	K.size(panel, W, h);
	pcall(function() panel:MoveTo(math.floor(x), math.floor(y)) end);
end;

local function alive_units()
	local out = {};
	for _, e in ipairs(engine().units()) do
		if safe(function() return e.unit:number_of_men_alive() > 0 end, false) then out[#out + 1] = e end;
	end;
	return out;
end;

local function set_row(i, on)
	for _, k in ipairs({ "hl", "edge", "arrow" }) do K.show(C("cd_bt_" .. k .. "_" .. i), on) end;
end;

local function draw()
	local eng = engine();
	if not (eng and eng.running()) then return end;
	if not P.sel then P.sel = alive_units()[1] end;
	local e = P.sel;
	local panel = C("cd_bt_panel");
	K.show(panel, true);

	if not e then
		K.text(C("cd_bt_name"), "Unit Tactics");
		K.text(C("cd_bt_sub"), "No regiment under tactics.");
		position(HEAD_H);
		return;
	end;
	local st = eng.state(e) or {};
	K.text(C("cd_bt_name"), K.unit_name(e.key));
	local list = e.tactics;
	K.text(C("cd_bt_close"), P.shown and "-" or "+");
	K.tip(C("cd_bt_close"), P.shown and "Fold this panel down to its title bar" or "Show this regiment's tactics");

	if not P.shown then
		local ad = st.act and T.ACTION_BY[st.act];
		K.text(C("cd_bt_sub"), st.idx and string.format("Following row %d: %s", st.idx, row_text(list[st.idx])) or status_text(e, st));
		for i = 1, T.MAX_SLOTS + 1 do
			set_row(i, false);
			K.text(C("cd_bt_num_" .. i), "");
			K.text(C("cd_bt_txt_" .. i), "");
		end;
		K.place(C("cd_bt_card"), 10, HEAD_H, 1, 1);
		K.text(C("cd_bt_nowcap"), "");
		K.text(C("cd_bt_now"), "");
		position(HEAD_H);
		return;
	end;

	K.text(C("cd_bt_sub"), string.format("%s%d tactic%s  |  %s", e.rank and ("Rank " .. e.rank .. "  |  ") or "", #list, #list == 1 and "" or "s",
		e.from_campaign and "set in campaign" or "default tactics"));

	local n = math.min(#list, T.MAX_SLOTS);
	local unreach = T.unreachable(list);
	for i = 1, T.MAX_SLOTS + 1 do
		local t, is_default = list[i], false;
		if i > n then t, is_default = (i == n + 1) and st.default or nil, true end;
		local num, txt = C("cd_bt_num_" .. i), C("cd_bt_txt_" .. i);
		if t then
			local active = (not is_default and st.idx == i) or is_default;
			local cast_lit = not is_default and st.cast_row == i and st.cast_ago and st.cast_ago < CAST_GLOW;
			local spell = T.is_cast(t[3]);
			set_row(i, active or cast_lit);
			K.text(num, is_default and "-" or tostring(i), (active or cast_lit) and "gold_c" or "dim_c");
			local s = row_text(t) .. (spell and "  (spell)" or "");
			if is_default then s = "No row applies - default: " .. row_text(t) end;
			K.text(txt, s, (active or cast_lit) and "bright" or (unreach[i] and "dim" or "body"));
			K.tip(txt, T.sentence(t));
		else
			set_row(i, false);
			K.text(num, "");
			K.text(txt, "");
		end;
	end;

	local rows = n + (st.default and 1 or 0);
	local cy = ROW_Y + rows * ROW_STEP + 6;
	K.place(C("cd_bt_card"), 10, cy, W - 20, 62);
	K.place(C("cd_bt_nowcap"), 22, cy + 6, W - 48, 16);
	K.place(C("cd_bt_now"), 22, cy + 22, W - 48, 38);
	K.text(C("cd_bt_nowcap"), "Now");
	K.text(C("cd_bt_now"), status_text(e, st));

	position(cy + 62 + 12);
	-- the first few draws go to the log, in case the panel still can't be seen
	if P.logged < 3 and (P.logged == 0 or os.clock() - (P.log_t or 0) > 10) then
		P.logged, P.log_t = P.logged + 1, os.clock();
		log(string.format("panel: %s fromroot=%s | arrow %d: %s", K.describe(panel), tostring(safe(function() return panel:VisibleFromRoot() end, "?")),
			st.idx or 1, K.describe(C("cd_bt_arrow_" .. (st.idx or 1)))));
	end;
end;

local function safe_draw()
	local ok, err = pcall(draw);
	if not ok then log("draw error: " .. tostring(err)) end;
end;

--------------------------------------------------------------------------------
-- selection
--------------------------------------------------------------------------------

local function select_entry(e)
	if not e then return end;
	if (P.sel_logs or 0) < 8 then P.sel_logs = (P.sel_logs or 0) + 1; log("selected " .. tostring(e.name)) end;
	P.sel = e;
	P.shown = true;
	safe_draw();
end;

-- (called again by the engine when reinforcements join; only new units get hooked)
local function hook_selection()
	P.hooked = true;
	P.hooked_units = P.hooked_units or {};
	local n = 0;
	for _, e in ipairs(engine().units()) do
		if not P.hooked_units[e] then
			P.hooked_units[e] = true;
			local ok = pcall(function()
				bm:register_unit_selection_callback(e.unit, function(u, selected)
					if selected then select_entry(engine().find(u) or e) end;
				end);
			end);
			if ok then n = n + 1 end;
		end;
	end;
	if n > 0 then log("selection hooks on " .. n .. " units") end;
end;

local function step(d)
	local list = alive_units();
	if #list == 0 then return end;
	local cur = 1;
	for i, e in ipairs(list) do if e == P.sel then cur = i end end;
	select_entry(list[(cur - 1 + d) % #list + 1]);
end;

core:add_listener("cd_bt_click", "ComponentLClickUp", true,
	function(context)
		local id = tostring(context.string);
		if not id:find("^cd_bt_") then
			-- a few of the game's own clicks, to learn what unit cards are called in battle
			if (P.other_clicks or 0) < 12 then P.other_clicks = (P.other_clicks or 0) + 1; log("game click: " .. id) end;
			return;
		end;
		log("click: " .. id);
		if id == "cd_bt_prev" then step(-1)
		elseif id == "cd_bt_next" then step(1)
		elseif id == "cd_bt_close" then P.shown = not P.shown; safe_draw() end;
	end, true);

--------------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------------

local function tick()
	local eng = engine();
	if not eng then return end;
	if eng.running() then
		if not P.built then
			local ok, err = pcall(build);
			if not ok then log("build error: " .. tostring(err)) end;
			if PROBES then
				local ok2, err2 = pcall(make_probes);
				if not ok2 then log("probe error: " .. tostring(err2)) end;
			end;
		end;
		if not P.hooked then pcall(hook_selection) end;
	end;
	if P.probes and os.clock() - P.probe_t > PROBE_SECONDS then pcall(end_probes) end;
	if P.built then safe_draw() end;
end;

bm:repeat_real_callback(function() pcall(tick) end, 250, "cd_bt_panel_tick");
core:add_listener("cd_bt_end", "BattleConflictFinished", true, function()
	pcall(end_probes);
	pcall(function() K.show(C("cd_bt_panel"), false) end);
	pcall(function() bm:remove_real_callback("cd_bt_panel_tick") end);
end, true);
log("battle tactics panel loaded");

CD_TACTICS_PANEL = { state = P, draw = draw, select = select_entry, step = step,
	status = function(e) return status_text(e, engine().state(e) or {}) end, rehook = hook_selection };
