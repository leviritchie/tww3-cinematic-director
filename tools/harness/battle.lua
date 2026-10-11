local V = {} V.__index = V
function v(x,y,z) return setmetatable({x=x,y=y,z=z},V) end
function V:get_x() return self.x end function V:get_y() return self.y end function V:get_z() return self.z end
T = 0
local Unit = {} Unit.__index = Unit
local nextid = 1001
local function mk(key,x,z,o) o=o or {} local u=setmetatable({key=key,x=x,z=z,men=o.men or 120,alive=o.men or 120,id=nextid,o=o,melee=false,hp=1,goal=nil},Unit) nextid=nextid+1 return u end
function Unit:position() return v(self.x,10,self.z) end
function Unit:type() return self.key end
function Unit:number_of_men_alive() return self.alive end
function Unit:initial_number_of_men() return self.men end
function Unit:is_shattered() return false end
function Unit:is_routing() return self.hp <= 0.05 end
function Unit:is_in_melee() return self.melee end
function Unit:is_under_missile_attack() return false end
function Unit:is_commanding_unit() return self.o.general or false end
function Unit:can_fly() return false end
function Unit:is_cavalry() return self.o.cav or false end
function Unit:unique_ui_id() return self.id end
function Unit:is_visible_to_alliance() return not self.hidden end
function Unit:ammo_left() return self.o.ammo or 0 end
function Unit:unary_hitpoints() return self.hp end
function Unit:starting_ammo() return self.o.ammo or 0 end
function Unit:is_moving_fast() return false end
function Unit:bearing() return 0 end
function Unit:unit_class() return self.o.class or (self.o.cav and "cav_shk" or (self.o.ammo and "inf_mis" or "inf_mel")) end
function Unit:number_of_enemies_killed() return self.kills or 0 end
function Unit:is_wavering() return self.hp < 0.3 and self.hp > 0.05 end
function Unit:is_rear_flank_threatened() return self.rear_override or self.rear or false end
function Unit:is_left_flank_threatened() return false end
function Unit:is_right_flank_threatened() return self.flank or false end
function Unit:current_target() return self.foe_override or self.foe end
function Unit:is_currently_flying() return false end
function Unit:can_perform_special_ability(k) return (self.o.general or self.o.hero) and (k=="fireball" or k=="heal") end
local function coll(t) return {count=function() return #t end, item=function(_,i) return t[i] end} end
-- player army: lord, 2 spears, archers, cavalry, hero ; enemy: 3 inf, archers, cav, monster
local A = { mk("lord_k",0,0,{general=true,men=1}), mk("spear",30,0), mk("spear",60,0), mk("archer",45,-30,{ammo=20}), mk("knight",150,0,{cav=true,men=60}), mk("wizard",20,-20,{hero=true,men=1}) }
local B = { mk("orc",0,200), mk("orc",30,200), mk("orc",60,200), mk("orc_arch",45,230,{ammo=20}), mk("wolf_ror",150,200,{cav=true,men=60}), mk("giant",80,210,{men=1,class="mon_giant"}) }
B[1].hidden=true
local army = {units=function() return coll(A) end, is_player_controlled=function() return true end}
local als = coll({ {armies=function() return coll({army}) end}, {armies=function() return coll({{units=function() return coll(B) end}}) end} })
CB = {} SELCB = {}
bm = { get_terrain_height=function() return 10 end, alliances=function() return als end, get_player_alliance_num=function() return 1 end,
  repeat_real_callback=function(_,f,ms,n) CB[n]={f=f,ms=ms,acc=0} end, remove_real_callback=function(_,n) CB[n]=nil end,
  is_conflict_phase=function() return T>3 end, is_multiplayer=function() return os.getenv("CD_MP")=="1" end, remove_process=function() end, register_unit_selection_callback=function(_,u,f) SELCB[u]=f end, disable_orders=function(_,b) P("disable_orders",b) end }
CASTS, ORDERS = {}, {}
local CAM = setmetatable({position=function() return v(0,60,-80) end}, {__index=function() return function() end end})
bm.camera=function() return CAM end
UNIT_IDS = {}
bm.enable_unit_ids=function(_,b) UNIT_IDS[#UNIT_IDS+1]=tostring(b) end
setmetatable(bm, {__index=function(_,k) return function() end end})
core.get_tm=function() return {real_callback=function(_,f) f() end} end
d_to_r = math.rad
local NAMES = {lord_k="Karl Franz", spear="State Troops Spearmen", archer="Crossbowmen", knight="Empire Knights", wizard="Battle Wizard",
  orc="Orc Boyz", orc_arch="Orc Arrer Boyz", wolf_ror="Da Warlord's Wolf Riders", giant="Giant"}
common.get_localised_string=function(k) local u=k:match("^land_units_onscreen_name_(.*)$") return u and NAMES[u] or "" end
function root:Bounds() local w,h=1920,1080 for _,c in ipairs(self.children) do if c.vis then local x,y=c:abs() w=math.max(w,x+c.w) h=math.max(h,y+c.h) end end return w,h end
do local h=root:CreateComponent("hud_battle","x/other.twui.xml") h:Resize(1920,1080) h:SetVisible(true)
  local cc=root.CreateComponent
  root.CreateComponent=function(self,id,path) local c=cc(self,id,path) if path:find("scripted_subtitles") then local t=c:CreateComponent("text_child","x/txt.twui.xml") t:SetVisible(false) c:Resize(600,60) end return c end end
local function goal(u,tx,tz) u.goal={tx,tz} end
UCO = {}
script_unit = { new=function(_,u,ref) local uc={perform_special_ability=function(_,k,t) CASTS[#CASTS+1]=k.."->"..t.key end}
  function uc:take_control() ORDERS.take_control=(ORDERS.take_control or 0)+1 end
  function uc:release_control() ORDERS.release_control=(ORDERS.release_control or 0)+1 if os.getenv("CD_CANCEL") then u.chase=nil u.goal=nil end end
  function uc:attack_unit(t,prim,run) assert(t.position and type(prim)=="boolean","bad attack_unit args") UCO[u.key..u.id]=(UCO[u.key..u.id] or 0)+1 ORDERS["attack_unit"..(prim and "" or "(melee)")]=(ORDERS["attack_unit"..(prim and "" or "(melee)")] or 0)+1 u.chase=t u.goal=nil u.guard=nil end
  function uc:halt() ORDERS.halt=(ORDERS.halt or 0)+1 u.chase=nil u.goal=nil end
  function uc:goto_location(p2,run) ORDERS.goto_location=(ORDERS.goto_location or 0)+1 u.chase=nil u.goal={p2.x,p2.z} end
  return {unit=u, name=ref, uc=uc} end }
script_ai_planner = { new=function(_,name,list) local s=list[1]; local p={}
  local function rec(f) ORDERS[f]=(ORDERS[f] or 0)+1 end
  function p:attack_force(l) rec("attack_force") s.unit.chase=l[1].unit end
  function p:rush_force(l) rec("rush_force") s.unit.chase=l[1].unit end
  function p:defend_position(p2,r) rec("defend_position") s.unit.chase=nil goal(s.unit,p2.x,p2.z) end
  function p:defend_force(o,r) rec("defend_force") s.unit.chase=nil s.unit.guard=o.unit end
  function p:move_to_position(p2) rec("move_to_position") s.unit.chase=nil goal(s.unit,p2.x,p2.z) end
  function p:release() rec("release") end
  return p end }
CD_DIRECTOR_NOTIFY = function(k,c,t) end
CD_ABILITIES = { D={"fireball"}, R={"heal"} }
-- export file: lord rank 9 (5 slots) with custom tactics; spear#2 rank 4 (3 slots) with a guard tactic; knight rank 0
local f = io.open("cinematic_director_tactics.txt","w")
f:write("# test\nforce 77\n")
f:write("unit 1 lord_k 11 9 hero always,enemy_large,cast_attack;hp_lt_50,ally_weakest,cast_buff;always,nearest_enemy,attack\n")
f:write("unit 2 spear 12 4 melee lord_in_melee,ally_lord,guard;always,nearest_enemy,attack\n")
f:write("unit 3 spear 13 4 melee enemy_cav_near,enemy_engaged,flank;few_enemies,enemy_weakest,melee;always,ally_missile,cover\n")
f:write("unit 4 archer 14 2 missile enemy_near_40,self,to_lord;always,enemy_archers,skirmish\n")
f:write("unit 5 knight 15 2 cavalry early,enemy_artillery,flank;always,enemy_isolated,charge\n")
f:write("unit 6 wizard 16 6 hero always,nearest_enemy,cast_attack;always,ally_lord,guard\n")
f:close()
P("load", pcall(dofile, MODDIR.."script/battle/mod/cinematic_director_tactics.lua"))
P("load panel", pcall(dofile, MODDIR.."script/battle/mod/cinematic_director_tactics_panel.lua"))
P("load director", pcall(dofile, MODDIR.."script/battle/mod/cinematic_director.lua"))
P("load hud", pcall(dofile, MODDIR.."script/battle/mod/cinematic_director_hud.lua"))
for i=1,900 do -- 90 s
  T=i*0.1
  for _,u in ipairs(A) do
    local tx,tz
    if u==A[3] and T<25 then elseif u.chase then tx,tz=u.chase.x,u.chase.z elseif u.guard then tx,tz=u.guard.x,u.guard.z-10 elseif u.goal then tx,tz=u.goal[1],u.goal[2] end
    if tx then local dx,dz=tx-u.x,tz-u.z local d=math.sqrt(dx*dx+dz*dz) if d>3 then u.x=u.x+dx/d*0.6 u.z=u.z+dz/d*0.6 end end
  end
  for _,b in ipairs(B) do b.z=b.z-0.3 b.x=b.x+math.sin(T*0.7+b.id)*0.5 end
  for _,a in ipairs(A) do a.melee=false a.foe=nil a.rear=false a.flank=false end
  for _,b in ipairs(B) do b.melee=false b.foe=nil for _,a in ipairs(A) do if math.abs(a.x-b.x)<8 and math.abs(a.z-b.z)<8 then
    if a.melee then a.rear=(b.o.cav or false) a.flank=true end
    a.melee=true b.melee=true a.hp=a.hp-0.002 b.hp=b.hp-0.003 a.foe=a.foe or b b.foe=b.foe or a
    a.kills=(a.kills or 0)+(a.men<=8 and 0.4 or 0.15) b.kills=(b.kills or 0)+(b.men<=8 and 0.5 or 0.1) end end end
  for n,c in pairs(CB) do c.acc=c.acc+100 if c.acc>=c.ms then c.acc=0 c.f() end end
  if i==200 then shot("b1_lord") end
  if i==210 then SELCB[A[4]](A[4], true) end
  if i==260 then shot("b2_archers") end
  if i==300 then SELCB[A[6]](A[6], true) end
  if i==420 then shot("b3_wizard") end
  if i==430 then fire("ComponentLClickUp",{string="cd_bt_close"}) end
  if i==440 then shot("b4_folded") fire("ComponentLClickUp",{string="cd_bt_close"}) fire("ComponentLClickUp",{string="cd_bt_next"}) end
  if i==500 then shot("b5_next") end
  if i%100==0 then local pn=U.find(root,"cd_bt_panel") P("panel x", T, pn and pn:abs()) end
  if i==20 then shot("b0_probes") end
  if i==40 then fire("ShortcutPressed",{string="toggle_tracking"}) end
  if i==150 then shot("h1_full") end
  if i==320 then fire("ComponentLClickUp",{string="cd_hud_mode"}) end
  if i==330 then shot("h2_film") fire("ComponentLClickUp",{string="cd_hud_mode"}) end
  if i==340 then shot("h3_clean") fire("ComponentLClickUp",{string="cd_hud_mode"}) end
  if i==350 then P("banners", table.concat(UNIT_IDS," ")) fire("ComponentLClickUp",{string="cd_hud_banners"}) shot("h3b_banners_on") end
  if i==360 then fire("ComponentLClickUp",{string="cd_hud_banners"}) P("banners", table.concat(UNIT_IDS," ")) end
  -- scripted duel (giant vs lord) and a rear attack on a spear regiment
  if i>=450 and i<540 then B[6].x,B[6].z=A[1].x+4,A[1].z+4 A[1].foe_override=B[6] B[6].foe_override=A[1] end
  if i==540 then A[1].foe_override=nil B[6].foe_override=nil end
  A[2].rear_override = (i>=480 and i<500 and A[2].melee) or nil
  if i==560 then for k=1,3 do B[k].hp=0.04 end B[6].alive=0 B[5].hp=0.3 end
  if i==700 then shot("h4_finale") end
  if i==760 then fire("ShortcutPressed",{string="toggle_tracking"}) end
  if i==780 then shot("h5_off") end
  if i==600 then local r=mk("spear",-40,-60) A[#A+1]=r P("reinforcement arrives", r.id) end
end
P("banners at end", table.concat(UNIT_IDS," "))
fire("BattleConflictFinished",{})
P("casts",#CASTS,table.concat(CASTS," ",1,math.min(#CASTS,6)))
for k,v in pairs(ORDERS) do P(k,v) end
for k,v in pairs(UCO) do P("attack orders",k,v) end
