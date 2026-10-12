--------------------------------------------------------------------------------
-- Cinematic Director: campaign tactics editor (v4)
--
-- Select one of your armies and click "Battle Tactics" above its unit cards.
-- The editor lists every regiment of the army on the left; pick one and edit
-- its tactics on the right. Each row reads WHEN -> DO -> TARGET. Clicking a
-- cell opens it in the browser below the rows: a column of groups on the left,
-- the choices in the chosen group on the right. Picking a choice moves on to
-- the next cell of the row. "Presets..." opens the presets in the same browser.
-- Every component is built once and stays in place; clicks only change text
-- and states (pop-up lists created on demand never appeared in game).
-- Tactics are stored in the save game per unit (by unit cqi) and exported to
-- cinematic_director_tactics.txt before every battle.
--------------------------------------------------------------------------------

local T = CD_TACTICS;
local K = CD_UI;
local LOG_PATH = "cinematic_director_log.txt";
local EXPORT_PATH = "cinematic_director_tactics.txt";
local SAVE_KEY = "cd_tactics_v1";

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

if not T or not K then
	log("catalogue or UI kit missing - tactics editor disabled");
	return;
end;
K.log = log;

--------------------------------------------------------------------------------
-- storage: cqi -> "c,t,a;c,t,a" for paradigm I, "<cqi>p<k>" for paradigms II-IV
-- (a paradigm with no entry of its own copies paradigm I)
--------------------------------------------------------------------------------

local store = {};

local function skey(cqi, p) return (p and p > 1) and (cqi .. "p" .. p) or cqi end;

local function load_store()
	store = {};
	local s = safe(function() return cm:get_saved_value(SAVE_KEY) end, nil);
	if type(s) == "string" then
		for k, tac in s:gmatch("(%w+)=([^|]*)|") do store[k] = tac end;
	end;
end;

-- does the unit have tactics of its own in any paradigm?
local function has_custom(cqi)
	for p = 1, T.MAX_PARADIGMS do if store[skey(cqi, p)] then return true end end;
	return false;
end;

