--------------------------------------------------------------------------------
-- Cinematic Director: battle tactics panel and paradigm buttons
--
-- While the tactics engine runs:
--   * a compact card on the right shows the selected regiment's tactics: one
--     line per row with a symbol, the row being followed lit gold, spell rows
--     lighting up when they cast, and under the name what the unit is doing
--     ("charging Orc Boyz"). It appears when you click one of your units in
--     the regular view, and in the cinematic view while the mouse is over one
--     of the unit cards (above that card); < > step through the army, "-"
--     folds the card to its title.
--   * top left, the paradigm buttons I-IV switch the whole army to another
--     tactics set. How many are unlocked depends on the highest rank among your
--     generals in the battle; with every general dead or fleeing they lock.
--     Shown only when the generals unlock more than one.
--   * during deployment the card is an editor: click a row, then its When / Do /
--     Target, and pick from the list that opens beside the card (the same
--     choices as the campaign editor). The paradigm buttons pick which set the
--     card shows. Changes last for this battle.
--
-- Everything is created visible and only hidden/shown afterwards: components
-- created hidden and shown later never appeared in game.
--------------------------------------------------------------------------------

local T = CD_TACTICS;
local K = CD_UI;
local LOG_PATH = "cinematic_director_log.txt";

local function log(s)
	local ok, f = pcall(io.open, LOG_PATH, "a");
	if ok and f then
		local t = "";
		pcall(function() t = os.date("%H:%M:%S ") end);
		f:write(t .. "[tactics-ui] " .. tostring(s) .. "\n");
		f:close();
	end;
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

local W = 300;
local HEAD_H = 52;
local ROW_Y, ROW_STEP, ROW_H = 56, 30, 28;
local CAST_GLOW = 4;		-- seconds a spell row stays lit after casting
local PB = 44;				-- paradigm button size
-- deployment editor: the cells of the row being changed, and the picker beside the card
local CELL_STEP, PH = 28, 26;
local PCAT_W, POPT_W, PSTEP, PTOP = 130, 216, 28, 38;
local PW = 10 + PCAT_W + 10 + 2 * POPT_W + 6 + 10;
local MAX_CAT, MAX_OPT = 7, 22;
local CELL_CAP = { c = "When", a = "Do", t = "Target" };

local P = {
	built = false,
	shown = true,		-- expanded (vs folded to the title bar)
	sel = nil,			-- engine entry being shown
	clicked = false,	-- the player has a unit selected: only then is the card shown
	hooked = false,
	logged = 0,
	-- deployment editor
	edit_k = 1,			-- paradigm shown and changed
	erow = nil,			-- row being changed
	ekind = nil,		-- its cell open in the picker: "c" (When), "a" (Do), "t" (Target)
	ecat = nil,			-- picker category (nil: the one holding the current choice)
	opts = nil,			-- options on show in the picker
	hover = nil,		-- cinematic view: the unit card under the mouse { id, e, card }
};

local function C(id) return K.get(id) end;
local function engine() return CD_TACTICS_ENGINE end;

local function ability_name(key)
	if not key then return nil end;
	return T.spell_name and T.spell_name(key) or tostring(key);
end;

-- screen size in the same space as Position()/MoveTo(). Not the UI root's Bounds():
-- in battle those grow to cover the root's children.
local function screen_size()
	local sw, sh = 1920, 1080;
	pcall(function()
		local w, h = core:get_screen_resolution();
		if w and h and w > 0 and h > 0 then sw, sh = w, h end;
	end);
	return sw, sh;
end;

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

local function icon(id, parent, name, x, y, size)
	local c = K.make(id, "cd_icon", parent);
	K.place(c, x, y, size, size);
	K.fill(c, name);
	K.click_through(c);
	return c;
end;

local function btn(id, parent, x, y, w, h, text, tip, style)
	local c = K.make(id, "cd_button", parent);
	K.place(c, x, y, w, h);
	K.text(c, text, style or "body_c");
	K.tip(c, tip);
	return c;
end;

