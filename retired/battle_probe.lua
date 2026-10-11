--------------------------------------------------------------------------------
-- Cinematic Director: battle probe (diagnostic, temporary)
-- * logs what identity/rank information battle units expose, so per-regiment
--   tactics set in the campaign can be matched to units in battle
-- * tests the order lockout: while the director is on, player orders are
--   disabled and we measure whether the AI-controlled units still move
-- Writes cinematic_director_probe.txt
--------------------------------------------------------------------------------

local PROBE_PATH = "cinematic_director_probe.txt";
CD_PROBE_LOCKOUT = true;	-- disable player orders while the director runs (test of the planned lockout)

local function plog(s)
	local ok, f = pcall(io.open, PROBE_PATH, "a");
	if ok and f then
		local t = "";
		pcall(function() t = os.date("%H:%M:%S ") end);
		f:write(t .. "[battle] " .. tostring(s) .. "\n");
		f:close();
	end;
end;

local function try(u, method)
	local ok, r = pcall(function() return u[method](u) end);
	if ok then return tostring(r) end;
	return "n/a";
end;

local METHODS = { "unit_key", "type", "name", "unique_ui_id", "command_queue_index", "unit_cqi", "cqi",
	"experience_level", "rank", "unit_class", "initial_number_of_men", "is_commanding_unit" };

local function dump_units()
	local pa = 1;
	pcall(function() pa = bm:get_player_alliance_num() end);
	local alliances = bm:alliances();
	for a = 1, alliances:count() do
		local armies = alliances:item(a):armies();
		for r = 1, armies:count() do
			local army = armies:item(r);
			local info = {};
			for _, m in ipairs({ "is_player_controlled", "faction_key", "army_handicap", "command_queue_index", "commander_cqi" }) do
				info[#info + 1] = m .. "=" .. try(army, m);
			end;
			plog(string.format("alliance %d%s army %d: %s", a, a == pa and " (player)" or "", r, table.concat(info, " ")));
			if a == pa then
				local units = army:units();
				for i = 1, units:count() do
					local u = units:item(i);
					local parts = {};
					for _, m in ipairs(METHODS) do parts[#parts + 1] = m .. "=" .. try(u, m) end;
					plog("   unit " .. i .. ": " .. table.concat(parts, " "));
				end;
			end;
		end;
	end;
end;

local probe = { start_pos = nil, active = false };

local function player_units()
	local out = {};
	pcall(function()
		local pa = bm:get_player_alliance_num();
		local armies = bm:alliances():item(pa):armies();
		for r = 1, armies:count() do
			local units = armies:item(r):units();
			for i = 1, units:count() do out[#out + 1] = units:item(i) end;
		end;
	end);
	return out;
end;

local function snapshot()
	local s = {};
	for i, u in ipairs(player_units()) do
		pcall(function() local p = u:position(); s[i] = { p:get_x(), p:get_z() } end);
	end;
	return s;
end;

local function measure(label)
	local now = snapshot();
	local moved, total = 0, 0;
	for i, p in pairs(now) do
		local p0 = probe.start_pos and probe.start_pos[i];
		if p0 then
			local d = math.sqrt((p[1] - p0[1]) ^ 2 + (p[2] - p0[2]) ^ 2);
			total = total + d;
			if d > 5 then moved = moved + 1 end;
		end;
	end;
	plog(string.format("%s: %d of %d player units moved >5 m since director on (total %.0f m)", label, moved, #player_units(), total));
end;

-- called by the director
CD_PROBE = {};

function CD_PROBE.on(active)
	if active then
		dump_units();
		if CD_PROBE_LOCKOUT then
			local ok, err = pcall(function() bm:disable_orders(true) end);
			plog("lockout: disable_orders(true) " .. (ok and "ok" or ("failed: " .. tostring(err))));
		end;
		probe.start_pos = snapshot();
		probe.active = true;
		local tm = core:get_tm();
		for _, secs in ipairs({ 10, 20, 40 }) do
			tm:real_callback(function() if probe.active then measure(secs .. " s") end end, secs * 1000);
		end;
	else
		probe.active = false;
		if CD_PROBE_LOCKOUT then
			local ok, err = pcall(function() bm:disable_orders(false) end);
			plog("lockout released: " .. (ok and "ok" or ("failed: " .. tostring(err))));
		end;
	end;
end;

plog("---- battle probe loaded ----");
