--------------------------------------------------------------------------------
-- Cinematic Director: campaign probe (diagnostic, temporary)
-- Logs the army panel's UI structure and the player's armies so the tactics
-- editor can be built against the real UI. Writes cinematic_director_probe.txt
--------------------------------------------------------------------------------

local PROBE_PATH = "cinematic_director_probe.txt";

local function plog(s)
	local ok, f = pcall(io.open, PROBE_PATH, "a");
	if ok and f then
		local t = "";
		pcall(function() t = os.date("%H:%M:%S ") end);
		f:write(t .. "[campaign] " .. tostring(s) .. "\n");
		f:close();
	end;
end;

local function safe(fn, default)
	local ok, r = pcall(fn);
	if ok then return r end;
	return default;
end;

-- dump a UI subtree: id, visibility, position, size, state text
local function dump(uic, depth, max_depth, lines)
	if depth > max_depth or #lines > 1500 then return end;
	local id = safe(function() return uic:Id() end, "?");
	local vis = safe(function() return uic:Visible() end, "?");
	local x, y = 0, 0;
	pcall(function() x, y = uic:Position() end);
	local w, h = 0, 0;
	pcall(function() w, h = uic:Bounds() end);
	local txt = safe(function() return uic:GetStateText() end, "") or "";
	if #txt > 40 then txt = txt:sub(1, 40) .. "..." end;
	local state = safe(function() return uic:CurrentState() end, "");
	lines[#lines + 1] = string.rep("  ", depth) .. id .. string.format("  vis=%s pos=%d,%d size=%dx%d state=%s%s",
		tostring(vis), x or 0, y or 0, w or 0, h or 0, tostring(state), txt ~= "" and ("  text=\"" .. txt .. "\"") or "");
	local n = safe(function() return uic:ChildCount() end, 0);
	for i = 0, n - 1 do
		local child = safe(function() return UIComponent(uic:Find(i)) end, nil);
		if child then dump(child, depth + 1, max_depth, lines) end;
	end;
end;

local function dump_component(id, max_depth)
	local root = safe(function() return core:get_ui_root() end, nil);
	if not root then return end;
	local uic = safe(function() return find_uicomponent(root, id) end, nil);
	if not uic then
		plog("component " .. id .. " not found");
		return;
	end;
	local lines = {};
	dump(uic, 0, max_depth or 6, lines);
	plog("---- UI tree of " .. id .. " (" .. #lines .. " components) ----\n" .. table.concat(lines, "\n"));
end;

local function dump_root_children()
	local root = safe(function() return core:get_ui_root() end, nil);
	if not root then return end;
	local lines = {};
	dump(root, 0, 1, lines);
	plog("---- UI root children ----\n" .. table.concat(lines, "\n"));
end;

local function dump_armies()
	local faction = safe(function() return cm:get_local_faction(true) end, nil)
		or safe(function() return cm:model():world():faction_by_key(cm:get_local_faction_name(true)) end, nil);
	if not faction then plog("no local faction"); return end;
	local forces = faction:military_force_list();
	plog("faction " .. faction:name() .. " forces=" .. forces:num_items());
	for i = 0, forces:num_items() - 1 do
		local mf = forces:item_at(i);
		local cqi = safe(function() return mf:command_queue_index() end, -1);
		local gen = safe(function() return mf:general_character():character_subtype_key() end, "none");
		local units = mf:unit_list();
		local parts = {};
		for j = 0, units:num_items() - 1 do
			local u = units:item_at(j);
			parts[#parts + 1] = string.format("%d:%s(cqi=%s rank=%s caste=%s)", j,
				safe(function() return u:unit_key() end, "?"),
				tostring(safe(function() return u:command_queue_index() end, "?")),
				tostring(safe(function() return u:experience_level() end, "?")),
				tostring(safe(function() return u:unit_caste() end, "?")));
		end;
		plog(string.format("force %d cqi=%s general=%s units=%d: %s", i, tostring(cqi), gen, units:num_items(), table.concat(parts, ", ")));
	end;
end;

local logged_clicks = 0;

core:add_listener("cd_probe_panel_opened", "PanelOpenedCampaign", true,
	function(context)
		plog("panel opened: " .. tostring(context.string));
		if context.string == "units_panel" or context.string == "main_units_panel" then
			cm:callback(function() dump_component(context.string, 7) end, 0.5);
		end;
	end, true);

core:add_listener("cd_probe_click", "ComponentLClickUp", true,
	function(context)
		if logged_clicks < 80 then
			logged_clicks = logged_clicks + 1;
			local parent = "";
			pcall(function()
				local uic = UIComponent(context.component);
				local p = UIComponent(uic:Parent());
				parent = p:Id() .. " < " .. UIComponent(p:Parent()):Id();
			end);
			plog("click: " .. tostring(context.string) .. "  (parent: " .. parent .. ")");
		end;
	end, true);

core:add_listener("cd_probe_army_selected", "CharacterSelected", true,
	function(context)
		plog("character selected: " .. tostring(safe(function() return context:character():character_subtype_key() end, "?")));
		cm:callback(function()
			dump_component("units_panel", 7);
			dump_component("main_units_panel", 7);
		end, 0.5);
	end, true);

core:add_listener("cd_probe_pending_battle", "PendingBattle", true,
	function(context)
		plog("pending battle");
		pcall(function()
			local pb = cm:model():pending_battle();
			local att = pb:attacker():military_force();
			local def = pb:defender():military_force();
			plog("attacker force cqi=" .. tostring(att:command_queue_index()) .. " defender force cqi=" .. tostring(def:command_queue_index()));
		end);
		dump_armies();
	end, true);

cm:add_first_tick_callback(function()
	plog("---- probe loaded (first tick) ----");
	dump_armies();
	cm:callback(dump_root_children, 1);
end);
