--------------------------------------------------------------------------------
-- Cinematic Director: tactics catalogue (shared by campaign editor and battle engine)
--
-- A tactic is { cond, target, action }. Regiments have 2 + floor(rank / 2) tactic
-- slots (2-5); lords and heroes always have all 5. In battle a unit walks its
-- tactics top to bottom and follows the first one whose condition holds and whose
-- target exists; if none apply it attacks the nearest enemy.
-- "Plays" are whole battle plans in one row (skirmish, cycle charge, hammer and
-- anvil, ...): the engine runs a small state machine for each.
-- Spell rows ("cast_attack", "cast_buff", "sp_<ability key>") run alongside the
-- movement rows.
--------------------------------------------------------------------------------

CD_TACTICS = {};
local T = CD_TACTICS;

T.MAX_SLOTS = 5;

-- role "hero" (lords and heroes): all slots, their spellcasting needs the room
function T.slots_for_rank(rank, role)
	if role == "hero" then return T.MAX_SLOTS end;
	rank = tonumber(rank) or 0;
	return math.min(T.MAX_SLOTS, 2 + math.floor(rank / 2));
end;

-- Paradigms: up to four whole-army tactics sets, switched with buttons in battle. Each unit has
-- one row list per paradigm; paradigms 2-4 copy paradigm 1 until edited. How many the player can
-- use depends on the highest character rank among the player's living generals in the battle.
T.MAX_PARADIGMS = 4;
T.PARADIGM_RANKS = { 1, 5, 12, 20 };		-- general's rank that unlocks paradigm k
T.PARADIGM_NAMES = { "I", "II", "III", "IV" };

function T.paradigms_for_rank(rank)
	rank = tonumber(rank) or 1;
	local n = 1;
	for k, r in ipairs(T.PARADIGM_RANKS) do if rank >= r then n = k end end;
	return n;
end;

-- Every list entry is { id, label, ... , category }. The editor groups entries by
-- category (in order of first appearance); ids are what gets saved, so never rename one.

-- conditions: when a tactic applies { id, label, category }
T.CONDITIONS = {
	{ "always",             "Always",                              "General" },
	{ "early",              "First 60 s of battle",                "General" },
	{ "after_60",           "After the first minute",              "General" },
	{ "after_180",          "After 3 minutes",                     "General" },

	{ "in_melee",           "Self in melee",                       "This unit" },
	{ "not_in_melee",       "Self not in melee",                   "This unit" },
	{ "under_fire",         "Self under missile fire",             "This unit" },
	{ "not_under_fire",     "Self not under fire",                 "This unit" },
	{ "hp_gt_75",           "Self HP above 75%",                   "This unit" },
	{ "hp_lt_75",           "Self HP below 75%",                   "This unit" },
	{ "hp_lt_50",           "Self HP below 50%",                   "This unit" },
	{ "hp_lt_25",           "Self HP below 25%",                   "This unit" },
	{ "has_ammo",           "Has ammo left",                       "This unit" },
	{ "ammo_low",           "Ammo below 25%",                      "This unit" },
	{ "ammo_out",           "Out of ammo",                         "This unit" },
	{ "isolated",           "No ally within 100 m",                "This unit" },

	{ "enemy_near_40",      "Enemy within 40 m",                   "Enemy distance" },
	{ "enemy_near",         "Enemy within 80 m",                   "Enemy distance" },
	{ "enemy_near_150",     "Enemy within 150 m",                  "Enemy distance" },
	{ "no_enemy_near",      "No enemy within 150 m",               "Enemy distance" },
	{ "enemies_near_3",     "3+ enemies within 120 m",             "Enemy distance" },

	{ "enemy_cav_near",     "Enemy cavalry within 120 m",          "Enemy type nearby" },
	{ "enemy_large_near",   "Enemy monster/hero within 120 m",     "Enemy type nearby" },
	{ "enemy_missile_near", "Enemy missiles within 200 m",         "Enemy type nearby" },
	{ "enemy_inf_near",     "Enemy infantry within 80 m",          "Enemy type nearby" },
	{ "enemy_general_near", "Enemy general within 150 m",          "Enemy type nearby" },

	{ "ally_in_melee",      "An ally within 150 m is in melee",    "Allies" },
	{ "ally_hurt_near",     "An ally within 150 m below 50% HP",   "Allies" },
	{ "missiles_threatened","Enemy within 60 m of our missiles",   "Allies" },
	{ "lord_in_melee",      "Our lord is in melee",                "Allies" },
	{ "lord_hurt",          "Our lord below 50% HP",               "Allies" },
	{ "lord_near",          "Our lord within 80 m",                "Allies" },
	{ "lord_far",           "Our lord over 150 m away",            "Allies" },

	{ "self_winning",       "Self winning its fight",              "Fights" },
	{ "self_winning_big",   "Self winning easily",                 "Fights" },
	{ "self_losing",        "Self losing its fight",               "Fights" },
	{ "self_losing_bad",    "Self losing badly",                   "Fights" },
	{ "ally_winning",       "Ally within 150 m winning",           "Fights" },
	{ "ally_losing",        "Ally within 150 m losing",            "Fights" },
	{ "ally_losing_bad",    "Ally within 150 m losing badly",      "Fights" },

	{ "winning",            "Our army is stronger",                "Battle" },
	{ "even",               "Armies about even",                   "Battle" },
	{ "losing",             "Our army is weaker",                  "Battle" },
	{ "outnumbered",        "Enemy has more units",                "Battle" },
	{ "few_enemies",        "3 or fewer enemy units left",         "Battle" },
};

