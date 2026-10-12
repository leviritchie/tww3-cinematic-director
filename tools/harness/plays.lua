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
local A = {
  mk("anvil_a",0,0), mk("anvil_b",40,0),
  mk("lord",20,-60,{general=true,men=1,caster=true,speed=6}),
  mk("cycle_knights",140,-20,{cav=true,men=60,speed=9}),
  mk("hammer_knights",-120,-20,{cav=true,men=60,speed=9}),
  mk("focus_xbows",10,-40,{ammo=20}), mk("focus_xbows2",40,-40,{ammo=20}),
  mk("skirmishers",220,-30,{ammo=20}),
  mk("lord_hunters",-160,-40,{cav=true,men=60,speed=9}),
  mk("hill_spears",-60,-10),
  mk("support_xbows",60,-50,{ammo=20}),
}
-- theirs: an orc line walking into the anvil, archers behind, wolves going for the skirmishers, the general alone at the back
local B = {
  mk("orc_a",0,220,{speed=3}), mk("orc_b",40,220,{speed=3}),
  mk("orc_arch",20,300,{ammo=20,speed=3}),
  mk("wolves",240,260,{cav=true,men=60,speed=8}),
  mk("warboss",-40,420,{general=true,men=1,speed=3}),
}
local ROWS = {
  anvil_a="always,nearest_enemy,attack", anvil_b="always,nearest_enemy,attack",
  lord="always,enemy_large,duelist;always,self,caster",
  cycle_knights="always,enemy_engaged,cycle_charge;always,nearest_enemy,cycle_charge",
  hammer_knights="always,self,hammer;hp_lt_25,self,regroup",
  focus_xbows="always,self,focus;hp_lt_25,self,to_lord", focus_xbows2="always,self,focus;hp_lt_25,self,to_lord",
  skirmishers="always,nearest_enemy,skirmish;hp_lt_25,self,to_lord",
  lord_hunters="always,self,kill_lord;always,self,hammer",
  hill_spears="always,self,high_ground;few_enemies,enemy_weakest,attack",
  support_xbows="always,enemy_engaged,fire_support;always,nearest_enemy,fire_support",
}
local ROLE = { lord="hero", cycle_knights="cavalry", hammer_knights="cavalry", lord_hunters="cavalry", focus_xbows="missile", focus_xbows2="missile", skirmishers="missile", support_xbows="missile" }
local f = io.open("cinematic_director_tactics.txt","w")
f:write("force 77 20\n")
for i,u in ipairs(A) do f:write(string.format("unit %d %s %d 2 %s %s\n", i, u.key, 100+i, ROLE[u.key] or "melee", ROWS[u.key])) end
f:write("para 1 2 always,self,hold\n")
f:write("para 2 2 always,self,hold\n")
f:close()

local army = {units=function() return coll(A) end, is_player_controlled=function() return true end}
local als = coll({ {armies=function() return coll({army}) end}, {armies=function() return coll({{units=function() return coll(B) end}}) end} })
local CB = {}
bm = setmetatable({ get_terrain_height=function(_,x,z) return 10 - (x or 0)*0.06 end, alliances=function() return als end, get_player_alliance_num=function() return 1 end,
  repeat_real_callback=function(_,f,ms,n) CB[n]={f=f,ms=ms,acc=0} end, remove_real_callback=function(_,n) CB[n]=nil end,
  is_conflict_phase=function() return T0>1 end, is_multiplayer=function() return false end, disable_orders=function() end },
  {__index=function() return function() end end})
