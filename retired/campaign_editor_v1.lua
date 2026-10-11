--------------------------------------------------------------------------------
-- Cinematic Director: campaign tactics editor
--
-- Select an army, click a unit card, then click "Tactics" to edit that
-- regiment's tactics. Each row is: condition | target | action (click to cycle).
-- Tactics are stored in the save game per unit (by unit cqi) and exported to
-- cinematic_director_tactics.txt before every battle for the battle engine.
--------------------------------------------------------------------------------

local T = CD_TACTICS;
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

if not T then
	log("catalogue missing - tactics editor disabled");
	return;
end;

--------------------------------------------------------------------------------
-- storage: cqi -> "c,t,a;c,t,a"
--------------------------------------------------------------------------------

local store = {};

local function load_store()
	store = {};
	local s = safe(function() return cm:get_saved_value(SAVE_KEY) end, nil);
	if type(s) == "string" then
		for cqi, tac in s:gmatch("(%d+)=([^|]*)|") do store[cqi] = tac end;
	end;
end;

local function save_store()
	local parts = {};
	for cqi, tac in pairs(store) do parts[#parts + 1] = cqi .. "=" .. tac .. "|" end;
	pcall(function() cm:set_saved_value(SAVE_KEY, table.concat(parts)) end);
end;

local function unit_info(u)
	local caste = safe(function() return u:unit_caste() end, "");
	local rank = safe(function() return u:experience_level() end, 0) or 0;
	-- lords and heroes: character rank (1-50) scaled onto the regiment scale (0-9)
	local char_rank = safe(function()
		if u:has_unit_commander() then return u:unit_commander():rank() end;
	end, nil);
	if char_rank then rank = math.min(9, math.floor(char_rank / 3)) end;
	return {
		cqi = tostring(safe(function() return u:command_queue_index() end, "")),
		key = safe(function() return u:unit_key() end, "?"),
		rank = rank,
		caste = caste,
		role = T.role_from_caste(caste),
	};
end;

-- the unit's tactics, padded/trimmed to its slot count
local function tactics_for(info)
	local n = T.slots_for_rank(info.rank);
	local list = store[info.cqi] and T.parse(store[info.cqi]) or nil;
	if not list or #list == 0 then return T.default_tactics(info.role, n), n, true end;
	local out = {};
	for i = 1, math.min(n, #list) do out[i] = list[i] end;
	-- pad (rank went up since the tactics were set) with defaults not already listed
	for _, d in ipairs(T.DEFAULTS[info.role] or T.DEFAULTS.melee) do
		if #out >= n then break end;
		local dup = false;
		for _, t in ipairs(out) do if T.serialise({ t }) == T.serialise({ d }) then dup = true end end;
		if not dup then out[#out + 1] = d end;
	end;
	while #out < n do out[#out + 1] = { "always", "nearest_enemy", "attack" } end;
	return out, n, false;
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
		f:write("force " .. tostring(safe(function() return mf:command_queue_index() end, -1)) .. "\n");
		local units = mf:unit_list();
		for j = 0, units:num_items() - 1 do
			local info = unit_info(units:item_at(j));
			local list = tactics_for(info);
			f:write(string.format("unit %d %s %s %d %s %s\n", j + 1, info.key, info.cqi, info.rank, info.role, T.serialise(list)));
			n_units = n_units + 1;
		end;
	end;
	f:close();
	log("exported tactics for " .. n_units .. " units");
end;

core:add_listener("cd_tactics_pending_battle", "PendingBattle", true, function() export() end, true);

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------

local TEMPLATE_BUTTON = "ui/templates/square_medium_text_button.twui.xml";
local TEMPLATE_FRAME = "ui/templates/panel_frame.twui.xml";

local ui = {
	force_cqi = nil,	-- selected army
	unit_index = nil,	-- selected card (0-based, matches unit_list order)
	open = false,
	built = false,
	button = nil,
	frame = nil,
	title = nil,
	rows = {},			-- [i] = {c=, t=, a=}
	reset = nil,
	close = nil,
	info = nil,
	list = nil,
	slots = 0,
};

local function root() return safe(function() return core:get_ui_root() end, nil) end;

local function create(id, path)
	local r = root();
	if not r then return nil end;
	local ok, c = pcall(function() return UIComponent(r:CreateComponent(id, path)) end);
	if not ok or not c then log("create " .. id .. " failed: " .. tostring(c)); return nil end;
	-- make sure it can be clicked
	pcall(function() c:SetState("active") end);
	pcall(function() c:SetDisabled(false) end);
	pcall(function() c:SetInteractive(true) end);
	pcall(function() c:PropagatePriority(5000) end);
	pcall(function() c:SetMoveable(false) end);
	return c;
end;

local function set_text(c, text)
	if not c then return end;
	local done = false;
	pcall(function()
		local child = find_uicomponent(c, "button_txt");
		if child then child:SetStateText(text); done = true end;
	end);
	if not done then pcall(function() c:SetStateText(text) end) end;
end;

local function place(c, x, y, w, h)
	if not c then return end;
	pcall(function()
		c:SetCanResizeWidth(true);
		c:SetCanResizeHeight(true);
		c:Resize(w, h);
		c:MoveTo(x, y);
	end);
end;

local function show(c, v) if c then pcall(function() c:SetVisible(v) end) end end;

local COL_W, ROW_H, PAD = 330, 38, 8;

local function build()
	if ui.built then return true end;
	ui.button = create("cd_tac_open", TEMPLATE_BUTTON);
	if not ui.button then return false end;
	set_text(ui.button, "Tactics");
	pcall(function() ui.button:SetTooltipText("Edit this regiment's battle tactics", true) end);

	ui.frame = create("cd_tac_frame", TEMPLATE_FRAME);
	ui.title = create("cd_tac_title", TEMPLATE_BUTTON);
	for i = 1, T.MAX_SLOTS do
		ui.rows[i] = {
			c = create("cd_tac_c_" .. i, TEMPLATE_BUTTON),
			t = create("cd_tac_t_" .. i, TEMPLATE_BUTTON),
			a = create("cd_tac_a_" .. i, TEMPLATE_BUTTON),
		};
	end;
	ui.info = create("cd_tac_info", TEMPLATE_BUTTON);
	ui.reset = create("cd_tac_reset", TEMPLATE_BUTTON);
	ui.close = create("cd_tac_close", TEMPLATE_BUTTON);
	set_text(ui.reset, "Reset to defaults");
	set_text(ui.close, "Close");
	pcall(function() ui.title:SetTooltipText("Tactics are checked top to bottom; the first whose condition holds and whose target exists is followed. Slots: 1 + rank/2.", true) end);
	ui.built = true;
	log("editor built");
	return true;
end;

local function selected_unit()
	if not ui.force_cqi or not ui.unit_index then return nil end;
	local mf = safe(function() return cm:get_military_force_by_cqi(ui.force_cqi) end, nil);
	if not mf then return nil end;
	local faction_ok = safe(function() return mf:faction():name() == cm:get_local_faction_name(true) end, false);
	if not faction_ok then return nil end;
	local units = mf:unit_list();
	if ui.unit_index >= units:num_items() then return nil end;
	return units:item_at(ui.unit_index);
end;

local function layout_editor()
	local u = selected_unit();
	if not u then ui.open = false end;
	for i = 1, T.MAX_SLOTS do
		local r = ui.rows[i];
		show(r.c, false); show(r.t, false); show(r.a, false);
	end;
	show(ui.frame, ui.open); show(ui.title, ui.open); show(ui.info, ui.open);
	show(ui.reset, ui.open); show(ui.close, ui.open);
	if not ui.open then return end;

	local info = unit_info(u);
	ui.unit = info;
	ui.list, ui.slots = tactics_for(info);

	local sw, sh = 1920, 1080;
	pcall(function() sw, sh = core:get_screen_resolution() end);
	local w = COL_W * 3 + PAD * 6;
	local h = PAD * 3 + ROW_H * (ui.slots + 3) + PAD * (ui.slots + 3);
	local x0 = math.floor((sw - w) / 2);
	local y0 = math.max(40, math.floor(sh * 0.55) - h);

	place(ui.frame, x0, y0, w, h);
	local name = safe(function() return common.get_localised_string("land_units_onscreen_name_" .. info.key) end, nil);
	if not name or name == "" then name = info.key end;
	place(ui.title, x0 + PAD * 2, y0 + PAD * 2, w - PAD * 4, ROW_H);
	set_text(ui.title, string.format("%s - rank %d - %d tactic slot%s", name, info.rank, ui.slots, ui.slots == 1 and "" or "s"));

	for i = 1, ui.slots do
		local r, t = ui.rows[i], ui.list[i];
		local y = y0 + PAD * 2 + i * (ROW_H + PAD);
		place(r.c, x0 + PAD * 2, y, COL_W, ROW_H);
		place(r.a, x0 + PAD * 3 + COL_W, y, COL_W, ROW_H);
		place(r.t, x0 + PAD * 4 + COL_W * 2, y, COL_W, ROW_H);
		set_text(r.c, i .. ". " .. T.COND_BY[t[1]].label);
		set_text(r.a, T.ACTION_BY[t[3]].label);
		local valid, why = T.validate(t);
		set_text(r.t, T.TARGET_BY[t[2]].label .. (valid and "" or "  (!)"));
		pcall(function() r.t:SetTooltipText(valid and "Target" or ("Invalid: action " .. why), true) end);
		show(r.c, true); show(r.t, true); show(r.a, true);
	end;

	local y = y0 + PAD * 2 + (ui.slots + 1) * (ROW_H + PAD);
	place(ui.info, x0 + PAD * 2, y, w - PAD * 4, ROW_H);
	set_text(ui.info, "Click a cell to cycle it. Top row wins. Spell rows are checked separately, so a caster can move and cast.");
	y = y + ROW_H + PAD;
	place(ui.reset, x0 + PAD * 2, y, COL_W, ROW_H);
	place(ui.close, x0 + w - PAD * 2 - COL_W, y, COL_W, ROW_H);
end;

local function update_button()
	if not ui.built then return end;
	local panel = safe(function() return find_uicomponent(root(), "main_units_panel") end, nil);
	local panel_vis = panel and safe(function() return panel:Visible() end, false);
	local u = panel_vis and selected_unit() or nil;
	if not u then
		show(ui.button, false);
		if ui.open then ui.open = false; layout_editor() end;
		return;
	end;
	local px, py = 0, 0;
	pcall(function() px, py = panel:Position() end);
	place(ui.button, px + 20, py - 50, 200, 40);
	show(ui.button, true);
end;

local function store_current()
	if not ui.unit or not ui.list then return end;
	store[ui.unit.cqi] = T.serialise(ui.list);
	save_store();
end;

local function cycle(list, cur)
	local idx = 1;
	for i, e in ipairs(list) do if e[1] == cur then idx = i end end;
	return list[idx % #list + 1][1];
end;

local function on_click(id)
	if id == "cd_tac_open" then
		ui.open = not ui.open;
		layout_editor();
		return true;
	end;
	if not ui.open then return false end;
	if id == "cd_tac_close" then
		ui.open = false;
		layout_editor();
		return true;
	end;
	if id == "cd_tac_reset" then
		store[ui.unit.cqi] = nil;
		save_store();
		layout_editor();
		return true;
	end;
	local col, i = id:match("^cd_tac_([cta])_(%d)$");
	if col then
		i = tonumber(i);
		local t = ui.list[i];
		if not t then return true end;
		if col == "c" then
			t[1] = cycle(T.CONDITIONS, t[1]);
		elseif col == "a" then
			t[3] = cycle(T.ACTIONS, t[3]);
			-- keep the target compatible with the action where possible
			local need = T.ACTION_BY[t[3]].kind;
			if need ~= "-" and T.TARGET_BY[t[2]].kind ~= need then
				t[2] = (need == "e") and "nearest_enemy" or "ally_engaged";
			elseif need == "-" then
				t[2] = "self";
			end;
		elseif col == "t" then
			-- only cycle through targets that suit the action
			local need = T.ACTION_BY[t[3]].kind;
			local pool = {};
			for _, e in ipairs(T.TARGETS) do if need == "-" and e[3] == "-" or e[3] == need then pool[#pool + 1] = e end end;
			if #pool > 0 then t[2] = cycle(pool, t[2]) end;
		end;
		store_current();
		layout_editor();
		log(string.format("unit %s slot %d -> %s", ui.unit.cqi, i, T.label(t)));
		return true;
	end;
	return false;
end;

--------------------------------------------------------------------------------
-- listeners
--------------------------------------------------------------------------------

core:add_listener("cd_tac_click", "ComponentLClickUp", true,
	function(context)
		local id = tostring(context.string);
		if id:find("^cd_tac_") then log("click " .. id) end;
		local ok, err = pcall(on_click, id);
		if not ok then log("click handler error: " .. tostring(err)) end;

		-- unit card selection: "LandUnit N" inside the units panel
		local n = id:match("^LandUnit (%d+)$");
		if n then
			ui.unit_index = tonumber(n);
			if ui.open then pcall(layout_editor) end;
			pcall(update_button);
		end;
	end, true);

-- mouse-over logging for our components (diagnoses clicks that never arrive)
local hover_logged = {};
core:add_listener("cd_tac_hover", "ComponentMouseOn", true,
	function(context)
		local id = tostring(context.string);
		if id:find("^cd_tac_") and not hover_logged[id] then
			hover_logged[id] = true;
			log("mouse over " .. id);
		end;
	end, true);

core:add_listener("cd_tac_char_selected", "CharacterSelected", true,
	function(context)
		local cqi = safe(function()
			local ch = context:character();
			if ch:has_military_force() then return ch:military_force():command_queue_index() end;
		end, nil);
		if cqi ~= ui.force_cqi then ui.unit_index = nil end;
		ui.force_cqi = cqi;
		pcall(build);
		cm:callback(function() pcall(update_button) end, 0.3);
	end, true);

core:add_listener("cd_tac_panel_closed", "PanelClosedCampaign", true,
	function(context)
		if context.string == "units_panel" or context.string == "main_units_panel" then
			ui.open = false;
			pcall(layout_editor);
			pcall(update_button);
		end;
	end, true);

-- keep the button in place and hide it when the army panel goes away
cm:add_first_tick_callback(function()
	load_store();
	log("tactics editor loaded, " .. (function() local n = 0 for _ in pairs(store) do n = n + 1 end return n end)() .. " units with custom tactics");
	cm:repeat_real_callback(function() pcall(update_button) end, 500, "cd_tac_watch");
end);
