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
bm = { get_terrain_height=function(_,x,z) return 10 + (x or 0)*0.04 end, alliances=function() return als end, get_player_alliance_num=function() return 1 end,
  repeat_real_callback=function(_,f,ms,n) CB[n]={f=f,ms=ms,acc=0} end, remove_real_callback=function(_,n) CB[n]=nil end,
  is_conflict_phase=function() return T>3 end, is_multiplayer=function() return os.getenv("CD_MP")=="1" end, remove_process=function() end, register_unit_selection_callback=function(_,u,f) SELCB[u]=f end, disable_orders=function(_,b) P("disable_orders",b) end }
CASTS, ORDERS = {}, {}
-- camera: linear interpolation from where it is to the move_to goal over the given time (engine behaviour assumed)
CAMS = {p={0,60,-80}, from={0,60,-80}, goal={0,60,-80}, t0=0, dur=0, moves=0, maxy=0}
local function cam_now() local c=CAMS if c.dur<=0 then return c.goal end local f=math.min((T-c.t0)/c.dur,1) return {c.from[1]+(c.goal[1]-c.from[1])*f, c.from[2]+(c.goal[2]-c.from[2])*f, c.from[3]+(c.goal[3]-c.from[3])*f} end
local function targ_now() local c=CAMS if not c.targ then return nil end if c.dur<=0 or not c.tfrom then return c.targ end local f=math.min((T-c.t0)/c.dur,1) return {c.tfrom[1]+(c.targ[1]-c.tfrom[1])*f, c.tfrom[2]+(c.targ[2]-c.tfrom[2])*f, c.tfrom[3]+(c.targ[3]-c.tfrom[3])*f} end
local function fov_now() local c=CAMS if not c.fov then return 45 end if c.dur<=0 or not c.ffrom then return c.fov end local f=math.min((T-c.t0)/c.dur,1) return c.ffrom+(c.fov-c.ffrom)*f end
-- independent check of the HUD's callouts: project a world point through the simulated engine camera
-- (look-at, vertical fov, +x right when looking along +z)
local function cam_project(wx,wy,wz) local p,t=cam_now(),targ_now() if not t then return nil end
  local fx,fy,fz=t[1]-p[1],t[2]-p[2],t[3]-p[3] local l=math.sqrt(fx*fx+fy*fy+fz*fz) fx,fy,fz=fx/l,fy/l,fz/l
  local rx,rz=fz,-fx local rl=math.sqrt(rx*rx+rz*rz) rx,rz=rx/rl,rz/rl
  local ux,uy,uz=fy*rz, fz*rx-fx*rz, -fy*rx
  local dx,dy,dz=wx-p[1],wy-p[2],wz-p[3] local Z=dx*fx+dy*fy+dz*fz if Z<1 then return nil end
  local th=math.tan(math.rad(fov_now())/2) return 960+(dx*rx+dz*rz)/(Z*th)*540, 540-(dx*ux+dy*uy+dz*uz)/(Z*th)*540 end
local CAM = setmetatable({position=function() local p=cam_now() return v(p[1],p[2],p[3]) end, target=function() local t=targ_now() or {0,0,0} return v(t[1],t[2],t[3]) end,
  move_to=function(_,pos,targ,dur,_c,fov) local c=CAMS c.from=cam_now() c.tfrom=targ_now() c.ffrom=fov_now() c.fov=(fov and fov>0) and fov or 45 c.goal={pos.x,pos.y,pos.z} c.targ={targ.x,targ.y,targ.z} c.t0=T c.dur=dur or 0 c.moves=c.moves+1 c.maxy=math.max(c.maxy,pos.y) end},
  {__index=function() return function() end end})
