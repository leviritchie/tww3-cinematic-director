--------------------------------------------------------------------------------
-- Cinematic Director: tactics catalogue (shared by campaign editor and battle engine)
--
-- A tactic is { cond, target, action }. Each unit has 2 + floor(rank / 2) tactic
-- slots (1-5). In battle a unit walks its tactics top to bottom and follows the
-- first one whose condition holds and whose target exists; if none apply it
-- falls back to its role's default behaviour.
--------------------------------------------------------------------------------

CD_TACTICS = {};
local T = CD_TACTICS;

T.MAX_SLOTS = 5;

function T.slots_for_rank(rank)
	rank = tonumber(rank) or 0;
	return math.min(T.MAX_SLOTS, 2 + math.floor(rank / 2));
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

	{ "ally_lord",           "Our lord",                     "a", "Allies" },
	{ "ally_engaged",        "Ally in melee",                "a", "Allies" },
	{ "ally_weakest",        "Most damaged ally",            "a", "Allies" },
	{ "ally_nearest",        "Nearest ally",                 "a", "Allies" },
	{ "ally_missile",        "Our missile units",            "a", "Allies" },
	{ "ally_large",          "Our nearest hero/monster",     "a", "Allies" },

	{ "self",                "Self",                         "-", "Self" },
};