-- targets: which unit the tactic acts on { id, label, kind, category }; kind "e" = enemy, "a" = ally, "-" = none
T.TARGETS = {
	{ "nearest_enemy",       "Nearest enemy",                "e", "Enemy: where" },
	{ "enemy_near_lord",     "Enemy nearest our lord",       "e", "Enemy: where" },
	{ "enemy_near_missiles", "Enemy nearest our missiles",   "e", "Enemy: where" },
	{ "enemy_isolated",      "Most isolated enemy",          "e", "Enemy: where" },
	{ "enemy_farthest",      "Farthest enemy",               "e", "Enemy: where" },

	{ "enemy_infantry",      "Enemy infantry",               "e", "Enemy: type" },
	{ "enemy_missile",       "Enemy missiles/artillery",     "e", "Enemy: type" },
	{ "enemy_archers",       "Enemy archers/gunners",        "e", "Enemy: type" },
	{ "enemy_artillery",     "Enemy artillery",              "e", "Enemy: type" },
	{ "enemy_cavalry",       "Enemy cavalry/fliers",         "e", "Enemy: type" },
	{ "enemy_flier",         "Enemy fliers",                 "e", "Enemy: type" },
	{ "enemy_large",         "Enemy monster/hero/lord",      "e", "Enemy: type" },
	{ "enemy_monster",       "Enemy monster",                "e", "Enemy: type" },
	{ "enemy_hero",          "Enemy hero",                   "e", "Enemy: type" },
	{ "enemy_general",       "Enemy general",                "e", "Enemy: type" },

	{ "enemy_engaged",       "Enemy fighting our units",     "e", "Enemy: state" },
	{ "enemy_free",          "Enemy not in melee",           "e", "Enemy: state" },
	{ "enemy_attacking_lord","Enemy fighting our lord",      "e", "Enemy: state" },
	{ "enemy_weakest",       "Weakest enemy",                "e", "Enemy: state" },
	{ "enemy_strongest",     "Strongest enemy",              "e", "Enemy: state" },
	{ "enemy_winning_fight", "Enemy beating one of ours",    "e", "Enemy: state" },
	{ "enemy_losing_fight",  "Enemy losing its fight",       "e", "Enemy: state" },

	{ "ally_lord",           "Our lord",                     "a", "Allies" },
	{ "ally_engaged",        "Ally in melee",                "a", "Allies" },
	{ "ally_weakest",        "Most damaged ally",            "a", "Allies" },
	{ "ally_nearest",        "Nearest ally",                 "a", "Allies" },
	{ "ally_missile",        "Our missile units",            "a", "Allies" },
	{ "ally_large",          "Our nearest hero/monster",     "a", "Allies" },
	{ "ally_losing_fight",   "Ally losing its fight",        "a", "Allies" },

	{ "trigger_enemy",       "Enemy from WHEN",              "e", "From the condition" },
	{ "trigger_ally",        "Ally from WHEN",               "a", "From the condition" },

	{ "self",                "Self",                         "-", "Self" },
};

-- actions: what the unit does { id, label, need, category, passes }; need = target kind the action
-- requires; passes = the action can decline (no fitting target right now), handing over to the next row
T.ACTIONS = {
	{ "hammer",      "Hammer and anvil",           "-", "Plays" },
	{ "hammer_flank","Hammer: flank charge",       "-", "Plays" },
	{ "hammer_wide", "Hammer: wide sweep",         "-", "Plays" },
	{ "cycle_charge","Cycle charge",               "e", "Plays", true },
	{ "skirmish",    "Skirmish (shoot and back off)",  "e", "Plays" },
	{ "focus",       "Focus fire",                 "-", "Plays", true },
	{ "fire_support","Fire support",               "e", "Plays" },
	{ "disrupt",     "Hunt missiles",              "-", "Plays", true },
	{ "kill_lord",   "Kill the general",           "-", "Plays", true },
	{ "high_ground", "Take the high ground",       "-", "Plays" },
	{ "duelist",     "Duel",                       "e", "Plays", true },
	{ "caster",      "Battle mage",                "-", "Plays" },

	{ "attack",      "Attack",                     "e", "Fight" },
	{ "charge",      "Charge (all out)",           "e", "Fight" },
	{ "melee",       "Melee attack",               "e", "Fight" },
	{ "flank",       "Flank and attack",           "e", "Fight" },
	{ "approach",    "Advance toward",             "e", "Fight" },

	{ "guard",       "Guard",                      "a", "Support" },
	{ "follow",      "Move to",                    "a", "Support" },
	{ "cover",       "Shield",                     "a", "Support" },

	{ "hold",        "Hold position",              "-", "Position" },
	{ "retreat",     "Fall back",                  "-", "Position" },
	{ "to_lord",     "Fall back to our lord",      "-", "Position" },
	{ "regroup",     "Regroup with the army",      "-", "Position" },

	{ "cast_attack", "Cast attack spell on",       "e", "Spells" },
	{ "cast_buff",   "Cast helpful spell on",          "a", "Spells" },
};

local function index(list, kind_field, cat_field)
	local by = {};
	for i, e in ipairs(list) do
		by[e[1]] = { i = i, id = e[1], label = e[2], kind = kind_field and e[kind_field] or nil, cat = e[cat_field] };
	end;
	return by;
end;
T.COND_BY = index(T.CONDITIONS, nil, 3);
T.TARGET_BY = index(T.TARGETS, 3, 4);
T.ACTION_BY = index(T.ACTIONS, 3, 4);
for _, e in ipairs(T.ACTIONS) do T.ACTION_BY[e[1]].passes = e[5] or false end;

