--------------------------------------------------------------------------------
-- Cinematic Director: banner probe (an experiment; set ENABLED = false or delete the file to remove)
--
-- Question: can a callout box ride on a unit's floating banner, so the engine moves it every frame?
-- The banners live in unit_id_holder > <unit unique_ui_id> > script_ping_parent (vanilla's
-- script_unit:add_ping_icon puts its ping there). Once per battle, three 10 s phases put a small "probe"
-- box there for one of our units and log, every second, whether it shows and where it is against where
-- the director's camera model puts the unit:
--   A  regular view, banners on
--   B  filming, banners hidden as usual (bm:enable_unit_ids(false))
--   C  filming, banners turned on but every part of them except script_ping_parent hidden
-- Phase C puts everything back when it ends. Results go to cinematic_director_log.txt as "[probe]".
--------------------------------------------------------------------------------

local ENABLED = false;
local PHASE_LEN = 10;
local K = CD_UI;
local LOG_PATH = "cinematic_director_log.txt";

local function log(s)
	local ok, f = pcall(io.open, LOG_PATH, "a");
	if ok and f then
		local t = "";
		pcall(function() t = os.date("%H:%M:%S ") end);
		f:write(t .. "[probe] " .. tostring(s) .. "\n");
		f:close();
	end;
end;

local function safe(fn, default)
	local ok, r = pcall(fn);
	if ok then return r end;
	return default;
end;

if not ENABLED or not K then return end;

local S = { done = {}, phase = nil, t0 = 0, last = -1, hidden = nil, n = 0 };

local function now()
	local t = CD_DIRECTOR and CD_DIRECTOR.clock and safe(CD_DIRECTOR.clock, nil);
	return t or os.clock();
end;

local function filming() return CD_DIRECTOR and CD_DIRECTOR.active and safe(CD_DIRECTOR.active, false) or false end;

local function screen_size()
	local sw, sh = 1920, 1080;
	pcall(function()
		local w, h = core:get_screen_resolution();
		if w and h and w > 0 then sw, sh = w, h end;
	end);
	return sw, sh;
end;

-- the unit through the director's camera model (as the HUD's callouts do)
local function project(u)
	if not (CD_DIRECTOR and CD_DIRECTOR.camera) then return nil end;
	local p, q, fov = CD_DIRECTOR.camera();
	local pos = safe(function() return u:position() end, nil);
	if not p or not pos then return nil end;
	local wx, wy, wz = pos:get_x(), pos:get_y() + 3, pos:get_z();
	local fx, fy, fz = q[1] - p[1], q[2] - p[2], q[3] - p[3];
	local l = math.sqrt(fx * fx + fy * fy + fz * fz);
	if l < 0.01 then return nil end;
	fx, fy, fz = fx / l, fy / l, fz / l;
	local rx, rz = fz, -fx;
	local rl = math.sqrt(rx * rx + rz * rz);
	if rl < 0.01 then return nil end;
	rx, rz = rx / rl, rz / rl;
	local ux, uy, uz = fy * rz, fz * rx - fx * rz, -fy * rx;
	local dx, dy, dz = wx - p[1], wy - p[2], wz - p[3];
	local Z = dx * fx + dy * fy + dz * fz;
	if Z < 1 then return nil end;
	local sw, sh = screen_size();
	local th = math.tan(math.rad(math.max(fov or 45, 5)) / 2);
	return math.floor(sw / 2 + (dx * rx + dz * rz) / (Z * th) * (sh / 2)), math.floor(sh / 2 - (dx * ux + dy * uy + dz * uz) / (Z * th) * (sh / 2));
end;

local function holder() return safe(function() return find_uicomponent(core:get_ui_root(), "unit_id_holder") end, nil) end;