CD_ABILITIES = { D={"fireball"}, R={"heal"} }
local CASTS = {}
script_unit = { new=function(_,u,ref) local uc={}
  function uc:take_control() end function uc:release_control() end
  function uc:perform_special_ability(k,t) CASTS[#CASTS+1]=u.key..":"..k.."->"..t.key end
  function uc:attack_unit(t,prim) u.chase=t u.goal=nil u.prim=prim end
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
local seen, last, track = {}, {}, {}
local function note(name, what) seen[name] = seen[name] or {} seen[name][what] = true end
for i = 1, 1800 do	-- 180 s
  T0 = i * 0.1
  -- ours: chase (stop at contact; shooters with ammo stop at 150 m and shoot) or walk to the goal
  for _, u in ipairs(A) do
    if u.hp > 0.05 and not u.melee then
      if u.chase and u.chase.hp > 0.05 then
        local d = d2(u, u.chase)
        local shoots = u.prim and u.ammo > 0
        if shoots and d < 150 then
          if i % 20 == 0 then u.ammo = u.ammo - 1 u.chase.hp = u.chase.hp - 0.01 end
        elseif d > 5 then step(u, u.chase.x, u.chase.z, u.speed) end
      elseif u.goal then step(u, u.goal[1], u.goal[2], u.speed) end
    end
    -- a unit ordered away from a fight walks out of it
    if u.melee and u.goal then step(u, u.goal[1], u.goal[2], u.speed * 0.6) end
  end
  -- theirs: orcs walk at the nearest of our units; wolves hunt the skirmishers; archers and the warboss stand
  for _, b in ipairs(B) do
    if b.hp > 0.05 and not b.melee then
      if b.key:find("^orc_[ab]") then
        local best, bd for _, a in ipairs(A) do if a.hp > 0.05 and (not bd or d2(a,b) < bd) then best, bd = a, d2(a,b) end end
        if best and bd > 5 then step(b, best.x, best.z, b.speed) end
      elseif b.key == "wolves" and T0 > 20 then
        local s = A[8] if s.hp > 0.05 and d2(s,b) > 5 then step(b, s.x, s.z, b.speed) end
      end
    end
  end
  -- melee: anyone within 6 m of an enemy fights it
  for _, u in ipairs(A) do u.melee = false end
  for _, b in ipairs(B) do b.melee = false end
  for _, a in ipairs(A) do for _, b in ipairs(B) do
    if a.hp > 0.05 and b.hp > 0.05 and d2(a,b) < 6 then a.melee, b.melee = true, true a.hp = a.hp - 0.0012 b.hp = b.hp - 0.0018 end
  end end
  for n, c in pairs(CB) do c.acc = c.acc + 100 if c.acc >= c.ms then c.acc = 0 c.f() end end
  -- what each play is doing
  if ENG.running() then
    for _, e in ipairs(ENG.units()) do
      local st = ENG.state(e) or {}
      local k = tostring(st.act) .. "/" .. tostring(st.phase)
      if k ~= last[e.key] then
        last[e.key] = k
        note(e.key, tostring(st.phase))
        note(e.key, "act:" .. tostring(st.act))
        P(string.format("%5.1f %-15s %-26s at %4.0f,%4.0f hp %.2f", T0, e.key, k, e.unit.x, e.unit.z, e.unit.hp))
      end
    end
  end
  if i % 300 == 0 then
    local s = {} for _, u in ipairs(A) do s[#s+1] = string.format("%s(%.0f,%.0f)", u.key, u.x, u.z) end P("t", T0, table.concat(s, " "))
  end
  -- paradigms: II holds the anvil; IV is unlocked (general rank 20); all generals down locks shifting
  if i == 300 then P("PARA switch II", ENG.paradigm(2), CD_TACTICS.serialise(ENG.units()[1].tactics)) end
  if i == 360 then P("PARA too soon (refused)", ENG.paradigm(1)) end
  if i == 510 then P("PARA switch I", ENG.paradigm(1), CD_TACTICS.serialise(ENG.units()[1].tactics)) end
  if i == 1700 then local pp = ENG.paradigms() P("PARA before", pp.n, pp.cur, pp.enabled) A[3].hp = 0 end
  if i == 1702 then local pp = ENG.paradigms() P("PARA lord down", pp.n, pp.enabled, ENG.paradigm(3)) end
  -- checks along the way
  if T0 > 5 and T0 < 25 then
    local h = A[5] track.wait_x = math.min(track.wait_x or 1e9, h.x)
    local c = A[3] track.caster_z = math.max(track.caster_z or -1e9, c.z)
  end
  if A[8].hp > 0.05 then track.kite_min = math.min(track.kite_min or 1e9, d2(A[8], B[4])) end
  local sup, line = A[11], math.max(A[1].z, A[2].z)
  if T0 > 20 and T0 < 60 then track.support_ahead = math.max(track.support_ahead or -1e9, sup.z - line) end
end
fire("BattleConflictFinished",{})
local function has(name, what) return seen[name] and seen[name][what] and "yes" or "NO" end
P("CHECK cycle_knights charge/contact/out/reform", has("cycle_knights","charge"), has("cycle_knights","contact"), has("cycle_knights","out"), has("cycle_knights","reform"))
P("CHECK hammer_knights wait/swing/rear/hit", has("hammer_knights","wait"), has("hammer_knights","swing"), has("hammer_knights","rear"), (seen.hammer_knights and (seen.hammer_knights.hit or seen.hammer_knights.contact)) and "yes" or "NO")
P("CHECK skirmishers kite", has("skirmishers","kite"), string.format("closest wolves got %.0f m", track.kite_min or -1))
P("CHECK focus", has("focus_xbows","act:focus"), has("focus_xbows2","act:focus"))
P("CHECK lord_hunters kill_lord", has("lord_hunters","act:kill_lord"))
P("CHECK hill_spears high_ground", has("hill_spears","act:high_ground"), string.format("now at x=%.0f (uphill is -x)", A[10].x))
P("CHECK lord caster", has("lord","act:caster"), string.format("max z while the line formed %.0f (line at 0)", track.caster_z or 0))
P("CHECK hammer wait spot x", string.format("%.0f (army flank)", track.wait_x or 0))
P("CHECK support_xbows stays behind the line", string.format("max %.0f m ahead of it", track.support_ahead or 0))
P("casts", #CASTS, table.concat(CASTS, " ", 1, math.min(#CASTS, 4)))