--------------------------------------------------------------------------------
-- a hero's own spells: action id "sp_<ability key>". The battle engine finds out which
-- abilities a character has and writes them to cinematic_director_spells.txt; the
-- campaign editor offers them from there. CD_ABILITIES (key lists by category) is shared.
--------------------------------------------------------------------------------

T.SPELLS_PATH = "cinematic_director_spells.txt";
local BUFF_CAT = { A = true, R = true };
local spell_cat_of;

function T.spell_cat(key)
	if not spell_cat_of then
		if type(CD_ABILITIES) ~= "table" then return nil end;
		spell_cat_of = {};
		for cat, list in pairs(CD_ABILITIES) do
			for _, k in ipairs(list) do spell_cat_of[k] = cat end;
		end;
	end;
	return spell_cat_of[key];
end;

-- "wh_main_spell_heavens_wind_blast_upgraded" -> "Wind Blast (upgraded)" when the game has no name for it
local function pretty_key(key)
	local s = key:gsub("^wh%d?_[%w]+_", "");
	s = s:gsub("^.-abilities_", ""):gsub("^spell_", "");
	local up = s:find("_upgraded$") ~= nil;
	s = s:gsub("_upgraded$", ""):gsub("_", " ");
	s = s:gsub("^%l", string.upper);
	return s .. (up and " (upgraded)" or "");
end;

function T.spell_name(key)
	local n;
	pcall(function() n = common.get_localised_string("unit_abilities_onscreen_name_" .. key) end);
	if type(n) == "string" and n ~= "" then return n end;
	return pretty_key(key);
end;

function T.is_spell_id(id) return type(id) == "string" and id:sub(1, 3) == "sp_" end;

setmetatable(T.ACTION_BY, { __index = function(t, id)
	if not T.is_spell_id(id) then return nil end;
	local key = id:sub(4);
	if key == "" or not key:match("^[%w_]+$") then return nil end;
	local cat = T.spell_cat(key);
	local e = { id = id, label = "Cast " .. T.spell_name(key), kind = BUFF_CAT[cat] and "a" or "e", cat = "Own spells",
		spell = key, scat = cat, passes = false };
	rawset(t, id, e);
	return e;
end });

