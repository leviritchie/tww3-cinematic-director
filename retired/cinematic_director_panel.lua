--------------------------------------------------------------------------------
-- Cinematic Director: strategy panel
-- A small collapsible panel shown while the director runs. Each row is a button
-- that cycles one AI setting. Settings are saved to cinematic_director_settings.txt.
--------------------------------------------------------------------------------

local LOG_PATH = "cinematic_director_log.txt";
local SETTINGS_PATH = "cinematic_director_settings.txt";

local function log(s)
	local ok, f = pcall(io.open, LOG_PATH, "a");
	if ok and f then
		local t = "";
		pcall(function() t = os.date("%H:%M:%S ") end);
		f:write(t .. "[panel] " .. tostring(s) .. "\n");
		f:close();
	end;
end;

CD_SETTINGS = CD_SETTINGS or {};

local ROWS = {
	{ name = "ai_control", label = "AI control",
		options = { { "on", "On" }, { "off", "Off (camera only)" } },
		tip = "On: the battle AI commands your army while the director runs.\nOff: you keep command; the director only films." },
	{ name = "army", label = "Army",
		options = { { "balanced", "Balanced" }, { "aggressive", "Aggressive" }, { "defensive", "Defensive" }, { "hold", "Hold position" } },
		tip = "Main battle line.\nBalanced: advance and engage the nearest enemy.\nAggressive: rush the enemy at full speed.\nDefensive: hold here and engage anything that comes close.\nHold position: stay where the army stood when this was chosen." },
	{ name = "missiles", label = "Missiles",
		options = { { "support", "Support line" }, { "skirmish", "Skirmish" }, { "hold", "Hold & shoot" } },
		tip = "Ranged units and artillery.\nSupport line: stay with the lord / main line.\nSkirmish: move up and engage freely.\nHold & shoot: stay put and fire at whatever comes into range." },
	{ name = "cavalry", label = "Cavalry",
		options = { { "flank", "Flank" }, { "with_army", "With army" }, { "reserve", "Reserve" } },
		tip = "Cavalry, chariots and fliers.\nFlank: hunt enemy missile units and artillery, then anything not already fighting.\nWith army: attack alongside the main line.\nReserve: guard the lord until the enemy comes close." },
	{ name = "heroes", label = "Lord & heroes",
		options = { { "fight", "Fight" }, { "stay_back", "Stay back" } },
		tip = "Fight: lords and heroes join the attack.\nStay back: they stay near the army's centre (casters still cast)." },
	{ name = "spells", label = "Spells",
		options = { { "all", "All" }, { "attack", "Attack only" }, { "support", "Buffs & heals only" }, { "off", "Off" } },
		tip = "Which abilities lords, heroes and monsters cast automatically." },
};

local P = {
	built = false,
	visible = false,
	collapsed = false,
	root = nil,
	header = nil,
	buttons = {},
	frame = nil,
};

--------------------------------------------------------------------------------
-- settings persistence
--------------------------------------------------------------------------------

local function load_settings()
	local ok, f = pcall(io.open, SETTINGS_PATH, "r");
	if not ok or not f then return end;
	for line in f:lines() do
		local k, val = line:match("^%s*([%w_]+)%s*=%s*([%w_]+)%s*$");
		if k == "collapsed" then
			P.collapsed = (val == "true");
		elseif k then
			CD_SETTINGS[k] = val;
		end;
	end;
	f:close();
end;

local function save_settings()
	local ok, f = pcall(io.open, SETTINGS_PATH, "w");
	if not ok or not f then return end;
	for _, row in ipairs(ROWS) do
		f:write(row.name .. " = " .. tostring(CD_SETTINGS[row.name]) .. "\n");
	end;
	f:write("collapsed = " .. tostring(P.collapsed) .. "\n");
	f:close();
end;

load_settings();

--------------------------------------------------------------------------------
-- ui helpers
--------------------------------------------------------------------------------

local TEMPLATE_BUTTON = "ui/templates/square_medium_text_button.twui.xml";
local TEMPLATE_FRAME = "ui/templates/panel_frame.twui.xml";
local BUTTON_W, BUTTON_H, PAD = 290, 34, 6;

local function create(parent, id, path)
	local ok, r = pcall(function() return UIComponent(parent:CreateComponent(id, path)) end);
	if ok and r then return r end;
	log("could not create " .. id .. " from " .. path .. ": " .. tostring(r));
	return nil;
end;

