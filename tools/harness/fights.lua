-- fight states scenario: CD_SCN=fights. Fixed melees with set health losses, run through the engine only;
-- checks who is winning or losing each fight, the WHEN conditions about fights, and the targets that take
-- the unit the WHEN condition found (movement rows and spell rows)
local V = {} V.__index = V
function v(x,y,z) return setmetatable({x=x,y=y,z=z},V) end
function V:get_x() return self.x end function V:get_y() return self.y end function V:get_z() return self.z end
local T0 = 0
local Unit = {} Unit.__index = Unit
local nextid = 3001
local function mk(key,x,z,o) o=o or {} local u=setmetatable({key=key,x=x,z=z,men=o.men or 120,alive=o.men or 120,id=nextid,o=o,melee=false,hp=1,ammo=0},Unit) nextid=nextid+1 return u end
function Unit:position() return v(self.x,10,self.z) end
function Unit:type() return self.key end
function Unit:number_of_men_alive() return self.hp > 0 and self.alive or 0 end
function Unit:initial_number_of_men() return self.men end
function Unit:is_shattered() return self.hp <= 0 end
function Unit:is_routing() return self.hp <= 0.05 end
function Unit:is_in_melee() return self.melee end
function Unit:is_wavering() return self.o.waver or false end
function Unit:is_under_missile_attack() return false end
function Unit:is_commanding_unit() return self.o.general or false end
function Unit:can_fly() return false end
function Unit:is_cavalry() return false end
function Unit:unique_ui_id() return self.id end
function Unit:is_visible_to_alliance() return true end
function Unit:ammo_left() return 0 end
function Unit:unary_hitpoints() return self.hp end
function Unit:starting_ammo() return 0 end
function Unit:unit_class() return "inf_mel" end
function Unit:can_perform_special_ability(k) return self.o.caster and k == "heal" end
function Unit:is_script_controlled() return false end
local function coll(t) return {count=function() return #t end, item=function(_,i) return t[i] end} end

-- three melees (losing badly, winning, even) and three helpers that read the WHEN condition's unit
local A = {
  mk("lord",20,-90,{general=true,men=1,caster=true}),
  mk("losing_sp",0,0), mk("winning_sw",100,0), mk("even_hal",200,0),
  mk("helper_atk",40,-60), mk("helper_grd",60,-60), mk("helper_none",80,-60),
}
local B = { mk("orc_big",0,5), mk("gob",100,5), mk("orc_c",200,5) }
-- health lost per second in each fight
local LOSS = { losing_sp=0.008, orc_big=0.002, winning_sw=0.002, gob=0.005, even_hal=0.004, orc_c=0.004 }
local ROWS = {
  lord="ally_losing,trigger_ally,cast_buff;always,self,hold",
  losing_sp="always,self,hold", winning_sw="always,self,hold", even_hal="always,self,hold",
  helper_atk="ally_losing,trigger_enemy,attack;always,self,hold",
  helper_grd="ally_losing,trigger_ally,guard;always,self,hold",
  helper_none="always,trigger_enemy,attack;always,self,hold",
}
local f = io.open("cinematic_director_tactics.txt","w")
f:write("force 77 20\n")
for i,u in ipairs(A) do f:write(string.format("unit %d %s %d 2 %s %s\n", i, u.key, 100+i, u.key == "lord" and "hero" or "melee", ROWS[u.key])) end
f:close()

local army = {units=function() return coll(A) end, is_player_controlled=function() return true end}
local als = coll({ {armies=function() return coll({army}) end}, {armies=function() return coll({{units=function() return coll(B) end}}) end} })
local CB = {}
bm = setmetatable({ get_terrain_height=function() return 10 end, alliances=function() return als end, get_player_alliance_num=function() return 1 end,
  repeat_real_callback=function(_,f,ms,n) CB[n]={f=f,ms=ms,acc=0} end, remove_real_callback=function(_,n) CB[n]=nil end,
  is_conflict_phase=function() return T0>1 end, is_multiplayer=function() return false end, disable_orders=function() end },
  {__index=function() return function() end end})
CD_ABILITIES = { R={"heal"} }
local CASTS = {}
script_unit = { new=function(_,u,ref) local uc={}
  function uc:take_control() end function uc:release_control() end
  function uc:perform_special_ability(k,t) CASTS[#CASTS+1]=u.key..":"..k.."->"..t.key end
  function uc:attack_unit(t) u.chase=t u.goal=nil end
  function uc:halt() u.chase=nil u.goal=nil end
  function uc:goto_location(p) u.chase=nil u.goal={p.x,p.z} end
  return {unit=u, name=ref, uc=uc} end }

-- the game's unit context: even_hal's strongest morale line is "Winning current combat"
local LOC = { random_localisation_strings_string_unit_encouraged_winning = "[[col:green]]Winning current combat[[/col]]",
  random_localisation_strings_string_unit_concerned_losing = "[[col:red]]Losing currently[[/col]]" }
local BYID = {} for _, u in ipairs(A) do BYID[tostring(u.id)] = u end for _, u in ipairs(B) do BYID[tostring(u.id)] = u end
local CCV = 0
common = { get_localised_string = function(k) return LOC[k] or "" end,
  get_context_value = function(ty, id, expr) CCV = CCV + 1 local u = BYID[id]
    if ty == "CcoBattleUnit" and u and expr == "MoraleGreatestEffect" then return u.key == "even_hal" and LOC.random_localisation_strings_string_unit_encouraged_winning or "Fighting near the general" end
    if expr == "StatusColour" then return 4278255360 end return nil end }
dofile(MODDIR.."script/battle/mod/cinematic_director_tactics.lua")
local ENG = CD_TACTICS_ENGINE
local function rec(u) for _, r in ipairs(ENG.world().own) do if r.u == u then return r end end for _, r in ipairs(ENG.world().enemy) do if r.u == u then return r end end end
local function entry(u) for _, e in ipairs(ENG.units()) do if e.unit == u then return e end end end
local got = {}
for i = 1, 300 do	-- 30 s; nothing moves, the melees start at 3 s
  T0 = i * 0.1
  for _, u in ipairs(A) do u.melee = T0 > 3 and LOSS[u.key] ~= nil end
  for _, u in ipairs(B) do u.melee = T0 > 3 end
  if T0 > 3 then
    for _, u in ipairs(A) do if LOSS[u.key] then u.hp = u.hp - LOSS[u.key] * 0.1 end end
    for _, u in ipairs(B) do u.hp = u.hp - LOSS[u.key] * 0.1 end
  end
  for n, c in pairs(CB) do c.acc = c.acc + 100 if c.acc >= c.ms then c.acc = 0 c.f() end end
  if ENG.running() and i % 50 == 0 then
    local s = {} for _, u in ipairs(A) do local r = rec(u) if r then s[#s+1] = string.format("%s=%s(%.4f)", u.key, tostring(r.fight), r.loss or -1) end end
    for _, u in ipairs(B) do local r = rec(u) if r then s[#s+1] = string.format("%s=%s(%.4f)", u.key, tostring(r.fight), r.loss or -1) end end
    P("FIGHTS", T0, table.concat(s, " "))
  end
  if ENG.running() and T0 > 20 then
    for _, k in ipairs({ 5, 6, 7 }) do
      local st = ENG.state(entry(A[k])) or {}
      got[A[k].key] = string.format("%s->%s", tostring(st.act), st.target_unit and st.target_unit.key or "-")
    end
  end
end
local W = ENG.world()
local function fight(u) local r = rec(u) return r and r.fight end
P("states", fight(A[2]), fight(B[1]), fight(A[3]), fight(B[2]), fight(A[4]), fight(B[3]))
P("CHECK fight states", (fight(A[2]) == "lose_bad" and fight(B[1]) == "win_big" and fight(A[3]) == "win" and fight(B[2]) == "lose"
  and fight(B[3]) == nil) and "yes" or "no")
P("CHECK game's verdict read", (fight(A[4]) == "win" and rec(A[4]).nat == "win" and rec(A[3]).nat == nil) and "yes" or "no", "context reads", CCV)
-- conditions from the units' own points of view, and the unit each one names
local function cond(id, u) local ok, t1, t2 = ENG.cond(id, rec(u)) return ok and (t1 and t1.u.key or "-") .. "/" .. (t2 and t2.u.key or "-") or "false" end
local C = {
  { "self_losing", A[2], "orc_big/-" }, { "self_losing_bad", A[2], "orc_big/-" }, { "self_winning", A[2], "false" },
  { "self_winning", A[3], "gob/-" }, { "self_winning_big", A[3], "false" }, { "self_losing", A[4], "false" }, { "self_winning", A[4], "orc_c/-" },
  { "ally_losing", A[5], "losing_sp/orc_big" }, { "ally_losing_bad", A[5], "losing_sp/orc_big" }, { "ally_winning", A[5], "winning_sw/gob" },
  { "lord_near", A[5], "lord/-" }, { "enemy_near", A[2], "orc_big/-" }, { "in_melee", A[3], "gob/-" }, { "hp_lt_25", A[2], "false" },
}
local bad = 0
for _, c in ipairs(C) do local r = cond(c[1], c[2]) if r ~= c[3] then bad = bad + 1 end P("COND", c[1], c[2].key, r, r == c[3] and "" or ("expected " .. c[3])) end
P("CHECK fight conditions", bad == 0 and "yes" or "no")
-- targets
local ea = ENG.target("enemy_winning_fight", rec(A[5])) local el = ENG.target("enemy_losing_fight", rec(A[5])) local al = ENG.target("ally_losing_fight", rec(A[5]))
P("targets", ea and ea.u.key, el and el.u.key, al and al.u.key)
P("CHECK fight targets", (ea and ea.u.key == "orc_big" and el and el.u.key == "gob" and al and al.u.key == "losing_sp") and "yes" or "no")
for k, s in pairs(got) do P("ROW", k, s) end
local heal = false for _, c in ipairs(CASTS) do P("CAST", c) if c == "lord:heal->losing_sp" then heal = true end end
P("CHECK trigger targets", (got.helper_atk == "attack->orc_big" and got.helper_grd == "guard->losing_sp" and got.helper_none == "hold->helper_none" and heal) and "yes" or "no")
fire("BattleConflictFinished",{})
