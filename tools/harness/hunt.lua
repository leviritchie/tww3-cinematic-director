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

-- missile hunt routing scenario: CD_SCN=hunt, CD_HC=<start case>. A static engaged line (5 v 5) with
-- three archer units 40-50 m behind theirs; cavalry, infantry and missile cavalry hunters (Hunt missiles)
-- start from the same spot. Reports how close each came to enemy troops on the way.
local HC = os.getenv("CD_HC") or "left"
local START = { left = {-200,-40}, right = {200,-40}, front = {-160,150}, far = {-60,-200}, centre = {0,-120} }
local sx, sz = START[HC][1], START[HC][2]
local A = {
  mk("anvil1",-80,0), mk("anvil2",-40,0), mk("anvil3",0,0), mk("anvil4",40,0), mk("anvil5",80,0),
  mk("lord",0,-60,{general=true,men=1,speed=6}),
  mk("hk",sx,sz,{cav=true,men=60,speed=9}), mk("hi",sx,sz,{speed=4}), mk("hm",sx+10,sz,{cav=true,men=60,speed=9,ammo=20,class="cav_mis"}),
}
local B = {
  mk("orc1",-80,5), mk("orc2",-40,5), mk("orc3",0,5), mk("orc4",40,5), mk("orc5",80,5),
  mk("arch1",-50,50,{ammo=20}), mk("arch2",10,55,{ammo=20}), mk("arch3",60,48,{ammo=20}),
  mk("warboss",0,120,{general=true,men=1}),
}
local ROWS = { hk="always,self,disrupt", hi="always,self,disrupt", hm="always,self,disrupt", lord="always,self,hold" }
for i=1,5 do ROWS["anvil"..i] = "always,nearest_enemy,attack" end
local ROLE = { lord="hero", hk="cavalry", hm="missile_cav" }
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
local H = { hk=A[7], hi=A[8], hm=A[9] }
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
          local t = tg and tg.u
          for _, b in ipairs(B) do if b ~= t and not b.key:find("^arch") then
            local dd = d2(u, b) if dd < r.clear then r.clear, r.near = dd, b.key end end end
          if t and (u.melee or d2(u, t) < 8 or (u.ammo > 0 and d2(u, t) < 150)) then
            r.hit, r.tgt, r.hitpath = T0, t.key, r.path
          end
        end
        if os.getenv("CD_TRACE") == e.key and i % 10 == 0 and not r.hit then local g = u.goal P(string.format("TRACE %5.1f at %4.0f,%4.0f goal %s closest %.0f %s", T0, u.x, u.z, g and string.format("%.0f,%.0f", g[1], g[2]) or "-", r.clear, tostring(r.near))) end
        if k ~= r.last then r.last = k P(string.format("%5.1f %-3s %-22s at %5.0f,%5.0f", T0, e.key, k, u.x, u.z)) end
      end
    end
  end
end
P(string.format("case %s, start %d,%d (enemy line z=5, x -80..80; archers at z 48-55 behind it)", HC, sx, sz))
for _, k in ipairs({ "hk", "hi", "hm" }) do
  local r = R[k]
  P(string.format("HUNT %s  reached %s at %s s, path %.0f m, closest enemy troops on the way %.0f m (%s)", k, tostring(r.tgt),
    r.hit and string.format("%.1f", r.hit) or "never", r.hitpath or r.path, r.clear, tostring(r.near)))
end