local function build()
	if P.built then return true end;
	local panel = K.make("cd_bt_panel", "cd_panel");
	if not panel then return false end;
	K.size(panel, W, 300);

	icon("cd_bt_icon", panel, "tactic_gold", 10, 10, 30);
	lbl("cd_bt_name", panel, "head", 46, 4, W - 46 - 102, 24);
	lbl("cd_bt_sub", panel, "small", 46, 26, W - 56, 20);
	btn("cd_bt_prev", panel, W - 100, 8, 28, 24, "<", "Previous regiment");
	btn("cd_bt_next", panel, W - 70, 8, 28, 24, ">", "Next regiment");
	btn("cd_bt_close", panel, W - 40, 8, 28, 24, "-", "Fold");
	local line = K.make("cd_bt_line", "cd_fill", panel);
	K.place(line, 10, HEAD_H, W - 20, 1);
	K.fill(line, "line");
	K.click_through(line);

	for i = 1, T.MAX_SLOTS + 1 do
		local y = ROW_Y + (i - 1) * ROW_STEP;
		-- deployment: the row is a button
		local rb = K.make("cd_bt_rowb_" .. i, "cd_row", panel);
		K.place(rb, 6, y, W - 12, ROW_H);
		K.text(rb, "", "body");
		K.show(rb, false);
		local hl = K.make("cd_bt_hl_" .. i, "cd_fill", panel);
		K.place(hl, 6, y, W - 12, ROW_H);
		K.fill(hl, "active");
		K.click_through(hl);
		local edge = K.make("cd_bt_edge_" .. i, "cd_fill", panel);
		K.place(edge, 6, y, 3, ROW_H);
		K.fill(edge, "gold");
		K.click_through(edge);
		lbl("cd_bt_num_" .. i, panel, "gold_c", 10, y, 18, ROW_H);
		icon("cd_bt_ri_" .. i, panel, "tactic_dim", 30, y + 4, 20);
		local t = lbl("cd_bt_txt_" .. i, panel, "body", 54, y, W - 62, ROW_H);
		pcall(function() t:SetInteractive(true) end);		-- for the tooltip
	end;

	for _, k in ipairs({ "c", "a", "t" }) do
		local c = K.make("cd_bt_cell_" .. k, "cd_row", panel);
		K.place(c, 10, ROW_Y, W - 20, PH);
		K.text(c, "", "body");
		K.show(c, false);
	end;

	-- deployment picker
	local pick = K.make("cd_bt_pick", "cd_panel");
	if pick then
		K.size(pick, PW, 200);
		lbl("cd_bt_ptitle", pick, "head", 12, 6, PW - 60, 24);
		btn("cd_bt_pclose", pick, PW - 40, 6, 28, 24, "x", "Close");
		for j = 1, MAX_CAT do
			local c = K.make("cd_bt_pcat_" .. j, "cd_row", pick);
			K.place(c, 10, PTOP + (j - 1) * PSTEP, PCAT_W, PH);
			K.text(c, "", "body");
		end;
		for k = 1, MAX_OPT do
			local c = K.make("cd_bt_opt_" .. k, "cd_row", pick);
			K.place(c, 20 + PCAT_W, PTOP + (k - 1) * PSTEP, POPT_W, PH);
			K.text(c, "", "body");
		end;
		pcall(function() pick:PropagatePriority(1500) end);
		K.top(pick, true);
		K.show(pick, false);
	end;

	-- paradigm strip
	local strip = K.make("cd_para", "cd_panel");
	if strip then
		K.size(strip, 12 + T.MAX_PARADIGMS * (PB + 6), PB + 12);
		for k = 1, T.MAX_PARADIGMS do
			btn("cd_para_" .. k, strip, 6 + (k - 1) * (PB + 6), 6, PB, PB, T.PARADIGM_NAMES[k], "", "big_c");
		end;
		pcall(function() strip:PropagatePriority(1500) end);
		K.top(strip, true);
	end;

	pcall(function() panel:PropagatePriority(1500) end);
	K.top(panel, true);
	P.built = true;
	log("battle tactics panel built");
	return true;
end;

--------------------------------------------------------------------------------
-- drawing
--------------------------------------------------------------------------------

-- one short line: "Hammer and anvil" / "HP<25%: Fall back to our lord" / "Attack > enemy cavalry"
-- (the full sentence is in the tooltip)
local ROW_CHARS = 34;
local function row_text(t)
	local c, tg, a = T.COND_BY[t[1]], T.TARGET_BY[t[2]], T.ACTION_BY[t[3]];
	if not c or not tg or not a then return "?" end;
	local when = T.COND_SHORT[t[1]] or c.label;
	if when ~= "" then when = when .. ": " end;
	local s = when .. a.label;
	if a.kind ~= "-" and t[2] ~= "self" and t[2] ~= "nearest_enemy" then
		local full = s .. " > " .. tg.label:lower();
		if #full <= ROW_CHARS then s = full end;
	end;
	if #s > ROW_CHARS then s = s:sub(1, ROW_CHARS - 3) .. "..." end;
	return s;
end;

local function status_text(e, st)
	if not st.alive then return "out of the fight" end;
	if st.cast_ago and st.cast_ago < CAST_GLOW then
		return "cast " .. tostring(ability_name(st.cast_key) or "a spell")
			.. (st.cast_tkey and (" on " .. K.unit_name(st.cast_tkey)) or "");
	end;
	if not st.act then
		return (engine().enemies_left() == 0) and "no enemies left" or "waiting";
	end;
	local ad = T.ACTION_BY[st.act];
	local who;
	if not (ad and ad.kind == "-") and not st.self_target and st.target_key then who = K.unit_name(st.target_key) end;
	if st.phase and st.target_key then who = K.unit_name(st.target_key) end;
	local s = T.doing(st.act, st.phase, who) or st.act;
	if st.hidden then s = s .. " (out of sight)" end;
	return s;