-- actions: what the unit does { id, label, need, category }; need = target kind the action requires
T.ACTIONS = {
	{ "attack",      "Attack",                     "e", "Fight" },
	{ "charge",      "Charge (all out)",           "e", "Fight" },
	{ "melee",       "Melee attack",               "e", "Fight" },
	{ "flank",       "Flank and attack",           "e", "Fight" },
	{ "skirmish",    "Shoot and keep distance",    "e", "Fight" },
	{ "approach",    "Advance toward",             "e", "Fight" },

	{ "guard",       "Guard",                      "a", "Support" },
	{ "follow",      "Move to",                    "a", "Support" },
	{ "cover",       "Shield",                     "a", "Support" },

	{ "hold",        "Hold position",              "-", "Position" },
	{ "retreat",     "Fall back",                  "-", "Position" },
	{ "to_lord",     "Fall back to our lord",      "-", "Position" },
	{ "regroup",     "Regroup with the army",      "-", "Position" },

	{ "cast_attack", "Cast attack spell on",       "e", "Spells" },
	{ "cast_buff",   "Cast buff/heal on",          "a", "Spells" },
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
T.DEFAULTS = {
	melee = {
		{ "always",         "nearest_enemy", "attack" },
		{ "enemy_cav_near", "enemy_cavalry", "attack" },
		{ "ally_in_melee",  "enemy_engaged", "attack" },
		{ "hp_lt_25",       "self",          "retreat" },
		{ "lord_in_melee",  "ally_lord",     "guard" },
	},
	missile = {
		{ "always",         "nearest_enemy", "attack" },
		{ "enemy_near",     "self",          "retreat" },
		{ "always",         "enemy_free",    "attack" },
		{ "always",         "enemy_large",   "attack" },
		{ "hp_lt_25",       "self",          "retreat" },
	},
	missile_cav = {
		{ "always",         "nearest_enemy", "attack" },
		{ "enemy_near",     "self",          "retreat" },
		{ "always",         "enemy_free",    "attack" },
		{ "always",         "enemy_missile", "attack" },
		{ "hp_lt_25",       "self",          "retreat" },
	},
	cavalry = {
		{ "always",         "enemy_missile", "charge" },
		{ "ally_in_melee",  "enemy_engaged", "charge" },
		{ "always",         "nearest_enemy", "attack" },
		{ "early",          "ally_lord",     "guard" },
		{ "hp_lt_25",       "self",          "retreat" },
	},
	monster = {
		{ "always",         "nearest_enemy", "attack" },
		{ "always",         "enemy_infantry","attack" },
		{ "ally_in_melee",  "enemy_engaged", "attack" },
		{ "hp_lt_25",       "self",          "retreat" },
		{ "always",         "enemy_missile", "attack" },
	},
	hero = {
		{ "always",         "nearest_enemy", "attack" },
		{ "always",         "enemy_engaged", "cast_attack" },
		{ "always",         "ally_engaged",  "cast_buff" },
		{ "hp_lt_50",       "self",          "retreat" },
		{ "always",         "enemy_large",   "attack" },
	},
};

-- default list for a unit with n slots: first n entries, conditional ones ahead of "always"
-- so earlier rules aren't shadowed (a tactic with "Always" and a target that exists always fires)
function T.default_tactics(role, n)
	local src = T.DEFAULTS[role] or T.DEFAULTS.melee;
	local out = {};
	for i = 1, math.min(n, #src) do out[#out + 1] = { src[i][1], src[i][2], src[i][3], order = i } end;
	table.sort(out, function(a, b)
		local ca, cb = a[1] ~= "always", b[1] ~= "always";
		if ca ~= cb then return ca end;
		return a.order < b.order;
	end);
	for _, t in ipairs(out) do t.order = nil end;
	return out;
end;

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
	return (c and c.label or t[1]) .. " | " .. (a and a.label or t[3]) .. " " .. (tg and tg.label or t[2]);
end;

-- plain-language help shown in the editor
T.HELP = {
	always = "Always applies. Rows below an 'Always' row are only reached when its target doesn't exist.",
	early = "Only during the first minute after deployment ends - e.g. hold the line, then advance.",
	after_60 = "From one minute into the battle onward.",
	after_180 = "From three minutes into the battle onward - a late push or a late retreat.",
	in_melee = "This unit is fighting in melee.",
	not_in_melee = "This unit is not fighting in melee.",
	under_fire = "This unit is being hit by missiles.",
	not_under_fire = "No missiles are hitting this unit.",
	hp_gt_75 = "This unit is still fresh: more than three quarters of its health left.",
	hp_lt_75 = "This unit has lost more than a quarter of its health.",
	hp_lt_50 = "This unit has lost more than half its health.",
	hp_lt_25 = "This unit has lost more than three quarters of its health.",
	has_ammo = "This unit still has ammunition (never true for units without missiles).",
	ammo_low = "This unit has used more than three quarters of its ammunition.",
	ammo_out = "This missile unit has no ammunition left.",
	isolated = "No friendly unit within 100 m - this unit is on its own.",
	enemy_near_40 = "An enemy unit is within 40 m - about to make contact.",
	enemy_near = "Any enemy unit within 80 m of this unit. A unit falling back because of this keeps going until 130 m clear.",
	enemy_near_150 = "Any enemy unit within 150 m of this unit.",
	no_enemy_near = "No enemy unit within 150 m of this unit.",
	enemies_near_3 = "Three or more enemy units within 120 m - this unit is about to be swarmed.",
	enemy_cav_near = "Enemy cavalry, chariots or flyers within 120 m.",
	enemy_large_near = "An enemy monster, hero or lord within 120 m.",
	enemy_missile_near = "Enemy archers, gunners or artillery within 200 m.",
	enemy_inf_near = "Enemy infantry within 80 m.",
	enemy_general_near = "The enemy general is within 150 m.",
	ally_in_melee = "A friendly unit within 150 m is fighting in melee.",
	ally_hurt_near = "A friendly unit within 150 m has lost more than half its health.",
	missiles_threatened = "An enemy unit is within 60 m of one of your missile units.",
	lord_in_melee = "Your lord is fighting in melee.",
	lord_hurt = "Your lord has lost more than half his health.",
	lord_near = "Your lord is within 80 m of this unit.",
	lord_far = "Your lord is more than 150 m away from this unit.",
	winning = "Your army's remaining strength is clearly greater than the enemy's.",
	even = "Neither army is clearly stronger.",
	losing = "Your army's remaining strength is clearly smaller than the enemy's.",
	outnumbered = "The enemy has more units still fighting than you do.",
	few_enemies = "Only three or fewer enemy units are still fighting - time to mop up.",

	nearest_enemy = "The closest enemy unit (always exists while enemies remain).",
	enemy_near_lord = "The enemy unit closest to your lord - keep him safe.",
	enemy_near_missiles = "The enemy unit closest to any of your missile units - protect your shooters.",
	enemy_isolated = "The enemy unit farthest from its own allies - easy prey.",
	enemy_farthest = "The enemy unit farthest from this unit - deep strikes for fast units.",
	enemy_infantry = "The closest enemy infantry regiment.",
	enemy_missile = "The closest enemy archers, gunners or artillery.",
	enemy_archers = "The closest enemy archers or gunners (not artillery).",
	enemy_artillery = "The closest enemy artillery piece or war machine.",
	enemy_cavalry = "The closest enemy cavalry, chariot or flyer.",
	enemy_flier = "The closest enemy unit that can fly.",
	enemy_large = "The closest enemy monster, hero or lord.",
	enemy_monster = "The closest enemy monster (not a hero or lord).",
	enemy_hero = "The closest enemy hero (a single character that is not the general).",
	enemy_general = "The enemy general.",
	enemy_engaged = "The closest enemy that is in melee with one of your units - good for flanking.",
	enemy_free = "The closest enemy that is not yet fighting.",
	enemy_attacking_lord = "An enemy unit fighting in melee next to your lord.",
	enemy_weakest = "The most damaged enemy unit (nearer ones preferred).",
	enemy_strongest = "The healthiest enemy unit (nearer ones preferred).",
	ally_lord = "Your lord.",
	ally_engaged = "The closest friendly unit that is fighting in melee.",
	ally_weakest = "The most damaged friendly unit.",
	ally_nearest = "The closest friendly unit.",
	ally_missile = "Your closest missile unit.",
	ally_large = "Your closest hero or monster (not the lord).",
	self = "This unit itself.",

	attack = "Advance and fight the target. Missile units shoot it from range.",
	charge = "Run at the target and fight it hand to hand - best for cavalry and shock troops.",
	melee = "Fight the target hand to hand, even if this unit could shoot.",
	flank = "Swing round to the target's side and rear first, then attack it from there.",
	skirmish = "Shoot the target but back away whenever it gets within 70 m. Melee units just attack.",
	approach = "Move to about 60 m from the target and wait there without attacking - screening, baiting or getting into range.",
	cast_attack = "Cast a damaging spell or ability on the target. Spell rows are checked separately from movement rows, so the unit can move and cast.",
	guard = "Stay close to the friendly target and fight anything that comes near it.",
	follow = "Move next to the friendly target without stopping to fight.",
	cover = "Stand between the friendly target and the nearest enemy, blocking its path.",
	cast_buff = "Cast a buff, ward or heal on the friendly target (heals only on damaged units).",
	hold = "Stay where the unit is and defend that spot.",
	retreat = "Pull back away from the enemy (toward your lord if he is safely behind).",
	to_lord = "Pull back to your lord's side.",
	regroup = "Move back to the middle of your army.",
};

function T.help(id) return T.HELP[id] or "" end;

-- the rank at which slot k unlocks (slots = 2 + floor(rank / 2): two from the start)
function T.rank_for_slot(k) return math.max(0, (k - 2) * 2) end;

-- a padded conditional row goes above the first "always" row, or it could never fire;
-- a padded "always" row goes last, as a fallback behind the player's own rows
function T.insert_padded(list, t)
	if t[1] == "always" then list[#list + 1] = t; return end;
	for i, r in ipairs(list) do
		if r[1] == "always" then table.insert(list, i, t); return end;
	end;
	list[#list + 1] = t;
end;

-- presets: { id, name, description, rows, category }; rows in importance order, a unit with n slots takes the first n
T.PRESETS = {
	{ "line",      "Hold the line",  "Hold position for the first minute, then fight whatever is nearest; turn to face cavalry.", {
		{ "always", "nearest_enemy", "attack" }, { "early", "self", "hold" }, { "enemy_cav_near", "enemy_cavalry", "attack" },
		{ "lord_in_melee", "ally_lord", "guard" }, { "hp_lt_25", "self", "retreat" } }, "Infantry" },
	{ "vanguard",  "Vanguard",       "Charge straight in and keep pushing; help allies already fighting.", {
		{ "always", "nearest_enemy", "charge" }, { "ally_in_melee", "enemy_engaged", "charge" }, { "enemy_cav_near", "enemy_cavalry", "attack" },
		{ "always", "enemy_large", "attack" }, { "hp_lt_25", "self", "retreat" } }, "Infantry" },
	{ "bodyguard", "Bodyguard",      "Stick to the lord and fight anything that reaches him.", {
		{ "always", "ally_lord", "guard" }, { "lord_in_melee", "enemy_engaged", "attack" }, { "enemy_near", "nearest_enemy", "attack" },
		{ "hp_lt_25", "self", "retreat" }, { "always", "nearest_enemy", "attack" } }, "Infantry" },
	{ "screen",    "Missile screen", "Stand between your missile units and the enemy, and attack anything that reaches them.", {
		{ "always", "ally_missile", "cover" }, { "missiles_threatened", "enemy_near_missiles", "attack" }, { "enemy_near_40", "nearest_enemy", "attack" },
		{ "hp_lt_25", "self", "to_lord" }, { "few_enemies", "enemy_weakest", "attack" } }, "Infantry" },
	{ "flanker",   "Flanker",        "Hit enemies that are already locked in melee with your units.", {
		{ "always", "nearest_enemy", "attack" }, { "ally_in_melee", "enemy_engaged", "charge" }, { "always", "enemy_missile", "charge" },
		{ "hp_lt_50", "self", "retreat" }, { "always", "enemy_free", "attack" } }, "Cavalry" },
	{ "hunter",    "Hunter",         "Ride down archers and artillery, then flank.", {
		{ "always", "enemy_missile", "charge" }, { "ally_in_melee", "enemy_engaged", "charge" }, { "always", "nearest_enemy", "attack" },
		{ "hp_lt_50", "self", "retreat" }, { "always", "enemy_free", "attack" } }, "Cavalry" },
	{ "hammer",    "Hammer and anvil", "Stay with the lord until the lines meet, then swing round and hit the enemies your infantry is fighting.", {
		{ "always", "nearest_enemy", "attack" }, { "ally_in_melee", "enemy_engaged", "flank" }, { "early", "ally_lord", "follow" },
		{ "enemy_cav_near", "enemy_cavalry", "charge" }, { "hp_lt_25", "self", "regroup" } }, "Cavalry" },
	{ "skirmish",  "Skirmisher",     "Shoot from range and back off when enemies close in.", {
		{ "always", "nearest_enemy", "attack" }, { "enemy_near", "self", "retreat" }, { "always", "enemy_free", "attack" },
		{ "always", "enemy_large", "attack" }, { "hp_lt_25", "self", "retreat" } }, "Missile" },
	{ "sniper",    "Monster hunter", "Focus fire on monsters, heroes and lords; keep distance.", {
		{ "always", "enemy_large", "attack" }, { "enemy_near", "self", "retreat" }, { "always", "nearest_enemy", "attack" },
		{ "always", "enemy_cavalry", "attack" }, { "hp_lt_25", "self", "retreat" } }, "Missile" },
	{ "harasser",  "Harasser",       "Pick off enemy shooters while keeping distance; fall back to the lord when hurt, and fight on once out of ammo.", {
		{ "always", "enemy_archers", "skirmish" }, { "always", "nearest_enemy", "skirmish" }, { "hp_lt_50", "self", "to_lord" },
		{ "ammo_out", "enemy_engaged", "attack" }, { "enemy_cav_near", "enemy_cavalry", "skirmish" } }, "Missile" },
	{ "champion",  "Champion",       "Duel monsters and heroes, casting attack spells as you go.", {
		{ "always", "enemy_large", "attack" }, { "always", "enemy_engaged", "cast_attack" }, { "always", "nearest_enemy", "attack" },
		{ "hp_lt_25", "self", "retreat" }, { "always", "ally_engaged", "cast_buff" } }, "Lords and heroes" },
	{ "mage",      "Battle mage",    "Stay near the lord and blast enemies with spells.", {
		{ "always", "ally_lord", "guard" }, { "always", "enemy_engaged", "cast_attack" }, { "enemy_near", "self", "retreat" },
		{ "always", "nearest_enemy", "cast_attack" }, { "always", "ally_engaged", "cast_buff" } }, "Lords and heroes" },
	{ "support",   "Support caster", "Stay back, heal and buff your fighting units.", {
		{ "always", "ally_lord", "guard" }, { "always", "ally_engaged", "cast_buff" }, { "hp_lt_50", "ally_weakest", "cast_buff" },
		{ "enemy_near", "self", "retreat" }, { "always", "enemy_engaged", "cast_attack" } }, "Lords and heroes" },
};
T.PRESET_BY = {};
for i, p in ipairs(T.PRESETS) do T.PRESET_BY[p[1]] = p end;

-- first n entries of a list, conditional rows first so "Always" rows don't shadow them
function T.take(src, n)
	local out = {};
	for i = 1, math.min(n, #src) do out[#out + 1] = { src[i][1], src[i][2], src[i][3], order = i } end;
	table.sort(out, function(a, b)
		local ca, cb = a[1] ~= "always", b[1] ~= "always";
		if ca ~= cb then return ca end;
		return a.order < b.order;
	end);
	for _, t in ipairs(out) do t.order = nil end;
	return out;
end;

local function is_cast(a) return a == "cast_attack" or a == "cast_buff" end;
T.is_cast = is_cast;

-- rows that can never fire because an earlier row of the same kind (movement or spell)
-- always applies: condition "Always" and a target that always exists
function T.unreachable(list)
	local out, blocked = {}, { move = false, cast = false };
	for i, t in ipairs(list) do
		local kind = is_cast(t[3]) and "cast" or "move";
		if blocked[kind] then out[i] = blocked[kind] end;
		if not blocked[kind] and t[1] == "always" and (t[2] == "nearest_enemy" or t[2] == "self") and kind == "move" then
			blocked[kind] = i;
		end;
	end;
	return out;
end;

-- one-line plain description of a row
function T.sentence(t)
	local c, tg, a = T.COND_BY[t[1]], T.TARGET_BY[t[2]], T.ACTION_BY[t[3]];
	if not c or not tg or not a then return "?" end;
	local when = t[1] == "always" and "Always" or ("When: " .. c.label:lower());
	if a.kind == "-" then return when .. " -> " .. a.label:lower() .. "." end;
	return when .. " -> " .. a.label:lower() .. ": " .. tg.label:lower() .. ".";
end;