local function save_store()
	local parts = {};
	for cqi, tac in pairs(store) do parts[#parts + 1] = cqi .. "=" .. tac .. "|" end;
	pcall(function() cm:set_saved_value(SAVE_KEY, table.concat(parts)) end);
end;

-- character ranks for the lord and embedded heroes of a force, by unit_list index
local function character_ranks(mf)
	local out = {};
	if not mf then return out end;
	local general = safe(function() return mf:general_character() end, nil);
	local gcqi = general and safe(function() return general:command_queue_index() end, nil);
	if general then out[0] = safe(function() return general:rank() end, nil) end;
	local heroes = {};
	pcall(function()
		local chars = mf:character_list();
		for i = 0, chars:num_items() - 1 do
			local c = chars:item_at(i);
			if c:command_queue_index() ~= gcqi then heroes[#heroes + 1] = c:rank() end;
		end;
	end);
	local h = 0;
	pcall(function()
		local units = mf:unit_list();
		for j = 1, units:num_items() - 1 do
			if units:item_at(j):unit_caste() == "hero" then
				h = h + 1;
				out[j] = heroes[h];
			end;
		end;
	end);
	return out;
end;

local ROLE_NAME = {
	melee = "Melee", missile = "Missile", missile_cav = "Missile cavalry", cavalry = "Cavalry",
	monster = "Monster", hero = "Lord / hero",
};

local function unit_info(u, char_rank)
	local caste = safe(function() return u:unit_caste() end, "");
	local rank = safe(function() return u:experience_level() end, 0) or 0;
	local cr = safe(function() if u:has_unit_commander() then return u:unit_commander():rank() end end, nil) or char_rank;
	local is_char = caste == "lord" or caste == "hero";
	-- lords and heroes: character rank (1-50) scaled onto the regiment scale (0-9)
	if cr and is_char then rank = math.min(9, math.floor(cr / 3)) end;
	return {
		cqi = tostring(safe(function() return u:command_queue_index() end, "")),
		key = safe(function() return u:unit_key() end, "?"),
		rank = rank,
		char_rank = is_char and cr or nil,
		caste = caste,
		role = T.role_from_caste(caste),
	};
end;

-- the unit's tactics in paradigm p (default I), padded/trimmed to its slot count (lords and heroes
-- get every slot); third value: using defaults; fourth: paradigm p has no set of its own (copies I)
local function tactics_for(info, p)
	p = p or 1;
	local n = T.slots_for_rank(info.rank, info.role);
	if p > 1 and not store[skey(info.cqi, p)] then
		local list, _, def = tactics_for(info, 1);
		return list, n, def, true;
	end;
	local s = store[skey(info.cqi, p)];
	local list = s and T.parse(s) or nil;
	if not list or #list == 0 then return T.default_tactics(info.role, n), n, true, false end;
	-- pads with defaults when the rank went up since the tactics were set
	local out = T.fit(list, n, info.role);
	while #out < n do out[#out + 1] = { "always", "nearest_enemy", "attack" } end;
	return out, n, false, false;
end;

-- the army general's character rank (unlocks paradigms)
local function general_rank(mf)
	local general = mf and safe(function() return mf:general_character() end, nil);
	return general and safe(function() return general:rank() end, nil) or 1;
end;

--------------------------------------------------------------------------------
-- export for the battle
--------------------------------------------------------------------------------

local function export()
	local faction = safe(function() return cm:get_local_faction(true) end, nil);
	if not faction then return end;
	local ok, f = pcall(io.open, EXPORT_PATH, "w");
	if not ok or not f then log("export failed: cannot open file"); return end;
	f:write("# Cinematic Director tactics export - one 'force' line per army, then its units in army order\n");
	local forces = faction:military_force_list();
	local n_units = 0;
	for i = 0, forces:num_items() - 1 do
		local mf = forces:item_at(i);
		f:write("force " .. tostring(safe(function() return mf:command_queue_index() end, -1)) .. " " .. tostring(general_rank(mf)) .. "\n");
		local ranks = character_ranks(mf);
		local units = mf:unit_list();
		for j = 0, units:num_items() - 1 do
			local info = unit_info(units:item_at(j), ranks[j]);
			local list = tactics_for(info);
			f:write(string.format("unit %d %s %s %d %s %s\n", j + 1, info.key, info.cqi, info.rank, info.role, T.serialise(list)));
			-- paradigms II-IV only where the unit has a set of its own
			for p = 2, T.MAX_PARADIGMS do
				if store[skey(info.cqi, p)] then
					f:write(string.format("para %d %d %s\n", j + 1, p, T.serialise((tactics_for(info, p)))));
				end;
			end;
			n_units = n_units + 1;
		end;
	end;
	f:close();
	log("exported tactics for " .. n_units .. " units");
end;

core:add_listener("cd_tactics_pending_battle", "PendingBattle", true, function() export() end, true);

--------------------------------------------------------------------------------
-- layout (pixels, relative to the editor panel)
--------------------------------------------------------------------------------

local MAX_UNITS = 20;
local MAX_CAT = 7;						-- category column
local OPT_COLS, OPT_ROWS = 3, 7;		-- choice grid
local MAX_OPT = OPT_COLS * OPT_ROWS;
local L = { w = 1100, h = 800 };
L.lx, L.lw = 16, 262;					-- roster column
L.rx = 306;								-- tactics column
L.rw = L.w - L.rx - 20;
L.col = {								-- tactics row columns (x relative to L.rx, width)
	n = { 0, 30 }, c = { 36, 250 }, a = { 292, 180 }, t = { 478, 190 }, up = { 674, 46 }, x = { 726, 48 },
};
L.row_y, L.row_step, L.row_h = 166, 46, 40;
L.foot_y = L.h - 16 - 34;
L.b_y = L.row_y + L.row_step * T.MAX_SLOTS + 8;		-- browser box
L.b_h = L.foot_y - 10 - L.b_y;
L.list_y, L.list_step, L.list_h = L.b_y + 30, 30, 28;	-- category and choice rows
L.cat_x, L.cat_w = 4, 172;
L.opt_x, L.opt_w, L.opt_gap = 192, 186, 8;
L.desc_y = L.list_y + OPT_ROWS * L.list_step + 4;

local ui = {
	force_cqi = nil,	-- selected army
	unit_index = nil,	-- unit being edited (0-based, matches unit_list order)
	open = false,
	unit = nil,			-- unit_info of the unit being edited
	list = nil,			-- its tactics
	slots = 0,
	is_default = true,
	inherits = false,	-- the paradigm being edited copies paradigm I
	para = 1,			-- paradigm being edited
	built = false,
	focus = { kind = "c", row = 1 },	-- the cell the browser is editing ("preset" = whole unit)
	cat = nil,			-- category shown in the browser (nil = the one holding the current choice)
	hover = nil,		-- choice under the mouse (index into the shown choices)
	shown = {},			-- choices currently in the grid
	note = nil,			-- one-off message for the description line
};

local function C(id) return K.get(id) end;

--------------------------------------------------------------------------------
-- army access
--------------------------------------------------------------------------------

local function selected_force()
	if not ui.force_cqi then return nil end;
	local mf = safe(function() return cm:get_military_force_by_cqi(ui.force_cqi) end, nil);
	if not mf then return nil end;
	local mine = safe(function() return mf:faction():name() == cm:get_local_faction_name(true) end, false);
	if not mine then return nil end;
	return mf;
end;

local function force_units(mf)
	local out = {};
	if not mf then return out end;
	local ranks = character_ranks(mf);
	pcall(function()
		local units = mf:unit_list();
		for j = 0, math.min(units:num_items(), MAX_UNITS) - 1 do
			out[#out + 1] = unit_info(units:item_at(j), ranks[j]);
		end;
	end);
	return out;
end;

local function store_current()
	if not ui.unit or not ui.list then return end;
	store[skey(ui.unit.cqi, ui.para)] = T.serialise(ui.list);
	save_store();
end;

--------------------------------------------------------------------------------
-- build (once per session)
--------------------------------------------------------------------------------

local function build()
	if ui.built then return true end;
	local open = K.make("cd_tac_open", "cd_button");
	if not open then return false end;
	K.size(open, 200, 36);
	K.text(open, "Battle Tactics", "big_c");
	K.tip(open, "Set how each regiment of this army fights on its own in battle.||Once a battle starts you cannot give orders: every unit follows its tactics.");
	K.show(open, false);

	local P = K.make("cd_tac_panel", "cd_panel");
	if not P then return false end;
	K.size(P, L.w, L.h);

	local function lbl(id, style, x, y, w, h, text)
		local c = K.make(id, "cd_label", P);
		K.place(c, x, y, w, h);
		K.text(c, text or "", style);
		K.click_through(c);
		return c;
	end;
	local function btn(id, x, y, w, h, text, tip)
		local c = K.make(id, "cd_button", P);
		K.place(c, x, y, w, h);
		K.text(c, text, "body_c");
		if tip then K.tip(c, tip) end;
		return c;
	end;
	local function row(id, x, y, w, h)
		local c = K.make(id, "cd_row", P);
		K.place(c, x, y, w, h);
		K.text(c, "", "body");
		return c;
	end;
	local function fill(id, colour, x, y, w, h)
		local c = K.make(id, "cd_fill", P);
		K.place(c, x, y, w, h);
		K.fill(c, colour);
		K.click_through(c);
		return c;
	end;

	-- header
	lbl("cd_tac_title", "title", 24, 14, 600, 30, "Battle Tactics");
	lbl("cd_tac_army", "small", 24, 46, 900, 20, "");
	btn("cd_tac_done", L.w - 24 - 110, 18, 110, 34, "Done", "Close the tactics editor. Changes are saved as you make them.");
	fill("cd_tac_hline", "line", 16, 74, L.w - 32, 1);
	fill("cd_tac_vline", "line", L.rx - 16, 86, 1, L.h - 102);

	-- roster
	lbl("cd_tac_rcap", "caps", L.lx + 8, 86, 240, 18, "Regiments");
	for j = 1, MAX_UNITS do
		local y = 108 + (j - 1) * 24;
		row("cd_tac_u_" .. j, L.lx, y, L.lw, 23);
		lbl("cd_tac_ur_" .. j, "small_r", L.lx + L.lw - 118, y, 110, 23, "");
	end;

	-- unit header
	lbl("cd_tac_name", "title", L.rx, 84, L.rw - 230, 30, "");
	-- paradigm tabs I-IV
	for p = 1, T.MAX_PARADIGMS do
		btn("cd_tac_p_" .. p, L.rx + L.rw - (T.MAX_PARADIGMS - p + 1) * 54, 84, 48, 30, T.PARADIGM_NAMES[p]);
	end;
	lbl("cd_tac_sub", "dim", L.rx, 116, L.rw, 20, "");
	lbl("cd_tac_cap_n", "caps", L.rx + L.col.n[1], 146, L.col.n[2], 18, "#");
	lbl("cd_tac_cap_c", "caps", L.rx + L.col.c[1] + 10, 146, 200, 18, "When");
	lbl("cd_tac_cap_a", "caps", L.rx + L.col.a[1] + 10, 146, 160, 18, "Do");
	lbl("cd_tac_cap_t", "caps", L.rx + L.col.t[1] + 10, 146, 180, 18, "Target");

	-- tactic rows: each cell is one flat row button; clicking it opens it in the browser below
	for i = 1, T.MAX_SLOTS do
		local y = L.row_y + (i - 1) * L.row_step;
		local card = K.make("cd_tac_card_" .. i, "cd_card", P);
		K.place(card, L.rx - 6, y, L.rw + 12, L.row_h);
		K.click_through(card);
		lbl("cd_tac_num_" .. i, "big_c", L.rx + L.col.n[1], y + 3, L.col.n[2], 34, tostring(i));
		for _, k in ipairs({ "c", "a", "t" }) do
			row("cd_tac_" .. k .. "_" .. i, L.rx + L.col[k][1], y + 3, L.col[k][2], 34);
		end;
		btn("cd_tac_up_" .. i, L.rx + L.col.up[1], y + 5, L.col.up[2], 30, "Up");
		btn("cd_tac_x_" .. i, L.rx + L.col.x[1], y + 5, L.col.x[2], 30, "Clear");
		lbl("cd_tac_lock_" .. i, "dim", L.rx + L.col.c[1] + 12, y + 3, 600, 34, "");
	end;

	-- browser: caption, category column, choice grid, description
	local bc = K.make("cd_tac_helpcard", "cd_card", P);
	K.place(bc, L.rx - 6, L.b_y, L.rw + 12, L.b_h);
	K.click_through(bc);
	lbl("cd_tac_bcap", "caps_gold", L.rx + 8, L.b_y + 8, L.rw - 16, 18, "");
	fill("cd_tac_bline", "line", L.rx + L.opt_x - 10, L.list_y, 1, OPT_ROWS * L.list_step - 3);
	for j = 1, MAX_CAT do
		row("cd_tac_cat_" .. j, L.rx + L.cat_x, L.list_y + (j - 1) * L.list_step, L.cat_w, L.list_h);
	end;
	for k = 1, MAX_OPT do
		local col, r = math.floor((k - 1) / OPT_ROWS), (k - 1) % OPT_ROWS;
		row("cd_tac_opt_" .. k, L.rx + L.opt_x + col * (L.opt_w + L.opt_gap), L.list_y + r * L.list_step, L.opt_w, L.list_h);
	end;
	lbl("cd_tac_help", "para", L.rx + 8, L.desc_y, L.rw - 16, L.b_y + L.b_h - L.desc_y - 6, "");

	-- footer
	btn("cd_tac_preset", L.rx, L.foot_y, 280, 34, "Presets", "Replace this regiment's tactics with a ready-made plan.");
	btn("cd_tac_copy", L.rx + 290, L.foot_y, 270, 34, "Copy to same type");
	btn("cd_tac_reset", L.rx + 570, L.foot_y, 204, 34, "Reset to default", "Go back to the default tactics for this kind of unit.");

	pcall(function() P:PropagatePriority(3000) end);
	K.show(P, false);
	ui.built = true;
	log("editor built");
	return true;
end;

--------------------------------------------------------------------------------
-- choices: what the focused cell can be, grouped into categories
--------------------------------------------------------------------------------

local KIND_CAP = { c = "When", a = "Do", t = "Target" };

local function preset_rows(p) return T.take(p[4], ui.slots) end;

-- categories for a kind: { { name, { {id, label}, ... } }, ... } and the id currently chosen
local function choices(kind, row)
	local t = ui.list and ui.list[row];
	if kind == "c" and t then return T.categories(T.CONDITIONS, 3), t[1] end;
	if kind == "a" and t then
		local cats = T.categories(T.ACTIONS, 4);
		-- lords and heroes: the spells this character showed in battle
		if ui.unit and ui.unit.role == "hero" then cats[#cats + 1] = { "Own spells", T.spell_entries(ui.unit.cqi) } end;
		return cats, t[3];
	end;
	if kind == "t" and t then
		local need = T.ACTION_BY[t[3]].kind;
		if need == "-" then return {}, nil end;
		return T.categories(T.TARGETS, 4, function(e) return e[3] == need end), t[2];
	end;
	if kind == "preset" then
		local now, cur = ui.list and T.serialise(ui.list), nil;
		for _, p in ipairs(T.PRESETS) do
			if now and T.serialise(preset_rows(p)) == now then cur = p[1] end;
		end;
		return T.categories(T.PRESETS, 5), cur;
	end;
	return {}, nil;
end;

local function choice_help(kind, e)
	if kind ~= "preset" then return T.help(e[1]) end;
	local lines = {};
	for k, r in ipairs(preset_rows(e)) do lines[#lines + 1] = k .. ". " .. T.sentence(r) end;
	return e[3] .. "\n" .. table.concat(lines, "   ");
end;

-- the category to show: the one picked, else the one holding the current choice, else the first
local function current_cat(cats, cur)
	for j, g in ipairs(cats) do if g[1] == ui.cat then return j end end;
	for j, g in ipairs(cats) do
		for _, e in ipairs(g[2]) do if e[1] == cur then return j end end;
	end;
	return 1;
end;

local function set_focus(kind, row)
	ui.focus = { kind = kind, row = row };
	ui.cat, ui.hover, ui.note = nil, nil, nil;
end;

--------------------------------------------------------------------------------
-- drawing
--------------------------------------------------------------------------------

local function hide_editor()
	ui.open = false;
	K.show(C("cd_tac_panel"), false);
end;

-- centre the editor on screen (UI space), a little above the middle so the unit cards stay visible
local function position_panel()
	local P = C("cd_tac_panel");
	local rw, rh = 1920, 1080;
	pcall(function() rw, rh = K.root():Bounds() end);
	local x = math.max(0, math.floor((rw - L.w) / 2));
	local y = math.max(0, math.floor((rh - L.h) / 2) - 110);
	K.anchor(P, 1, x, y, L.w, L.h);
end;

local function slot_text(info, i)
	local need = T.rank_for_slot(i);
	if info.char_rank then return string.format("Slot %d unlocks at character rank %d", i, need * 3) end;
	return string.format("Slot %d unlocks at rank %d", i, need);
end;

local function draw_browser(warnings)
	local f = ui.focus;
	local cats, cur = choices(f.kind, f.row);
	local j = current_cat(cats, cur);
	local group = cats[j] and cats[j][2] or {};
	ui.shown = group;

	if f.kind == "preset" then
		K.text(C("cd_tac_bcap"), "Presets  -  replace all of this regiment's tactics with a ready-made plan");
	elseif f.kind == "t" and #cats == 0 then
		K.text(C("cd_tac_bcap"), string.format("Target for row %d", f.row));
	else
		K.text(C("cd_tac_bcap"), string.format("%s for row %d  -  pick a group on the left, then a choice", KIND_CAP[f.kind], f.row));
	end;

	for k = 1, MAX_CAT do
		local c, g = C("cd_tac_cat_" .. k), cats[k];
		if g then
			local has_cur = false;
			for _, e in ipairs(g[2]) do if e[1] == cur then has_cur = true end end;
			K.text(c, g[1] .. (has_cur and "  *" or ""), k == j and "bright" or (has_cur and "gold" or "body"));
			K.state(c, k == j and "selected" or "active");
			K.tip(c, string.format("%d choice%s", #g[2], #g[2] == 1 and "" or "s"));
		else
			-- unused rows stay visible but empty and transparent (never hidden and re-shown)
			K.text(c, "", "body");
			K.state(c, "inactive");
			K.tip(c, "");
		end;
	end;

	local cur_e = nil;
	for k = 1, MAX_OPT do
		local c, e = C("cd_tac_opt_" .. k), group[k];
		if e then
			local is_cur = e[1] == cur;
			if is_cur then cur_e = e end;
			K.text(c, (is_cur and "> " or "") .. e[2], is_cur and "gold" or "body");
			K.state(c, is_cur and "selected" or "active");
			K.tip(c, choice_help(f.kind, e));
		else
			K.text(c, "", "body");
			K.state(c, "inactive");
			K.tip(c, "");
		end;
	end;
	if not cur_e then
		for _, g in ipairs(cats) do for _, e in ipairs(g[2]) do if e[1] == cur then cur_e = e end end end;
	end;

	-- description: the choice under the mouse, else a note, else warnings and the current choice
	local desc;
	local h = ui.hover and group[ui.hover];
	if h then
		desc = h[2] .. ":  " .. choice_help(f.kind, h);
	elseif cats[j] and cats[j][1] == "Own spells" and #group == 0 then
		desc = "This character's own spells appear here after their first battle with this mod. Until then use 'Cast attack spell on' or 'Cast helpful spell on' from Spells.";
	elseif ui.note then
		desc = ui.note;
	elseif f.kind == "t" and #cats == 0 then
		desc = "This action needs no target. Pick a DO that acts on a unit to choose one.";
	else
		local parts = {};
		if #warnings > 0 then parts[#parts + 1] = "Check: " .. table.concat(warnings, "  ") end;
		if cur_e then
			parts[#parts + 1] = "Chosen: " .. cur_e[2] .. "  -  " .. choice_help(f.kind, cur_e);
		elseif f.kind == "preset" then
			parts[#parts + 1] = "These tactics are your own, not one of the presets. Hover a preset to see what it does.";
		end;
		if #parts == 0 then parts[1] = "Hover a choice to see what it does." end;
		desc = table.concat(parts, "\n");
	end;
	K.text(C("cd_tac_help"), desc);
end;

local function draw()
	if not ui.open then hide_editor(); return end;
	local mf = selected_force();
	local units = force_units(mf);
	if #units == 0 then hide_editor(); return end;
	if not ui.unit_index or ui.unit_index >= #units then ui.unit_index = 0 end;
	local info = units[ui.unit_index + 1];
	ui.unit = info;
	ui.list, ui.slots, ui.is_default, ui.inherits = tactics_for(info, ui.para);
	local gr = general_rank(mf);
	local avail = T.paradigms_for_rank(gr);
	for p = 1, T.MAX_PARADIGMS do
		local b = C("cd_tac_p_" .. p);
		local own = p == 1 or store[skey(info.cqi, p)] ~= nil;
		K.state(b, p == ui.para and "selected" or "active");
		K.text(b, T.PARADIGM_NAMES[p], p == ui.para and "gold_c" or ((p <= avail and own) and "body_c" or "dim_c"));
		K.tip(b, string.format("Paradigm %s%s. In battle, buttons I-IV switch the whole army between paradigms.%s", T.PARADIGM_NAMES[p],
			p == 1 and ": the army's opening tactics" or (own and "" or ": same as I until you change a row"),
			p > avail and string.format(" Unlocks with a general of rank %d in the battle (this one is rank %d).", T.PARADIGM_RANKS[p], gr) or ""));
	end;
	if ui.focus.kind ~= "preset" and ui.focus.row > ui.slots then set_focus("c", 1) end;

	local P = C("cd_tac_panel");
	position_panel();
	K.show(P, true);

	-- header
	local general = safe(function() return mf:general_character() end, nil);
	local gname = general and safe(function() return common.get_localised_string(general:get_forename()) end, nil);
	K.text(C("cd_tac_army"), string.format("%s%d regiments. From the moment a battle starts you cannot give orders: every regiment follows its tactics on its own.",
		(gname and gname ~= "") and (gname .. "'s army  |  ") or "", #units));

	-- roster
	for j = 1, MAX_UNITS do
		local r, rr = C("cd_tac_u_" .. j), C("cd_tac_ur_" .. j);
		local u = units[j];
		if u then
			local custom = has_custom(u.cqi);
			local ns = T.slots_for_rank(u.rank, u.role);
			K.text(r, K.unit_name(u.key), (j - 1 == ui.unit_index) and "bright" or "body");
			K.state(r, (j - 1 == ui.unit_index) and "selected" or "active");
			K.text(rr, string.format("%s%d slot%s", custom and "custom | " or "", ns, ns == 1 and "" or "s"),
				custom and "gold_r" or "small_r");
			K.tip(r, string.format("%s  |  %s  |  %s", ROLE_NAME[u.role] or u.role,
				u.char_rank and ("character rank " .. u.char_rank) or ("rank " .. u.rank), custom and "custom tactics" or "default tactics"));
			K.show(r, true); K.show(rr, true);
		else
			K.show(r, false); K.show(rr, false);
		end;
	end;

	-- unit header
	K.text(C("cd_tac_name"), K.unit_name(info.key));
	local rank_txt = info.char_rank and string.format("Character rank %d", info.char_rank) or string.format("Rank %d", info.rank);
	local next_txt = (ui.slots < T.MAX_SLOTS and info.role ~= "hero") and ("  |  next slot at " .. (info.char_rank and ("character rank " .. T.rank_for_slot(ui.slots + 1) * 3)
		or ("rank " .. T.rank_for_slot(ui.slots + 1)))) or "";
	local state_txt = ui.inherits and ("paradigm " .. T.PARADIGM_NAMES[ui.para] .. " same as I - change a row to give it its own")
		or (ui.is_default and "default tactics" or "custom tactics");
	K.text(C("cd_tac_sub"), string.format("%s  |  %s  |  %d of %d tactic slots%s  |  %s", ROLE_NAME[info.role] or info.role, rank_txt,
		ui.slots, T.MAX_SLOTS, next_txt, state_txt));

	-- rows
	local unreach = T.unreachable(ui.list);
	local warnings = {};
	local f = ui.focus;
	for i = 1, T.MAX_SLOTS do
		local t = ui.list[i];
		local ids = {};
		for _, k in ipairs({ "card", "num", "c", "a", "t", "up", "x", "lock" }) do ids[k] = C("cd_tac_" .. k .. "_" .. i) end;
		if i <= ui.slots and t then
			local cd, ad, td = T.COND_BY[t[1]], T.ACTION_BY[t[3]], T.TARGET_BY[t[2]];
			local valid, why = T.validate(t);
			local no_target = ad and ad.kind == "-";
			local dead = unreach[i] ~= nil;
			local function cell(k, text, style)
				local on = f.kind == k and f.row == i;
				K.text(ids[k], text, on and "bright" or style);
				K.state(ids[k], on and "selected" or "active");
			end;
			K.text(ids.num, tostring(i), dead and "dim_c" or "big_c");
			cell("c", cd and cd.label or t[1], dead and "dim" or "body");
			cell("a", ad and ad.label or t[3], dead and "dim" or "gold");
			cell("t", no_target and "(no target)" or (td and td.label or t[2]), (dead or no_target) and "dim" or "body");
			K.tip(ids.num, T.sentence(t));
			K.tip(ids.c, "Click to choose WHEN this row applies");
			K.tip(ids.a, "Click to choose what the regiment DOES");
			K.tip(ids.t, no_target and "This action needs no target" or "Click to choose the TARGET");
			K.state(ids.up, i > 1 and "active" or "inactive");
			K.text(ids.up, nil, i > 1 and "body_c" or "dim_c");
			K.tip(ids.up, i > 1 and "Move this row up. Higher rows win." or "");
			K.tip(ids.x, "Reset this row to: Always - Attack - Nearest enemy.");
			for _, k in ipairs({ "num", "c", "a", "t", "up", "x" }) do K.show(ids[k], true) end;
			K.show(ids.lock, false);
			if dead then warnings[#warnings + 1] = string.format("row %d is never reached (row %d always applies first).", i, unreach[i]) end;
			if not valid then warnings[#warnings + 1] = string.format("row %d: %s %s.", i, ad and ad.label or "?", why or "is invalid") end;
		else
			for _, k in ipairs({ "num", "c", "a", "t", "up", "x" }) do K.show(ids[k], false) end;
			K.text(ids.lock, slot_text(info, i), "dim");
			K.show(ids.lock, true);
		end;
	end;

	-- footer
	local same = 0;
	for _, u in ipairs(units) do if u.key == info.key then same = same + 1 end end;
	local copy = C("cd_tac_copy");
	K.text(copy, same > 1 and string.format("Copy to all %d of this type", same) or "Copy to same type", same > 1 and "body_c" or "dim_c");
	K.state(copy, same > 1 and "active" or "inactive");
	K.tip(copy, "Give every " .. K.unit_name(info.key) .. " in this army the same tactics (each keeps only as many rows as its rank allows).");
	local _, pcur = choices("preset");
	local pname = pcur and T.PRESET_BY[pcur][2];
	local preset = C("cd_tac_preset");
	K.text(preset, pname and ("Preset: " .. pname) or "Presets...", f.kind == "preset" and "gold_c" or "body_c");
	K.state(preset, f.kind == "preset" and "selected" or "active");
	local reset = C("cd_tac_reset");
	local can_reset = store[skey(info.cqi, ui.para)] ~= nil;
	K.state(reset, can_reset and "active" or "inactive");
	K.text(reset, ui.para > 1 and "Same as paradigm I" or "Reset to default", can_reset and "body_c" or "dim_c");
	K.tip(reset, ui.para > 1 and "Drop this paradigm's own tactics: it copies paradigm I again."
		or "Go back to the default tactics for this kind of unit.");

	draw_browser(warnings);
end;

--------------------------------------------------------------------------------
-- open button above the army's unit cards
--------------------------------------------------------------------------------

local function update_button()
	if not ui.built then return end;
	local open = C("cd_tac_open");
	local panel = safe(function() return find_uicomponent(K.root(), "main_units_panel") end, nil);
	local vis = panel and K.visible(panel) and selected_force() ~= nil;
	if not vis then
		K.show(open, false);
		if ui.open then hide_editor() end;
		return;
	end;
	local px, py = 0, 0;
	pcall(function() px, py = panel:Position() end);
	pcall(function() open:MoveTo(math.floor(px + 20), math.floor(py - 44)) end);
	K.text(open, ui.open and "Close Tactics" or "Battle Tactics");
	K.show(open, true);
end;

--------------------------------------------------------------------------------
-- applying a choice
--------------------------------------------------------------------------------

local NEXT = { c = "a", a = "t" };

local function apply(k)
	local f = ui.focus;
	local e = ui.shown[k];
	if not e then return end;
	if f.kind == "preset" then
		ui.list = preset_rows(e);
		store_current();
		log(string.format("unit %s: preset %s", ui.unit.cqi, e[2]));
		ui.note = "Applied preset " .. e[2] .. ".";
		draw();
		return;
	end;
	local t = ui.list[f.row];
	if not t then return end;
	if f.kind == "c" then
		t[1] = e[1];
	elseif f.kind == "a" then
		t[3] = e[1];
		-- keep the target compatible with the new action
		local need = T.ACTION_BY[e[1]].kind;
		if need == "-" then t[2] = "self"
		elseif T.TARGET_BY[t[2]].kind ~= need then t[2] = (need == "e") and "nearest_enemy" or "ally_lord" end;
	elseif f.kind == "t" then
		t[2] = e[1];
	end;
	store_current();
	log(string.format("unit %s row %d -> %s", ui.unit.cqi, f.row, T.label(t)));
	-- move on to the next cell of the row (When -> Do -> Target)
	local nk = NEXT[f.kind];
	if nk == "t" and T.ACTION_BY[t[3]].kind == "-" then nk = nil end;
	if nk then set_focus(nk, f.row) else ui.hover = nil end;
	draw();
end;

--------------------------------------------------------------------------------
-- clicks and hover
--------------------------------------------------------------------------------

local function on_click(id)
	if id == "cd_tac_open" then
		if ui.open then hide_editor() else ui.open = true; draw() end;
		update_button();
		return true;
	end;
	if not ui.open then return false end;

	if id == "cd_tac_done" then hide_editor(); update_button(); return true end;

	local u = id:match("^cd_tac_u_(%d+)$");
	if u then
		ui.unit_index = tonumber(u) - 1;
		ui.hover, ui.note = nil, nil;
		draw();
		return true;
	end;

	local k = id:match("^cd_tac_opt_(%d+)$");
	if k then apply(tonumber(k)); return true end;

	local j = id:match("^cd_tac_cat_(%d+)$");
	if j then
		local cats = choices(ui.focus.kind, ui.focus.row);
		local g = cats[tonumber(j)];
		if g then ui.cat, ui.hover, ui.note = g[1], nil, nil end;
		draw();
		return true;
	end;

	local p = id:match("^cd_tac_p_(%d)$");
	if p then
		ui.para = tonumber(p);
		ui.hover, ui.note = nil, nil;
		draw();
		return true;
	end;

	if id == "cd_tac_reset" then
		local key = skey(ui.unit.cqi, ui.para);
		if store[key] then
			store[key] = nil;
			save_store();
			log("unit " .. ui.unit.cqi .. " paradigm " .. ui.para .. " reset");
		end;
		set_focus("c", 1);
		ui.note = ui.para > 1 and ("Paradigm " .. T.PARADIGM_NAMES[ui.para] .. " copies paradigm I again.")
			or "Back to the default tactics for this kind of unit.";
		draw();
		return true;
	end;
	if id == "cd_tac_preset" then
		if ui.focus.kind == "preset" then set_focus("c", 1) else set_focus("preset", 0) end;
		draw();
		return true;
	end;
	if id == "cd_tac_copy" then
		local mf = selected_force();
		local n = 0;
		pcall(function()
			local units = mf:unit_list();
			for j2 = 0, units:num_items() - 1 do
				local un = units:item_at(j2);
				if un:unit_key() == ui.unit.key then
					store[skey(tostring(un:command_queue_index()), ui.para)] = T.serialise(ui.list);
					n = n + 1;
				end;
			end;
		end);
		save_store();
		log(string.format("copied tactics of unit %s to %d units", ui.unit.cqi, n));
		ui.note = string.format("Copied: all %d %s in this army now use these tactics.", n, K.unit_name(ui.unit.key));
		draw();
		return true;
	end;

	local col, i = id:match("^cd_tac_(%a+)_(%d)$");
	if col then
		i = tonumber(i);
		local t = ui.list and ui.list[i];
		if not t then return true end;
		if col == "up" then
			if i > 1 then
				ui.list[i], ui.list[i - 1] = ui.list[i - 1], ui.list[i];
				store_current();
				if ui.focus.row == i then ui.focus.row = i - 1 elseif ui.focus.row == i - 1 then ui.focus.row = i end;
				draw();
			end;
		elseif col == "x" then
			ui.list[i] = { "always", "nearest_enemy", "attack" };
			store_current();
			draw();
		elseif col == "c" or col == "a" or col == "t" then
			set_focus(col, i);
			draw();
		end;
		return true;
	end;
	return id:find("^cd_tac_") ~= nil;
end;

local function on_hover(id)
	if not ui.open then return end;
	local k = id:match("^cd_tac_opt_(%d+)$");
	local was = ui.hover;
	ui.hover = k and tonumber(k) or nil;
	if ui.hover ~= was then draw_browser({}) end;
	if not ui.hover and was then draw() end;
end;

core:add_listener("cd_tac_click", "ComponentLClickUp", true,
	function(context)
		local id = tostring(context.string);
		if ui.open or id:find("^cd_tac_") then log("click: " .. id) end;
		local ok, err = pcall(on_click, id);
		if not ok then log("click handler error: " .. tostring(err)) end;
		if ui.open and id:find("^cd_tac_") then
			log(string.format("  focus %s row %s, group %s", ui.focus.kind, tostring(ui.focus.row), tostring(ui.cat)));
		end;

		-- unit card selection in the game's own panel: "LandUnit N"
		local n = id:match("^LandUnit (%d+)$");
		if n then
			ui.unit_index = tonumber(n);
			if ui.open then pcall(draw) end;
		end;
	end, true);

core:add_listener("cd_tac_hover", "ComponentMouseOn", true,
	function(context)
		local ok, err = pcall(on_hover, tostring(context.string));
		if not ok then log("hover handler error: " .. tostring(err)) end;
	end, true);

core:add_listener("cd_tac_char_selected", "CharacterSelected", true,
	function(context)
		local cqi = safe(function()
			local ch = context:character();
			if ch:has_military_force() then return ch:military_force():command_queue_index() end;
		end, nil);
		if cqi ~= ui.force_cqi then ui.unit_index = nil; hide_editor() end;
		ui.force_cqi = cqi;
		local ok, err = pcall(build);
		if not ok then log("build error: " .. tostring(err)) end;
		cm:callback(function() pcall(update_button) end, 0.3);
	end, true);

core:add_listener("cd_tac_panel_closed", "PanelClosedCampaign", true,
	function(context)
		if context.string == "units_panel" or context.string == "main_units_panel" then
			pcall(hide_editor);
			pcall(update_button);
		end;
	end, true);

-- keep the button in place and hide it when the army panel goes away
cm:add_first_tick_callback(function()
	load_store();
	local n = 0;
	for _ in pairs(store) do n = n + 1 end;
	log("tactics editor v4 loaded, " .. n .. " units with custom tactics");
	cm:repeat_real_callback(function() pcall(update_button) end, 500, "cd_tac_watch");
end);

-- debug hook for the harness
CD_TAC_EDITOR = { ui = ui, draw = draw, click = on_click, hover = on_hover, export = export, store = function() return store end };