end;

local function position(h)
	local sw, sh = screen_size();
	local x = math.max(0, sw - W - 24);
	local y = math.max(60, math.floor(sh * 0.26));
	local card = P.hover and P.hover.shown and P.hover.card;
	if card then
		local ok, cx, cy, cw = pcall(function()
			local ax, ay = card:Position();
			local w = card:Bounds();
			return ax, ay, w;
		end);
		if ok and cx and cy then
			x = math.max(8, math.min(sw - W - 8, cx + (cw or 0) / 2 - W / 2));
			y = math.max(8, cy - h - 8);
		end;
	end;
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
	for _, k in ipairs({ "hl", "edge" }) do K.show(C("cd_bt_" .. k .. "_" .. i), on) end;
end;

local function clear_row(i)
	set_row(i, false);
	K.show(C("cd_bt_ri_" .. i), false);
	K.text(C("cd_bt_num_" .. i), "");
	K.text(C("cd_bt_txt_" .. i), "");
	K.tip(C("cd_bt_txt_" .. i), "");
end;

local function draw_paradigms()
	local strip = C("cd_para");
	if not strip then return end;
	local p = engine().paradigms();
	-- only worth showing when the generals unlock more than one (or did, before they fell)
	local show = p.seen > 1;
	K.show(strip, show);
	if not show then return end;
	local sw, sh = screen_size();
	pcall(function() strip:MoveTo(16, math.floor(sh * 0.12)) end);
	if engine().deploying and engine().deploying() then
		for k = 1, T.MAX_PARADIGMS do
			local b = C("cd_para_" .. k);
			if k > math.max(1, p.n) then
				K.state(b, "inactive");
				K.text(b, T.PARADIGM_NAMES[k], "dim_c");
				K.tip(b, string.format("Paradigm %s unlocks with a general of rank %d in the battle.", T.PARADIGM_NAMES[k], T.PARADIGM_RANKS[k]));
			elseif k == P.edit_k then
				K.state(b, "selected");
				K.text(b, T.PARADIGM_NAMES[k], "gold_c");
				K.tip(b, string.format("Paradigm %s: the tactics card shows this set; click a unit, then a row to change it. The battle starts in paradigm I.", T.PARADIGM_NAMES[k]));
			else
				K.state(b, "active");
				K.text(b, T.PARADIGM_NAMES[k], "big_c");
				K.tip(b, string.format("Paradigm %s: show this set on the tactics card to change it.", T.PARADIGM_NAMES[k]));
			end;
		end;
		return;
	end;
	for k = 1, T.MAX_PARADIGMS do
		local b = C("cd_para_" .. k);
		local tip;
		if p.n == 0 then
			K.state(b, "inactive");
			K.text(b, T.PARADIGM_NAMES[k], k == p.cur and "gold_c" or "dim_c");
			tip = "Every general is down or fleeing: paradigm shifting is disabled.";
		elseif k > p.n then
			K.state(b, "inactive");
			K.text(b, T.PARADIGM_NAMES[k], "dim_c");
			tip = string.format("Paradigm %s unlocks with a general of rank %d in the battle.", T.PARADIGM_NAMES[k], T.PARADIGM_RANKS[k]);
		elseif k == p.cur then
			K.state(b, "selected");
			K.text(b, T.PARADIGM_NAMES[k], "gold_c");
			tip = string.format("Paradigm %s: the army is using this tactics set.", T.PARADIGM_NAMES[k]);
		elseif p.cooldown > 0 then
			K.state(b, "inactive");
			K.text(b, T.PARADIGM_NAMES[k], "dim_c");
			tip = string.format("Paradigm %s: ready in %d s.", T.PARADIGM_NAMES[k], math.ceil(p.cooldown));
		else
			K.state(b, "active");
			K.text(b, T.PARADIGM_NAMES[k], "big_c");
			tip = string.format("Paradigm %s: switch the whole army to this tactics set.%s", T.PARADIGM_NAMES[k],
				p.custom and "" or " (Set paradigms per unit in the campaign tactics editor; unedited ones copy paradigm I.)");
		end;
		K.tip(b, tip);
	end;
end;

-- the rows the card shows: during deployment the paradigm picked on the strip
local function edit_list(e)
	return (e.sets and e.sets[P.edit_k]) or e.tactics;
end;

