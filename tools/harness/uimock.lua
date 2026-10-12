-- mock of the game's UIComponent tree + a renderer for our cd_* templates
local M = {}
local all = {}
M.all = all
local Comp = {} Comp.__index = Comp
local DEF = { cd_panel={400,300,"default"}, cd_card={300,60,"default"}, cd_fill={100,2,"line"}, cd_label={200,24,"body"},
  cd_arrow={24,24,"default"}, cd_icon={32,32,"eye"}, cd_button={160,32,"active"}, cd_row={260,28,"active"}, txt={160,32,"body_c"}, root={1920,1080,"x"}, other={300,200,"x"} }
local function new(id, tpl, parent)
  local d = DEF[tpl] or DEF.other
  local c = setmetatable({id=id, tpl=tpl, parent=parent, children={}, dock=0, ox=0, oy=0, w=d[1], h=d[2], st=d[3], texts={}, vis=true, inter=true, prio=0}, Comp)
  if parent then parent.children[#parent.children+1] = c end
  all[#all+1] = c
  if tpl == "cd_button" or tpl == "cd_row" then local t = new("txt", "txt", c); t.st = tpl == "cd_row" and "body" or "body_c"; t.dock = 5 end
  return c
end
M.new = new
function Comp:CreateComponent(id, path) local tpl = path:match("([%w_]+)%.twui%.xml$") return new(id, tpl, self) end
function Comp:SetDockingPoint(p) self.dock = p end
function Comp:SetDockOffset(x, y) self.ox, self.oy = x, y end
function Comp:Resize(w, h) self.w, self.h = w, h end
function Comp:SetState(s) self.st = s end
function Comp:CurrentState() return self.st end
function Comp:SetStateText(t) self.texts[self.st] = t end
function Comp:GetStateText() return self.texts[self.st] or "" end
function Comp:SetVisible(v) self.vis = v end
function Comp:Visible() return self.vis end
function Comp:VisibleFromRoot() return self:shown() end
function Comp:Bounds() return self.w, self.h end
function Comp:Id() return self.id end
function Comp:SetInteractive(v) self.inter = v end
function Comp:SetTooltipText(t) self.tip = t end
function Comp:PropagatePriority(p) self.prio = p end
function Comp:Priority() return self.prio end
function Comp:MoveTo(x, y) self.dock = -1; self.ax, self.ay = x, y end
function Comp:Position() return self:abs() end
function Comp:abs()
  if self.dock == -1 then return rawget(self,"ax") or 0, rawget(self,"ay") or 0 end
  if not rawget(self, "parent") then return 0, 0 end
  local px, py = self.parent:abs()
  local pw, ph = self.parent.w, self.parent.h
  if self.dock == 5 then return px + (pw - self.w) / 2 + self.ox, py + (ph - self.h) / 2 + self.oy end
  return px + self.ox, py + self.oy
end
function Comp:Parent() return rawget(self, "parent") end
function Comp:ChildCount() return #self.children end
function Comp:Find(i) if type(i) == "number" then return self.children[i + 1] end for _, k in ipairs(self.children) do if k.id == i then return k end end end
function Comp:GetContextObjectId(t) return rawget(self, "ctx") end
function Comp:shown() local c = self while c do if not c.vis then return false end c = rawget(c, "parent") end return true end
setmetatable(Comp, {__index = function() return function() end end})

function M.find_child(c, id) for _, k in ipairs(c.children) do if k.id == id then return k end end end
function M.find(c, id) for _, k in ipairs(all) do if k.id == id then return k end end end

-- rendering ---------------------------------------------------------------------------------
local function hex(s, a) local r, g, b = tonumber(s:sub(1,2),16)/255, tonumber(s:sub(3,4),16)/255, tonumber(s:sub(5,6),16)/255
  return {r, g, b, a or (#s >= 8 and tonumber(s:sub(7,8),16)/255) or 1} end
local STY = {
  body={14,"E9E1CC","left"}, dim={13,"8F8879","left"}, small={12,"8F8879","left"}, gold={14,"E0BE72","left"}, bright={14,"FFF6DE","left"},
  title={20,"E0BE72","left",true}, title_c={20,"E0BE72","center",true}, head={16,"E0BE72","left",true}, caps={11,"8F8879","left",false,true},
  caps_gold={11,"E0BE72","left",false,true}, body_c={14,"E9E1CC","center"}, dim_c={13,"8F8879","center"}, gold_c={14,"E0BE72","center"},
  big_c={16,"E0BE72","center",true}, small_r={12,"8F8879","right"}, gold_r={12,"E0BE72","right"}, warn={13,"E08A6A","left"}, para={14,"E9E1CC","left",false,false,true}, para_dim={13,"8F8879","left",false,false,true},
  hud_name={20,"FFF6DE","center",true}, hud_c={15,"E9E1CC","center"}, hud_dim_c={13,"B8B0A0","center"}, feed={14,"E9E1CC","left"}, feed_good={14,"E0BE72","left"},
  feed_bad={14,"E8846A","left"}, feed_old={13,"8F8879","left"}, tide_l={12,"9CC0EC","left",false,true}, tide_r={12,"E8846A","right",false,true}, caps_c={11,"E0BE72","center",false,true},
  banner={17,"FFF6DE","center"}, toast={13,"D8D0BC","center"} }
local FILL = { line="7A644080", gold="D4B26AFF", active="D4B26A30", shade="00000070", clear="00000000", red="B0483AFF", green="6FA05AFF", blue="4F86C6FF", black="000000FF", dark="0E0F12C8", green_bg="24461CD8", red_bg="561A12D8" }
local fonts = {}
local ICONS = {}
local TINT = { good="8FB8EAFF", bad="EC8A72FF", gold="E0BE72FF", dim="8F8879A0" }
local function icon_img(name)
  if ICONS[name] == nil then
    ICONS[name] = false
    local f = io.open(MODDIR .. "ui/skins/default/cinematic_director/i_" .. name .. ".png", "rb")
    if f then local d = f:read("*a") f:close() ICONS[name] = love.graphics.newImage(love.filesystem.newFileData(d, name .. ".png")) end
  end
  return ICONS[name]
end
local function font(n, bold) local k = n .. (bold and "b" or "") if not fonts[k] then fonts[k] = love.graphics.newFont(n) end return fonts[k] end
local function box(x, y, w, h, fill, line)
  love.graphics.setColor(fill) love.graphics.rectangle("fill", x, y, w, h)
  if line then love.graphics.setColor(line) love.graphics.rectangle("line", x + .5, y + .5, w - 1, h - 1) end
end
local BTN = { active={"1E2026","605034"}, hover={"2C2A28","D4B26A"}, down={"141418","D4B26A"}, down_off={"1E2026","605034"},
  selected={"423620","D4B26A"}, selected_hover={"423620","D4B26A"}, selected_down={"141418","D4B26A"}, inactive={"18181B","32302E"} }
local WASH = { active="FFFFFF08", hover="D4B26A22", down="D4B26A38", down_off="FFFFFF08", selected="D4B26A30", selected_hover="D4B26A44", inactive="00000000" }
function M.draw()
  for _, c in ipairs(all) do
    if c:shown() and c.tpl ~= "root" then
      local x, y = c:abs()
      if c.tpl == "cd_panel" then if c.st == "solid" then box(x, y, c.w, c.h, hex("141519"), hex("D4B26A")) else box(x, y, c.w, c.h, hex("0E0F12", .93), hex("7A6440")) end
      elseif c.tpl == "cd_card" then box(x, y, c.w, c.h, hex("181920", .92), hex("34302A"))
      elseif c.tpl == "cd_fill" then box(x, y, c.w, c.h, hex(FILL[c.st] or "FF00FFFF"))
      elseif c.tpl == "cd_arrow" then love.graphics.setColor(hex("D4B26A")) love.graphics.polygon("fill", x+5, y+3, x+21, y+12, x+5, y+21, x+9, y+12)
      elseif c.tpl == "cd_button" then local b = BTN[c.st] or BTN.active box(x, y, c.w, c.h, hex(b[1]), hex(b[2]))
      elseif c.tpl == "cd_row" then box(x, y, c.w, c.h, hex(WASH[c.st] or "00000000"))
        if c.st:find("selected") then box(x, y, 3, c.h, hex("D4B26A")) elseif c.st == "hover" then box(x, y, 3, c.h, hex("D4B26A70")) end
      elseif c.tpl == "cd_icon" then
        local base, suf = c.st:match("^([%w]+)_?(%w*)$")
        local img = icon_img(base or c.st)
        if img then love.graphics.setColor(hex(TINT[suf] or "F2EAD6FF")) love.graphics.draw(img, x, y, 0, c.w / img:getWidth(), c.h / img:getHeight())
        else box(x, y, c.w, c.h, hex("FF00FFFF")) end
      elseif c.tpl == "other" then box(x, y, c.w, c.h, hex("303848", .8), hex("8090A0")) love.graphics.setColor(1,1,1) love.graphics.print(c.id, x + 6, y + 6)
      end
      local t = c.texts[c.st]
      if t and t ~= "" then
        local s = STY[c.st] or STY.body
        local f = font(s[1], s[4]) love.graphics.setFont(f)
        if s[5] then t = t:upper() end
        local pad = (c.tpl == "txt" and c.parent.tpl == "cd_row") and 12 or 0
        local _, lines = f:getWrap(t, c.w - pad - (pad > 0 and 6 or 0))
        local th = #lines * f:getHeight()
        love.graphics.setColor(hex(s[2]))
        love.graphics.printf(t, x + pad, s[6] and y or y + math.floor((c.h - th) / 2), c.w - pad - (pad > 0 and 6 or 0), s[3])
      end
    end
  end
end
function M.render(path, w, h, bg)
  local cv = love.graphics.newCanvas(w, h)
  love.graphics.setCanvas(cv)
  love.graphics.clear(bg or {0.27, 0.31, 0.24, 1})
  -- fake "game" backdrop stripes
  for i = 0, h, 40 do love.graphics.setColor(0.24, 0.28, 0.21, 1) love.graphics.rectangle("fill", 0, i, w, 20) end
  M.draw()
  love.graphics.setCanvas()
  cv:newImageData():encode("png", path)
end
return M
