--------------------------------------------------------------------------------
-- Cinematic Director: small UI kit shared by the campaign editor and the
-- battle tactics panel. Uses the mod's own templates (ui/templates/cd_*.twui.xml):
--   cd_panel  dark panel with a gold hairline (blocks clicks to the map)
--   cd_card   quieter inset box
--   cd_fill   solid colour: line, gold, active, shade, clear, red, green
--   cd_label  text: body, dim, small, gold, bright, title, title_c, head, caps,
--             caps_gold, body_c, dim_c, gold_c, big_c
--   cd_arrow  gold arrow marker
--   cd_button framed button, text child "txt" (body_c, dim_c, gold_c, big_c)
--   cd_row    flat list row, text child "txt" (body, dim, gold, bright)
-- Everything except a top-level panel is docked to its parent's top-left
-- corner, so only the panel itself is ever positioned on screen.
--------------------------------------------------------------------------------

local K = {};
CD_UI = K;

local TPL = "ui/templates/";
local C, RECT, TEXT, STYLE, TIP, LAST = {}, {}, {}, {}, {}, {};

K.log = function() end;

local function safe(fn, default)
	local ok, r = pcall(fn);
	if ok then return r end;
	return default;
end;
K.safe = safe;

function K.root() return safe(function() return core:get_ui_root() end, nil) end;
function K.get(id) return C[id] end;

-- create (once) a component from one of our templates inside parent (root if nil)
function K.make(id, tpl, parent)
	if C[id] then return C[id] end;
	local p = parent or K.root();
	if not p then return nil end;
	local ok, c = pcall(function() return UIComponent(p:CreateComponent(id, TPL .. tpl .. ".twui.xml")) end);
	if not ok or not c then K.log("ui: create " .. id .. " (" .. tpl .. ") failed: " .. tostring(c)); return nil end;
	pcall(function() c:SetMoveable(false) end);
	C[id] = c;
	return c;
end;

-- top-left docking inside the parent, offset x, y; optional size
function K.place(c, x, y, w, h)
	if not c then return end;
	pcall(function()
		c:SetDockingPoint(1);
		c:SetDockOffset(math.floor(x), math.floor(y));
	end);
	if w then K.size(c, w, h) end;
end;

-- top-level panel docked to a screen anchor (5 = centre, 6 = centre right, 8 = bottom centre ...)
function K.anchor(c, point, x, y, w, h)
	if not c then return end;
	pcall(function()
		c:SetDockingPoint(point);
		c:SetDockOffset(math.floor(x), math.floor(y));
	end);
	if w then K.size(c, w, h) end;
end;

function K.size(c, w, h)
	if not c then return end;
	w, h = math.floor(w), math.floor(h);
	RECT[c] = { w = w, h = h };
	pcall(function()
		c:SetCanResizeWidth(true);
		c:SetCanResizeHeight(true);
		c:Resize(w, h);
	end);
	local t = safe(function() return find_child_uicomponent(c, "txt") end, nil);
	if t then
		pcall(function()
			t:SetCanResizeWidth(true);
			t:SetCanResizeHeight(true);
			t:Resize(w, h);
		end);
	end;
end;

function K.show(c, v) if c then pcall(function() c:SetVisible(v and true or false) end) end end;
function K.visible(c) return c and safe(function() return c:Visible() end, false) or false end;

-- text lives on the component (labels) or its "txt" child (buttons, rows)
local function text_target(c) return safe(function() return find_child_uicomponent(c, "txt") end, nil) or c end;

-- set text and/or style; both are re-applied after any state change because text is per state
function K.text(c, s, style)
	if not c then return end;
	local t = text_target(c);
	if style and STYLE[t] ~= style then
		pcall(function() t:SetState(style) end);
		STYLE[t] = style;
		TEXT[t] = nil;
	end;
	if s == nil then s = LAST[t] end;
	LAST[t] = s;
	if s ~= nil and TEXT[t] ~= s then
		pcall(function() t:SetStateText(s) end);
		TEXT[t] = s;
	end;
end;

function K.tip(c, s)
	if not c or TIP[c] == s then return end;
	TIP[c] = s;
	pcall(function() c:SetTooltipText(s or "", true) end);
end;

-- button/row state: "active", "selected" or "inactive"; keeps size and text
function K.state(c, s)
	if not c then return end;
	local cur = safe(function() return c:CurrentState() end, "");
	local want = s;
	-- don't knock a hovered button out of its hover look
	if s == "active" and (cur == "hover" or cur == "down" or cur == "down_off") then want = nil end;
	if s == "selected" and (cur == "selected_hover" or cur == "selected_down") then want = nil end;
	if want and cur ~= want then
		pcall(function() c:SetState(want) end);
		local r = RECT[c];
		if r then pcall(function() c:Resize(r.w, r.h) end) end;
	end;
	pcall(function() c:SetInteractive(s ~= "inactive") end);
end;

function K.fill(c, colour) if c then pcall(function() c:SetState(colour) end) end end;

function K.top(c, on)
	if not c then return end;
	if on then pcall(function() c:RegisterTopMost() end) else pcall(function() c:RemoveTopMost() end) end;
end;

function K.click_through(c) if c then pcall(function() c:SetInteractive(false) end) end end;

function K.describe(c)
	if not c then return "missing" end;
	local x, y, w, h = 0, 0, 0, 0;
	pcall(function() x, y = c:Position() end);
	pcall(function() w, h = c:Bounds() end);
	return string.format("%s vis=%s pos=%d,%d size=%dx%d state=%s", tostring(safe(function() return c:Id() end, "?")),
		tostring(K.visible(c)), x or 0, y or 0, w or 0, h or 0, tostring(safe(function() return c:CurrentState() end, "?")));
end;

-- readable unit name from a land unit key
function K.unit_name(key)
	local n = safe(function() return common.get_localised_string("land_units_onscreen_name_" .. key) end, nil);
	if not n or n == "" then
		n = tostring(key):gsub("^wh%d?_[%w]+_[%w]+_", ""):gsub("_%d+$", ""):gsub("_", " ");
		n = n:gsub("^%l", string.upper);
	end;
	return n;
end;

return K;