CD_REAL_CLOCK = function() return T end
bm.camera=function() return CAM end
UNIT_IDS = {}
-- battle speed (slow motion): scales the simulation; every change is logged
SPEED, SPEEDS, ARMYPANEL = 1, {}, {}
bm.current_battle_speed=function() return SPEED end
bm.modify_battle_speed=function(_,s) SPEED=s SPEEDS[#SPEEDS+1]={T,s} P("SPEED",T,s) end
bm.show_army_panel=function(_,b) ARMYPANEL[#ARMYPANEL+1]=tostring(b) end
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
-- the unit cards (battle_orders > cards_panel), 150 px tall at the bottom
do local bo=root:CreateComponent("battle_orders","x/other.twui.xml") bo:Resize(800,170) bo:MoveTo(560,910) bo.prio=5
  local cp=bo:CreateComponent("cards_panel","x/other.twui.xml") cp:Resize(800,150) cp:SetDockOffset(0,20)
  -- the cards: review_DY > one card per unit (its CcoBattleUnit context id is the unit's unique_ui_id), each with a portrait
  local rv=cp:CreateComponent("review_DY","x/other.twui.xml") rv:Resize(800,150)
  for k,u in ipairs(A) do local c=rv:CreateComponent("unit_card_"..k,"x/other.twui.xml") c:Resize(70,110) c:SetDockOffset(20+(k-1)*76,20) c.ctx=tostring(u.id)
    local pt=c:CreateComponent("portrait","x/other.twui.xml") pt:Resize(60,80) pt:SetDockOffset(5,5) end end
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
f:write("# test\nforce 77 12\n")
f:write("unit 1 lord_k 11 3 hero always,enemy_large,duelist;always,self,caster;hp_lt_25,self,to_lord;always,self,kill_lord;hp_lt_50,ally_weakest,cast_buff\n")
f:write("unit 2 spear 12 4 melee lord_in_melee,ally_lord,guard;always,nearest_enemy,attack\n")
f:write("unit 3 spear 13 0 melee always,self,hammer;hp_lt_25,self,regroup\n")
f:write("unit 4 archer 14 2 missile always,self,focus;hp_lt_25,self,to_lord\n")
f:write("unit 5 knight 15 2 cavalry always,self,disrupt;always,self,hammer\n")
f:write("unit 6 wizard 16 1 hero always,self,caster;always,nearest_enemy,sp_fireball\n")
f:close()
P("load", pcall(dofile, MODDIR.."script/battle/mod/cinematic_director_tactics.lua"))
P("load panel", pcall(dofile, MODDIR.."script/battle/mod/cinematic_director_tactics_panel.lua"))
P("load director", pcall(dofile, MODDIR.."script/battle/mod/cinematic_director.lua"))
P("load hud", pcall(dofile, MODDIR.."script/battle/mod/cinematic_director_hud.lua"))
-- the floating banners: unit_id_holder > <unique_ui_id> > parts and script_ping_parent
-- (48x75 as in game, centred over the unit with its bottom 57 px above the unit's heads, moved each tick;
-- every unit but the giant has one, so the giant's callouts are placed by projection)
MPRUN = os.getenv("CD_MP")=="1"
BANNERS = {}
do local hd=root:CreateComponent("unit_id_holder","x/other.twui.xml") hd:Resize(10,10)
  for _,u in ipairs(A) do local b=hd:CreateComponent(tostring(u.id),"x/other.twui.xml") b:Resize(48,75) b:MoveTo(100+u.id%10*80,300) BANNERS[u]=b
    b:CreateComponent("banner_flag","x/other.twui.xml"):Resize(48,20) b:CreateComponent("script_ping_parent","x/other.twui.xml"):Resize(1,1) end
  for k=1,5 do local u=B[k] local b=hd:CreateComponent(tostring(u.id),"x/other.twui.xml") b:Resize(48,75) BANNERS[u]=b end end
local function move_banners() for u,b in pairs(BANNERS) do local px,py=cam_project(u.x,13,u.z) if px and u.alive>0 then b.vis=true b:MoveTo(px-24,py-57-75) else b.vis=false end end end
P("load probe", pcall(dofile, MODDIR.."script/battle/mod/cinematic_director_probe.lua"))
-- CD_GALLOP=1: cavalry ride at 18 m/s (a real charge) instead of 6, to test the close charge cam
GALLOP = os.getenv("CD_GALLOP") == "1"
CC = {}
for i=1,900 do -- 90 s
  T=i*0.1
  pcall(move_banners)
  for _,u in ipairs(A) do
    local tx,tz
    if u==A[3] and T<25 then elseif u.chase then tx,tz=u.chase.x,u.chase.z elseif u.guard then tx,tz=u.guard.x,u.guard.z-10 elseif u.goal then tx,tz=u.goal[1],u.goal[2] end
    if tx then local dx,dz=tx-u.x,tz-u.z local d=math.sqrt(dx*dx+dz*dz) local st=((u.o.cav and GALLOP) and 1.8 or 0.6)*SPEED if d>3 then st=math.min(st,d-3) u.x=u.x+dx/d*st u.z=u.z+dz/d*st end end
  end
  for _,b in ipairs(B) do b.z=b.z-0.3*SPEED b.x=b.x+math.sin(T*0.7+b.id)*0.5*SPEED end
  -- the wolf riders charge your crossbowmen at a gallop (the brace cam)
  if i==470 then WOLF=mk("wolf_ror",A[4].x+40,A[4].z-100,{cav=true,men=60}) B[#B+1]=WOLF P("wolf riders arrive", WOLF.id) end
  if WOLF and os.getenv("CD_TRACE_WOLF") and i%2==0 and i>=480 and i<620 then local t=A[4] P("WTRACE",T,string.format("wolf %.1f,%.1f hp %.3f melee %s archers %.1f,%.1f d %.1f", WOLF.x, WOLF.z, WOLF.hp, tostring(WOLF.melee), t.x, t.z, math.sqrt((WOLF.x-t.x)^2+(WOLF.z-t.z)^2))) end
  if WOLF and i>=480 then local u,t=WOLF,A[4] local dx,dz=t.x-u.x,t.z-u.z local d=math.sqrt(dx*dx+dz*dz) if d>4 then local st=math.min(1.8*SPEED,d-4) u.x=u.x+dx/d*st u.z=u.z+dz/d*st end end
  -- a second fight far from the main one (two places at once): knights meet the wolf riders off to the side
  if i>=380 and i<440 then A[5].x,A[5].z=230,95 B[5].x,B[5].z=234,99 end
  for _,a in ipairs(A) do a.melee=false a.foe=nil a.rear=false a.flank=false end
  for _,b in ipairs(B) do b.melee=false b.foe=nil for _,a in ipairs(A) do if math.abs(a.x-b.x)<8 and math.abs(a.z-b.z)<8 then
    if a.melee then a.rear=(b.o.cav or false) a.flank=true end
    a.melee=true b.melee=true a.hp=a.hp-0.002*SPEED b.hp=b.hp-0.003*SPEED a.foe=a.foe or b b.foe=b.foe or a
    a.kills=(a.kills or 0)+(a.men<=8 and 0.4 or 0.15) b.kills=(b.kills or 0)+(b.men<=8 and 0.5 or 0.1) end end end
  for n,c in pairs(CB) do c.acc=c.acc+100 if c.acc>=c.ms then c.acc=0 c.f() end end
  -- the close charge cam: where the camera is against the riders each tick (behind, beside, height, pitch,
  -- its speed against theirs, and how much its speed jumps from one tick to the next)
  do local sh=CD_DIRECTOR.active() and CD_DIRECTOR.shot() if sh and sh.type=="charge_close" and CAMS.targ then
    local p,t=cam_now(),targ_now() local u,q=sh.c.u,sh.partner.u
    local fx,fz=q.x-u.x,q.z-u.z local l=math.sqrt(fx*fx+fz*fz) if l>1 then fx,fz=fx/l,fz/l else fx,fz=sh.fx,sh.fz end
    local behind=-((p[1]-u.x)*fx+(p[3]-u.z)*fz) local side=math.abs((p[1]-u.x)*-fz+(p[3]-u.z)*fx)
    local hgt=p[2]-(10+p[1]*0.04) local dx,dy,dz=t[1]-p[1],t[2]-p[2],t[3]-p[3] local pit=math.deg(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
    local r=CC[sh.n] if not r then r={n=sh.n,ticks=0,dv=0,dvmax=0,bmin=1e9,bmax=-1e9,hmin=1e9,hmax=0,pmax=-90,spd=0,uspd=0,run=0} CC[sh.n]=r CC[#CC+1]=r end
    r.ticks=r.ticks+1
    if r.lp then local sp=math.sqrt((p[1]-r.lp[1])^2+(p[3]-r.lp[3])^2)/0.1 local us=math.sqrt((u.x-r.lu[1])^2+(u.z-r.lu[2])^2)/0.1
      if r.lsp then local dv=math.abs(sp-r.lsp) r.dv=r.dv+dv r.dvmax=math.max(r.dvmax,dv) if dv>5 then P("CLOSE jump",T,string.format("%.1f -> %.1f m/s, el %.1f hit %s", r.lsp, sp, sh.elapsed, tostring(sh.hit_t))) end end r.lsp=sp
      if not sh.hit_t then r.run=r.run+1 r.spd=r.spd+sp r.uspd=r.uspd+us r.bmin=math.min(r.bmin,behind) r.bmax=math.max(r.bmax,behind) r.smax=math.max(r.smax or 0,side) end end
    if not sh.hit_t then r.hmin=math.min(r.hmin,hgt) r.hmax=math.max(r.hmax,hgt) r.pmax=math.max(r.pmax,pit) end
    if sh.hit_t and not r.hit then r.hit=T r.hitgap=l end
    if os.getenv("CD_TRACE_CLOSE") then P("CTRACE",T,string.format("behind %.1f side %.1f cam %.1f,%.1f rider %.1f,%.1f tgt %.1f,%.1f sp %.1f hit %s", behind, side, p[1], p[3], u.x, u.z, q.x, q.z, r.lsp or -1, tostring(sh.hit_t))) end
    r.lp=p r.lu={u.x,u.z} end end
  -- the brace cam: low behind your unit, looking at the charger until the hit
  do local sh=CD_DIRECTOR.active() and CD_DIRECTOR.shot() if sh and sh.type=="charge_brace" and CAMS.targ then
    local p,t=cam_now(),targ_now() local u,q=sh.c.u,sh.partner.u
    BR=BR or {} local r=BR[sh.n] if not r then r={n=sh.n,ticks=0,hmax=0,pmax=-90,look=0,behind=1e9} BR[sh.n]=r BR[#BR+1]=r end r.ticks=r.ticks+1
    if r.ticks==6 and not BR.shot then BR.shot=true shot("d2_brace") end
    if not sh.hit_t then local hgt=p[2]-(10+p[1]*0.04) local dx,dy,dz=t[1]-p[1],t[2]-p[2],t[3]-p[3] local pit=math.deg(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
      r.hmax=math.max(r.hmax,hgt) r.pmax=math.max(r.pmax,pit) if r.ticks>2 then r.look=math.max(r.look,math.sqrt((t[1]-q.x)^2+(t[3]-q.z)^2)) end
      local fx,fz=u.x-q.x,u.z-q.z local l=math.sqrt(fx*fx+fz*fz) if l>1 then r.behind=math.min(r.behind,((p[1]-u.x)*fx+(p[3]-u.z)*fz)/l) end
    elseif not r.hit then r.hit=T end end end
  -- action shots: units hit hard
  do local sh=CD_DIRECTOR.active() and CD_DIRECTOR.shot() if sh and sh.type=="action_hit" and CAMS.targ and not (ACT and ACT[sh.n]) then
    ACT=ACT or {} ACT[sh.n]=true ACT[#ACT+1]=string.format("#%d at %.1f: %s (%s)", sh.n, T, sh.reason and sh.reason.text or "?", sh.c.friendly and "yours" or "enemy") end
    if sh and sh.type=="action_hit" and CAMS.targ and not sh.glide then local p,t=cam_now(),targ_now() local dx,dy,dz=t[1]-p[1],t[2]-p[2],t[3]-p[3]
      local pit=math.deg(math.atan2(-dy,math.sqrt(dx*dx+dz*dz))) local d=math.sqrt((p[1]-sh.c.u.x)^2+(p[3]-sh.c.u.z)^2) ACT.pmax=math.max(ACT.pmax or -90,pit) ACT.dmax=math.max(ACT.dmax or 0,d) if os.getenv("CD_TRACE_ACT") then P("ATRACE",T,string.format("#%d el %.1f pitch %.0f cam %.1f,%.1f,%.1f unit %.1f,%.1f targ %.1f,%.1f,%.1f", sh.n, sh.elapsed, pit, p[1],p[2],p[3], sh.c.u.x, sh.c.u.z, t[1],t[2],t[3])) end
      if not ACT.shot and sh.elapsed>0.6 then ACT.shot=true shot("d1_action_hit") end end end
  -- forced heavy hits out of melee: an enemy unit (just after our wizard casts at it) and one of yours
  -- no enemy within 30 m (the heavy hit detector ignores units next to enemies)
  local function clear(u) local mine=false for _,a in ipairs(A) do if a==u then mine=true end end
    for _,o in ipairs(mine and B or A) do if o.alive>0 and o.hp>0.05 and math.sqrt((o.x-u.x)^2+(o.z-u.z)^2)<30 then return false end end return true end
  local function pick(l) for _,u in ipairs(l) do if not u.melee and u.hp>0.3 and u.alive>0 and clear(u) then return u end end end
  if i==698 then HITE=pick({B[4],B[5],B[1],B[2],B[3],WOLF}) P("forced hit on", HITE and HITE.key) if HITE then CD_DIRECTOR_NOTIFY("cast",A[6],HITE) end end
  if i>=700 and i<703 and HITE then HITE.hp=HITE.hp-0.04 end
  if i==745 then HITF=pick({A[2],A[3],A[4],A[5],A[6],A[7]}) P("forced hit on", HITF and HITF.key) end
  if i>=746 and i<749 and HITF then HITF.hp=HITF.hp-0.035 end
  -- the unit cards: kept, and the banner and callouts above them
  if i>45 and i<760 and CD_DIRECTOR.active() then CARDS=CARDS or {n=0,bad=0}
    for _,id in ipairs({"cd_hud_ban","cd_hud_co1","cd_hud_co2","cd_hud_co3","cd_hud_co4"}) do local c=U.find(root,id) if c and c:shown() then local _,y=c:abs() CARDS.n=CARDS.n+1
      if y+c.h>910+20 then CARDS.bad=CARDS.bad+1 if CARDS.bad<4 then P("CARDS overlap",T,id,y+c.h) end end end end
    if i==300 then CARDS.prio=U.find(root,"battle_orders").prio end end
  if i==770 then CARDS=CARDS or {} CARDS.after=U.find(root,"battle_orders").prio end
  -- camera motion stats: speed change per step of the simulated engine camera
  do local p=cam_now() local q=CAMS.lastp if q then local sp=math.sqrt((p[1]-q[1])^2+(p[2]-q[2])^2+(p[3]-q[3])^2)/0.1
    if CAMS.lastsp then local dv=math.abs(sp-CAMS.lastsp) CAMS.dvmax=math.max(CAMS.dvmax or 0,dv) CAMS.dvsum=(CAMS.dvsum or 0)+dv CAMS.n=(CAMS.n or 0)+1 if dv>40 then CAMS.big=(CAMS.big or 0)+1 end end
    CAMS.lastsp=sp CAMS.spmax=math.max(CAMS.spmax or 0,sp) if CAMS.dur>0 and T>4.5 then CAMS.spmax_glide=math.max(CAMS.spmax_glide or 0,sp) if sp>36 then P("FAST",T,sp,CAMS.dur) end end end CAMS.lastp=p
    -- view stats while filming: facing within 60 deg of the player's view (+z, toward the enemy), and pitch down
    if i>45 and i<760 and CAMS.targ and not (CD_DIRECTOR.shot() and ({charge_close=1,charge_brace=1,action_hit=1})[CD_DIRECTOR.shot().type]) then local sh=CD_DIRECTOR.shot() if sh and sh.glide and sh.P then local g=CAMS.goal local vx,vz=CAMS.targ[1]-g[1],CAMS.targ[3]-g[3] local ux,uz=sh.P.x-g[1],sh.P.z-g[3] local a=math.deg(math.abs(math.atan2(vx*uz-vz*ux, vx*ux+vz*uz))) CAMS.gn=(CAMS.gn or 0)+1 if a<20 then CAMS.glock=(CAMS.glock or 0)+1 end local lk=sh.glide.look if lk then local wx,wz=lk[1]-g[1],lk[3]-g[3] local b=math.deg(math.abs(math.atan2(vx*wz-vz*wx, vx*wx+vz*wz))) if b<10 then CAMS.glk2=(CAMS.glk2 or 0)+1 end CAMS.gt=CAMS.gt or {} local t=CAMS.gt[sh.type] or {0,0,0} t[1]=t[1]+1 if a<20 then t[2]=t[2]+1 end if b<10 then t[3]=t[3]+1 end CAMS.gt[sh.type]=t end end local g=CAMS.goal local dx,dy,dz=CAMS.targ[1]-g[1],CAMS.targ[2]-g[2],CAMS.targ[3]-g[3] local h=math.sqrt(dx*dx+dz*dz)
      if h>1 then CAMS.vn=(CAMS.vn or 0)+1 if dz/h>math.cos(math.rad(60)) then CAMS.vhome=(CAMS.vhome or 0)+1 end
        local pit=math.deg(math.atan2(-dy,h)) if pit<12 or dz/h<0.5 then CAMS.badlog=(CAMS.badlog or 0)+1 if CAMS.badlog%5==1 then local s=CD_DIRECTOR.shot() P("BADVIEW",T,string.format("pitch %.0f facing %.0f h %.0f %s #%d el %.1f glide %s", pit, math.deg(math.atan2(dx,dz)), h, s.type, s.n, s.elapsed, tostring(s.glide~=nil))) end end CAMS.psum=(CAMS.psum or 0)+pit if pit>45 then CAMS.steep=(CAMS.steep or 0)+1 end CAMS.pmax=math.max(CAMS.pmax or -90,pit) CAMS.pmin=math.min(CAMS.pmin or 90,pit) end end end
  -- every line shown names its own event: no "and N more" summaries
  do local sh=CD_DIRECTOR.active() and CD_DIRECTOR.shot() local r=sh and sh.reason if r then
    local ls={r} for _,x in ipairs(r.extra or {}) do ls[#ls+1]=x end MORE=MORE or {bad=0,maxl=0}
    MORE.maxl=math.max(MORE.maxl,#ls) for _,x in ipairs(ls) do if x.text:find("and %d+ more") then MORE.bad=MORE.bad+1 if MORE.bad<3 then P("MORE text",T,x.text) end end end end end
  -- callouts: each shown leader line should end on its unit's head as the engine camera sees it
  if i>45 and i<760 and CD_HUD and CD_HUD.state.co then
    local hs=CD_HUD.state local boxes={} NL=0
    for k,co in ipairs(hs.co) do
      local box=U.find(root,"cd_hud_co"..k) local ln=U.find(root,"cd_hud_co"..k.."_line")
      if co.a then box=U.find(root,"cd_hud_ab_"..co.a.uid) ln=U.find(root,"cd_hud_ab_"..co.a.uid.."_line") ln=ln and ln:shown() and ln or nil AB=(AB or 0)+1 end
      if box and box:shown() then if ln and ln.vis then NL=(NL or 0)+1 end
        CO=CO or {n=0,lines=0,err=0,emax=0,over=0,multi=0,shots={},moves=0,lastpos={}} CO.n=CO.n+1
        local bx,by=box:abs() boxes[#boxes+1]={bx,by,box.w,box.h}
        local key=k..":"..tostring(co.unit.key) local lp=CO.lastpos[key] if lp and (lp[1]~=bx or lp[2]~=by) then CO.moves=CO.moves+1 end CO.lastpos[key]={bx,by}
        local u=co.unit.u local cls=u.o.class or (u.o.cav and "cav" or "") local h=cls:find("^mon") and 8 or (cls:find("cav") and 4.2) or (co.unit.big and 3.5) or 2.8
        local px,py=cam_project(u.x,10+h,u.z)
        if ln and ln.vis and px then CO.lines=CO.lines+1 local lx,ly=ln:abs() local tipy=(ly+ln.h>by+box.h-6) and (ly+ln.h) or ly local tipx=lx+1
          local hl=not co.a and U.find(root,"cd_hud_co"..k.."_hline") if hl and hl.vis then local hx=hl:abs() tipx=(math.abs(hx+1-tipx)<2) and (hx+hl.w-1) or (hx+1) end
          local e=math.sqrt((tipx-px)^2+(tipy-py)^2) CO.err=CO.err+e CO.emax=math.max(CO.emax,e) if e>40 and (CO.bad or 0)<4 then CO.bad=(CO.bad or 0)+1 P("CALLOUT off",T,string.format("line tip %.0f,%.0f unit %.0f,%.0f (%s)",tipx,tipy,px,py,CD_DIRECTOR.shot().type).." hud "..string.format("%.0f,%.0f lx %.0f hl %s", co.ax or -1, co.ay or -1, lx+1, tostring(hl and hl.vis))) end end
      end
    end
    if #boxes>1 then CO.multi=CO.multi+1 if not CO.shot_multi and i>200 and NL>=2 then CO.shot_multi=true shot("c2_callouts_multi") end end
    for a=1,#boxes do for b=a+1,#boxes do local A1,B1=boxes[a],boxes[b] if A1[1]<B1[1]+B1[3] and B1[1]<A1[1]+A1[3] and A1[2]<B1[2]+B1[4] and B1[2]<A1[2]+A1[4] then CO.over=CO.over+1 end end end
    if #boxes==1 and NL==1 and not CO.shot1 and i>120 then CO.shot1=true shot("c1_callout") end
    -- highlights: a big green/red box (render the first good and the first bad one)
    do local sh=CD_DIRECTOR.shot() local r=sh and sh.reason if r and r.highlight and #boxes>0 and NL>=1 then HLT=HLT or {} HLT[sh.n]=r.tone..": "..r.text.." ("..sh.type..")"
      local k="shot_"..r.tone HLT[k]=HLT[k] or i if HLT[k]~=true and i-HLT[k]>=5 then HLT[k]=true shot("c3_highlight_"..r.tone) end end end
  end
  if i==200 then shot("b1_lord") end
  if i==210 then (SELCB[A[4]] or function() end)(A[4], true) end
  if i==260 then shot("b2_archers") end
  if i==300 then (SELCB[A[6]] or function() end)(A[6], true) end
  if i==420 then shot("b3_wizard") end
  if i==430 then fire("ComponentLClickUp",{string="cd_bt_close"}) end
  if i==440 then shot("b4_folded") fire("ComponentLClickUp",{string="cd_bt_close"}) fire("ComponentLClickUp",{string="cd_bt_next"}) end
  if i==500 then shot("b5_next") end
  if i==520 then fire("ComponentLClickUp",{string="cd_para_2"}) fire("ComponentLClickUp",{string="cd_para_4"}) end
  if i==530 then local pp = CD_TACTICS_ENGINE.paradigms() P("PARA after clicks", pp.cur, pp.n) shot("b6_paradigm") end
  if i%100==0 then local pn=U.find(root,"cd_bt_panel") P("panel x", T, pn and pn:abs()) end
  if i==20 then shot("b0_probes") end
  if i==21 then local cw=CD_DIRECTOR.charges_well
    local function U(t) t.x=t.x or 0 t.z=t.z or 0 t.bearing=t.bearing or 0 return t end
    local kn=U{cavalry=true,class="cav_shk",z=-60}
    local cases={ {"knights -> swordsmen", kn, U{class="inf_mel"}, true}, {"knights -> archers", kn, U{class="inf_mis"}, true},
      {"knights -> artillery", kn, U{class="art_fld",big=true}, false}, {"knights -> spears facing them", kn, U{class="inf_spr",bearing=180}, false},
      {"knights -> spears from behind", kn, U{class="inf_spr",bearing=0}, true}, {"knights -> spears already fighting", kn, U{class="inf_spr",bearing=180,melee=true}, true},
      {"knights -> monster", kn, U{class="mon",big=true}, false}, {"knights -> cavalry", kn, U{class="cav_mel",cavalry=true}, false},
      {"horse archers -> archers", U{cavalry=true,class="cav_mis",z=-60}, U{class="inf_mis"}, false}, {"chariot -> swordsmen", U{class="chariot",big=true,z=-60}, U{class="inf_mel"}, true},
      {"swordsmen -> archers", U{class="inf_mel",z=-60}, U{class="inf_mis"}, false},
      {"giant -> swordsmen", U{class="mon_giant",big=true,z=-60}, U{class="inf_mel"}, true}, {"giant -> monster", U{class="mon_giant",big=true,z=-60}, U{class="mon",big=true}, false} }
    local bad=0 for _,c in ipairs(cases) do local got=cw(c[2],c[3]) and true or false if got~=c[4] then bad=bad+1 end P("MATCHUP",c[1],got and "close cam" or "no",got==c[4] and "ok" or "WRONG") end
    P("CHECK close charge matchups", bad==0 and "yes" or "no") end
  if i==22 then local hf=CD_DIRECTOR.highlight_of
    local function U(t) t.x=t.x or 0 t.z=t.z or 0 t.bearing=t.bearing or 0 t.key=t.key or tostring(t) return t end
    local ours_art, ours_arch, ours_inf, ours_kn, ours_gen = U{friendly=true,class="art_fld",big=true,ranged=true}, U{friendly=true,class="inf_mis",ranged=true}, U{friendly=true,class="inf_mel"}, U{friendly=true,cavalry=true,class="cav_shk",z=-60}, U{friendly=true,general=true,class="com"}
    local foe_inf, foe_arch, foe_cav = U{class="inf_mel"}, U{class="inf_mis",ranged=true}, U{cavalry=true,class="cav_mel"}
    local cases={ {"enemy infantry reach our artillery","contact",foe_inf,ours_art,"bad"}, {"enemy cavalry charge our archers","charge",foe_cav,ours_arch,"bad"},
      {"our infantry reach enemy archers","contact",ours_inf,foe_arch,"good"}, {"our knights charge enemy infantry","charge",ours_kn,foe_inf,"good"},
      {"enemy cavalry hit our infantry in the rear","rear",foe_cav,ours_inf,"bad"}, {"our infantry break","break",foe_inf,ours_inf,"bad"},
      {"our general badly hurt","hurt",ours_gen,foe_inf,"bad"}, {"infantry meet infantry","contact",ours_inf,foe_inf,nil},
      {"archers meet archers","contact",ours_arch,foe_arch,nil}, {"infantry flank infantry","flank",ours_inf,foe_inf,nil} }
    local bad=0 for _,c in ipairs(cases) do local h=hf(c[2],c[3],c[4]) local got=h and h.tone if got~=c[5] then bad=bad+1 end P("HLCASE",c[1],h and (h.tone..": "..h.text) or "none",got==c[5] and "ok" or "WRONG") end
    P("CHECK highlight classes", bad==0 and "yes" or "no") end
  -- a bad highlight's box, forced onto the shot on screen (for the render)
  if i>=600 and i<=608 then local sh=CD_DIRECTOR.shot() if sh and sh.c then sh.reason={icon="clash",text="Your Archers caught in melee by Orc Boyz",tone="bad",unit=sh.c,highlight=true} end end
  if i==608 then shot("c4_highlight_bad_forced") end
  if i==40 then P("CHECK director auto start", CD_DIRECTOR.active() and "yes" or "no", "hud mode", CD_HUD and CD_HUD.state.mode) end
  if i==150 then shot("h1_film") end
  if i==320 then fire("ComponentLClickUp",{string="cd_hud_mode"}) fire("ComponentLClickUp",{string="cd_hud_mode"}) end -- film -> clean -> full
  if i==330 then shot("h2_full") fire("ComponentLClickUp",{string="cd_hud_mode"}) fire("ComponentLClickUp",{string="cd_hud_mode"}) end -- -> film -> clean
  if i==340 then shot("h3_clean") fire("ComponentLClickUp",{string="cd_hud_mode"}) fire("ComponentLClickUp",{string="cd_hud_mode"}) P("hud mode back to", CD_HUD.state.mode) end -- -> full -> film
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
  -- cinematic view: the mouse over the knights' card shows their tactics card above it; leaving it hides it
  if not MPRUN and i==640 then local card=U.find(root,"unit_card_5") fire("ComponentMouseOn",{string="portrait",component=U.find_child(card,"portrait")}) end
  if not MPRUN and i==645 then local pn,card=U.find(root,"cd_bt_panel"),U.find(root,"unit_card_5") local px,py=pn:abs() local cx,cy=card:abs()
    local name=CD_TACTICS_PANEL.state.hover and CD_TACTICS_PANEL.state.hover.e and CD_TACTICS_PANEL.state.hover.e.name
    HOV={vis=pn.vis and pn:shown(), above=py+pn.h<=cy and math.abs(px+pn.w/2-(cx+card.w/2))<2, name=name, filming=CD_DIRECTOR.active()} P("CARD HOVER", HOV.vis, px, py, pn.h, "card", cx, cy, name) shot("b8_card_hover")
    fire("ComponentMouseOff",{string="portrait"}) end
  if not MPRUN and i==652 then local pn=U.find(root,"cd_bt_panel") P("CHECK unit card hover", (HOV and HOV.filming and HOV.vis and HOV.above and HOV.name=="knight#5" and not pn.vis) and "yes" or "no") end
  if i==210 then local pn=U.find(root,"cd_bt_panel") P("PANEL while filming visible:", pn and pn.vis) end
  -- the same without events: the card's portrait in a hover state (polled), then a click (selection) on another card
  if not MPRUN and i==660 then U.find_child(U.find(root,"unit_card_5"),"portrait").st="hover" end
  if not MPRUN and i==664 then local h=CD_TACTICS_PANEL.state.hover HOV2={vis=U.find(root,"cd_bt_panel").vis, name=h and h.e and h.e.name} U.find_child(U.find(root,"unit_card_5"),"portrait").st="active" end
  if not MPRUN and i==668 then HOV2.gone=not U.find(root,"cd_bt_panel").vis P("CHECK unit card hover (states)", (HOV2.vis and HOV2.name=="knight#5" and HOV2.gone) and "yes" or "no", tostring(HOV2.name)) end
  if not MPRUN and i==672 then for u,f in pairs(SELCB) do if u==A[3] then f(u,true) end end end
  if not MPRUN and i==676 then local h=CD_TACTICS_PANEL.state.hover CLK={vis=U.find(root,"cd_bt_panel").vis, name=h and h.e and h.e.name} for u,f in pairs(SELCB) do if u==A[3] then f(u,false) end end end
  if not MPRUN and i==680 then P("CHECK unit card click while filming", (CLK.vis and CLK.name and not U.find(root,"cd_bt_panel").vis) and "yes" or "no", tostring(CLK.name)) end
  if i==790 then (SELCB[A[4]] or function() end)(A[4], true) end
  if i==800 then local pn=U.find(root,"cd_bt_panel") P("PANEL after click in regular view visible:", pn and pn.vis) shot("b7_panel_regular"); (SELCB[A[4]] or function() end)(A[4], false) end
  if i==850 then local all_back=true for _,c in ipairs(U.all) do if c.id=="banner_flag" and not c.vis then all_back=false end end
    if not CD_PROBE then P("banner probe off") else P("CHECK banner probe", (CD_PROBE and CD_PROBE.done.B and CD_PROBE.done.C and CD_PROBE.hidden==nil and all_back) and "yes" or "no", "phases", CD_PROBE and (tostring(CD_PROBE.done.A).." "..tostring(CD_PROBE.done.B).." "..tostring(CD_PROBE.done.C)), "unit ids", table.concat(UNIT_IDS," ")) end end
  if i==810 then local pn=U.find(root,"cd_bt_panel") P("PANEL after deselect visible:", pn and pn.vis) end
  if i==600 then local r=mk("spear",-40,-60) A[#A+1]=r P("reinforcement arrives", r.id) end
end
P("banners at end", table.concat(UNIT_IDS," "))
P("CHECK no 'and N more' lines", (MORE and MORE.bad==0) and "yes" or "no", "most lines on one shot", MORE and MORE.maxl)
do local n=0 for k,v in pairs(HLT or {}) do if type(k)=="number" then n=n+1 P("HIGHLIGHT #"..k..": "..v) end end P("highlights shown: "..n) end
P("anchored callout box-ticks", AB or 0)
if CO then P(string.format("callouts: %d box-ticks, %d with a line, line tip off the unit by %.1f px on average (max %.0f), %d ticks with several boxes, %d overlaps; boxes moved on %d ticks (%.1f%%)", CO.n, CO.lines, CO.err/math.max(CO.lines,1), CO.emax, CO.multi, CO.over, CO.moves, 100*CO.moves/math.max(CO.n,1))) else P("callouts: none shown") end
for _,r in ipairs(CC) do P(string.format("CLOSE #%d: %d ticks, riding in %d: camera %.0f-%.0f m behind the riders, up to %.0f m beside, %.1f-%.1f m above ground, pitch at most %.0f deg down; speed %.1f m/s vs riders %.1f; impact %s (gap %.0f m); speed jump per tick %.1f avg, %.1f max",
  r.n, r.ticks, r.run, r.bmin, r.bmax, r.smax or 0, r.hmin, r.hmax, r.pmax, r.spd/math.max(r.run,1), r.uspd/math.max(r.run,1), r.hit and string.format("at %.1f", r.hit) or "never", r.hitgap or -1, r.dv/math.max(r.ticks-1,1), r.dvmax)) end
if #CC==0 then P("CLOSE none") end
for _,r in ipairs(BR or {}) do P(string.format("BRACE #%d: %d ticks, camera up to %.1f m above ground, pitch at most %.0f deg down, at least %.0f m behind the unit, look point within %.0f m of the charger, hit %s",
  r.n, r.ticks, r.hmax, r.pmax, r.behind, r.look, tostring(r.hit))) end
do local ok=false for _,r in ipairs(BR or {}) do if r.hit and r.hmax<4.5 and r.pmax<14 and r.behind>3 and r.look<15 then ok=true end end P("CHECK brace cam", ok and "yes" or "no") end
for _,a in ipairs(ACT or {}) do P("ACTION "..a) end
if ACT then P(string.format("action shots: pitch at most %.0f deg down, camera at most %.0f m from the unit", ACT.pmax or 0, ACT.dmax or 0)) end
do local en,fr=false,false for _,a in ipairs(ACT or {}) do if a:find("enemy%)$") then en=true end if a:find("yours%)$") then fr=true end end
  P("CHECK heavy hits filmed", ((en or not HITE) and (fr or not HITF) and ACT and (ACT.pmax or 99)<16) and "yes" or "no", "enemy", en, "yours", fr) end
do local per,bad,st={},0 for _,x in ipairs(SPEEDS) do if x[2]<1 then st=x[1] elseif st then per[#per+1]=x[1]-st st=nil end end
  for _,d in ipairs(per) do if d<1.8 or d>2.4 then bad=bad+1 end end
  local s={} for _,d in ipairs(per) do s[#s+1]=string.format("%.1fs",d) end
  P("slow motion periods:", #per, table.concat(s," "), "speed now", SPEED)
  if os.getenv("CD_MP")=="1" then P("CHECK no slow motion in multiplayer", #SPEEDS==0 and "yes" or "no")
  else P("CHECK slow motion", (#per>=2 and bad==0 and SPEED==1 and not st) and "yes" or "no") end end
P("CHECK unit cards", (CARDS and CARDS.bad==0 and (CARDS.n or 0)>0 and CARDS.prio==1402 and CARDS.after==5 and #ARMYPANEL==0) and "yes" or "no",
  "lines checked", CARDS and CARDS.n, "overlaps", CARDS and CARDS.bad, "priority while filming", CARDS and CARDS.prio, "after", CARDS and CARDS.after, "army panel calls", table.concat(ARMYPANEL," "))
P(string.format("glides: subject within 20 deg of the view %d%% of glide time, look point within 10 deg %d%%", 100*(CAMS.glock or 0)/math.max(CAMS.gn or 1,1), 100*(CAMS.glk2 or 0)/math.max(CAMS.gn or 1,1)))
for k,t in pairs(CAMS.gt or {}) do P("  glide into", k, t[1], "subject ok", t[2], "look ok", t[3]) end
P(string.format("view: %d%% of the time within 60 deg of the player's view, mean pitch %.0f deg down, min %.0f, max %.0f, steeper than 45: %d%%; max speed outside cuts %.1f m/s",
  100*(CAMS.vhome or 0)/math.max(CAMS.vn or 1,1), (CAMS.psum or 0)/math.max(CAMS.vn or 1,1), CAMS.pmin or 0, CAMS.pmax or 0, 100*(CAMS.steep or 0)/math.max(CAMS.vn or 1,1), CAMS.spmax_glide or 0))
P(string.format("camera: %d moves, max speed %.0f m/s, mean speed change/step %.2f m/s, max %.1f, jumps(>40 m/s change) %d, max height %.0f",
  CAMS.moves, CAMS.spmax or 0, (CAMS.dvsum or 0)/math.max(CAMS.n or 1,1), CAMS.dvmax or 0, CAMS.big or 0, CAMS.maxy))
fire("BattleConflictFinished",{})
P("casts",#CASTS,table.concat(CASTS," ",1,math.min(#CASTS,6)))
for k,v in pairs(ORDERS) do P(k,v) end
if MPRUN then local n=0 for _ in pairs(ORDERS) do n=n+1 end P("CHECK no unit tactics in multiplayer", (n==0 and not CD_TACTICS_ENGINE.running() and #CD_TACTICS_ENGINE.units()==0) and "yes" or "no", "orders", n) end
for k,v in pairs(UCO) do P("attack orders",k,v) end
