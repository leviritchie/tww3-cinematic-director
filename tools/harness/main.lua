io.stdout:setvbuf("no")
function love.load()
local ok, err = xpcall(function()
local MOD = os.getenv("CD_MOD")
local SCN = os.getenv("CD_SCN") or "campaign"
local OUT = os.getenv("CD_OUT") or "."
function P(...) local t={} for i=1,select('#',...) do t[#t+1]=tostring(select(i,...)) end io.write(table.concat(t,"\t").."\n") end
U = require("uimock")
function UIComponent(x) return x end
function find_child_uicomponent(c, id) return U.find_child(c, id) end
function find_uicomponent(p, ...) local ids = {...} return U.find(p, ids[#ids]) end
common = { get_localised_string=function(k) return "" end }
root = U.new("root", "root", nil)
local L = {}
core = { get_ui_root=function() return root end, add_listener=function(_,n,ev,c,fn) L[#L+1]={ev=ev,fn=fn} end, get_screen_resolution=function() return 1920,1080 end }
function fire(ev,ctx) for _,l in ipairs(L) do if l.ev==ev then l.fn(ctx) end end end
-- real-time timers run later, never inside the event that scheduled them (as in the game)
RQ, REPEAT = {}, {}
function pump() for _ = 1, 3 do local q = RQ; RQ = {}; for _, f in ipairs(q) do f() end end; for _, f in ipairs(REPEAT) do f() end end
local function click(id) fire("ComponentLClickUp",{string=id}) pump() end
local function hover(id) fire("ComponentMouseOn",{string=id}) pump() end
function shot(name) name = name:gsub("^.*/", "") U.render(name .. ".png", 1920, 1080) P("rendered", name) end
dofile(MOD.."script/_lib/mod/cinematic_director_tactics_catalog.lua")
dofile(MOD.."script/_lib/mod/cinematic_director_ui.lua")

if SCN == "battle" then
  MODDIR = MOD
  dofile("battle.lua")
elseif SCN == "campaign" then
  local function list(t) return {num_items=function() return #t end, item_at=function(_,i) return t[i+1] end} end
  local function unit(key,cqi,xp,caste) return {unit_key=function() return key end, command_queue_index=function() return cqi end, experience_level=function() return xp end, unit_caste=function() return caste end} end
  local fac
  local U2 = { unit("wh_main_emp_cha_karl_franz",11,0,"lord"), unit("wh_main_emp_inf_spearmen_0",12,5,"melee_infantry"), unit("wh_main_emp_inf_spearmen_0",17,1,"melee_infantry"),
    unit("wh_main_emp_inf_crossbowmen",13,3,"missile_infantry"), unit("wh_main_emp_cav_empire_knights",14,8,"cavalry"), unit("wh_main_emp_art_great_cannon",15,0,"artillery"),
    unit("wh_main_emp_inf_greatswords",16,9,"melee_infantry"), unit("wh2_dlc13_emp_cha_huntsmarshal_0",18,0,"hero") }
  local mf = {command_queue_index=function() return 77 end, unit_list=function() return list(U2) end,
    general_character=function() return {command_queue_index=function() return 900 end, rank=function() return 14 end, get_forename=function() return "x" end} end,
    character_list=function() return list({{command_queue_index=function() return 900 end, rank=function() return 14 end}, {command_queue_index=function() return 901 end, rank=function() return 7 end}}) end, faction=function() return fac end}
  fac = {name=function() return "me" end, military_force_list=function() return list({mf}) end}
  SAVED = {}
  local CBS = {}
  cm = { get_saved_value=function(_,k) return SAVED[k] end, set_saved_value=function(_,k,v) SAVED[k]=v end, get_local_faction=function() return fac end, get_local_faction_name=function() return "me" end,
    get_military_force_by_cqi=function(_,c) return c==77 and mf or nil end, callback=function(_,f) f() end, add_first_tick_callback=function(_,f) CBS[#CBS+1]=f end,
    real_callback=function(_,f,ms) if ms <= 0 then f() else RQ[#RQ+1]=f end end, repeat_real_callback=function(_,f) REPEAT[#REPEAT+1]=f end,
    campaign_ui_manager={ mf_selected_cqi=false }, is_multiplayer_campaign=false }
  local mup = root:CreateComponent("main_units_panel", "x/other.twui.xml") mup:MoveTo(560, 900) mup:Resize(800, 170)
  P("load", pcall(dofile, MOD.."script/campaign/mod/cinematic_director_tactics.lua"))
  for _,f in ipairs(CBS) do f() end
  pump() P("button before selection", U.find(root,"cd_tac_open") and U.find(root,"cd_tac_open"):shown())
  -- the game's own selection listener records the army; any script touching the event context fails the run
  cm.campaign_ui_manager.mf_selected_cqi = 77
  fire("CharacterSelected", setmetatable({}, {__index=function(_,k) error("event context accessed: " .. tostring(k)) end}))
  pump()
  P("open button", U.find(root,"cd_tac_open"):shown(), U.find(root,"cd_tac_open"):abs())
  click("cd_tac_open")
  click("cd_tac_u_2")
  shot(OUT .. "/c1_editor")
  P("focus", CD_TAC_EDITOR.ui.focus.kind, CD_TAC_EDITOR.ui.focus.row)
  click("cd_tac_c_2") click("cd_tac_cat_3") hover("cd_tac_opt_2")
  shot(OUT .. "/c2_when_group")
  click("cd_tac_opt_2")
  P("after when pick", SAVED.cd_tactics_v1, CD_TAC_EDITOR.ui.focus.kind, CD_TAC_EDITOR.ui.focus.row)
  click("cd_tac_cat_2") click("cd_tac_opt_3")
  P("after do pick", SAVED.cd_tactics_v1, CD_TAC_EDITOR.ui.focus.kind)
  shot(OUT .. "/c3_targets")
  click("cd_tac_opt_1")
  click("cd_tac_a_1") click("cd_tac_cat_3") click("cd_tac_opt_2")
  P("hold pick", SAVED.cd_tactics_v1, CD_TAC_EDITOR.ui.focus.kind)
  click("cd_tac_t_1")
  shot(OUT .. "/c4_notarget")
  click("cd_tac_preset") click("cd_tac_cat_2") hover("cd_tac_opt_3")
  shot(OUT .. "/c5_presets")
  click("cd_tac_opt_3")
  P("preset", SAVED.cd_tactics_v1)
  click("cd_tac_u_1") click("cd_tac_a_3") click("cd_tac_cat_4") hover("cd_tac_title")
  shot(OUT .. "/c6_lord_spells")
  click("cd_tac_up_2") click("cd_tac_x_1") click("cd_tac_reset") click("cd_tac_copy")
  P("saved", SAVED.cd_tactics_v1)
  click("cd_tac_done") P("panel shown after done", U.find(root,"cd_tac_panel"):shown())
end
end, debug.traceback)
if not ok then print("ERROR", err) end
love.event.quit()
end
