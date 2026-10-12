-- deployment editing scenario: CD_SCN=deploy. The tactics engine sets the units up during deployment; the
-- battle tactics panel changes their rows (paradigm I and II) before the fight; the battle then uses them.
local V = {} V.__index = V
function v(x,y,z) return setmetatable({x=x,y=y,z=z},V) end
function V:get_x() return self.x end function V:get_y() return self.y end function V:get_z() return self.z end
local T0 = 0
local Unit = {} Unit.__index = Unit
local nextid = 5001
local function mk(key,x,z,o) o=o or {} local u=setmetatable({key=key,x=x,z=z,men=o.men or 120,alive=o.men or 120,id=nextid,o=o,melee=false,hp=1},Unit) nextid=nextid+1 return u end
function Unit:position() return v(self.x,10,self.z) end
function Unit:type() return self.key end
function Unit:number_of_men_alive() return self.alive end
function Unit:initial_number_of_men() return self.men end
function Unit:is_shattered() return false end
function Unit:is_routing() return false end
function Unit:is_in_melee() return false end
function Unit:is_wavering() return false end
function Unit:is_under_missile_attack() return false end
function Unit:is_commanding_unit() return self.o.general or false end
function Unit:can_fly() return false end
function Unit:is_cavalry() return self.o.cav or false end
function Unit:unique_ui_id() return self.id end
function Unit:is_visible_to_alliance() return true end
function Unit:ammo_left() return 0 end
function Unit:unary_hitpoints() return self.hp end
function Unit:starting_ammo() return 0 end
function Unit:unit_class() return self.o.cav and "cav_shk" or "inf_mel" end
function Unit:can_perform_special_ability() return false end
function Unit:is_script_controlled() return false end
local function coll(t) return {count=function() return #t end, item=function(_,i) return t[i] end} end

local A = { mk("lord",0,-60,{general=true,men=1}), mk("spear",0,0), mk("knight",80,0,{cav=true,men=60}) }
local B = { mk("orc",0,300), mk("wolf",80,300,{cav=true,men=60}) }
local f = io.open("cinematic_director_tactics.txt","w")
f:write("force 77 20\n")
f:write("unit 1 lord 101 20 hero always,self,hold\n")
f:write("unit 2 spear 102 2 melee always,nearest_enemy,attack;early,self,hold\n")
f:write("unit 3 knight 103 4 cavalry always,nearest_enemy,charge\n")
f:close()

local army = {units=function() return coll(A) end, is_player_controlled=function() return true end}
local als = coll({ {armies=function() return coll({army}) end}, {armies=function() return coll({{units=function() return coll(B) end}}) end} })
local CB, SEL, LOCK = {}, {}, {}
bm = setmetatable({ get_terrain_height=function() return 10 end, alliances=function() return als end, get_player_alliance_num=function() return 1 end,
  repeat_real_callback=function(_,f,ms,n) CB[n]={f=f,ms=ms,acc=0} end, remove_real_callback=function(_,n) CB[n]=nil end,
  is_conflict_phase=function() return T0>10 end, is_multiplayer=function() return false end,
  disable_orders=function(_,b) LOCK[#LOCK+1]=string.format("%s@%.1f", tostring(b), T0) end,
  register_unit_selection_callback=function(_,u,fn) SEL[u]=fn end },
  {__index=function() return function() end end})
local NAMES = { spear="State Troops Spearmen", knight="Empire Knights", lord="Karl Franz", orc="Orc Boyz", wolf="Wolf Riders" }
common.get_localised_string=function(k) local u=k:match("^land_units_onscreen_name_(.*)$") return u and NAMES[u] or "" end
script_unit = { new=function(_,u,ref) local uc={}
  function uc:take_control() end function uc:release_control() end function uc:perform_special_ability() end
  function uc:attack_unit(t) u.chase=t end function uc:halt() u.chase=nil end function uc:goto_location() end
  return {unit=u, name=ref, uc=uc} end }
dofile(MODDIR.."script/battle/mod/cinematic_director_tactics.lua")
dofile(MODDIR.."script/battle/mod/cinematic_director_tactics_panel.lua")
local ENG, PNL, T = CD_TACTICS_ENGINE, CD_TACTICS_PANEL, CD_TACTICS
local function entry(u) for _, e in ipairs(ENG.units()) do if e.unit == u then return e end end end
local function click(id) fire("ComponentLClickUp",{string=id}) PNL.draw() end
local function vis(id) local c = U.find(root, id) return c and c.vis and true or false end
local function step() T0 = T0 + 0.1 for n, c in pairs(CB) do c.acc = c.acc + 100 if c.acc >= c.ms then c.acc = 0 c.f() end end end
-- the picker's category and option numbers for a choice
local function where(kind, id, need)
  local cats
  if kind == "c" then cats = T.categories(T.CONDITIONS, 3)
  elseif kind == "a" then cats = T.categories(T.ACTIONS, 4)
  else cats = T.categories(T.TARGETS, 4, function(x) return x[3] == need end) end
  for j, g in ipairs(cats) do for k, x in ipairs(g[2]) do if x[1] == id then return j, k end end end
end
local function choose(kind, id, need) local j, k = where(kind, id, need) click("cd_bt_pcat_" .. j) click("cd_bt_opt_" .. k) end

while T0 < 2 do step() end
local sp = entry(A[2])
P("deploying", ENG.deploying(), "running", ENG.running(), "units", #ENG.units(), "locks", table.concat(LOCK, " "))
P("CHECK set up during deployment", (ENG.deploying() and not ENG.running() and sp and #LOCK == 0) and "yes" or "no")

-- click the spearmen; the card shows; click row 1, pick When "Always", then Do "Hold position"
SEL[A[2]](A[2], true)
local card = vis("cd_bt_panel")
click("cd_bt_rowb_1")
local picker_c = vis("cd_bt_pick") and PNL.state.ekind == "c"
choose("c", "always")
local j = where("a", "hold") click("cd_bt_pcat_" .. j)
shot("e1_deploy_picker")
choose("a", "hold")
P("spear rows", T.serialise(sp.tactics), "next cell", tostring(PNL.state.ekind))
local ok1 = sp.tactics[1][1] == "always" and sp.tactics[1][3] == "hold" and sp.tactics[1][2] == "self" and PNL.state.ekind == nil
-- row 2: When "Self HP below 50%", Do "Guard", Target "Our lord" (the action needs an ally: the target becomes one)
click("cd_bt_rowb_2")
choose("c", "hp_lt_50")
P("after When", tostring(PNL.state.ekind))
choose("a", "guard")
P("after Do", tostring(PNL.state.ekind), T.serialise(sp.tactics))
local fits = sp.tactics[2][2] == "ally_lord"
choose("t", "ally_engaged", "a")
shot("e2_deploy_row")
local ok2 = sp.tactics[2][1] == "hp_lt_50" and sp.tactics[2][3] == "guard" and sp.tactics[2][2] == "ally_engaged" and fits
P("spear rows", T.serialise(sp.tactics))
P("CHECK deployment editing", (card and picker_c and ok1 and ok2) and "yes" or "no")

-- paradigm II: it follows I until changed; change its row 1 to charge enemy cavalry
local follows = T.serialise(sp.sets[2]) == T.serialise(sp.tactics)
click("cd_para_2")
P("editing paradigm", PNL.state.edit_k)
click("cd_bt_rowb_1") click("cd_bt_cell_a")
choose("a", "charge")
P("after charge", tostring(PNL.state.ekind), T.serialise(sp.sets[2]))
choose("t", "enemy_cavalry", "e")
shot("e3_deploy_paradigm2")
P("sets", T.serialise(sp.sets[1]), "|", T.serialise(sp.sets[2]), "|", T.serialise(sp.sets[3]))
P("CHECK paradigm editing", (follows and PNL.state.edit_k == 2 and T.serialise(sp.sets[2]):find("^always,enemy_cavalry,charge") ~= nil
  and sp.tactics[1][3] == "hold" and T.serialise(sp.sets[3]) == T.serialise(sp.sets[1])) and "yes" or "no")

-- clicks read from button states (in game the click events never arrived): down, then hover = a click
click("cd_bt_pclose") PNL.state.edit_k = 1
local rb = U.find(root, "cd_bt_rowb_3")
rb.st = "down" step() step() rb.st = "hover" step() step()
P("state click: row", tostring(PNL.state.erow), "cell", tostring(PNL.state.ekind))
P("CHECK clicks from button states", (PNL.state.erow == 3 and PNL.state.ekind == "c" and vis("cd_bt_pick")) and "yes" or "no")
click("cd_bt_pclose")

-- the battle starts: the edited rows are used, orders lock only now, the editor closes
while T0 < 14 do step() end
local st = ENG.state(sp) or {}
P("running", ENG.running(), "locks", table.concat(LOCK, " "), "spear does", tostring(st.act), "picker", vis("cd_bt_pick"), "row buttons", vis("cd_bt_rowb_1"))
P("CHECK battle uses the edits", (ENG.running() and st.act == "hold" and #LOCK == 1 and LOCK[1]:find("^true@1[01]") and not vis("cd_bt_pick")
  and not vis("cd_bt_rowb_1") and not vis("cd_bt_cell_c")) and "yes" or "no")
-- edits refused once the battle runs
P("CHECK no edits in battle", (ENG.set_rows(sp, 1, {{"always","self","retreat"}}) == false and sp.tactics[1][3] == "hold") and "yes" or "no")
-- paradigm II in battle: row 1 charges enemy cavalry
ENG.paradigm(2)
while T0 < 18 do step() end
st = ENG.state(sp) or {}
P("paradigm II: spear does", tostring(st.act), st.target_unit and st.target_unit.key)
P("CHECK paradigm II used", (st.act == "charge" and st.target_unit == B[2]) and "yes" or "no")
fire("BattleConflictFinished",{})