local function set_text(uic, text)
	local done = false;
	pcall(function()
		local child = uic:Find("button_txt");
		if child then
			UIComponent(child):SetStateText(text);
			done = true;
		end;
	end);
	if not done then pcall(function() uic:SetStateText(text) end) end;
end;

local function option_label(row)
	local cur = CD_SETTINGS[row.name];
	for _, o in ipairs(row.options) do
		if o[1] == cur then return o[2] end;
	end;
	return tostring(cur);
end;

local function refresh()
	if not P.built then return end;
	set_text(P.header, P.collapsed and "Director  [+]" or "Director  [-]");
	for _, row in ipairs(ROWS) do
		local b = P.buttons[row.name];
		if b then
			set_text(b, row.label .. ": " .. option_label(row));
			pcall(function() b:SetVisible(P.visible and not P.collapsed) end);
		end;
	end;
	pcall(function()
		local rows = P.collapsed and 0 or #ROWS;
		local h = PAD * 2 + BUTTON_H * (rows + 1) + PAD * rows;
		P.frame:SetCanResizeWidth(true);
		P.frame:SetCanResizeHeight(true);
		P.frame:Resize(BUTTON_W + PAD * 4, h + PAD * 2);
		P.frame:SetVisible(P.visible);
	end);
	pcall(function() P.header:SetVisible(P.visible) end);
end;

local function safe_ui_root()
	local ok, r = pcall(function() return core:get_ui_root() end);
	if ok then return r end;
	return nil;
end;

local function build()
	if P.built then return true end;
	local ui_root = safe_ui_root();
	if not ui_root then return false end;

	local sw = 1920;
	pcall(function() sw = core:get_screen_resolution() end);
	local x0, y0 = sw - BUTTON_W - PAD * 4 - 20, 110;

	P.frame = create(ui_root, "cd_panel_frame", TEMPLATE_FRAME);
	if P.frame then pcall(function() P.frame:MoveTo(x0, y0) end) end;

	local function make_button(id, i)
		local b = create(ui_root, id, TEMPLATE_BUTTON);
		if not b then return nil end;
		pcall(function()
			b:SetCanResizeWidth(true);
			b:SetCanResizeHeight(true);
			b:Resize(BUTTON_W, BUTTON_H);
			b:MoveTo(x0 + PAD * 2, y0 + PAD * 2 + i * (BUTTON_H + PAD));
		end);
		return b;
	end;

	P.header = make_button("cd_panel_header", 0);
	if not P.header then return false end;
	pcall(function() P.header:SetTooltipText("Cinematic Director: click to collapse/expand", true) end);
	for i, row in ipairs(ROWS) do
		local b = make_button("cd_set_" .. row.name, i);
		if b then
			P.buttons[row.name] = b;
			pcall(function() b:SetTooltipText(row.tip, true) end);
		end;
	end;
	P.built = true;
	log("panel built");
	return true;
end;

--------------------------------------------------------------------------------
-- clicks
--------------------------------------------------------------------------------

local function cycle(row)
	local cur = CD_SETTINGS[row.name];
	local idx = 1;
	for i, o in ipairs(row.options) do if o[1] == cur then idx = i end end;
	idx = idx % #row.options + 1;
	CD_SETTINGS[row.name] = row.options[idx][1];
	log(row.name .. " -> " .. CD_SETTINGS[row.name]);
	save_settings();
	refresh();
	if CD_COMMANDER and CD_COMMANDER.settings_changed then
		local ok, err = pcall(CD_COMMANDER.settings_changed, row.name);
		if not ok then log("settings_changed failed: " .. tostring(err)) end;
	end;
end;

core:add_listener("cinematic_director_panel_click", "ComponentLClickUp", true,
	function(context)
		if not P.visible then return end;
		local id = context.string;
		if id == "cd_panel_header" then
			P.collapsed = not P.collapsed;
			save_settings();
			refresh();
			return;
		end;
		for _, row in ipairs(ROWS) do
			if id == "cd_set_" .. row.name then
				cycle(row);
				return;
			end;
		end;
	end, true);

--------------------------------------------------------------------------------
-- api
--------------------------------------------------------------------------------

CD_PANEL = {};

function CD_PANEL.show()
	local ok, r = pcall(build);
	if not ok or not r then
		log("panel unavailable: " .. tostring(r));
		return;
	end;
	P.visible = true;
	refresh();
end;

function CD_PANEL.hide()
	P.visible = false;
	if P.built then refresh() end;
end;
