# Total War: WARHAMMER III – Real-Time Battle Tactics for a Scripted Commander

Reference for the `cinematic_director` mod: what good human players do in field battles, translated into
rules a `script_ai_planner` + per-unit-controller AI can execute. Campaign strategy is out of scope.

## 0. How to read this document

**Confidence tags** are used on every number:

| Tag | Meaning |
|-----|---------|
| **[S]** | Stated by a cited source (wiki/forum/patch notes/official). |
| **[C]** | Community consensus or rule of thumb; no single authoritative number. |
| **[E]** | Engineering estimate chosen for the script. Tune it in testing, or read the real value from the db (`unit_special_abilities`, `special_ability_phases`, `projectiles`, `battle_vortexs`, `land_units`, `melee_weapons`, `missile_weapons`). |
| **[OLD]** | Comes from WH1/WH2 or from WH3 before about patch 5.x. Probably still true, but the value may have changed. |

**Game version context.** WH3 is now past patch 7.0 (4 Dec 2025: campaign AI recruitment overhaul plus a
battle balance pass on flying units, cavalry and Daemon Princes) and 8.1 (9 Jul 2026, campaign AI) ([gamewatcher 7.0](https://www.gamewatcher.com/total-war-warhammer-3-patch-7-0-release-date-latest-news), [PCGamesN 8.1](https://www.pcgamesn.com/total-war-warhammer-3/patch-notes-8-1-campaign-ai)).
No patch from 5.x to 8.x changed the core battle mechanics: charge bonus, bracing, leadership, flanking,
shields, fatigue and the winds of magic pool. Unit stats and spell numbers do change between patches,
so **read stats from the db at runtime, not from this file.**

**Distances.** All distances are in game metres (the same units as `battle_vector`). For scale, an
infantry unit in default formation is about 30–45 m wide and 6–10 m deep [E]. The two deployment
zones usually start about 300–600 m apart on land maps [E].

---

## 1. Core battle principles

### 1.1 The battle line

- **Hold a continuous front.** Put the infantry side by side with their flanks nearly touching, with
  gaps of 0–5 m [E]. Any gap is a hole that enemy cavalry or monsters can drive through
  ([TW Academy](https://academy.totalwar.com/battle-basic-tactics/)).
- **Fight as a group.** Experienced players lock the main line into a formation group and right-click
  a central enemy. The line then advances together and picks its own targets
  ([Steam discussion](https://steamcommunity.com/app/1142710/discussions/0/4416425392682933578)).
  - **Script:** issue one `attack_force`/`defend_position` to the whole line through its planner. Do
    not give every infantry unit its own target. Keep per-unit micro for flankers, flyers, heroes
    and casters.
- **Checkerboard formation.** A staggered infantry front (alternating units about 10–20 m forward) makes
  firing gaps for archers. It also makes it harder for one enemy unit to tie up two of yours
  ([same thread](https://steamcommunity.com/app/1142710/discussions/0/4416425392682933578)). This is
  optional. Use it for gunline presets, not for anvil presets.
- **Standard layout**, back to front [C]:
  - Artillery: 60–120 m behind the line, ideally on high ground.
  - Ranged infantry: 15–40 m behind the melee line. They only fire over it with an arcing trajectory.
    Flat-trajectory guns need a clear line of sight, so put them in front, in gaps, or on the wings.
  - Melee line: spears and anti-large go in the centre-front and opposite enemy cavalry and monsters.
    Swords and great weapons go wherever enemy infantry will be.
  - Cavalry and fast units: on the wings, 30–60 m outside the end of the line, and slightly back.
  - Lord and caster heroes: 30–60 m behind the centre. That keeps them inside the leadership aura
    and their spell range while they stay out of contact.

### 1.2 Hammer and anvil

The infantry (the anvil) pins the enemy in frontal melee. Cavalry, monsters or flyers (the hammer) then
charge the enemy's flank or rear. The result is heavy casualties plus a big leadership penalty, which
cascades into routs ([TW Academy](https://academy.totalwar.com/battle-basic-tactics/)).

Script rules:
1. The hammer waits for the anvil to engage first. Trigger when the target enemy unit has been
   `is_in_melee` with one of our line units for at least 3–5 s [E]. Charging before the enemy is pinned
   lets it turn around and brace (spears) or counter-charge.
2. Approach on a curve. The hammer's waypoint is a point 60–100 m to the side of and behind the target,
   computed from the target's bearing (see 7.4). Only then issue the attack. A straight-line attack order
   from the wing usually hits the flank at an angle, or collides with our own line.
3. Prefer targets in this order: engaged ranged or artillery > engaged non-spear infantry >
   engaged monsters (only with an anti-large or high-mass hammer). **Never** take engaged spears or
   halberds from the front.

### 1.3 Flanking and rear attacks

- Attacks on the flank or rear cause more casualties and a leadership penalty
  ([TW Academy](https://academy.totalwar.com/battle-basic-tactics/)).
- **Shields only block from the front.** The arc is 120°, so 60° each side of facing. Block chance is
  `(20 + shield + armour) × 0.5`% [S, OLD]
  ([Steam](https://steamcommunity.com/app/364360/discussions/0/350532795331336157)). Shooting a unit in
  the back ignores its shields, so missile cavalry and flanking gunners should shoot from the side or rear.
- **Bracing only works from the front.** Charge defence only works when the unit is stationary and
  charged frontally ([Steam WH2](https://steamcommunity.com/app/594570/discussions/0/3175526477755400640)).
  A flank or rear charge on spears is safe.
- **Leadership values.** Hover tooltips show modifiers such as "Attacked in flank", "Attacked in rear",
  "General nearby", "General wounded" and "Lord died recently"
  ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3365901931426620282)). Approximate
  magnitudes from community data [C, OLD]: flank −6 and rear −12 (unverified). Lord death is a large
  penalty ("recently" −16 in WH2) ([Steam WH2](https://steamcommunity.com/app/594570/discussions/0/1771511442687123095)).
  Routs come from several modifiers stacking ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3832045766778568866)).
  Script takeaway: **two simultaneous attack directions on one enemy unit nearly always break it.**

### 1.4 Charge bonus and cycle charging

- **Charge bonus.** Added to melee attack and weapon damage on impact. It **decays over about 13 s
  after contact** [S, OLD] ([Steam WH2](https://steamcommunity.com/app/594570/discussions/0/3175526477755400640)).
  A unit has to run a minimum distance before contact to count as charging [C]. If it starts adjacent
  it gets little or no bonus.
- **Cycle charge.** Charge, then pull out after about 8–12 s, retreat, and charge again. A single attack
  order is not enough: after passing through, the unit turns and fights at walking pace without the
  bonus. It has to be ordered away and re-ordered
  ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3809535864679012912)). Shock cavalry
  can stay in melee about 10 s until the bonus runs out. Chariots do about 99% of their damage on
  impact, so they must always be cycled.

Script cycle-charge state machine (per hammer unit):
```
APPROACH  -> attack(target)                         ; until is_in_melee
IMPACT    -> wait T_contact = 6-10 s [E] (cavalry 8-12, chariots 2-4, monsters 10-20 or never)
DISENGAGE -> move_to point 60-90 m [E] away, opposite to the target, biased toward our own lines
             (run, not walk); timeout 10 s
REFORM    -> wait until dist(target) >= 50 m [E] and not in melee, then pick a (new) target
CHARGE    -> attack(target) again
abort DISENGAGE->RETREAT if HP < 35 % or wavering; abort cycling if the target is anti-large and faces us
```
Pulling out of melee costs some free hits from the enemy. Don't cycle out of a fight we are clearly
winning (enemy wavering or routing). Let the unit finish it.

### 1.5 Mass, bracing and impact

- High-mass units (monsters, chariots, ogres, heavy cavalry) send low-mass infantry flying and deal
  impact damage. The charger's mass compared with the target's mass decides how deep it penetrates
  ([Steam WH2](https://steamcommunity.com/app/594570/discussions/0/3175526477755400640)).
- **Bracing.** Stationary units facing the charge brace automatically. Braced anti-large units with
  "charge defence vs large" cancel the charger's charge bonus. Bracing gives about +20% melee defence,
  which fades over 13 s once in melee [S, OLD].
  - Community quote: anything with mass of 4000 or less is "dead-stopped" by spear entities attacking
    it after a charge [C] ([Steam](https://steamcommunity.com/app/1142710/discussions/0/4339851902698051173)).
  - **Script:** defensive presets should keep anti-large units **stationary** when enemy large units
    approach. Don't reissue move orders to them in the last 3 s before contact.
- **7.0 flying and mass changes.** Coverage of patch 7.0 says flying monster and dragon mass rose about
  14–34%. They stagger less, behave more like sustained-fight units and are worse at rapid cycling
  [C, single secondary source] ([dtgre](https://www.dtgre.com/2025/12/total-war-warhammer-3-update-7-0-air-combat-dragon-overhaul-guide.html)).
  Low confidence: that site appears to be auto-generated. Verify in the db (`battle_entities.mass`).

### 1.6 Morale, leadership and routing

States: Eager/Confident → Steady → Wavering → Broken (routing) → Shattered (gone for good). Units that
rout may rally after some seconds out of combat. Contributing modifiers [C]: casualties taken, losing
the fight, being flanked or attacked from the rear, missile and artillery fire, fear/terror, nearby
friends routing, lord wounded or dead, low HP. Positive modifiers: general nearby (leadership aura),
winning the fight, high ground [C].

- **General's aura.** Keep the lord within the leadership aura of the line (on the order of 30–60 m
  [E]; read the actual radius from the lord's ability or effect). The "Confident – General Nearby"
  modifier needs the lord close by and unhurt
  ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3365901931426620282)).
- **Undead and daemons** don't rout. They crumble, losing HP as their leadership falls. Leadership
  pressure still works on them, it just shows up as damage.
- **Unbreakable** units (VC/TK undead, some constructs) never rout. Treat them as tarpits.
- Script heuristics:
  - Push the attack where an enemy unit `is_wavering()`. Add one more unit or a rear charge there.
    Breaking one unit tends to cascade to its neighbours.
  - **Don't chase routers with the main line.** Chase only with fast units, and only when no unrouted
    enemy is within 100 m [E] of the chaser. Shattered units are gone; ignore them.
  - If one of **our** units is wavering, pull it out of melee only if we have a replacement within
    30 m [E]. Otherwise leave it (pulling out exposes its rear). Cast leadership augments on it if
    available.

### 1.7 Fatigue

Running, fighting and firing all cause fatigue. The vanilla **Exhausted** penalties are
[S, from a fatigue-mod discussion]: speed ×0.85, armour ×0.75, charge bonus ×0.70, melee attack ×0.70,
melee AP damage ×0.90, melee defence ×0.90, reload ×0.90
([Steam workshop discussion](https://steamcommunity.com/workshop/filedetails/discussion/3308073985/612032174956240488)).

Script rules [E]:
- Walk, don't run, for any advance longer than 150 m when no enemy is within 200 m. The planner's
  move orders may run by default, so check whether there's a walk option.
- Don't run the hammer around the map. Keep the cycle-charge disengage distance short (60–90 m).
- In long defensive battles, rotate engaged line units only if there is a fresh reserve behind them.

### 1.8 Terrain, high ground and forests

- **High ground.** Gives a melee bonus and better visibility. Charging downhill is stronger. Missile
  units on a hill get longer range and can shoot over their own line
  ([TW Academy](https://academy.totalwar.com/battle-basic-tactics/)) [C].
  - **Script:** for a defensive preset, sample `ground height` in a grid around our deployment
    centroid (radius 200 m). Pick the highest point that still lies between us and the enemy as the
    `defend_position` anchor.
- **Forests.** Most units can hide in forests ([TW Academy](https://academy.totalwar.com/battle-basic-tactics/)).
  Trees break formations, slow cavalry and chariots, and block missile line of sight. Large units and
  chariots should not fight inside forests. Units with stealth or vanguard (Wood Elves, Skaven, Beastmen)
  benefit from them.
- **Chokepoints.** The vanilla AI was patched in 5.2.5 to rush through chokepoints under fire instead of
  reforming ([gamewatcher 5.2.5](https://www.gamewatcher.com/news/total-war-warhammer-3-patch-notes-2024-v5-2-5-patch-released)).
  When we defend a chokepoint, expect the enemy to push through rather than hesitate. Put area
  spells (vortex, bombardment) at the exit of the choke.

### 1.9 Defending and attacking

| | Defender (or anyone with better ranged/artillery) | Attacker (or anyone with a melee edge and no ranged) |
|---|---|---|
| Goal | Make the enemy walk through fire into braced spears | Close the distance fast, engage everything at once |
| Line | `defend_position(anchor, r=40–80 m)` | `attack_force`/`rush_force` with the whole line together |
| Ranged | Fire at the most dangerous approaching unit | Fire at enemy ranged units first (counter-battery) |
| Cavalry | Hold back on the flank and intercept enemy flankers, then rear-charge once the line is engaged | Go around the flank early and dive the enemy artillery and missile units |
| Magic | Bombardments and vortexes on the approach; hexes when they hit the line | Augments (speed, defence, ward save) during the advance; hexes at contact |
| Timing | Hold until the enemy is within about 100 m of the line or 40% of their army is engaged | Advance at once; don't trade shots with a stronger gunline |

### 1.10 Fighting outnumbered or losing

- **Shorten the line.** Anchor one flank on impassable terrain (map edge, cliff, river, dense forest)
  so the enemy can only flank from one side. Fall back into a corner or tight arc and use
  `defend_position` with a smaller radius (40 m) [C].
- **Kill the lord.** Lord death gives a large army-wide leadership penalty (see 1.3). An outnumbered
  army should focus magic missiles, artillery and duelist heroes on the enemy lord [C]
  ([Steam Khorne advice](https://steamcommunity.com/app/1142710/discussions/0/3272436223667796057)).
- **Break one wing.** Concentrate about 60% of our force on about 30% of the enemy line. Routing one
  wing cascades leadership damage across the rest.
- **Keep our lord alive.** Pull back when HP is under 50% [E].

---

## 2. Unit role playbooks

Classify every unit at battle start. Use `unit_class` from the db: `inf_mel`, `inf_spr`/anti-large,
`inf_mis`, `cav_shk`, `cav_mel`, `cav_mis`, `chariot`, `mon`, `art_fld`/`art_fix`, `com`. Combine it with
`can_fly`, `is_large`/entity size, `is_commanding_unit` and the presence of spells. Exact class keys
vary, so verify against `land_units` / `unit_class` tables [E].

### 2.1 Line infantry (melee)
- **Job:** hold the front and pin enemy infantry. Swords are DPS against infantry, great weapons give
  armour piercing, shields counter missiles (keep them facing the enemy ranged).
- **Targets:** enemy infantry in front of them. Avoid charging into monsters unless supported.
- **Rules:**
  - Stay in formation and advance with the line group.
  - Don't let one unit chase more than 60 m [E] out of line.
  - Once engaged, don't re-order it (each re-order makes the unit stop fighting and reform).

### 2.2 Anti-large infantry (spears, halberds)
- **Job:** stand against enemy cavalry, monsters and chariots. Guard the artillery and missile line.
- **Rules:**
  - Place them opposite the largest concentration of enemy large units.
  - Stand still to brace once enemy large units are within 80 m and closing [E].
  - Never charge cavalry; cavalry will just disengage.
  - When enemy monsters dive our backline, move the reserve spear unit to intercept by attacking the
    monster directly.

### 2.3 Shock and melee cavalry
- **Job:** the hammer: flank, rear-charge and cycle charge. Also hunts enemy artillery, missile units,
  casters and routers. Weak against spears, halberds and monsters
  ([TW Academy](https://academy.totalwar.com/battle-basic-tactics/)).
- **Targets (score):** engaged missile infantry/artillery (+100) > unengaged artillery (+90, high chance
  it is unprotected) > engaged caster hero (+70) > engaged infantry from the rear (+60) > routing enemies
  late in the battle (+20). Penalty −200 for anti-large units in front-facing contact.
- **Rules:**
  - Hold on the flank until the anvil engages (see 1.2).
  - Use the cycle-charge state machine (see 1.4).
  - If engaged by anti-large, or HP below 40%, disengage immediately.
  - Shock cavalry (`cav_shk`) cycles. Melee cavalry (`cav_mel`) can stay in a fight it is winning.

### 2.4 Missile cavalry and skirmishers
- **Job:** harass, kite, kill enemy missile and artillery crews from the flank, and pull enemy
  cavalry out of position.
- **Rules:**
  - Turn on skirmish mode if the API allows it. It keeps ranged units at a safe distance
    ([TW Academy](https://academy.totalwar.com/battle-basic-tactics/)). Otherwise implement it by hand:
    when an enemy melee unit is within `0.4 × range` [E] and closing, move away 60–80 m perpendicular to
    or away from it, then turn and shoot.
  - Shoot from the flank or rear to bypass shields.
  - Avoid enemy ranged units with a range that matches or beats ours.
  - Units that fire while moving (Wood Elf tier-2 archers, many missile cavalry) can shoot while
    retreating ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3825284575362429511)) [C].
- **Ammo:** when `ammo < 10%`, switch the unit to melee flanker (if it has melee), or keep it back as a
  router chaser.

### 2.5 Fast flankers (light cavalry, hounds, fast monsters)
- **Job:** anti-artillery, anti-caster, chase routers, and distract the enemy (the AI will commit units
  to chase them; see section 6).
- **Rules:** go around the outside edge early, with a waypoint 120–200 m [E] wide of the enemy flank,
  then dive the artillery. Pull out when anti-large or cavalry come to save it.

### 2.6 Ranged infantry
- **Arcs:** archers, crossbows and slings arc over friendly lines. Handguns, many crossbows, warpfire
  throwers and repeaters fire flat and need a clear line of sight. Put them on the wings, in gaps or on
  high ground.
- **Ranges:** typically 150–180 m (archers about 150–180, guns about 140–160) [E]. Read `missile_range`
  from the unit.
- **Friendly fire:** firing at enemies already in melee with our units hits our own units, especially
  with flat trajectories, artillery, mortars and explosive projectiles
  ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3948028800072759169)).
- **Target priority (score; see section 7):** enemy ranged in range (counter-battery) > enemy
  single-entity casters and heroes, lords > unengaged enemy infantry approaching > enemy cavalry
  approaching > engaged enemy (only if arcing and it is a big unit; never flat fire into a melee).
  Ignore monsters with high missile resistance or ward save.
- **Rules:**
  - **Stutter-step fix (vanilla bug):** don't let ranged units shuffle. Keep them on fire-at-will with
    a stable `defend_position`, or set guard mode if available, which reportedly helps
    ([Steam](https://steamcommunity.com/app/1142710/discussions/0/596268777261239940)).
  - Re-target only every ≥ 8 s [E] and only if the current target is dead, routing or out of range.
    Each re-target costs reload and turn time.
  - Fall back behind the melee line if an enemy melee unit gets within 40 m [E].
  - Ammo: if `ammo < 10%`, use the unit as a reserve (or melee if it's good at it).

### 2.7 Artillery
- **Job:** long-range damage and leadership shock. Strong against blobs, slow infantry, monsters (direct
  fire) and enemy artillery. Weak against fast single entities.
- **Targets (score):** stationary blobs (3+ enemy units within 30 m) > enemy artillery and weapon teams
  > large monsters (direct-fire cannons/bolts only) > dense infantry walking forward > lords (cannons) >
  everything else. **Never** fire on any enemy engaged with our melee units if the projectile is
  explosive or a mortar, or if our units are within 20 m of the target [E].
- **Rules:**
  - Keep artillery behind the line on high ground, with an anti-large or cheap infantry guard within
    40 m.
  - Mortars and catapults (indirect fire) can't hit fast units. Use them early on the approach.
  - **Dreadquake-style mortars waste shots on single entities and monsters, and have low ammo.** Feed
    them blobs ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3820783808437734105)).
    Conversely, when the enemy has these, advance our single entities first to soak the shots.
  - Once all enemies are in melee, stop firing unless there is a target with no friends within 30 m.

### 2.8 Monsters
- **Large vs small:** monsters wreck small infantry (high mass, splash attacks, terror). Anti-large
  units, artillery and AP missiles counter them.
- **Targets:** non-anti-large infantry > missile units > artillery > cavalry. Avoid spears and
  halberds, anti-large heroes, and heavy armour-piercing guns.
- **Rules:**
  - Monsters work best charging into the side of engaged infantry or into isolated ranged units.
  - Retreat to our lines when HP < 30% [E] (and cast regeneration if available).
  - Single-entity monsters attract missile fire. In ranged-heavy matchups, keep them out of enemy
    missile range until the lines engage, then commit.
  - Monster-cycle only big chargers (dinosaurs, ogre beasts). Most monsters should stay in.

### 2.9 Flying units
- **Job:** dive enemy artillery, missile units and casters. Kill routers. Draw AI units into chasing.
  Flyers excel against ranged and artillery ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3775742435234834844)).
- **Rules:**
  - Stay airborne while moving. Land (attack) only on the chosen target.
  - Avoid enemy missile units that are not engaged (count them in range of the target).
  - Avoid anti-large and enemy flyers.
  - Treat disengage-and-dive as a cycle charge: `T_contact` 10–15 s [E] for flying cavalry, longer
    for flying monsters.
  - If the target gets a spear or halberd escort within 30 m, abort.
  - Flying lords and heroes on dragons: post-7.0 they reportedly fight well in sustained melee
    [C, low confidence]. Keep them out of anti-large anyway.
  - Chaos furies and harpies are cheap distraction. The AI will send units after them.

### 2.10 Chariots
- About 99% of their damage is impact. Always cycle ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3809535864679012912)).
  `T_contact` is 2–4 s [E], then disengage 60 m straight through or away.
- Never charge spears from the front or into forests. Best targets are flanks of engaged infantry and
  unbraced missile units.
- If micro capacity is limited, use at most 2–4 chariots
  ([Steam](https://steamcommunity.com/app/1142710/discussions/0/6554498588628181472)) [C].

### 2.11 Lords and heroes
- **Classify them:**
  - Melee duelist: high melee and HP, few or no spells.
  - Caster: has spells (`magic_missile`, `vortex`, etc.).
  - Support/buffer: augments, auras.
  - Anti-large: "anti-large" attribute or bonus vs large.
  - Mounted/flying: mount status.
- **Duelists:**
  - Target enemy single entities: heroes and lords first, then monsters (if anti-large) or infantry
    (if anti-infantry).
  - Fight next to our line, not ahead of it. The vanilla AI is notorious for lords running ahead alone
    and dying ([Steam](https://steamcommunity.com/app/1142710/discussions/0/596268777261239940)).
  - Commit only when at least one friendly unit is within 40 m of the target, or the target is
    isolated.
- **Casters:**
  - Stay 40–80 m [E] behind the line, within the range of their key spells (usually 150–300 m for
    magic missiles; Fireball is 300 m [S]).
  - Never enter melee voluntarily. If engaged, retreat toward the nearest friendly melee unit.
- **Our lord:**
  - Lord death gives a big leadership penalty (see 1.3).
  - Retreat when HP < 40% [E]. Go back to the front at > 60% only if healing is available.
  - The lord should never be the first unit into contact unless it is a heavily armoured monster lord
    the army is built around.
- **Enemy lord:** high-value target for magic missiles, artillery (cannons) and duelists once it is
  separated from its escort (see section 7).

### 2.12 Summoned units
- Summons (zombies, skeletons, spirits, daemons, Vermintide rats) are free bodies with timers or decay.
  They're best as:
  1. **Tarpits:** summon in front of a charging enemy elite or monster.
  2. **Flankers:** summon behind or beside an engaged enemy unit to create a rear attack.
  3. **Missile and artillery killers:** summon on top of enemy gunlines.
- Vampire Counts can raise units in out-flanking or cut-off positions, and their fodder never runs, so
  it works as a tarpit ([Steam](https://steamcommunity.com/app/1142710/discussions/0/4521136490642404774)).
- **Script:** summon with target = a position 20–40 m [E] behind the selected enemy, or just in front of
  an enemy charger about 60 m out. Then order the summon to `attack` that enemy. Don't hold summons in
  reserve; they decay.

---

## 3. Magic

### 3.1 The winds of magic pool (WH3)
- The army has a **current pool** for casting now and a **reserve** of how much more it can recover
  during this battle. It recharges quickly at first, but each cast slows the recharge. When the reserve
  runs out the recharge stops
  ([ludo.guide](https://www.ludo.guide/guide/total-war-warhammer-3/effective-use-of-magic-spells),
  [Steam](https://steamcommunity.com/app/1142710/discussions/0/3496509339501484197)).
- The pool is **shared by every caster**. Spells cost roughly 4 (weak) to 16+ (strong)
  ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3826415019288347326)).
- Each spell also has its own cooldown, usually 30–90 s (Fireball: cost 5, cooldown 29 s, range 300 m
  [S]) ([Steam mod changelog](https://steamcommunity.com/sharedfiles/filedetails/changelog/2856313886?p=7)).
  **Overcast** versions cost more for a stronger effect.
- The campaign reserve at battle start depends on the campaign area and the army (starts about 50,
  max 100). This affects battle length but is out of scope here
  ([totalwar.com](https://totalwar.com/?p=15964)).

**Budget rules [E]:**
1. **Hold a floor.** Keep `pool ≥ cost of our best emergency spell` (usually a ward save, heal or big
   hex) until the main engagement starts. After that, spend freely.
2. **Front-load nothing.** Don't cast augments or hexes before contact. Exception: speed or ward
   augments during an advance under heavy enemy fire.
3. **Value per wind.** Score each candidate cast as `expected_value / cost` (see 3.3). Cast at most one
   spell per 2–3 s globally so the camera has something to cut to, and so the pool isn't drained in one
   burst.
4. **Late battle.** When the enemy has < 30% strength left or more than half is routing, stop casting
   expensive spells. Keep winds for heals and hexes on remaining elites.
5. Prefer non-overcast versions unless the pool is above 70% of max and the target value is very high.

### 3.2 When to cast what (by db ability category)

| Category (db) | Best target | Trigger conditions | Avoid |
|---|---|---|---|
| `wh_type_augment` (single) | Our elite or large unit, lord, or a unit doing most of the damage | Our unit `is_in_melee` (or about to be, < 30 m) and HP > 20%. Or a defensive augment on a unit under heavy missile fire | Augmenting units not in combat; buffing nearly dead units |
| `area_of_augments` | Centre of 2+ of our engaged units | ≥ 2 friendly units in melee within the radius (about 30–50 m) | Units not fighting |
| `hex` (single) | Enemy elite, monster or lord engaged with our units; or the unit threatening to break our line | Target engaged with one of ours ≥ 2 s; target value high | Hexing chaff; units about to rout anyway |
| `area_of_hexes` | Centroid of 2+ engaged enemy units | ≥ 2 enemies in the radius, engaged | Single units |
| `direct_damage` | Enemy single entities (heroes, lords, casters, artillery), high-value low-model units | Target in range; HP fraction low enough to finish it is a bonus | Big chaff blobs (low value) |
| `magic_missile(s)` | Enemy hero, lord, caster or artillery; missile units not near our units | In range (150–300 m) with line of sight | Engaged targets if the projectile explodes (check `friendly_fire`) |
| `vortex` | Dense enemy blobs, missile or artillery lines, chokepoint exits, enemies advancing across open ground | ≥ 3 enemy units within about 40 m of the cast point; **no friendly unit within the vortex radius + 40–60 m of drift** | Anywhere near our lines: vortexes wander randomly ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3806155895391772037)) |
| `wind` (line spells, e.g. Burning Head) | Line along the long axis of an enemy formation; ranged lines; marching columns | Enemy line or column within range, cast parallel to the formation's length | Pathing through our units at any point |
| `bombardment` | Stationary blobs: units on walls, units engaged with each other (enemy vs enemy), enemy gunlines, defending enemies | Target stationary ≥ 3 s; ≥ 2 enemy units within radius. Easy to land on enemies that are on walls or already in combat ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3496509339501484197)) | **Engaged with our units** unless ours are expendable (summons, chaff) and the enemy is elite |
| `explosion` | Clusters near the caster (often caster-centred) | ≥ 2 enemy units within radius, no friends | — |
| `breath` | Short range (about 30–60 m) cone; enemy infantry, especially low armour | Caster is a monster or mounted unit facing the enemy, enemy in the cone, no friends in the cone | Anything engaged with our line in the cone |
| `regeneration` | Our damaged elite, large or single-entity unit, or lord | HP < 60% [E] and (in combat or about to be); best on high-value single entities | Chaff; units at full HP |
| `ward_save` / barrier | Our elite or large unit about to take heavy missile or magic fire, or a lord in a duel | Enemy missile and artillery units targeting it, or a big enemy spell incoming; or our hero engaged with an enemy lord | Casting with no incoming damage |
| `summon_unit` | See 2.12 | Enemy elite charging, or a flank opening to exploit | Summoning far from the action |
| `transform` | The caster itself | When about to enter melee or a duel (when the form is melee) | When the caster should be casting |
| `hiding` | Flankers or ambushers | Before a flank move, when no enemy within 80 m | — |

### 3.3 Spell scoring formula (proposed) [E]
```
value = Σ over affected units u of:
          w_side(u) × unit_value(u) × expected_fraction_affected(u)
  where w_side = +1 for enemy targets of damage/hex, +1 for friendly targets of augments,
                 −2 for friendly units in a damage spell's area (friendly-fire penalty, doubled)
  unit_value(u) = recruitment cost (or 1000 for lord, 600 hero, ...) × (hp_fraction)
  expected_fraction_affected: 0.8 for stationary/engaged targets, 0.4 for moving infantry,
                              0.2 for fast cavalry/flyers (they dodge; AI dodging was improved in 2.3.0
                              per patch notes) ([levelup](https://www.levelup.com/en/news/total-war-warhammer-iii-shares-its-patch-notes-for-update-230/))
score = value / wind_cost ; cast if score > threshold_preset and all hard gates pass
```
Hard gates: in range; target alive and not routing (except to finish a lord); no friendly unit within
`radius + safety` for damage AoE (safety: vortex 60 m, bombardment 20 m, wind 15 m along its path,
breath 10 m); pool ≥ cost + floor.

### 3.4 Friendly-fire avoidance rules (summary)
- Damage spells hit both sides. The common "hit an engaged target" trick also hurts our own units
  ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3496509339501484197)).
- **Vortex:** the minimum clear distance to any friendly unit is the vortex radius plus 60 m [E], and
  the vortex must travel away from us. Some players report that dragging when placing sets the initial
  direction ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3806155895391772037)). A
  script can't drag, so only cast it on targets that are farther from us than from the enemy rear.
- **Bombardment:** only on enemy-only areas, or enemy elite engaged with our cheap units (accept the
  loss).
- **Wind/line spells:** compute the swept line (start → end along the facing) and require no friendly
  unit within 15 m [E] of the line.
- **Missiles and explosive projectiles:** check the db `friendly_fire`/`is_magical` flags if exposed;
  otherwise assume yes for explosive projectiles.

### 3.5 Typical ranges (verify per ability in the db) [E]
| Category | Typical cast range |
|---|---|
| Magic missile | 150–300 m (Fireball 300 m [S]) |
| Direct damage | 150–250 m |
| Hex / augment (single) | 150–300 m |
| Area hex/augment | 150–250 m, effect radius 30–50 m |
| Vortex | 200–300 m cast, radius 15–30 m, drifts 50–150 m over its lifetime |
| Wind | 150–250 m, travels 100–200 m |
| Bombardment | 200–400 m, effect radius 30–50 m, duration 6–15 s |
| Breath | 30–60 m cone |
| Explosion | Often caster-centred, radius 20–40 m |
| Summon | 100–200 m |

---

## 4. Strategic archetypes and presets

Each preset is a set of planner assignments plus parameter overrides. **Groups:** `LINE` (melee
infantry plus anti-large), `RANGED` (ranged infantry), `ART` (artillery), `HAMMER` (shock/melee cavalry,
chariots, fast monsters), `SKIRM` (missile cavalry), `FLY` (flyers), `MON` (non-flying monsters),
`LORD`, `CASTERS`, `DUEL` (melee heroes), `SUMMONS`.

### P1 – Balanced line and flanks (default, hammer and anvil)
- **Works when:** mixed armies, roughly even strength. Fits most factions.
- **Planner:**
  - `LINE`: advance to a position 60–100 m in front of `RANGED`, then `attack_force(enemy_main)` when
    enemy within 150 m.
  - `RANGED`: `defend_position(behind LINE, 40 m)`, fire at will.
  - `ART`: `defend_position(rear high point, 30 m)`.
  - `HAMMER`/`MON`: `move_to_position(flank points)` → cycle-charge FSM after the anvil engages.
  - `FLY`: dive enemy artillery/ranged.
  - `CASTERS`: follow `LINE` centroid −50 m.
  - `LORD`: follow `LINE` centroid −30 m and join the fight only to kill isolated targets.
- **Parameters:** hammer wait 4 s; spell threshold medium.

### P2 – Aggressive rush (all-in)
- **Works when:** we are melee-dominant (Khorne, Beastmen, Ogres, Norsca, Greenskins, VC) or the enemy
  outguns us (gunline or artillery). Khorne prefers getting into melee as soon as possible and staying
  there ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3272436223667796057)).
- **Planner:**
  - All melee groups: `rush_force(enemy_all)` at t=0. Fast units target enemy ranged and artillery
    first (their own `rush_force(enemy_ranged ∪ enemy_art)`).
  - `RANGED`: advance with the line and shoot ranged targets.
  - `CASTERS`: speed and defence augments on the leading units during the advance, then hexes.
- **Parameters:**
  - No hammer wait.
  - Cycle charging off for monsters, on for cavalry and chariots.
  - Spell floor low.
  - Chase routers on.

### P3 – Defensive / hold and shoot (gunline)
- **Works when:** strong ranged and artillery (Empire, Dwarfs, Cathay, Chaos Dwarfs, Skaven gunline,
  High Elves archers), or the enemy has no ranged (VC, Khorne).
- **Planner:**
  - `LINE`: `defend_position(anchor = best high ground, r = 50 m)`, anti-large in front of the gunners.
  - `RANGED`: `defend_position(anchor + 30 m back, r = 40)`.
  - `ART`: `defend_position(anchor + 80 m back)`.
  - `HAMMER`: `defend_force(our flank-end LINE unit, 60 m)` to intercept flankers. Release to
    cycle-charge once ≥ 50% of enemy melee is engaged with `LINE`.
  - `FLY`: guard vs enemy flyers (`defend_force(ART, 80 m)`).
  - `CASTERS`: bombardments and vortexes on the approach; ward save on the line before contact.
- **Parameters:**
  - Hold until the enemy is within 100 m or 40% engaged.
  - If the enemy refuses to advance (has artillery and outranges us) for > 90 s [E], switch to P1.

### P4 – Skirmish / kite
- **Works when:** army of fast ranged units (Wood Elves, Dark Elf missile cav, Kislev horse archers,
  Tzeentch, Skaven jezzails plus screens), against slow enemies. Wood Elves skirmish from multiple
  directions so the AI splits its forces, then pick off units one by one
  ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3825284575362429511)).
- **Planner:**
  - `SKIRM` and fast `RANGED`: manual kite FSM (see 2.4).
  - `LINE` (if any): `defend_position` far back as a fallback anchor.
  - Melee flankers: punish enemy units that split off to chase.
  - Plan two shooting groups 90° apart to create crossfire.
- **Parameters:**
  - Kite distance `0.6 × range` [E].
  - Retreat waypoint toward our anchor.
  - Abort to P1 when ammo across all ranged units is below 25%.

### P5 – Monster mash
- **Works when:** army is mostly monsters (Lizardmen, Ogres, Beastmen, Chaos Dwarfs bull centaurs, Tomb
  Kings constructs, Daemons).
- **Planner:**
  - Monsters advance as a wedge, never single-file: `move_to_force(enemy_main)` together, then each
    monster attacks the highest-scoring non-anti-large target.
  - Cheap infantry (skinks, gnoblars) go ahead as a screen and absorb missile fire.
  - `CASTERS`: regeneration and ward saves on monsters.
- **Parameters:**
  - Monster retreat HP 25%.
  - Anti-large avoidance weight very high.
  - Target enemy artillery first with the fastest monster.

### P6 – Magic-heavy
- **Works when:** 3+ casters (Tzeentch, Lizardmen slann, High Elves, VC, Cathay, Skaven).
- **Planner:**
  - `LINE`: `defend_position` (pin the enemy in place so area spells land).
  - `CASTERS`: cast vortexes and bombardments on approach and on blobs, hexes at contact.
  - Lower the spell threshold; floor 0 after contact.
  - Use summons as tarpits.
- **Parameters:**
  - Hold the line and let the enemy come.
  - Cast rate up to 1 per 1.5 s.
  - Tzeentch casters: let the barrier absorb, then withdraw
    ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3272436223667796057)).

### P7 – Artillery castle
- **Works when:** 4+ artillery (Dwarfs, Empire, Chaos Dwarfs, Skaven).
- **Planner:**
  - Like P3, but with a horseshoe of infantry around the artillery, about 60 m out.
  - Artillery targets blobs and enemy artillery.
  - `HAMMER`: only guard.
  - Flyers: hunt enemy flyers diving our artillery.
- **Parameters:**
  - Strongest `defend_position` (radius 30 m).
  - Never advance unless the enemy also sits still for > 120 s.

### P8 – Cavalry hammer
- **Works when:** 4+ shock cavalry or chariots (Bretonnia, Kislev, Chaos knights, Empire knights, Dark
  Elf cold one knights).
- **Planner:**
  - Small `LINE`: `defend_position` in the centre.
  - Cavalry split into 2 wings, each running the cycle-charge FSM against flanks and the rear.
  - Priority: enemy ranged and artillery first, then engaged infantry from behind.
- **Parameters:**
  - `T_contact` 8 s.
  - Disengage 70 m.
  - Spear avoidance on.

### P9 – Swarm
- **Works when:** many cheap units (Skaven, Greenskins, VC zombies, Nurgle, Kislev peasants).
- **Planner:**
  - `rush_force` to engage everything everywhere and wrap around the enemy line: assign each extra unit
    to an enemy flank or rear.
  - Use chaff as tarpits for elites.
  - Artillery and casters target the stationary engagement (accept friendly fire on chaff only).
- **Parameters:**
  - Skaven trick: let fodder bunch the enemy up, then nuke the blob
    ([Steam](https://steamcommunity.com/app/1142710/discussions/0/6690735450901051218)).
  - Friendly-fire tolerance high for units below a value threshold.

### P10 – Assassinate (optional)
- **Works when:** the enemy relies on a single strong lord, or the enemy outnumbers us.
- **Planner:**
  - `LINE` holds.
  - `DUEL` heroes, flyers and cavalry `attack` the enemy lord.
  - Casters cast hexes and magic missiles on the enemy lord.
  - Retreat duelists below 40% HP.

---

## 5. Faction notes (only where they materially change tactics)

| Faction | What changes |
|---|---|
| **Empire** | Strong gunlines and artillery (handgunners flat fire, mortars, cannons, Helblaster). Default P3/P7. Knights work as a cavalry hammer (P8). |
| **Dwarfs** | No cavalry (gyrocopters are the fast flankers). Slow but tough. Default P3/P7: hold, shoot, let them come. Use gyrobombers to dive artillery ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3820783808437734105)). |
| **Chaos Dwarfs** | Strong artillery (Dreadquake: low ammo, can't target ground manually, weak vs single entities). Infernal Guard anvil plus bull centaur hammer ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3820783808437734105)). Default P7/P1. Note: enemy CD mortars → spread out and close fast. |
| **Skaven** | Weapon teams and artillery plus cheap slaves. Friendly fire is acceptable on chaff. Fodder pins the enemy so the nukes land. Vermintide summons as roadblocks ([Steam](https://steamcommunity.com/app/1142710/discussions/0/6690735450901051218)). P9/P7. |
| **Vampire Counts** | No ranged. Magic, flyers and summons do the ranged work; fodder never routs. Fly-dive enemy artillery first ([Steam](https://steamcommunity.com/app/1142710/discussions/0/4521136490642404774)). P2/P6/P9. |
| **Tomb Kings** | Unbreakable undead, constructs as monsters, some ranged. Like VC but with archers and artillery. |
| **Wood Elves** | Kite and skirmish, multi-direction ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3825284575362429511)). Forests are their ally. P4. Hawk Riders were nerfed vs small units (homing now hits a single model) ([Steam](https://steamcommunity.com/app/1142710/discussions/0/4130430927303114881)). |
| **High/Dark Elves** | High-quality archers plus flankers; Dark Elves have strong melee infantry and cold one knights. P1/P3/P8. |
| **Ogre Kingdoms** | High-mass infantry chargers. Cycle-charge even the infantry (bulls, ironguts), and rear-charge. Leadbelchers and Ironblasters are strong ranged/artillery. Tie up the enemy with gnoblars and outflank ([Steam](https://steamcommunity.com/app/1142710/discussions/0/4339851480062715557)). P2/P5. |
| **Khorne** | Melee only, few ranged. Rush and stay engaged. Cycle-charge with hounds and cavalry to overload flanks. Assassinate heroes and lords ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3272436223667796057)). P2/P10. |
| **Tzeentch** | Magic, barrier (ward), flyers and missile units. Barrier units dive, then withdraw once the barrier is spent ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3272436223667796057)). P4/P6. |
| **Nurgle** | Slow, durable, regenerating units and summons. Hold or grind. P1/P9. |
| **Slaanesh** | Very fast, fragile, flanking- and charge-oriented. P8/P2. |
| **Lizardmen** | Monster mash plus skink screens; casters (Slann). P5/P6. |
| **Cathay** | **Harmony:** Yin and Yang units buff each other when near each other. Archers (Yang) behind melee (Yin), so keep ranged within buff range of the line (don't let them spread out) ([Steam](https://steamcommunity.com/app/1142710/discussions/0/3814034217019113256)). P3/P1. |
| **Kislev** | Horse archers plus heavy cavalry; ice magic. P4/P8. |
| **Bretonnia** | Knight cavalry hammer, cheap peasant anvil. P8. |
| **Greenskins/Beastmen/Norsca** | Melee-heavy, aggressive, monsters. P2/P5/P9. |
| **Daemons of Chaos / Daemon Prince** | Mix. Pick by army composition (see 7.5 composition auto-pick). |

---

## 6. Known vanilla battle-AI mistakes (compensate for or exploit)

| Mistake | Source | Compensation in our script |
|---|---|---|
| Ranged units **stutter-step** into melee or go idle with a clear shot | [Steam](https://steamcommunity.com/app/1142710/discussions/0/596268777261239940) | Static `defend_position` for ranged; re-target only every ≥ 8 s; guard mode; check `is_firing`/idle and re-issue an attack on a valid target after 5 s idle. |
| Ranged target selection: tries targets it can't hit (blocked, out of range) | [Steam](https://steamcommunity.com/app/1142710/discussions/0/596268777261239940) | Pre-filter targets by range and line of sight (height check); fallback order. |
| **Lords and monster lords charge ahead alone** and die (e.g. Bloodthirsters) | [Steam](https://steamcommunity.com/app/1142710/discussions/0/596268777261239940) | Lord leash: never more than 40 m ahead of the line centroid before contact; retreat at HP < 40%. |
| Cavalry suiciding into braced spears from the front | [TW Academy](https://academy.totalwar.com/battle-basic-tactics/) | Penalty in target scoring; check the target's facing (front 120°). |
| The AI breaks formation before taking a charge (doesn't brace) | [Steam](https://steamcommunity.com/app/1142710/discussions/0/3827536762635287125) | Freeze anti-large units when enemy large units < 80 m. Exploit it: the enemy line will be un-braced. |
| The AI chases single-entity flyers or fast units with its own flyers and lord | [Steam](https://steamcommunity.com/app/1142710/discussions/0/3880472899724744261) | Exploit: a bait flyer drags enemy units away. Don't let our units chase baits: chase only within 150 m of our main body. |
| Poor or late spell use, blowing winds on low-value targets | [Steam](https://steamcommunity.com/app/1142710/discussions/0/3496509339501484197) | Value/cost scoring and pool floor (section 3). |
| AI dodges spells and artillery (improved in 2.3.0) | [levelup](https://www.levelup.com/en/news/total-war-warhammer-iii-shares-its-patch-notes-for-update-230/) | Prefer stationary or engaged targets for slow spells; lower the expected hit for moving targets. |
| Reinforcements: the AI used to idle until all arrived; now attacks earlier (6.0.5) | [gamewatcher 6.0.5](https://www.gamewatcher.com/total-war-warhammer-3-patch-notes-hotfix-6-0-5) | Check reinforcement arrival; send a fast unit to the reinforcement edge to delay them. |
| Siege AI: units respond poorly in settlement battles (improved in 3.0, still weak) | [NME 3.0](https://www.nme.com/news/total-war-warhammer-3-reveals-stacked-update-3-0-patch-notes-3429808) | For sieges, our script should fall back to the vanilla planner or a simple `attack_force` on the defenders; don't run cinematic micro. |
| Ranged units clumping and getting stuck when repositioned in different directions (fixed in 6.0.x) | [gamewatcher 6.0.5](https://www.gamewatcher.com/total-war-warhammer-3-patch-notes-hotfix-6-0-5) | Give each ranged unit its own `defend_position` with a slight offset, not one shared point. |
| Chokepoint: the AI now rushes through under fire (5.2.5) | [gamewatcher 5.2.5](https://www.gamewatcher.com/news/total-war-warhammer-3-patch-notes-2024-v5-2-5-patch-released) | Put vortexes and bombardments at the exit of the choke. |

---

## 7. Target-priority tables (scoring heuristics)

**Generic scoring** for unit `u` attacking enemy `e` [E]:
```
score(u,e) = base[role(u)][class(e)]
           + 40 × (1 - hp_frac(e))                   ; finish wounded targets
           + 30 if e.is_in_melee with a friendly      ; pinned target (hammer/hex)
           + 50 if e is attacked from flank/rear by u's approach (angle > 60° from e's facing)
           + 20 if e.is_wavering
           - 999 if e.is_routing and role(u) not in {HAMMER, FLY, SKIRM}   ; let fast units chase
           - 150 if class(e)=anti_large and u is large and approach angle < 60° (frontal)
           - dist(u,e) / 5                            ; prefer close (per metre)
           - 60 × n_enemy_ranged_in_range_of_e        ; flyers/monsters avoid escorted targets
```

**Base table** (`base[attacker role][target class]`) [E]:

| Attacker ↓ / Target → | Artillery | Ranged inf | Missile cav | Caster hero/lord | Duelist hero/lord | Inf (non-AL) | Anti-large inf | Cavalry | Chariot | Monster | Flyer |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Line infantry | 60 | 70 | 20 | 50 | 30 | **80** | 70 | 30 | 30 | 20 | 10 |
| Anti-large inf | 50 | 50 | 40 | 40 | 50 | 40 | 40 | **90** | **90** | **100** | 60 |
| Shock/melee cav | **100** | **95** | 50 | 80 | 30 | 60 (rear) | −100 (front) | 40 | 40 | −50 | 10 |
| Missile cav | 70 | **90** | 60 | 80 | 40 | 50 | 60 | 40 | 40 | 30 | 30 |
| Ranged inf | 70 | **90** | 50 | 85 | 60 | 60 | 60 | 70 | 60 | 50 (AP) / 20 | 50 |
| Artillery | **90** | 80 | 20 | 70 | 50 | 60 (blob +40) | 60 | 30 | 30 | 70 (direct fire) | 10 |
| Monster | 80 | 80 | 40 | 60 | 40 | **90** | −80 | 50 | 50 | 50 | 20 |
| Flyer | **100** | **95** | 50 | 90 | 20 | 30 | −100 | 10 | 20 | 10 | 40 (anti-air) |
| Chariot | 70 | 90 | 30 | 50 | 20 | **90** (flank) | −150 | 20 | 20 | −80 | 0 |
| Duelist hero/lord | 50 | 60 | 30 | **100** | **90** | 40 | 40 (if AL hero +50) | 40 | 40 | 60 (if AL) | 30 |
| Caster (spell target) | 60 | 70 | 20 | **100** | 80 | 40 (blob +60) | 40 | 30 | 30 | 70 | 20 |

---

## 8. Implementation cheatsheet

### 8.1 Tick loop (recommended cadence)
```
every 1.0 s : update caches (positions, hp, in_melee, routing, ammo, winds pool)
every 2.0 s : per-unit FSM step (cycle charge, kite, retreat, leash)
every 2.5 s : spell picker (at most 1 cast globally per 2-3 s; preset may lower)
every 8.0 s : re-target ranged/artillery (only if current target invalid)
every 5.0 s : planner-level phase check (DEPLOY → ADVANCE → ENGAGE → EXPLOIT → MOP-UP)
```
Never re-issue an identical order to a unit already executing it; that resets animations and forms.

### 8.2 Battle phases
| Phase | Enter when | Behaviour |
|---|---|---|
| DEPLOY/HOLD | t=0 | Form line; flankers to flank points; ranged and artillery positioned |
| ADVANCE | preset is aggressive, or enemy static > 60–90 s | Line walks forward as a group |
| ENGAGE | ≥ 1 of our line units in melee | Hammer release after 3–5 s; spells unlocked; ranged switch to unengaged targets |
| EXPLOIT | ≥ 30% of enemy units wavering/routing, or enemy lord dead | Push wavering units; fast units chase routers within 150 m of the main body |
| MOP-UP | enemy < 15% strength | Everyone `attack_force` closest; stop expensive spells |

### 8.3 Hard rules (all presets)
1. **Lord leash:**
   - Before contact the lord stays ≤ 40 m ahead of the line centroid; prefer 30 m behind.
   - Retreat at HP < 40%; re-engage at > 60% (only if healing is available).
2. **Caster leash:** 40–80 m behind the line, inside the key spell range. Never voluntarily in melee.
3. **Anti-large freeze:** when enemy large units are within 80 m and closing, stop issuing move orders
   to anti-large units (brace).
4. **No frontal spear charges:** for cavalry, chariots and monsters, skip any target whose class is
   anti-large and whose facing is within ±60° of the approach vector.
5. **Hammer gate:** flank/rear charges only once the target is engaged ≥ 3 s (aggressive presets 0 s).
6. **Cycle charge:** `T_contact` cavalry 8–12 s, chariots 2–4 s, flying cavalry 10–15 s; disengage
   60–90 m; reform until ≥ 50 m away; retreat at HP < 35%.
7. **Ranged stability:** fixed positions; re-target ≥ 8 s; never fire at a target with any friendly unit
   within 15 m (flat-trajectory) or 25 m (explosive/artillery); arc units may fire on engaged targets
   only if the target is large.
8. **Fall back:** ranged units retreat 40–60 m toward the line if an enemy melee unit is within 40 m and
   no friendly melee unit is closer than 20 m to them.
9. **Router chase:** only fast units; only if no unrouted enemy within 100 m of the chaser; and within
   150 m of our main body.
10. **Spell gates:**
    - pool ≥ cost + floor; target in range.
    - Clearance: no friendly unit within radius + safety (vortex +60 m, bombardment +20 m,
      wind path 15 m, breath cone +10 m).
    - Prefer targets stationary ≥ 2 s.
11. **Ammo:** at < 10% ammo, convert ranged units to reserve or melee role.
12. **Sieges:** fall back to simple planner behaviour (attack or defend); disable fancy micro.

### 8.4 Preset definitions (data)
```lua
PRESETS = {
  balanced  = { line="advance_then_attack", ranged="hold_behind_line", art="hold_rear_high",
                hammer="flank_cycle", fly="dive_backline", lord="behind_line",
                hammer_wait_s=4, spell_threshold=1.0, spell_floor="emergency", cast_gap_s=2.5,
                chase_routers=true, kite=false },
  rush      = { line="rush_all", ranged="advance_shoot_ranged", art="hold_rear",
                hammer="dive_ranged_then_cycle", fly="dive_backline", lord="with_line",
                hammer_wait_s=0, spell_threshold=0.8, spell_floor=0, cast_gap_s=2.0,
                chase_routers=true },
  gunline   = { line="hold_high_ground", ranged="hold", art="hold_rear_high",
                hammer="guard_flanks_then_cycle", fly="guard_artillery", lord="behind_line",
                hold_until_enemy_m=100, release_engaged_frac=0.5, refuse_timeout_s=90,
                spell_threshold=1.0, spell_floor="emergency" },
  skirmish  = { line="hold_far_anchor", ranged="kite", skirm="kite", art="hold_rear",
                hammer="punish_chasers", fly="dive_backline", kite_frac=0.6,
                abort_ammo_frac=0.25, abort_to="balanced" },
  monsters  = { line="screen_ahead", mon="wedge_advance_then_best_target", hammer="flank_cycle",
                monster_retreat_hp=0.25, anti_large_penalty=-300, regen_priority="monsters" },
  magic     = { line="hold", ranged="hold", casters="aggressive_cast",
                spell_threshold=0.6, spell_floor=0, cast_gap_s=1.5, summon_mode="tarpit" },
  artillery = { line="horseshoe_around_art", art="blobs_and_counterbattery", hammer="guard",
                fly="hunt_enemy_flyers", defend_radius=30, advance_after_static_s=120 },
  cavalry   = { line="hold_centre", hammer="two_wing_cycle", t_contact_s=8, disengage_m=70,
                priority={"art","ranged","engaged_inf_rear"} },
  swarm     = { line="rush_wrap_flanks", art="hit_stationary_engagements",
                friendly_fire_value_cap=500, summon_mode="tarpit" },
  assassinate = { line="hold", duel="hunt_enemy_lord", casters="hex_missile_enemy_lord",
                  fly="hunt_enemy_lord", duel_retreat_hp=0.4 },
}
```

### 8.5 Auto-pick preset (optional "Auto" button) [E]
```
ranged_share  = cost of ranged+artillery / army cost
monster_share = cost of monsters / army cost
cav_share     = cost of cavalry+chariots / army cost
caster_count  = number of units with ≥ 2 damaging spells

if   art_count >= 4                                   -> artillery
elif ranged_share >= 0.45 and enemy_ranged_share < 0.25 -> gunline
elif cav_share >= 0.35                                -> cavalry
elif monster_share >= 0.40                            -> monsters
elif caster_count >= 3                                -> magic
elif ranged_share >= 0.45 and avg_ranged_speed high   -> skirmish
elif our_strength < 0.7 * enemy_strength              -> gunline (hold) ; or assassinate if enemy lord is isolated
elif ranged_share < 0.10 and enemy_ranged_share > 0.30 -> rush
elif unit_count >= 18 and avg_unit_cost low           -> swarm
else                                                  -> balanced
```

### 8.6 Spell picker (pseudo)
```
for caster in casters_ready:
  for ab in caster.abilities where ready and pool >= ab.cost + floor:
    targets = candidates_by_category(ab.category)   -- see table 3.2
    for t in targets: if gates_pass(ab, t) then s = value(ab,t)/ab.cost ; keep best
pick global best; if best.s > preset.spell_threshold and now - last_cast >= cast_gap_s:
  uc:perform_special_ability(best.ab.key, best.target_unit)   -- or position variant if exposed
  last_cast = now ; notify camera (spell event shot)
```
Category → candidate generator:
- `augment`, `regeneration`, `ward_save`, `transform`: friendly units, ranked by `value × in_melee ×
  (1 − hp_frac for regen)`.
- `area_of_augments`: centroid of friendly melee clusters.
- `hex`, `direct_damage`, `magic_missile`: enemy units ranked per the caster row of the table in section 7.
- `area_of_hexes`, `vortex`, `bombardment`, `explosion`: enemy clusters (≥ 2–3 units within 40 m),
  passing the friendly clearance check.
- `wind`, `breath`: enemy units in a line or cone from the caster, with path clearance.
- `summon_unit`: points behind engaged enemies, or in front of enemy chargers.

### 8.7 Camera-friendly notes
- Cycle charges, rear charges, spell casts, lord duels and routs are the best "moments". Emit an event
  from each FSM transition (CHARGE, IMPACT, CAST, ROUT) so the director can cut to it.
- Space out spells (`cast_gap_s`) and stagger the hammer wings by 2–4 s so the camera can cover both.

---

## Sources

- TW Academy – Battle: Basic Tactics: https://academy.totalwar.com/battle-basic-tactics/
- Steam: lock formation and group micro advice: https://steamcommunity.com/app/1142710/discussions/0/4416425392682933578
- Steam: cycle charge micro, shock cavalry ~10 s, chariots: https://steamcommunity.com/app/1142710/discussions/0/3809535864679012912
- Steam: chariot Khorne army discussion: https://steamcommunity.com/app/1142710/discussions/0/6554498588628181472
- Steam (WH2): charge bonus 13 s, bracing +20% MD, mass: https://steamcommunity.com/app/594570/discussions/0/3175526477755400640
- Steam: anti-large / mass 4000 / charge reflect discussion: https://steamcommunity.com/app/1142710/discussions/0/4339851902698051173
- Steam (WH1): shields 120° arc and block formula: https://steamcommunity.com/app/364360/discussions/0/350532795331336157
- Steam: friendly fire into melee: https://steamcommunity.com/app/1142710/discussions/0/3948028800072759169
- Steam: leadership modifiers (general nearby/wounded/died): https://steamcommunity.com/app/1142710/discussions/0/3365901931426620282
- Steam: multiple leadership modifiers cause routs: https://steamcommunity.com/app/1142710/discussions/0/3832045766778568866
- Steam (WH2): lord death leadership penalty: https://steamcommunity.com/app/594570/discussions/0/1771511442687123095
- Steam workshop: vanilla exhausted fatigue multipliers: https://steamcommunity.com/workshop/filedetails/discussion/3308073985/612032174956240488
- Steam: ranged stutter-step, idle units, lords charging alone: https://steamcommunity.com/app/1142710/discussions/0/596268777261239940
- Steam: AI breaks formation before charges: https://steamcommunity.com/app/1142710/discussions/0/3827536762635287125
- Steam: AI chasing flyers / bait: https://steamcommunity.com/app/1142710/discussions/0/3880472899724744261
- Steam: magic pool / spell types easy to land / bombardments on engaged: https://steamcommunity.com/app/1142710/discussions/0/3496509339501484197
- Steam: vortex random movement: https://steamcommunity.com/app/1142710/discussions/0/3806155895391772037
- Steam: spell costs 4–16: https://steamcommunity.com/app/1142710/discussions/0/3826415019288347326
- Steam mod changelog (Fireball cost 5, CD 29, 300 m): https://steamcommunity.com/sharedfiles/filedetails/changelog/2856313886?p=7
- ludo.guide magic overview: https://www.ludo.guide/guide/total-war-warhammer-3/effective-use-of-magic-spells
- Official "Magic in TW:WH3": https://totalwar.com/?p=15964
- Steam: flyers vs artillery/ranged: https://steamcommunity.com/app/1142710/discussions/0/3775742435234834844
- Steam: Dreadquake, gyrobombers, Chaos Dwarf tactics: https://steamcommunity.com/app/1142710/discussions/0/3820783808437734105
- Steam: Vampire Counts tactics: https://steamcommunity.com/app/1142710/discussions/0/4521136490642404774
- Steam: Wood Elves skirmish: https://steamcommunity.com/app/1142710/discussions/0/3825284575362429511
- Steam: Hawk Riders homing change: https://steamcommunity.com/app/1142710/discussions/0/4130430927303114881
- Steam: Ogre tactics: https://steamcommunity.com/app/1142710/discussions/0/4339851480062715557
- Steam: Khorne/Tzeentch tactics: https://steamcommunity.com/app/1142710/discussions/0/3272436223667796057
- Steam: Skaven weapon-team tactics: https://steamcommunity.com/app/1142710/discussions/0/6690735450901051218
- Steam: Cathay harmony in battle: https://steamcommunity.com/app/1142710/discussions/0/3814034217019113256
- Patch 2.3.0 (AI dodging): https://www.levelup.com/en/news/total-war-warhammer-iii-shares-its-patch-notes-for-update-230/
- Patch 3.0 (siege AI): https://www.nme.com/news/total-war-warhammer-3-reveals-stacked-update-3-0-patch-notes-3429808
- Patch 5.2.5 (chokepoint, skirmish AI): https://www.gamewatcher.com/news/total-war-warhammer-3-patch-notes-2024-v5-2-5-patch-released
- Hotfix 6.0.5 (reinforcement AI, ranged clumping): https://www.gamewatcher.com/total-war-warhammer-3-patch-notes-hotfix-6-0-5
- Patch 7.0 overview: https://www.gamewatcher.com/total-war-warhammer-3-patch-7-0-release-date-latest-news
- Patch 7.0 flying/mass summary (low confidence): https://www.dtgre.com/2025/12/total-war-warhammer-3-update-7-0-air-combat-dragon-overhaul-guide.html
- Patch 8.1 (campaign AI, July 2026): https://www.pcgamesn.com/total-war-warhammer-3/patch-notes-8-1-campaign-ai

Note: the totalwarwarhammer.fandom.com wiki returned HTTP 402 to automated fetches during research, so
wiki numbers couldn't be cross-checked. Treat all [E] and [C] numbers as starting points and verify
against db tables in the current game version.