-- When / Do / Target of the row being changed, under the rows; returns the card's height
local function draw_cells(list, y, deploy)
	local t = deploy and P.erow and list[P.erow];
	for _, k in ipairs({ "c", "a", "t" }) do K.show(C("cd_bt_cell_" .. k), t and true or false) end;
	if not t then return y end;
	local ad = T.ACTION_BY[t[3]];
	local vals = { c = T.COND_BY[t[1]], a = ad, t = T.TARGET_BY[t[2]] };
	y = y + 2;
	for _, k in ipairs({ "c", "a", "t" }) do
		local c = C("cd_bt_cell_" .. k);
		K.place(c, 10, y, W - 20, PH);
		local none = k == "t" and ad and ad.kind == "-";
		local s = CELL_CAP[k] .. ": " .. (none and "-" or (vals[k] and vals[k].label or "?"));
		if #s > ROW_CHARS + 4 then s = s:sub(1, ROW_CHARS + 1) .. "..." end;
		K.state(c, none and "inactive" or (P.ekind == k and "selected" or "active"));
		K.text(c, s, none and "dim" or (P.ekind == k and "gold" or "body"));
		K.tip(c, none and "This action needs no target." or string.format("Change the %s of row %d.", CELL_CAP[k]:lower(), P.erow));
		y = y + CELL_STEP;
	end;
	return y + 4;
end;

-- choices for a cell, as in the campaign editor: { { category, { {id, label, ...}, ... } }, ... } and the id chosen
local function choices(e, kind, t)
	if kind == "c" then return T.categories(T.CONDITIONS, 3), t[1] end;
	if kind == "a" then
		local cats = T.categories(T.ACTIONS, 4);
		if e.role == "hero" and e.cqi then
			local sp = T.spell_entries(e.cqi);
			if #sp > 0 then cats[#cats + 1] = { "Own spells", sp } end;
		end;
		return cats, t[3];
	end;
	if kind == "t" then
		local need = T.ACTION_BY[t[3]] and T.ACTION_BY[t[3]].kind;
		if not need or need == "-" then return {}, nil end;
		return T.categories(T.TARGETS, 4, function(x) return x[3] == need end), t[2];
	end;
	return {}, nil;
end;

local function hide_pick() K.show(C("cd_bt_pick"), false); P.opts = nil end;

