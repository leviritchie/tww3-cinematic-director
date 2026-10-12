-- tactics plays scenario: CD_SCN=plays. A small battle with real-ish speeds, run through the engine only;
-- prints every play's step changes and checks the plans behave (cycle charges cycle, hammers swing round, ...)
local V = {} V.__index = V
function v(x,y,z) return setmetatable({x=x,y=y,z=z},V) end
function V:get_x() return self.x end function V:get_y() return self.y end function V:get_z() return self.z end
local T0 = 0
local Unit = {} Unit.__index = Unit
local nextid = 2001
local function mk(key,x,z,o) o=o or {} local u=setmetatable({key=key,x=x,z=z,men=o.men or 120,alive=o.men or 120,id=nextid,o=o,melee=false,hp=1,speed=o.speed or 4,ammo=o.ammo or 0},Unit) nextid=nextid+1 return u end
function Unit:position() return v(self.x,10,self.z) end
function Unit:type() return self.key end
function Unit:number_of_men_alive() return self.hp > 0 and self.alive or 0 end
function Unit:initial_number_of_men() return self.men end
function Unit:is_shattered() return self.hp <= 0 end
function Unit:is_routing() return self.hp <= 0.05 end
function Unit:is_in_melee() return self.melee end
function Unit:is_under_missile_attack() return false end
function Unit:is_commanding_unit() return self.o.general or false end
function Unit:can_fly() return false end
function Unit:is_cavalry() return self.o.cav or false end
function Unit:unique_ui_id() return self.id end
function Unit:is_visible_to_alliance() return true end
function Unit:ammo_left() return self.ammo end
function Unit:unary_hitpoints() return self.hp end
function Unit:starting_ammo() return self.o.ammo or 0 end
function Unit:unit_class() return self.o.class or (self.o.cav and "cav_shk" or (self.o.ammo and "inf_mis" or "inf_mel")) end
function Unit:can_perform_special_ability(k) return self.o.caster and (k=="fireball" or k=="heal") end
function Unit:is_script_controlled() return false end
local function coll(t) return {count=function() return #t end, item=function(_,i) return t[i] end} end

-- ours: two spear regiments as the anvil, the plays around them

-- hammer routing scenario: CD_SCN=hammer, CD_HC=<start case>. A static engaged line (5 v 5) with a reserve
-- behind the enemy; one unit per hammer variant starts from the same spot. Reports each route.
local HC = os.getenv("CD_HC") or "left"
local START = { left = {-200,-40}, right = {200,-40}, front = {-160,150}, far = {-60,-200} }
local sx, sz = START[HC][1], START[HC][2]
local A = {
  mk("anvil1",-80,0), mk("anvil2",-40,0), mk("anvil3",0,0), mk("anvil4",40,0), mk("anvil5",80,0),
  mk("lord",0,-60,{general=true,men=1,speed=6}),
  mk("hk",sx,sz,{cav=true,men=60,speed=9}), mk("hf",sx,sz,{cav=true,men=60,speed=9}), mk("hw",sx,sz,{cav=true,men=60,speed=9}),
  mk("hi",sx,sz,{speed=4}),
}
local B = {
  mk("orc1",-80,5), mk("orc2",-40,5), mk("orc3",0,5), mk("orc4",40,5), mk("orc5",80,5),
  mk("reserve",-20,60), mk("warboss",0,120,{general=true,men=1}),
}
local ROWS = { hk="always,self,hammer", hf="always,self,hammer_flank", hw="always,self,hammer_wide", hi="always,self,hammer", lord="always,self,hold" }
for i=1,5 do ROWS["anvil"..i] = "always,nearest_enemy,attack" end
local ROLE = { lord="hero", hk="cavalry", hf="cavalry", hw="cavalry" }
local f = io.open("cinematic_director_tactics.txt","w")
f:write("force 77 20\n")
for i,u in ipairs(A) do f:write(string.format("unit %d %s %d 2 %s %s\n", i, u.key, 100+i, ROLE[u.key] or "melee", ROWS[u.key])) end
f:close()
local army = {units=function() return coll(A) end, is_player_controlled=function() return true end}
local als = coll({ {armies=function() return coll({army}) end}, {armies=function() return coll({{units=function() return coll(B) end}}) end} })
local CB = {}
bm = setmetatable({ get_terrain_height=function() return 10 end, alliances=function() return als end, get_player_alliance_num=function() return 1 end,
  repeat_real_callback=function(_,f,ms,n) CB[n]={f=f,ms=ms,acc=0} end, remove_real_callback=function(_,n) CB[n]=nil end,
  is_conflict_phase=function() return T0>1 end, is_multiplayer=function() return false end, disable_orders=function() end },
  {__index=function() return function() end end})
CD_ABILITIES = { D={}, R={} }
script_unit = { new=function(_,u,ref) local uc={}
  function uc:take_control() end function uc:release_control() end
  function uc:perform_special_ability() end
  function uc:attack_unit(t,prim) u.chase=t u.goal=nil end
  function uc:halt() u.chase=nil u.goal=nil end
  function uc:goto_location(p) u.chase=nil u.goal={p.x,p.z} end
  return {unit=u, name=ref, uc=uc} end }
dofile(MODDIR.."script/battle/mod/cinematic_director_tactics.lua")
local ENG = CD_TACTICS_ENGINE
local function d2(a,b) return math.sqrt((a.x-b.x)^2+(a.z-b.z)^2) end
local function step(u, tx, tz, sp)
  local dx,dz = tx-u.x, tz-u.z local d=math.sqrt(dx*dx+dz*dz)
  if d > 0.5 then local s=math.min(d, sp*0.1) u.x=u.x+dx/d*s u.z=u.z+dz/d*s end
end
local H = { hk=A[7], hf=A[8], hw=A[9], hi=A[10] }
local R = {} for k in pairs(H) do R[k] = { path=0, clear=1e9, last=nil } end
for i = 1, 900 do
  T0 = i * 0.1
  for _, u in ipairs(A) do
    if not u.melee then
      if u.chase then if d2(u,u.chase) > 5 then step(u, u.chase.x, u.chase.z, u.speed) end
      elseif u.goal then step(u, u.goal[1], u.goal[2], u.speed) end
    elseif u.goal then step(u, u.goal[1], u.goal[2], u.speed * 0.6) end
  end
  for _, u in ipairs(A) do u.melee = false end
  for _, b in ipairs(B) do b.melee = false end
  for _, a in ipairs(A) do for _, b in ipairs(B) do
    if d2(a,b) < 6 then a.melee, b.melee = true, true end
  end end
  for n, c in pairs(CB) do c.acc = c.acc + 100 if c.acc >= c.ms then c.acc = 0 c.f() end end
  if ENG.running() then
    for _, e in ipairs(ENG.units()) do
      local r = R[e.key]
      if r then
        local u = H[e.key]
        local st = ENG.state(e) or {}
        local tg = e.cur and e.cur.target
        local tk = tg and tg.u and tg.u.key or (tg and tostring(tg.key)) or "-"
        local k = tostring(st.phase) .. " " .. tk
        if r.prev then r.path = r.path + d2(u, r.prev) end
        r.prev = { x = u.x, z = u.z }
        if not r.hit then
          for _, b in ipairs(B) do if b.key ~= tk then r.clear = math.min(r.clear, d2(u, b)) end end
          if st.phase == "hit" or st.phase == "flank_hit" or st.phase == "contact" or u.melee then
            r.hit = T0
            local t = tg and tg.u
            if t then r.hitang = math.deg(math.atan2(u.x - t.x, u.z - t.z)) r.tgt = t.key end
            r.hitpath = r.path
          end
        end
        if k ~= r.last then r.last = k P(string.format("%5.1f %-3s %-22s at %5.0f,%5.0f", T0, e.key, k, u.x, u.z)) end
      end
    end
  end
end
P(string.format("case %s, start %d,%d (enemy line z=5, x -80..80; reserve -20,60; their rear is +z)", HC, sx, sz))
for _, k in ipairs({ "hk", "hf", "hw", "hi" }) do
  local r = R[k]
  P(string.format("ROUTE %s  hit at %s s on %s, %.0f deg off its rear, path %.0f m, closest other enemy %.0f m", k,
    r.hit and string.format("%.1f", r.hit) or "never", tostring(r.tgt), r.hitang or -1, r.hitpath or r.path, r.clear))
end