-- the spells the battle engine has seen this unit (unit cqi) use: list of ability keys
function T.known_spells(cqi)
	local out = {};
	local ok, f = pcall(io.open, T.SPELLS_PATH, "r");
	if not ok or not f then return out end;
	pcall(function()
		for line in f:lines() do
			local c, rest = line:match("^spells (%S+) ?(.*)$");
			if c and c == tostring(cqi) then
				for k in rest:gmatch("[%w_]+") do out[#out + 1] = k end;
			end;
		end;
	end);
	f:close();
	return out;
end;

-- editor entries for a unit's own spells { id, label, need, category }
function T.spell_entries(cqi)
	local out = {};
	for _, k in ipairs(T.known_spells(cqi)) do
		local a = T.ACTION_BY["sp_" .. k];
		if a then out[#out + 1] = { a.id, a.label, a.kind, "Own spells" } end;
	end;
	return out;
end;

-- categories of a list in order of first appearance: { { name, { entries } }, ... }
function T.categories(list, cat_field, filter)
	local out, at = {}, {};
	for _, e in ipairs(list) do
		if not filter or filter(e) then
			local c = e[cat_field];
			if not at[c] then out[#out + 1] = { c, {} }; at[c] = #out end;
			local g = out[at[c]][2];
			g[#g + 1] = e;
		end;
	end;
	return out;
end;

-- roles, from campaign unit caste or battle unit class
function T.role_from_caste(caste)
	caste = caste or "";
	if caste == "lord" or caste == "hero" then return "hero" end;
	if caste:find("missile_cavalry") then return "missile_cav" end;
	if caste:find("missile") or caste == "artillery" or caste:find("warmachine") or caste:find("war_machine") then return "missile" end;
	if caste:find("cavalry") or caste == "chariot" or caste == "war_beast" then return "cavalry" end;
	if caste:find("monster") or caste:find("monstrous") then return "monster" end;
	return "melee";
end;

function T.role_from_class(class, men, general, ammo, cav, fly)
	class = class or "";
	if general or class == "com" or (men and men <= 1 and not class:find("^art")) then return "hero" end;
	if class:find("^art") then return "missile" end;
	if class == "cav_mis" then return "missile_cav" end;
	if class:find("^inf_mis") or ((ammo or 0) > 0 and not cav) then return "missile" end;
	if cav or fly or class:find("^cav") or class:find("chariot") then return "cavalry" end;
	if men and men <= 8 then return "monster" end;
	return "melee";
end;

-- default tactics per role, most important first; a unit with n slots gets the first n
-- (the first two are what a fresh recruit does, so they carry a whole plan)
T.DEFAULTS = {
	melee = {
		{ "always",         "nearest_enemy", "attack" },
		{ "enemy_cav_near", "enemy_cavalry", "attack" },
		{ "lord_in_melee",  "ally_lord",     "guard" },
		{ "hp_lt_25",       "self",          "retreat" },
		{ "ally_in_melee",  "enemy_engaged", "attack" },
	},
	missile = {
		{ "always",         "self",          "focus" },
		{ "hp_lt_25",       "self",          "to_lord" },
		{ "always",         "nearest_enemy", "skirmish" },
		{ "enemy_cav_near", "enemy_cavalry", "skirmish" },
		{ "few_enemies",    "enemy_weakest", "attack" },
	},
	missile_cav = {
		{ "always",         "enemy_missile", "skirmish" },
		{ "always",         "nearest_enemy", "skirmish" },
		{ "hp_lt_25",       "self",          "regroup" },
		{ "always",         "self",          "kill_lord" },
		{ "always",         "self",          "hammer" },
	},
	cavalry = {
		{ "always",         "self",          "disrupt" },
		{ "always",         "self",          "hammer" },
		{ "hp_lt_25",       "self",          "regroup" },
		{ "always",         "self",          "kill_lord" },
		{ "enemy_cav_near", "enemy_cavalry", "cycle_charge" },
	},
	monster = {
		{ "always",         "self",          "hammer" },
		{ "enemy_large_near","enemy_large",  "attack" },
		{ "hp_lt_25",       "self",          "regroup" },
		{ "always",         "self",          "kill_lord" },
		{ "always",         "self",          "disrupt" },
	},
	hero = {
		{ "always",         "enemy_large",   "duelist" },
		{ "always",         "self",          "caster" },
		{ "hp_lt_25",       "self",          "to_lord" },
		{ "always",         "self",          "kill_lord" },
		{ "always",         "ally_weakest",  "cast_buff" },
	},
};

-- sort order for a taken list: conditional rows first, then "Always" rows that can hand over
-- to the next row (plays that decline), then the rest; otherwise keep the source order
local function row_rank(t)
	if t[1] ~= "always" then return 0 end;
	local a = T.ACTION_BY[t[3]];
	if T.is_cast(t[3]) or (a and a.passes) then return 1 end;
	if t[2] ~= "nearest_enemy" and t[2] ~= "self" then return 1 end;
	return 2;
end;

local function take(src, n)
	local out = {};
	for i = 1, math.min(n, #src) do out[#out + 1] = { src[i][1], src[i][2], src[i][3], order = i } end;
	table.sort(out, function(a, b)
		local ra, rb = row_rank(a), row_rank(b);
		if ra ~= rb then return ra < rb end;
		return a.order < b.order;
	end);
	for _, t in ipairs(out) do t.order = nil end;
	return out;
end;

-- default list for a unit with n slots: first n entries, conditional ones ahead of "always"
-- so earlier rules aren't shadowed (a tactic with "Always" and a target that exists always fires)
function T.default_tactics(role, n) return take(T.DEFAULTS[role] or T.DEFAULTS.melee, n) end;

-- is the combination usable? returns false and a reason if not
function T.validate(t)
	local tg, ac = T.TARGET_BY[t[2]], T.ACTION_BY[t[3]];
	if not tg or not ac or not T.COND_BY[t[1]] then return false, "unknown entry" end;
	if ac.kind == "-" then return true end;
	if ac.kind ~= tg.kind then
		return false, (ac.kind == "e" and "needs an enemy target" or "needs an ally target");
	end;
	return true;
end;

-- serialisation: "cond,target,action;cond,target,action"
function T.serialise(list)
	local parts = {};
	for _, t in ipairs(list) do parts[#parts + 1] = t[1] .. "," .. t[2] .. "," .. t[3] end;
	return table.concat(parts, ";");
end;

function T.parse(s)
	local out = {};
	for item in tostring(s or ""):gmatch("[^;]+") do
		local c, tg, a = item:match("^([%w_]+),([%w_]+),([%w_]+)$");
		if c then out[#out + 1] = { c, tg, a } end;
	end;
	return out;
end;

function T.label(t)
	local c, tg, a = T.COND_BY[t[1]], T.TARGET_BY[t[2]], T.ACTION_BY[t[3]];
	if a and a.kind == "-" then return (c and c.label or t[1]) .. " | " .. a.label end;
	return (c and c.label or t[1]) .. " | " .. (a and a.label or t[3]) .. " " .. (tg and tg.label or t[2]);
end;

-- plain-language help shown in the editor
T.HELP = {
	always = "Always true. Rows below are used only when this row's target doesn't exist.",
	early = "The first minute after deployment.",
	after_60 = "From one minute into the battle.",
	after_180 = "From three minutes into the battle.",
	in_melee = "This unit is in melee.",
	not_in_melee = "This unit is not in melee.",
	under_fire = "This unit is being hit by missiles.",
	not_under_fire = "No missiles are hitting this unit.",
	hp_gt_75 = "This unit has more than 75% health.",
	hp_lt_75 = "This unit has less than 75% health.",
	hp_lt_50 = "This unit has less than 50% health.",
	hp_lt_25 = "This unit has less than 25% health.",
	has_ammo = "This unit has ammunition left.",
	ammo_low = "This unit has less than 25% ammunition.",
	ammo_out = "This missile unit has no ammunition.",
	isolated = "No friendly unit within 100 m.",
	enemy_near_40 = "An enemy within 40 m.",
	enemy_near = "An enemy within 80 m (a unit falling back on this keeps going to 130 m).",
	enemy_near_150 = "An enemy within 150 m.",
	no_enemy_near = "No enemy within 150 m.",
	enemies_near_3 = "Three or more enemies within 120 m.",
	enemy_cav_near = "Enemy cavalry, chariots or flyers within 120 m.",
	enemy_large_near = "An enemy monster, hero or lord within 120 m.",
	enemy_missile_near = "Enemy archers, gunners or artillery within 200 m.",
	enemy_inf_near = "Enemy infantry within 80 m.",
	enemy_general_near = "The enemy general within 150 m.",
	ally_in_melee = "A friendly unit within 150 m is in melee.",
	ally_hurt_near = "A friendly unit within 150 m has less than 50% health.",
	missiles_threatened = "An enemy within 60 m of one of your missile units.",
	lord_in_melee = "Your lord is in melee.",
	lord_hurt = "Your lord has less than 50% health.",
	lord_near = "Your lord is within 80 m.",
	lord_far = "Your lord is more than 150 m away.",
	self_winning = "This unit is in melee and the enemies it is fighting are losing health at least 1.5 times as fast as it is (over the last few seconds).",
	self_winning_big = "This unit is in melee and the enemies it is fighting are losing health at least 2.5 times as fast as it is, or one of them is wavering.",
	self_losing = "This unit is in melee and losing health at least 1.5 times as fast as the enemies it is fighting (over the last few seconds).",
	self_losing_bad = "This unit is in melee and losing health at least 2.5 times as fast as the enemies it is fighting, or it is wavering.",
	ally_winning = "A friendly unit within 150 m is winning its fight (see Self winning its fight).",
	ally_losing = "A friendly unit within 150 m is losing its fight (see Self losing its fight).",
	ally_losing_bad = "A friendly unit within 150 m is losing its fight badly (see Self losing badly).",
	winning = "Your army is clearly stronger.",
	even = "Neither army is clearly stronger.",
	losing = "Your army is clearly weaker.",
	outnumbered = "The enemy has more units fighting.",
	few_enemies = "Three or fewer enemy units still fighting.",

	nearest_enemy = "The closest enemy.",
	enemy_near_lord = "The enemy closest to your lord.",
	enemy_near_missiles = "The enemy closest to your missile units.",
	enemy_isolated = "The enemy farthest from its allies.",
	enemy_farthest = "The enemy farthest from this unit.",
	enemy_infantry = "The closest enemy infantry.",
	enemy_missile = "The closest enemy archers, gunners or artillery.",
	enemy_archers = "The closest enemy archers or gunners.",
	enemy_artillery = "The closest enemy artillery or war machine.",
	enemy_cavalry = "The closest enemy cavalry, chariot or flyer.",
	enemy_flier = "The closest enemy flyer.",
	enemy_large = "The closest enemy monster, hero or lord.",
	enemy_monster = "The closest enemy monster.",
	enemy_hero = "The closest enemy hero.",
	enemy_general = "The enemy general.",
	enemy_engaged = "The closest enemy in melee with your units.",
	enemy_free = "The closest enemy not in melee.",
	enemy_attacking_lord = "An enemy in melee next to your lord.",
	enemy_weakest = "The most damaged enemy (nearer ones first).",
	enemy_strongest = "The healthiest enemy (nearer ones first).",
	enemy_winning_fight = "The closest enemy in melee that is beating the unit it is fighting (losing health at most two thirds as fast).",
	enemy_losing_fight = "The closest enemy in melee that is losing its fight (losing health at least 1.5 times as fast as your units fighting it).",
	ally_lord = "Your lord.",
	ally_engaged = "The closest friendly unit in melee.",
	ally_weakest = "The most damaged friendly unit.",
	ally_nearest = "The closest friendly unit.",
	ally_missile = "Your closest missile unit.",
	ally_large = "Your closest hero or monster (not the lord).",
	ally_losing_fight = "The closest friendly unit that is losing its fight.",
	trigger_enemy = "The enemy the row's WHEN condition found, the closest one: for example the enemy within 80 m, the enemy this unit or an ally is fighting, the enemy near your lord or your missile units, or the closest enemy shooter when under fire. If the condition is about no enemy, the row is skipped.",
	trigger_ally = "The friendly unit the row's WHEN condition found, the closest one: for example the ally losing its fight, the hurt ally, the ally in melee, your missile unit with an enemy near, or your lord. If the condition is about no friendly unit, the row is skipped.",
	self = "This unit.",

	hammer = "Wait beside your army. When your other units have been fighting an enemy for 3 s, go round it the shortest clear way and charge it from behind. Cavalry and monsters then pull back and charge again; mounted missile units shoot instead. After a minute of waiting, attack the nearest enemy.",
	hammer_flank = "Like Hammer and anvil, but charges as soon as it reaches the enemy's side.",
	hammer_wide = "Like Hammer and anvil, but stays 45 m farther away while going round.",
	cycle_charge = "Charge, fight for a set time (cavalry 9 s, chariots 3 s, monsters 14 s), pull back 70 m toward your army, line up, charge again. Stays in the fight if the enemy is below 35% health. Passes to the next row below 30% health.",
	skirmish = "Shoot the target. Move back toward your army when enemy melee troops come within 75 m, unless they are already fighting. Out of ammunition: join the nearest fight.",
	focus = "All units on Focus fire shoot the same enemy: lords, heroes, monsters and artillery first, damaged ones first. Move away from enemy melee troops. Out of ammunition: join the nearest fight.",
	fire_support = "Stay 20-40 m behind the nearest friendly melee unit and shoot the target. Fall back behind it if enemy melee troops come within 45 m. Out of ammunition: join the fight.",
	disrupt = "Attack enemy archers, gunners and artillery, one of your units per target, going round enemy troops in the way. Passes to the next row when none are left.",
	kill_lord = "Attack the enemy general when at most one enemy unit is near him, he is in melee, or he is below 50% health. Passes to the next row otherwise, or below 30% health (60% for your general).",
	high_ground = "Move to the highest point within 120 m, not toward the enemy, and stay there. Fight enemies that come close; shoot those in range.",
	duelist = "Fight the target in melee when a friendly unit is near it, it is in melee, or it is alone. Passes to the next row otherwise, or below 40% health (60% for your general).",
	caster = "Stay 50 m behind the nearest friendly unit that is fighting, move away from enemies, and cast damaging and helpful spells. A hero with no spells does Hammer and anvil instead.",
	attack = "Attack the target. Missile units shoot.",
	charge = "Attack the target in melee at a run.",
	melee = "Attack the target in melee, even if this unit can shoot.",
	flank = "Move to the target's side, then attack it.",
	approach = "Move to 60 m from the target and stop.",
	cast_attack = "Cast a damaging spell on the target. Spell rows run alongside movement rows.",
	guard = "Stay next to the friendly target and attack enemies that come near it.",
	follow = "Move next to the friendly target without fighting.",
	cover = "Stand between the friendly target and the nearest enemy.",
	cast_buff = "Cast a helpful spell on the friendly target (healing only on damaged units).",
	hold = "Stay in place and defend.",
	retreat = "Move away from the enemy (toward your lord if he is behind).",
	to_lord = "Move to your lord.",
	regroup = "Move to the middle of your army.",
};

function T.help(id)
	if T.is_spell_id(id) then
		local a = T.ACTION_BY[id];
		return "Cast this spell when it is ready and the condition holds. Spell rows run alongside movement rows."
			.. (a and a.kind == "a" and " Needs a friendly target." or " Needs an enemy target.");
	end;
	return T.HELP[id] or "";
end;

-- the rank at which slot k unlocks (slots = 2 + floor(rank / 2): two from the start)
function T.rank_for_slot(k) return math.max(0, (k - 2) * 2) end;

-- a padded conditional row goes above the first "always" row, or it could never fire;
-- a padded "always" row goes last, as a fallback behind the player's own rows
-- a padded row that could never fire (an earlier "Always" row takes every case) is left out
function T.insert_padded(list, t)
	local at = #list + 1;
	if t[1] ~= "always" then
		for i, r in ipairs(list) do
			if r[1] == "always" then at = i; break end;
		end;
	end;
	table.insert(list, at, t);
	if T.unreachable(list)[at] then table.remove(list, at); return false end;
	return true;
end;

-- a saved row list fitted to n slots: cut to n, then padded with the role's defaults not already listed
function T.fit(list, n, role)
	local out = {};
	for k = 1, math.min(n, #list) do out[k] = list[k] end;
	for _, d in ipairs(T.DEFAULTS[role] or T.DEFAULTS.melee) do
		if #out >= n then break end;
		local dup = false;
		for _, t in ipairs(out) do if t[1] == d[1] and t[2] == d[2] and t[3] == d[3] then dup = true end end;
		if not dup then T.insert_padded(out, { d[1], d[2], d[3] }) end;
	end;
	return out;
end;

-- presets: { id, name, description, rows, category }; rows in importance order, a unit with n slots takes
-- the first n. Every preset's plan is complete in its first two rows; later rows refine it.
T.PRESETS = {
	{ "line",      "Hold the line",  "Hold position for the first minute, then attack the nearest enemy. Attack cavalry that comes near.", {
		{ "always", "nearest_enemy", "attack" }, { "early", "self", "hold" }, { "enemy_cav_near", "enemy_cavalry", "attack" },
		{ "lord_in_melee", "ally_lord", "guard" }, { "hp_lt_25", "self", "retreat" } }, "Infantry" },
	{ "hill",      "Hold the hill",  "Take and hold the nearest high ground.", {
		{ "always", "self", "high_ground" }, { "few_enemies", "enemy_weakest", "attack" }, { "lord_in_melee", "enemy_attacking_lord", "attack" },
		{ "hp_lt_25", "self", "retreat" }, { "enemy_cav_near", "enemy_cavalry", "attack" } }, "Infantry" },
	{ "inf_flank", "Flanking infantry", "Wait until your other units are fighting, then attack the sides and backs of the enemies they fight.", {
		{ "always", "self", "hammer" }, { "hp_lt_25", "self", "regroup" }, { "lord_in_melee", "enemy_attacking_lord", "attack" },
		{ "enemy_cav_near", "enemy_cavalry", "attack" }, { "always", "self", "kill_lord" } }, "Infantry" },
	{ "vanguard",  "Vanguard",       "Charge the nearest enemy. Help allies in melee.", {
		{ "always", "nearest_enemy", "charge" }, { "ally_in_melee", "enemy_engaged", "charge" }, { "enemy_cav_near", "enemy_cavalry", "attack" },
		{ "always", "enemy_large", "attack" }, { "hp_lt_25", "self", "retreat" } }, "Infantry" },
	{ "bodyguard", "Bodyguard",      "Stay with the lord and attack enemies that reach him.", {
		{ "always", "ally_lord", "guard" }, { "lord_in_melee", "enemy_attacking_lord", "attack" }, { "enemy_near", "nearest_enemy", "attack" },
		{ "hp_lt_25", "self", "retreat" }, { "always", "nearest_enemy", "attack" } }, "Infantry" },
	{ "screen",    "Missile screen", "Stand between your missile units and the enemy. Attack enemies that reach them.", {
		{ "always", "ally_missile", "cover" }, { "missiles_threatened", "enemy_near_missiles", "attack" }, { "enemy_near_40", "nearest_enemy", "attack" },
		{ "hp_lt_25", "self", "to_lord" }, { "few_enemies", "enemy_weakest", "attack" } }, "Infantry" },
	{ "hammer",    "Hammer and anvil", "Wait beside your army. Go round an enemy your other units are fighting, charge it from behind, pull back, charge again.", {
		{ "always", "self", "hammer" }, { "hp_lt_25", "self", "regroup" }, { "enemy_cav_near", "enemy_cavalry", "cycle_charge" },
		{ "always", "self", "kill_lord" }, { "few_enemies", "enemy_weakest", "cycle_charge" } }, "Cavalry" },
	{ "hunter",    "Missile hunter", "Attack enemy archers and artillery, then charge from behind enemies your other units are fighting.", {
		{ "always", "self", "disrupt" }, { "always", "self", "hammer" }, { "hp_lt_25", "self", "regroup" },
		{ "always", "self", "kill_lord" }, { "enemy_cav_near", "enemy_cavalry", "cycle_charge" } }, "Cavalry" },
	{ "shock",     "Shock cavalry",  "Charge, pull back, charge again.", {
		{ "always", "enemy_engaged", "cycle_charge" }, { "always", "nearest_enemy", "cycle_charge" }, { "hp_lt_25", "self", "regroup" },
		{ "always", "self", "kill_lord" }, { "always", "enemy_missile", "cycle_charge" } }, "Cavalry" },
	{ "assassin",  "Lord hunter",    "Attack the enemy general when he is alone, in melee or badly hurt. Otherwise charge from behind enemies your other units are fighting.", {
		{ "always", "self", "kill_lord" }, { "always", "self", "hammer" }, { "hp_lt_25", "self", "regroup" },
		{ "always", "self", "disrupt" }, { "always", "enemy_hero", "duelist" } }, "Cavalry" },
	{ "focus",     "Focus fire",     "All shooters on this plan shoot the same enemy. Move away from enemy melee troops.", {
		{ "always", "self", "focus" }, { "hp_lt_25", "self", "to_lord" }, { "enemy_cav_near", "enemy_cavalry", "skirmish" },
		{ "always", "nearest_enemy", "skirmish" }, { "few_enemies", "enemy_weakest", "attack" } }, "Missile" },
	{ "skirmish",  "Skirmisher",     "Shoot from range. Move away when enemy melee troops come near.", {
		{ "always", "nearest_enemy", "skirmish" }, { "hp_lt_25", "self", "to_lord" }, { "always", "enemy_free", "skirmish" },
		{ "always", "enemy_large", "skirmish" }, { "enemy_cav_near", "enemy_cavalry", "skirmish" } }, "Missile" },
	{ "support",   "Fire support",   "Shoot from just behind your melee units. Fall back behind them if the enemy gets through.", {
		{ "always", "enemy_engaged", "fire_support" }, { "always", "nearest_enemy", "fire_support" }, { "hp_lt_25", "self", "to_lord" },
		{ "always", "enemy_large", "fire_support" }, { "always", "self", "focus" } }, "Missile" },
	{ "battery",   "Hilltop battery", "Shoot from the highest ground nearby.", {
		{ "always", "self", "high_ground" }, { "hp_lt_25", "self", "to_lord" }, { "missiles_threatened", "enemy_near_missiles", "attack" },
		{ "enemy_near_40", "nearest_enemy", "attack" }, { "always", "self", "focus" } }, "Missile" },
	{ "harasser",  "Harasser",       "Shoot enemy archers and gunners from range, then anything else.", {
		{ "always", "enemy_archers", "skirmish" }, { "always", "nearest_enemy", "skirmish" }, { "hp_lt_50", "self", "to_lord" },
		{ "always", "self", "kill_lord" }, { "enemy_cav_near", "enemy_cavalry", "skirmish" } }, "Missile" },
	{ "champion",  "Champion",       "Fight enemy monsters and heroes in melee. Otherwise charge from behind enemies your other units are fighting. Cast spells.", {
		{ "always", "enemy_large", "duelist" }, { "always", "self", "hammer" }, { "always", "enemy_engaged", "cast_attack" },
		{ "hp_lt_25", "self", "to_lord" }, { "always", "ally_engaged", "cast_buff" } }, "Lords and heroes" },
	{ "mage",      "Battle mage",    "Stay behind your fighting units and cast spells.", {
		{ "always", "self", "caster" }, { "hp_lt_50", "ally_weakest", "cast_buff" }, { "always", "enemy_large", "cast_attack" },
		{ "lord_hurt", "ally_lord", "cast_buff" }, { "always", "ally_engaged", "cast_buff" } }, "Lords and heroes" },
	{ "slayer",    "Lord slayer",    "Attack the enemy general when he is alone, in melee or badly hurt. Fight enemy monsters and heroes in melee.", {
		{ "always", "self", "kill_lord" }, { "always", "enemy_large", "duelist" }, { "hp_lt_25", "self", "to_lord" },
		{ "always", "self", "hammer" }, { "always", "enemy_engaged", "cast_attack" } }, "Lords and heroes" },
	{ "commander", "Commander",      "Stay behind your fighting units and cast spells. Fight only enemies within 40 m.", {
		{ "always", "self", "caster" }, { "enemy_near_40", "nearest_enemy", "attack" }, { "hp_lt_50", "self", "regroup" },
		{ "always", "ally_engaged", "cast_buff" }, { "always", "enemy_engaged", "cast_attack" } }, "Lords and heroes" },
};
T.PRESET_BY = {};
for i, p in ipairs(T.PRESETS) do T.PRESET_BY[p[1]] = p end;

-- first n entries of a list, ordered so "Always" rows don't shadow the rows below them
T.take = take;

local function is_cast(a) return a == "cast_attack" or a == "cast_buff" or T.is_spell_id(a) end;
T.is_cast = is_cast;

-- rows that can never fire because an earlier row of the same kind (movement or spell)
-- always applies: condition "Always", a target that always exists, an action that never declines
function T.unreachable(list)
	local out, blocked = {}, { move = false, cast = false };
	for i, t in ipairs(list) do
		local kind = is_cast(t[3]) and "cast" or "move";
		if blocked[kind] then out[i] = blocked[kind] end;
		local a = T.ACTION_BY[t[3]];
		if not blocked[kind] and t[1] == "always" and (t[2] == "nearest_enemy" or t[2] == "self") and kind == "move"
			and not (a and a.passes) then
			blocked[kind] = i;
		end;
	end;
	return out;
end;

-- symbols (HUD icon names, see tools/make_ui.py) and what a unit is doing, for the battle panel and the
-- director's banner. Plays describe their current step (the engine's state().phase).
T.ACT_ICON = {
	hammer = "rear", hammer_flank = "flank", hammer_wide = "rear", cycle_charge = "charge", skirmish = "volley", focus = "volley", fire_support = "volley",
	disrupt = "charge", kill_lord = "general", high_ground = "hold", duelist = "duel", caster = "spell",
	attack = "clash", charge = "charge", melee = "clash", flank = "flank", approach = "charge",
	guard = "hold", follow = "hold", cover = "hold", hold = "hold", retreat = "rout", to_lord = "general", regroup = "hold",
	cast_attack = "spell", cast_buff = "spell",
};
local PHASE_ICON = { wait = "hold", swing = "flank", rear = "rear", hit = "rear", flank_hit = "flank", charge = "charge", contact = "clash",
	out = "charge", reform = "hold", kite = "volley", round = "flank" };

function T.icon(act, phase)
	if phase and PHASE_ICON[phase] then return PHASE_ICON[phase] end;
	if T.is_spell_id(act) then return "spell" end;
	return T.ACT_ICON[act] or "tactic";
end;

-- %s = the target's name
local PHASE_TEXT = {
	wait = "waiting beside the army", swing = "going round %s", rear = "getting behind %s", hit = "hitting %s in the rear", flank_hit = "hitting %s in the flank",
	charge = "charging %s", contact = "fighting %s", out = "pulling back to charge again", reform = "lining up another charge",
	kite = "backing off to keep shooting", round = "going round enemy troops to reach %s",
};
local ACT_TEXT = {
	hammer = "hitting %s in the rear", hammer_flank = "hitting %s in the flank", hammer_wide = "hitting %s in the rear", cycle_charge = "charging %s", skirmish = "shooting %s and keeping away", focus = "shooting %s with the others",
	fire_support = "shooting %s from behind our units", disrupt = "hunting down %s", kill_lord = "going for %s", high_ground = "holding the high ground",
	duelist = "fighting %s", caster = "casting spells from behind our units",
	attack = "attacking %s", charge = "charging %s", melee = "fighting %s", flank = "attacking %s from the side", approach = "advancing on %s",
	guard = "guarding %s", follow = "moving to %s", cover = "standing in front of %s", hold = "holding position", retreat = "falling back",
	to_lord = "falling back to the general", regroup = "regrouping",
};
T.PLAYS = { hammer = true, hammer_flank = true, hammer_wide = true, cycle_charge = true, skirmish = true, focus = true, fire_support = true, disrupt = true,
	kill_lord = true, high_ground = true, duelist = true, caster = true };

-- "charging Orc Boyz"; who = the target's name (nil: "the enemy")
function T.doing(act, phase, who)
	local f = (phase and PHASE_TEXT[phase]) or ACT_TEXT[act];
	if not f then return nil end;
	if act == "caster" and phase ~= "kite" then f = ACT_TEXT.caster end;
	if act == "high_ground" then f = ACT_TEXT.high_ground end;
	return (f:gsub("%%s", function() return who or "the enemy" end));
end;

-- very short condition names for the compact battle panel
T.COND_SHORT = {
	always = "", early = "First 60 s", after_60 = "After 1 min", after_180 = "After 3 min",
	in_melee = "In melee", not_in_melee = "Not in melee", under_fire = "Under fire", not_under_fire = "Not under fire",
	hp_gt_75 = "HP>75%", hp_lt_75 = "HP<75%", hp_lt_50 = "HP<50%", hp_lt_25 = "HP<25%",
	has_ammo = "Has ammo", ammo_low = "Ammo<25%", ammo_out = "No ammo", isolated = "Alone",
	enemy_near_40 = "Foe<40 m", enemy_near = "Foe<80 m", enemy_near_150 = "Foe<150 m", no_enemy_near = "No foe near",
	enemies_near_3 = "3+ foes near", enemy_cav_near = "Cavalry near", enemy_large_near = "Monster near",
	enemy_missile_near = "Shooters near", enemy_inf_near = "Infantry near", enemy_general_near = "Their general near",
	ally_in_melee = "Ally fighting", ally_hurt_near = "Ally hurt", missiles_threatened = "Shooters threatened",
	lord_in_melee = "Lord fighting", lord_hurt = "Lord hurt", lord_near = "Lord near", lord_far = "Lord far",
	self_winning = "Winning fight", self_winning_big = "Winning easily", self_losing = "Losing fight", self_losing_bad = "Losing badly",
	ally_winning = "Ally winning", ally_losing = "Ally losing", ally_losing_bad = "Ally losing badly",
	winning = "Army winning", even = "Armies even", losing = "Army losing", outnumbered = "Outnumbered", few_enemies = "Mop-up",
};

-- one-line plain description of a row
function T.sentence(t)
	local c, tg, a = T.COND_BY[t[1]], T.TARGET_BY[t[2]], T.ACTION_BY[t[3]];
	if not c or not tg or not a then return "?" end;
	local when = t[1] == "always" and "Always" or ("When: " .. c.label:lower());
	if a.kind == "-" then return when .. " -> " .. a.label:lower() .. "." end;
	return when .. " -> " .. a.label:lower() .. ": " .. tg.label:lower() .. ".";
end;