local function draw_picker(e, list, deploy)
	local pick = C("cd_bt_pick");
	if not pick then return end;
	local t = deploy and P.erow and P.ekind and list[P.erow];
	local cats, cur;
	if t then cats, cur = choices(e, P.ekind, t) end;
	if not t or #cats == 0 then hide_pick(); return end;
	K.show(pick, true);
	local j = P.ecat;
	if not j or not cats[j] then
		j = 1;
		for jj, g in ipairs(cats) do
			for _, x in ipairs(g[2]) do if x[1] == cur then j = jj end end;
		end;
		P.ecat = j;
	end;
	K.text(C("cd_bt_ptitle"), string.format("%s for row %d - %s", CELL_CAP[P.ekind], P.erow, K.unit_name(e.key)));
	for k = 1, MAX_CAT do
		local c, g = C("cd_bt_pcat_" .. k), cats[k];
		K.show(c, g ~= nil);
		if g then
			K.state(c, k == j and "selected" or "active");
			K.text(c, g[1], k == j and "gold" or "body");
		end;
	end;
	local group = cats[j][2];
	local nrow = math.max(1, math.ceil(math.min(#group, MAX_OPT) / 2));
	P.opts = group;
	for k = 1, MAX_OPT do
		local c, x = C("cd_bt_opt_" .. k), group[k];
		K.show(c, x ~= nil and k <= MAX_OPT);
		if x then
			-- two columns, top to bottom
			local col, r = math.floor((k - 1) / nrow), (k - 1) % nrow;
			local at = col * 100 + r;
			if P.opt_at == nil then P.opt_at = {} end;
			if P.opt_at[k] ~= at then
				P.opt_at[k] = at;
				K.place(c, 20 + PCAT_W + col * (POPT_W + 6), PTOP + r * PSTEP, POPT_W, PH);
			end;
			local is_cur = x[1] == cur;
			K.state(c, is_cur and "selected" or "active");
			K.text(c, x[2], is_cur and "gold" or "body");
			K.tip(c, x[2] .. ": " .. T.help(x[1]));
		end;
	end;
	local ph = PTOP + math.max(math.min(#cats, MAX_CAT), nrow) * PSTEP + 8;
	if P.pick_h ~= ph then P.pick_h = ph; K.size(pick, PW, ph) end;
	local sw, sh = screen_size();
	local px = math.max(0, sw - W - 24 - PW - 8);
	local py = math.max(60, math.floor(sh * 0.26));
	pcall(function() pick:MoveTo(math.floor(px), math.floor(py)) end);
end;

-- cinematic view: the unit card under the mouse and its unit (cards are hud_battle > battle_orders > ... >
-- cards_panel > review_DY > <card>; a card's CcoBattleUnit context id is its unit's unique_ui_id)
local function cards_holder()
	return safe(function() return find_uicomponent(core:get_ui_root(), "battle_orders", "cards_panel", "review_DY") end, nil);
end;

local function hovered()
	local h = P.hover;
	if not h then return nil end;
	local holder = cards_holder();
	local card = holder and safe(function() return find_child_uicomponent(holder, h.id) end, nil);
	if not card and holder then
		-- a click gives the unit's id: find its card by context
		for i = 0, safe(function() return holder:ChildCount() end, 0) - 1 do
			local c = safe(function() return UIComponent(holder:Find(i)) end, nil);
			if c and tostring(safe(function() return c:GetContextObjectId("CcoBattleUnit") end, "")) == h.id then card = c end;
		end;
	end;
	if not card then return nil end;
	h.card = card;
	if h.e == nil then
		local cid = safe(function() return card:GetContextObjectId("CcoBattleUnit") end, nil);
		h.e = false;
		for _, e in ipairs(engine().units()) do
			local u = tostring(safe(function() return e.unit:unique_ui_id() end, ""));
			if (cid and u == tostring(cid)) or u == h.id then h.e = e end;
		end;
		if (P.hover_logs or 0) < 6 then
			P.hover_logs = (P.hover_logs or 0) + 1;
			log(string.format("card hover: card %s, unit context %s -> %s", tostring(h.id), tostring(cid), h.e and h.e.name or "not one of ours"));
		end;
	end;
	return h.e or nil;
end;

local function draw()
	local eng = engine();
	local deploy = eng and eng.deploying and eng.deploying();
	if not (eng and (eng.running() or deploy)) then return end;
	pcall(draw_paradigms);
	local panel = C("cd_bt_panel");
	-- the cinematic doesn't need it; in the regular view only once a unit is clicked
	local filming = CD_DIRECTOR and CD_DIRECTOR.active and CD_DIRECTOR.active();
	if filming then P.clicked = false end;
	if not deploy then P.erow, P.ekind, P.edit_k = nil, nil, 1 end;
	local hov = filming and hovered();
	if P.hover then P.hover.shown = hov and true or false end;
	if not P.clicked and not hov then K.show(panel, false); hide_pick(); return end;
	if not P.sel then P.sel = alive_units()[1] end;
	local e = hov or P.sel;
	K.show(panel, true);

	if not e then
		K.text(C("cd_bt_name"), "Tactics");
		K.text(C("cd_bt_sub"), "no regiment under tactics");
		for i = 1, T.MAX_SLOTS + 1 do clear_row(i) end;
		draw_cells({}, 0, false);
		hide_pick();
		position(HEAD_H + 4);
		return;
	end;
	local st = eng.state(e) or {};
	local p = eng.paradigms();
	if deploy and P.edit_k > math.max(1, p.n) then P.edit_k = 1 end;
	K.text(C("cd_bt_name"), K.unit_name(e.key));
	if deploy then
		K.text(C("cd_bt_sub"), (p.seen > 1 and ("Paradigm " .. T.PARADIGM_NAMES[P.edit_k] .. ": ") or "Deployment: ") .. "click a row to change it");
	else
		K.text(C("cd_bt_sub"), status_text(e, st));
	end;
	local ic = st.alive and (T.icon(st.act, st.phase) .. "_gold") or "skull_dim";
	if P.icon ~= ic then P.icon = ic; K.fill(C("cd_bt_icon"), ic) end;
	K.text(C("cd_bt_close"), P.shown and "-" or "+");
	K.tip(C("cd_bt_close"), P.shown and "Fold" or "Show this regiment's tactics");
	K.tip(C("cd_bt_name"), string.format("%s%s, %d tactics%s", e.rank and ("Rank " .. e.rank .. ", ") or "", e.role,
		#e.tactics, p.seen > 1 and (", paradigm " .. T.PARADIGM_NAMES[p.cur]) or ""));

	if not P.shown and not hov then
		for i = 1, T.MAX_SLOTS + 1 do clear_row(i); K.show(C("cd_bt_rowb_" .. i), false) end;
		draw_cells({}, 0, false);
		hide_pick();
		position(HEAD_H + 4);
		return;
	end;

	local list = deploy and edit_list(e) or e.tactics;
	local n = math.min(#list, T.MAX_SLOTS);
	if P.erow and P.erow > n then P.erow, P.ekind = nil, nil end;
	local unreach = T.unreachable(list);
	for i = 1, T.MAX_SLOTS + 1 do
		local t, is_default = list[i], false;
		if i > n then t, is_default = (i == n + 1 and not deploy) and st.default or nil, true end;
		local rb = C("cd_bt_rowb_" .. i);
		K.show(rb, deploy and t ~= nil and not is_default);
		if t then
			local active, cast_lit;
			if deploy then
				active, cast_lit = (i == P.erow), false;
				K.state(rb, "active");
			else
				active = (not is_default and st.idx == i) or is_default;
				cast_lit = not is_default and st.cast_row == i and st.cast_ago and st.cast_ago < CAST_GLOW;
			end;
			local lit = active or cast_lit;
			set_row(i, lit);
			K.show(C("cd_bt_ri_" .. i), true);
			K.fill(C("cd_bt_ri_" .. i), T.icon(t[3]) .. (lit and "_gold" or "_dim"));
			K.text(C("cd_bt_num_" .. i), is_default and "-" or tostring(i), lit and "gold_c" or "dim_c");
			K.text(C("cd_bt_txt_" .. i), row_text(t), lit and "bright" or (unreach[i] and "dim" or "body"));
			K.tip(C("cd_bt_txt_" .. i), (is_default and "No row applies - default: " or "") .. T.sentence(t) .. "\n" .. T.help(t[3])
				.. (deploy and "\nClick to change this row." or ""));
		else
			clear_row(i);
		end;
	end;
	if deploy and P.dlog ~= e then
		P.dlog = e;
		log(string.format("deployment card: %s, %d rows, row buttons %s, %s", e.name, n,
			tostring(safe(function() return C("cd_bt_rowb_1"):Visible() end, "?")), K.describe(panel)));
	end;
	local rows = n + ((st.default and not deploy) and 1 or 0);
	position(draw_cells(list, ROW_Y + rows * ROW_STEP + 6, deploy));
	draw_picker(e, list, deploy);

	if P.logged < 2 and (P.logged == 0 or os.clock() - (P.log_t or 0) > 10) then
		P.logged, P.log_t = P.logged + 1, os.clock();
		log(string.format("panel: %s fromroot=%s", K.describe(panel), tostring(safe(function() return panel:VisibleFromRoot() end, "?"))));
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
	if P.sel ~= e then P.erow, P.ekind, P.ecat = nil, nil, nil end;
	P.sel = e;
	P.shown = true;
	safe_draw();
end;

local function hook_selection()
	if P.hooked then return end;
	P.hooked = true;
	local n = 0;
	for _, e in ipairs(engine().units()) do
		local ok = pcall(function()
			bm:register_unit_selection_callback(e.unit, function(u, selected)
				pcall(function()
					local me = engine().find(u) or e;
					local filming = CD_DIRECTOR and CD_DIRECTOR.active and CD_DIRECTOR.active();
					if (P.sel_logs or 0) < 20 then P.sel_logs = (P.sel_logs or 0) + 1; log("selection: " .. tostring(me.name) .. " " .. tostring(selected) .. (filming and " (filming)" or "")) end;
					if filming then
						-- cinematic view: clicking a unit card shows its card above the unit card until it is deselected
						local id = tostring(safe(function() return me.unit:unique_ui_id() end, ""));
						if selected then P.hover = { id = id, src = "click" }
						elseif P.hover and P.hover.src == "click" and P.hover.id == id then P.hover = nil end;
						safe_draw();
					elseif selected then
						P.clicked = true;
						select_entry(me);
					elseif P.sel == me then
						P.clicked = false;
						safe_draw();
					end;
				end);
			end);
		end);
		if ok then n = n + 1 end;
	end;
	log("selection hooks on " .. n .. " units");
end;

local function step(d)
	local list = alive_units();
	if #list == 0 then return end;
	local cur = 1;
	for i, e in ipairs(list) do if e == P.sel then cur = i end end;
	select_entry(list[(cur - 1 + d) % #list + 1]);
end;

-- deployment editing
local NEXT = { c = "a", a = "t" };

local function pick_row(i)
	if not (engine().deploying and engine().deploying()) then return end;
	if P.erow == i and P.ekind then P.ekind = nil
	else P.erow, P.ekind, P.ecat = i, "c", nil end;
	safe_draw();
end;

local function apply(k)
	local e, eng = P.sel, engine();
	local x = P.opts and P.opts[k];
	if not (e and x and eng.deploying and eng.deploying() and P.erow and P.ekind) then return end;
	local rows = {};
	for i, t in ipairs(edit_list(e)) do rows[i] = { t[1], t[2], t[3] } end;
	local t = rows[P.erow];
	if not t then return end;
	if P.ekind == "c" then
		t[1] = x[1];
	elseif P.ekind == "a" then
		t[3] = x[1];
		-- keep the target fitting the new action
		local need = T.ACTION_BY[x[1]].kind;
		local tg = T.TARGET_BY[t[2]];
		if need == "-" then t[2] = "self"
		elseif not tg or tg.kind ~= need then t[2] = (need == "e") and "nearest_enemy" or "ally_lord" end;
	else
		t[2] = x[1];
	end;
	if not eng.set_rows(e, P.edit_k, rows) then log("edit refused for " .. tostring(e.name)); return end;
	-- on to the next cell of the row (When -> Do -> Target)
	local nk = NEXT[P.ekind];
	if nk == "t" and T.ACTION_BY[t[3]].kind == "-" then nk = nil end;
	P.ekind, P.ecat = nk, nil;
	safe_draw();
end;

local function paradigm(k)
	local eng = engine();
	if eng and eng.deploying and eng.deploying() then
		local p = eng.paradigms();
		if k and k >= 1 and k <= math.max(1, p.n) then P.edit_k = k end;
		safe_draw();
		return;
	end;
	if not (eng and eng.paradigm) then return end;
	local ok, why = eng.paradigm(k);
	if not ok then log("paradigm " .. tostring(k) .. " refused: " .. tostring(why)) end;
	safe_draw();
end;

-- real seconds (the director's clock; os.clock is processor time)
local function now()
	local t = CD_DIRECTOR and CD_DIRECTOR.clock and safe(CD_DIRECTOR.clock, nil);
	return t or os.clock();
end;

-- the card a hovered component belongs to: itself or the ancestor directly under review_DY
local function card_of(c)
	for _ = 1, 10 do
		if not c then return nil end;
		local p = UIComponent(c:Parent());
		if not p then return nil end;
		if p:Id() == "review_DY" then return c end;
		c = p;
	end;
	return nil;
end;

-- hover tracking only while filming; the card under the mouse is looked up again on each draw
core:add_listener("cd_bt_card_on", "ComponentMouseOn", true,
	function(context)
		pcall(function()
			if not (CD_DIRECTOR and CD_DIRECTOR.active and CD_DIRECTOR.active()) then P.hover = nil; return end;
			if (P.on_logs or 0) < 25 then P.on_logs = (P.on_logs or 0) + 1; log("mouse-over event: " .. tostring(context.string)) end;
			if (P.chain_logs or 0) < 15 then
				P.chain_logs = (P.chain_logs or 0) + 1;
				local ids, c = {}, UIComponent(context.component);
				for _ = 1, 8 do
					if not c then break end;
					ids[#ids + 1] = tostring(safe(function() return c:Id() end, "?"));
					c = safe(function() return UIComponent(c:Parent()) end, nil);
				end;
				local cid = safe(function() return UIComponent(context.component):GetContextObjectId("CcoBattleUnit") end, nil);
				log("hover while filming: " .. table.concat(ids, " < ") .. " (unit context " .. tostring(cid) .. ")");
			end;
			local card = card_of(UIComponent(context.component));
			local id = card and card:Id();
			if id then
				if not (P.hover and P.hover.id == id) then P.hover = { id = id, src = "event" } end;
				P.hover.leaving, P.hover.on_t = nil, now();
			elseif P.hover and P.hover.src == "event" then
				P.hover = nil;
			end;
			safe_draw();
		end);
	end, true);

-- leaving a card: cleared on the next tick unless the mouse went onto one of its parts (that "on" clears leaving)
core:add_listener("cd_bt_card_off", "ComponentMouseOff", true,
	function(context)
		pcall(function()
			-- an "off" in the same moment as the "on" is the mouse moving between parts of the card
			if P.hover and P.hover.src == "event" and now() - (P.hover.on_t or 0) > 0.03 then P.hover.leaving = true end;
		end);
	end, true);

-- a click on one of our components, from the click event or from its button state (poll_clicks); the
-- same click seen both ways counts once
local LAST_CLICK = {};
local function handle(id, src)
	local t, last = now(), LAST_CLICK[id];
	if last and last.src ~= src and t - last.t < 0.4 and t >= last.t then return end;
	LAST_CLICK[id] = { t = t, src = src };
	if (P.click_logs or 0) < 40 then
		P.click_logs = (P.click_logs or 0) + 1;
		log("click " .. id .. " (" .. src .. (engine().deploying and engine().deploying() and ", deployment" or "") .. ")");
	end;
	local k = id:match("^cd_para_(%d)$");
	if k then pcall(paradigm, tonumber(k)); return end;
	pcall(function()
			local r = id:match("^cd_bt_rowb_(%d)$") or id:match("^cd_bt_txt_(%d)$");
			local cell = id:match("^cd_bt_cell_(%a)$");
			local cat = id:match("^cd_bt_pcat_(%d)$");
			local opt = id:match("^cd_bt_opt_(%d+)$");
			if r then pick_row(tonumber(r))
			elseif cell then
				if P.ekind == cell then P.ekind = nil else P.ekind, P.ecat = cell, nil end;
				safe_draw();
			elseif cat then P.ecat = tonumber(cat); safe_draw()
			elseif opt then apply(tonumber(opt))
			elseif id == "cd_bt_pclose" then P.ekind = nil; safe_draw()
			elseif id == "cd_bt_prev" then step(-1)
			elseif id == "cd_bt_next" then step(1)
			elseif id == "cd_bt_close" then P.shown = not P.shown; safe_draw() end;
	end);
end;

core:add_listener("cd_bt_click", "ComponentLClickUp", true,
	function(context)
		pcall(function()
			local id = tostring(context.string);
			if (P.ev_logs or 0) < 25 then P.ev_logs = (P.ev_logs or 0) + 1; log("click event: " .. id) end;
			if id:find("^cd_para_%d$") or id:find("^cd_bt_") then handle(id, "event") end;
		end);
	end, true);

-- In game the click events never arrived for the card's rows and buttons (they did for the HUD's own
-- buttons), though the rows took their hover look. So clicks are also read from the button states:
-- "down" then "hover" (or "selected_down" then "selected_hover") is a click.
local PRESS = {};
local function clickables()
	local ids = { "cd_bt_prev", "cd_bt_next", "cd_bt_close", "cd_bt_pclose" };
	for i = 1, T.MAX_SLOTS + 1 do ids[#ids + 1] = "cd_bt_rowb_" .. i end;
	for _, k in ipairs({ "c", "a", "t" }) do ids[#ids + 1] = "cd_bt_cell_" .. k end;
	for j = 1, MAX_CAT do ids[#ids + 1] = "cd_bt_pcat_" .. j end;
	for k = 1, MAX_OPT do ids[#ids + 1] = "cd_bt_opt_" .. k end;
	for k = 1, T.MAX_PARADIGMS do ids[#ids + 1] = "cd_para_" .. k end;
	return ids;
end;
local CLICKABLE;

local function poll_clicks()
	if not P.built then return end;
	CLICKABLE = CLICKABLE or clickables();
	for _, id in ipairs(CLICKABLE) do
		local c = C(id);
		local st = c and K.visible(c) and safe(function() return c:CurrentState() end, nil);
		if st then
			if st == "down" or st == "selected_down" then
				PRESS[id] = true;
			elseif PRESS[id] then
				PRESS[id] = nil;
				if st == "hover" or st == "selected_hover" or st == "selected" then handle(id, "state") end;
			end;
		else
			PRESS[id] = nil;
		end;
	end;
end;

-- cinematic view: the card under the mouse, also read from the cards' states (mouse-over events never
-- arrived while filming): a card, or one of its parts, in a state with "hover" in its name
local CARD_STATES = {};
local function poll_cards()
	if not (CD_DIRECTOR and CD_DIRECTOR.active and CD_DIRECTOR.active()) then
		P.hover = nil;
		return;
	end;
	local holder = cards_holder();
	if not holder then return end;
	local found, picked;
	for i = 0, safe(function() return holder:ChildCount() end, 0) - 1 do
		local card = safe(function() return UIComponent(holder:Find(i)) end, nil);
		if card then
			local id = tostring(safe(function() return card:Id() end, "?"));
			local parts = { card };
			for j = 0, safe(function() return card:ChildCount() end, 0) - 1 do
				local ch = safe(function() return UIComponent(card:Find(j)) end, nil);
				if ch then parts[#parts + 1] = ch end;
			end;
			for _, c in ipairs(parts) do
				local st = tostring(safe(function() return c:CurrentState() end, ""));
				local key = id .. "/" .. tostring(safe(function() return c:Id() end, "?"));
				if CARD_STATES[key] ~= st then
					if CARD_STATES[key] ~= nil and (P.cs_logs or 0) < 40 then
						P.cs_logs = (P.cs_logs or 0) + 1;
						log("card state: " .. key .. " " .. tostring(CARD_STATES[key]) .. " -> " .. st);
					end;
					CARD_STATES[key] = st;
				end;
				local l = st:lower();
				if l:find("hover") then found = id elseif l:find("selected") then picked = picked or id end;
			end;
		end;
	end;
	if found then
		if not (P.hover and P.hover.id == found) then P.hover = { id = found, src = "state" } end;
	elseif picked then
		if not (P.hover and P.hover.id == picked) then P.hover = { id = picked, src = "sel" } end;
	elseif P.hover and (P.hover.src == "state" or P.hover.src == "sel") then
		P.hover = nil;
	end;
end;

bm:repeat_real_callback(function()
	pcall(poll_clicks);
	P.pc = (P.pc or 0) + 1;
	if P.pc % 2 == 0 then
		local had = P.hover and P.hover.id;
		pcall(poll_cards);
		if (P.hover and P.hover.id) ~= had then safe_draw() end;
	end;
end, 50, "cd_bt_poll");

--------------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------------

local function tick()
	local eng = engine();
	if not eng then return end;
	if eng.running() or (eng.deploying and eng.deploying()) then
		if not P.built then
			local ok, err = pcall(build);
			if not ok then log("build error: " .. tostring(err)) end;
		end;
		if not P.hooked then pcall(hook_selection) end;
	end;
	if P.hover and P.hover.leaving then P.hover = nil end;
	if P.built then safe_draw() end;
end;

bm:repeat_real_callback(function() pcall(tick) end, 250, "cd_bt_panel_tick");
core:add_listener("cd_bt_end", "BattleConflictFinished", true, function()
	pcall(function() K.show(C("cd_bt_panel"), false) end);
	pcall(function() K.show(C("cd_para"), false) end);
	pcall(function() bm:remove_real_callback("cd_bt_panel_tick") end);
	pcall(function() bm:remove_real_callback("cd_bt_poll") end);
end, true);
log("battle tactics panel loaded");

CD_TACTICS_PANEL = { state = P, draw = draw, select = select_entry, step = step, paradigm = paradigm, apply = apply, pick_row = pick_row,
	status = function(e) return status_text(e, engine().state(e) or {}) end };