local function children(c)
	local out = {};
	pcall(function()
		for i = 0, c:ChildCount() - 1 do
			local ch = UIComponent(c:Find(i));
			if ch then out[#out + 1] = ch end;
		end;
	end);
	return out;
end;

local function describe(c)
	if not c then return "nil" end;
	local x, y, w, h;
	pcall(function() x, y = c:Position() end);
	pcall(function() w, h = c:Bounds() end);
	return string.format("%s at %s,%s size %sx%s visible %s fromroot %s", tostring(safe(function() return c:Id() end, "?")),
		tostring(x), tostring(y), tostring(w), tostring(h), tostring(safe(function() return c:Visible() end, "?")),
		tostring(safe(function() return c:VisibleFromRoot() end, "?")));
end;

-- the unit to try it on: while filming, the living unit of ours nearest the middle of the picture (none on
-- screen: wait); in the regular view (no camera model), the unit the player last clicked, else the first one
local function subject()
	local eng = CD_TACTICS_ENGINE;
	if not eng then return nil end;
	if filming() then
		local sw, sh = screen_size();
		local best, bd;
		for _, e in ipairs(eng.units()) do
			if safe(function() return e.unit:number_of_men_alive() end, 0) > 0 then
				local x, y = project(e.unit);
				if x and x > sw * 0.15 and x < sw * 0.85 and y > sh * 0.2 and y < sh * 0.75 then
					local d = (x - sw / 2) ^ 2 + (y - sh / 2) ^ 2;
					if not bd or d < bd then best, bd = e.unit, d end;
				end;
			end;
		end;
		return best;
	end;
	local sel = CD_TACTICS_PANEL and CD_TACTICS_PANEL.state and CD_TACTICS_PANEL.state.sel;
	if sel and safe(function() return sel.unit:number_of_men_alive() end, 0) > 0 then return sel.unit end;
	for _, e in ipairs(eng.units()) do
		if safe(function() return e.unit:number_of_men_alive() end, 0) > 0 then return e.unit end;
	end;
	return nil;
end;

-- phase C: every part of every banner hidden except script_ping_parent (and put back afterwards)
local function strip_banners(on)
	if on then
		S.hidden = {};
		local hd = holder();
		if not hd then return end;
		for _, b in ipairs(children(hd)) do
			for _, ch in ipairs(children(b)) do
				if safe(function() return ch:Id() end, "") ~= "script_ping_parent" and safe(function() return ch:Visible() end, false) then
					pcall(function() ch:SetVisible(false) end);
					S.hidden[#S.hidden + 1] = ch;
				end;
			end;
		end;
		log(string.format("phase C: %d banner parts hidden", #S.hidden));
	elseif S.hidden then
		for _, ch in ipairs(S.hidden) do pcall(function() ch:SetVisible(true) end) end;
		log(string.format("phase C: %d banner parts shown again", #S.hidden));
		S.hidden = nil;
	end;
end;

local function begin(phase)
	local u = subject();
	if not u then return end;
	local uid = tostring(safe(function() return u:unique_ui_id() end, "?"));
	S.phase, S.t0, S.last, S.u, S.uid = phase, now(), -1, u, uid;
	if phase == "C" then
		pcall(function() bm:enable_unit_ids(true) end);
		strip_banners(true);
	end;
	local hd = holder();
	log(string.format("phase %s begins (%s): unit %s uid %s; holder %s", phase,
		phase == "A" and "regular view, banners on" or (phase == "B" and "filming, banners hidden" or "filming, banners on, their parts hidden"),
		safe(function() return u:type() end, "?"), uid, describe(hd)));
	local banner = hd and safe(function() return find_child_uicomponent(hd, uid) end, nil);
	local parent = banner and (safe(function() return find_child_uicomponent(banner, "script_ping_parent") end, nil) or banner);
	if banner and S.n < 1 then
		S.n = S.n + 1;
		local parts = {};
		for _, ch in ipairs(children(banner)) do parts[#parts + 1] = describe(ch) end;
		log("banner " .. describe(banner) .. "; parts: " .. table.concat(parts, " | "));
	end;
	if not parent then log("no banner component for this unit"); S.box = nil; return end;
	local box = K.make("cd_probe_" .. phase, "cd_card", parent);
	if box then
		K.place(box, 0, -40, 120, 30);
		local t = K.make("cd_probe_" .. phase .. "_t", "cd_label", box);
		K.place(t, 8, 4, 104, 22);
		K.text(t, "PROBE " .. phase, "gold");
		pcall(function() box:PropagatePriority(1500) end);
	end;
	S.box, S.parent = box, parent;
	log("box made in " .. describe(parent) .. ": " .. describe(box));
end;

local function finish()
	K.show(S.box, false);
	if S.phase == "C" then
		strip_banners(false);
		-- back to what the director wants
		local hide = CD_DIRECTOR and CD_DIRECTOR.banners_hidden and safe(CD_DIRECTOR.banners_hidden, false);
		if filming() and hide then pcall(function() bm:enable_unit_ids(false) end) end;
	end;
	log("phase " .. S.phase .. " over");
	S.done[S.phase] = true;
	S.phase, S.box = nil, nil;
end;

local function tick()
	if not safe(function() return bm:is_conflict_phase() end, false) then return end;
	if not S.phase then
		if filming() then
			if not S.done.B then begin("B") elseif not S.done.C then begin("C") end;
		elseif not S.done.A and now() > 5 then
			begin("A");
		end;
		return;
	end;
	-- a phase ends after PHASE_LEN, or when the view it needs is gone
	local t = now() - S.t0;
	if t > PHASE_LEN or (S.phase == "A") == filming() then finish(); return end;
	if math.floor(t) == S.last then return end;
	S.last = math.floor(t);
	local px, py = project(S.u);
	local back;
	if S.phase == "C" and S.hidden and #S.hidden > 0 then back = safe(function() return S.hidden[1]:Visible() end, "?") end;
	log(string.format("phase %s %ds: box %s; parent %s; unit projects to %s; %s", S.phase, S.last, describe(S.box), describe(S.parent),
		px and (px .. "," .. py) or "-", back == nil and "" or ("first hidden banner part visible again: " .. tostring(back))));
end;

--------------------------------------------------------------------------------
-- more one-run diagnostics
--   * camera check: the engine camera (position, target) against the director's camera model, which the
--     callouts project through; summed every 5 s, normal speed and slow motion apart (does move_to run in
--     game time while slowed?)
--   * unit cards: the layout under battle_orders (ids, context ids), once in deployment and once filming
--   * deployment: what lies over the tactics card while it shows
--------------------------------------------------------------------------------

local CAM = { t = 0, n = {}, sum = {}, max = {}, ang = {} };

local function cam_check()
	if not filming() then return end;
	local model_p, model_q = CD_DIRECTOR.camera();
	if not model_p then return end;
	local cam = bm:camera();
	local rp, rq = cam:position(), cam:target();
	if not rp or not rq then return end;
	local k = (CD_DIRECTOR.slow and safe(CD_DIRECTOR.slow, nil)) and "slow" or "normal";
	local dx, dy, dz = rp:get_x() - model_p[1], rp:get_y() - model_p[2], rp:get_z() - model_p[3];
	local d = math.sqrt(dx * dx + dy * dy + dz * dz);
	-- angle between the two look directions
	local ax, ay, az = rq:get_x() - rp:get_x(), rq:get_y() - rp:get_y(), rq:get_z() - rp:get_z();
	local bx, by, bz = model_q[1] - model_p[1], model_q[2] - model_p[2], model_q[3] - model_p[3];
	local la, lb = math.sqrt(ax * ax + ay * ay + az * az), math.sqrt(bx * bx + by * by + bz * bz);
	local ang = 0;
	if la > 0.01 and lb > 0.01 then ang = math.deg(math.acos(math.max(-1, math.min(1, (ax * bx + ay * by + az * bz) / (la * lb))))) end;
	CAM.n[k] = (CAM.n[k] or 0) + 1;
	CAM.sum[k] = (CAM.sum[k] or 0) + d;
	CAM.max[k] = math.max(CAM.max[k] or 0, d);
	CAM.ang[k] = math.max(CAM.ang[k] or 0, ang);
	if now() - CAM.t >= 5 then
		CAM.t = now();
		for _, kk in ipairs({ "normal", "slow" }) do
			if CAM.n[kk] then
				log(string.format("camera check (%s speed, %d samples): engine camera vs model: mean %.1f m, max %.1f m apart, look direction up to %.0f deg off",
					kk, CAM.n[kk], CAM.sum[kk] / CAM.n[kk], CAM.max[kk], CAM.ang[kk]));
			end;
		end;
		CAM.n, CAM.sum, CAM.max, CAM.ang = {}, {}, {}, {};
	end;
end;

local DUMP = {};
local function dump_cards(tag)
	if DUMP[tag] then return end;
	DUMP[tag] = true;
	local bo = find_uicomponent(core:get_ui_root(), "battle_orders");
	if not bo then log("cards (" .. tag .. "): no battle_orders"); return end;
	local lines = 0;
	local function walk(c, depth, path)
		if lines >= 80 then return end;
		for _, ch in ipairs(children(c)) do
			if lines >= 80 then return end;
			local id = tostring(safe(function() return ch:Id() end, "?"));
			local cid = safe(function() return ch:GetContextObjectId("CcoBattleUnit") end, nil);
			local n = safe(function() return ch:ChildCount() end, 0);
			if cid or depth <= 3 then
				lines = lines + 1;
				local x, y, w, h;
				pcall(function() x, y = ch:Position() end);
				pcall(function() w, h = ch:Bounds() end);
				log(string.format("cards (%s): %s > %s [%d children] at %s,%s size %sx%s visible %s%s", tag, path, id, n,
					tostring(x), tostring(y), tostring(w), tostring(h), tostring(safe(function() return ch:Visible() end, "?")),
					cid and (" unit context " .. tostring(cid)) or ""));
			end;
			-- below a card (one with a unit context) only its first level is of interest
			if depth < 7 and not cid then walk(ch, depth + 1, path .. ">" .. id) end;
		end;
	end;
	walk(bo, 1, "battle_orders");
end;

local function dump_over_card()
	if DUMP.over then return end;
	local panel = K.get("cd_bt_panel");
	if not (panel and safe(function() return panel:VisibleFromRoot() end, false)) then return end;
	DUMP.over = true;
	local px, py, pw, ph;
	pcall(function() px, py = panel:Position() end);
	pcall(function() pw, ph = panel:Bounds() end);
	log(string.format("deployment: tactics card at %s,%s size %sx%s priority %s", tostring(px), tostring(py), tostring(pw), tostring(ph),
		tostring(safe(function() return panel:Priority() end, "?"))));
	if not (px and pw) then return end;
	local root = core:get_ui_root();
	for _, ch in ipairs(children(root)) do
		local x, y, w, h;
		pcall(function() x, y = ch:Position() end);
		pcall(function() w, h = ch:Bounds() end);
		local vis = safe(function() return ch:Visible() end, false);
		if vis and x and w and x < px + pw and px < x + w and y < py + ph and py < y + h then
			log(string.format("deployment: over the card's area: %s at %s,%s size %sx%s priority %s", tostring(safe(function() return ch:Id() end, "?")),
				tostring(x), tostring(y), tostring(w), tostring(h), tostring(safe(function() return ch:Priority() end, "?"))));
		end;
	end;
end;

bm:repeat_real_callback(function()
	pcall(cam_check);
	pcall(function()
		local eng = CD_TACTICS_ENGINE;
		if eng and eng.deploying and eng.deploying() then
			dump_cards("deployment");
			dump_over_card();
		elseif filming() then
			dump_cards("filming");
		end;
	end);
end, 250, "cd_probe_more");

bm:repeat_real_callback(function()
	local ok, err = pcall(tick);
	if not ok then
		log("error: " .. tostring(err));
		pcall(function() bm:remove_real_callback("cd_probe") end);
		pcall(function() if S.phase == "C" then strip_banners(false) end end);
	end;
end, 200, "cd_probe");
core:add_listener("cd_probe_end", "BattleConflictFinished", true, function()
	pcall(function() if S.hidden then strip_banners(false) end end);
	pcall(function() bm:remove_real_callback("cd_probe") end);
	pcall(function() bm:remove_real_callback("cd_probe_more") end);
end, true);
CD_PROBE = S;
log("banner probe loaded");
