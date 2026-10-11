# Unicorn Overlord "Tactics": a reference for a player-configurable WH3 battle AI

This document explains how the Tactics system in *Unicorn Overlord* (Vanillaware / Atlus, March 2024)
works. It compares the system with FFXII Gambits and Dragon Age: Origins tactics. It then proposes a
rule format, default rule sets and a UI for the `cinematic_director` mod. The real-time unit rules
that the actions should carry out are in [battle_tactics.md](battle_tactics.md).

**Confidence tags**

| Tag | Meaning |
|-----|---------|
| **[S]** | A cited source states it (official text, wiki or guide). |
| **[T]** | Community testing (wiki write-ups or player experiments), not official. |
| **[U]** | Uncertain: sources disagree, I translated it, or I am recalling it without a source. |
| **[D]** | A design proposal for this mod, not a fact about Unicorn Overlord. |

**Translation note.** The fullest condition catalogue I could reach is on the Japanese community
database wiki (wikiwiki.jp/uol_db). The English-language wikis (Fextralife, Fandom, GameFAQs, Reddit)
were unreachable or very thin from this environment. The English condition names in §2 are therefore
my translations. They may differ slightly from the in-game English text **[U]**, but the meaning of
each condition is reliable.

---

## 0. TL;DR

- Each character has an **ordered list of skill rows**. Each row has one skill and up to **two
  conditions**. On its turn a character walks the list from the top and uses the **first row whose
  conditions find a valid target** and that it can pay for (AP). If no active row qualifies, it does
  nothing that turn [S][T].
- Every condition is one of two kinds [T]:
  - **Limit** (filter, 限定): removes candidates, or blocks the row entirely ("Own HP ≤ 50%",
    "Back row enemy", "Cavalry enemy"). A limit can fail, which makes the row fall through to the
    next one.
  - **Prioritize** (sort, 優先): reorders candidates ("Prioritize cavalry", "Lowest HP"). A
    prioritize condition never fails, so a row with only prioritize conditions **always fires**. It
    blocks every row below it.
- The pipeline is: default target order (nearest front-row target first), then **Condition 1**, then
  **Condition 2**, then pick the top candidate. Two limits act as **AND**. If both conditions are
  sorts, **Condition 2 wins** (it is the primary key), which surprises most players [T].
- There is **no OR** inside a row. You get OR by adding the same skill again as another row with a
  different condition [T].
- **Passives** (PP, blue) are reactions such as guard, cover, counter, or a buff at battle start.
  They have built-in triggers. Conditions only narrow when they fire [S][T].
- Beginner help comes from three things. Every skill has a **default condition**. There is a
  one-button **Optimize** for tactics and equipment. There is a **battle preview** with an
  "Organize" shortcut, so you can fix tactics right before a fight and watch the predicted damage
  change [S].
- **Fit for our mod:** the filter → sort → first-match pipeline maps almost one-to-one onto WH3 group
  orders. The big differences are that WH3 is real-time (we need re-evaluation ticks, commitment
  timers and hysteresis) and target-sharing (we need per-target caps). The cinematic camera also
  hates jitter. Our existing panel presets should become **named rule templates**. Full editing
  should happen in a config file outside battle.

---

## 1. How Tactics work

### 1.1 The battle model that Tactics run in

- A squad holds up to 5 characters in a front row and a back row, each with up to 3 slots. An army
  deploys up to 10 squads. Squads move in real time on the map. When two hostile squads touch, an
  **automatic, turn-based skirmish** plays out [S]
  ([Fandom: Battle Stages](https://unicornoverlord.fandom.com/wiki/Battle_Stages)).
- In a skirmish, combatants act in **Initiative order**. On its turn a character uses one **Active
  skill**, which costs **AP** (red gems). The skirmish ends when both sides run out of AP or one side
  is wiped out [S]
  ([Gematsu, official details](https://gematsu.com/2024/02/unicorn-overlord-details-more-characters-battle-stages-skills-and-tactics)).
- **Passive skills** cost **PP** (blue gems). They fire automatically in response to events, such as
  being attacked, an ally being attacked, or the start of battle [S] (same source).
- The player controls nothing during a skirmish. The result is decided by squad composition,
  equipment and Tactics [S]
  ([FullCleared review](https://fullcleared.com/reviews/unicorn-overlord-review/)). The developers
  chose this at the planning stage. Preparation and composition were meant to be the strategy
  [S] ([OneMoreGame interview](https://onemoregame.ph/2024/04/vanillaware-interview-unicorn-overlord/)).
- **Relevance to us:** Tactics govern the *micro* layer only, meaning what each character does inside
  a skirmish. The *macro* layer (where squads go) stays under manual real-time control. In our mod
  the panel presets are roughly the macro layer and rules are the micro layer. Both are scripted.

### 1.2 The tactics list (Active skills)

- Each character has a **priority-ordered list of rows**. A row is [Skill] [Condition 1]
  [Condition 2], and each row can be switched On or Off. The editor menu offers: Edit, Set Tactic,
  Tactics Template, Remove, Optimize, On/Off [S]
  ([TheGamer guide](https://www.thegamer.com/unicorn-overlord-tactics-complete-guide/)).
- **Evaluation:** on each of its turns, the character checks row 1 first. If row 1 cannot be used, it
  moves down the list. It uses the highest-priority row whose conditions are met [S]
  ([TheGamer](https://www.thegamer.com/unicorn-overlord-tactics-complete-guide/);
  [AppMedia (JP)](https://appmedia.jp/?p=77500972)).
- **A row "cannot be used"** when any of these is true [T]:
  - A limit condition has no valid target.
  - A self-condition (own HP, own AP, Nth action, enemy contains cavalry, ...) is false.
  - The character lacks the AP for the skill.
- **If nothing matches:** the character skips its turn [S]
  ([TheGamer](https://www.thegamer.com/unicorn-overlord-tactics-complete-guide/)). Guides therefore
  recommend ending every list with an **unconditional fallback** row [S].
- **The list is evaluated again on every turn.** There is no memory or commitment between turns,
  except what the conditions themselves read. Examples are the "1st action … 5th action" conditions
  and AP/PP counts [T].
- **The classic trap:** an unconditional row, or a row with only "Prioritize X" conditions, is always
  satisfied. Nothing below it will ever run [S]
  ([Tobold's blog](https://tobolds.blogspot.com/2024/07/unicorn-overlord-tips.html?m=1);
  [AppMedia](https://appmedia.jp/?p=77500972)). The standard advice is to put the narrowest, most
  conditional rows at the top and the broad ones at the bottom [S]
  ([RPG Site, official preview](https://www.rpgsite.net/news/15481-unicorn-overlord-highlights-tactics-priority-and-battle-stages-along-with-several-new-non-human-allies)).
- **OR logic:** add the same skill twice. For example, row 1 is *Sharp Edge — Scout enemy* and row 2
  is *Sharp Edge — Flying enemy* [T]
  ([uol_db wiki: 作戦について](https://wikiwiki.jp/uol_db/%E4%BD%9C%E6%88%A6%E3%81%AB%E3%81%A4%E3%81%84%E3%81%A6)).

### 1.3 The two-condition structure: limit vs prioritize, and order

This is the most important and least obvious mechanic. The uol_db wiki derives the algorithm below
from testing [T]
([uol_db: 作戦について](https://wikiwiki.jp/uol_db/%E4%BD%9C%E6%88%A6%E3%81%AB%E3%81%A4%E3%81%84%E3%81%A6)):

1. **Build the default candidate list.** The closest front-row target comes first, then the others in
   order of distance.
   - Some skills use a fixed order instead: front row far → mid → near, then back row far → mid →
     near.
   - Melee attacks can only target the front row while it has anyone in it. Back-row enemies are
     dropped from the list.
2. **Apply Condition 1.**
   - A *limit* condition removes everyone who does not match.
   - A *prioritize* condition stable-sorts matching candidates to the top.
3. **Apply Condition 2** in the same way.
4. **Fire at the top candidate.**
   - If the list is empty, the row is skipped and evaluation continues with the next row.
   - Multi-target skills take candidates from the top of the list.

Consequences:

- **Two limits act as AND.** "Scout enemy" + "Flying enemy" never fires, because no unit is both [T].
- **Two prioritize conditions: Condition 2 is the primary key** and Condition 1 is the tie-break
  [T]. A player test with Chloe's Long Thrust showed this. With C1 = *Prioritize cavalry* and
  C2 = *Lowest HP*, she ignored the cavalry and hit the lowest-HP enemy. With the conditions swapped,
  she hit the cavalry [T] (user test in the comments of
  [AppMedia](https://appmedia.jp/?p=77500972)). Rule of thumb: **put the preference you care about
  most in Condition 2.**
- **Uncertain:** some English guides say condition order is random
  ([Prima Games](https://primagames.com/gaming/unicorn-overlord-tactics-and-conditions-explained)) or
  that Condition 2 is a fallback when Condition 1 fails
  ([Game8](https://game8.co/games/Unicorn-Overlord/archives/447561)). Both claims contradict the
  tested sort/filter model above, which I consider more reliable [U].
- **The words matter:** "Back row" (limit) means *only* the back row. "Prioritize back row" (sort)
  means the back row if anyone is there, otherwise anyone [S]
  ([TheGamer](https://www.thegamer.com/unicorn-overlord-tactics-complete-guide/);
  [GameFAQs thread](https://gamefaqs.gamespot.com/boards/426397-unicorn-overlord/80757827)).
- **Self/global conditions** gate the whole row and do not touch the list. Examples are own HP, own
  AP/PP, number of enemies, enemy contains cavalry, daytime and Nth action. A single row can mix a
  gate with a target sort, for example *Own HP ≤ 50%* + *Lowest HP ally*.
- The wiki notes that some multi-row and column attack skills appear to use special target selection
  that the community has not fully worked out [T][U].

### 1.4 Passive skills and PP

- Each passive has a **built-in trigger** written into the skill, for example "when an ally is
  attacked", "after an ally acts", "at the start of battle" or "when attacked by a physical attack".
  A passive fires on its trigger even with no conditions set. Conditions only **narrow** when it
  fires [S] ([AppMedia](https://appmedia.jp/?p=77500972)).
- PP is scarce, especially early in the game. Conditions keep it from being wasted. Examples:
  - Only cover allies whose HP is low.
  - Only self-buff when your own HP is low.
  - Only cover **back-row** allies. Unconditioned cover skills also trigger for sturdy front-liners
    [S] ([AppMedia](https://appmedia.jp/?p=77500972)).
- **"No simultaneous activation" trait:** some passives (cover/guard types, and some buffs/debuffs)
  will not fire twice for the same event when two squad members both have them. This prevents wasted
  PP. The downside is that same-type buffs or debuffs cannot stack [S]
  ([AppMedia](https://appmedia.jp/?p=77500972)). FFXII's "no redundant actions" rule (§4.1) is the
  same idea: built-in de-duplication.
- Passive-specific conditions include "when physically attacked", "when magically attacked", "when
  hit by a row/column/all attack" and "when attacked by cavalry/flying/…" (see §2.H) [T].

### 1.5 Default behaviour

- Every skill comes with a **default condition** that fits the skill. Examples [S]
  ([Fandom: List of Tactics](https://unicornoverlord.fandom.com/wiki/List_of_Tactics)):
  - *Heal*: "Target HP under 75%".
  - *Slice*: "Enemy with the lowest HP".
  - *Holy Light*: "Prioritize armored".
- Default offensive tactics usually just hit the **front row**. Guides say this is the first thing to
  change when the enemy keeps healers in its back row [S]
  ([RPG Site](https://www.rpgsite.net/news/15481-unicorn-overlord-highlights-tactics-priority-and-battle-stages-along-with-several-new-non-human-allies)).

---

## 2. Condition catalogue (near-complete)

Source: [uol_db wiki: 作戦について, 条件一覧](https://wikiwiki.jp/uol_db/%E4%BD%9C%E6%88%A6%E3%81%AB%E3%81%A4%E3%81%84%E3%81%A6)
(last modified 2025-08-02). The English names are my translations [U]. **L** = limit (filter or
gate). **P** = prioritize (sort). "[enemy/ally]" means the condition exists in both forms: the enemy
form for attack and debuff skills, the ally form for support skills. I found about 230 condition
variants in total.

### A. Formation / situation (隊列・状況)
| Condition | Type |
|---|---|
| Prioritize front-row [enemy/ally] | P |
| Prioritize back-row [enemy/ally] | P |
| Front-row [enemy/ally] | L |
| Back-row [enemy/ally] | L |
| [enemy/ally] lined up front and back (a column with two in it) | L |
| [enemy/ally] in the row with the most units | P |
| [enemy/ally] in the row with the fewest units | P |
| [enemy/ally] in a row with ≥ 2 units | L |
| [enemy/ally] in a row with ≥ 3 units | L |
| Daytime | L |
| Night | L |

### B. Class type (兵種)
Types: Infantry, Cavalry, Flying, Armored (heavy), Scout, Archer, Caster, Elf, Bestral (beastfolk),
Angel / winged (有翼人) **[U on the English race names]**.

| Condition | Type |
|---|---|
| Prioritize ⟨type⟩ [enemy/ally] (10 variants) | P |
| ⟨type⟩ [enemy/ally] (10 variants) | L |

### C. HP
| Condition | Type |
|---|---|
| Highest HP / Lowest HP [enemy/ally] | P |
| Highest HP% / Lowest HP% [enemy/ally] | P |
| [enemy/ally] with HP ≤ 25 / 50 / 75 % | L |
| [enemy/ally] with HP ≥ 25 / 50 / 75 / 100 % | L |
| [enemy/ally] with HP < 100 % | L |
| [enemy/ally] **average** HP ≤ 25 / 50 / 75 % | L (group gate) |
| [enemy/ally] average HP ≥ 25 / 50 / 75 / 100 %, or < 100 % | L (group gate) |

### D. AP / PP of the target
| Condition | Type |
|---|---|
| Highest AP / Lowest AP [enemy/ally] | P |
| [enemy/ally] with AP = 0, ≤ 1/2/3, ≥ 1/2/3/4 | L |
| Highest PP / Lowest PP [enemy/ally] | P |
| [enemy/ally] with PP = 0, ≤ 1/2/3, ≥ 1/2/3/4 | L |

### E. Status (状態)
| Condition | Type |
|---|---|
| Prioritize buffed / debuffed [enemy/ally] | P |
| Prioritize non-buffed / non-debuffed [enemy/ally] | P |
| Buffed / debuffed / not buffed / not debuffed [enemy/ally] | L |
| [enemy/ally] with any status ailment / with none | L |
| Poisoned / Burning / Frozen / Stunned / Blinded (and the "not" forms) | L |
| Passive Seal / Guard Seal (and the "not" forms) | L |

### F. Unit headcount (編成人数) — gates
| Condition | Type |
|---|---|
| Enemies ≥ 2 / 3 / 4 / 5 | L |
| Enemies ≤ 1 / 2 / 3 / 4 | L |
| Allies ≥ 2 / 3 / 4 / 5 | L |
| Allies ≤ 1 / 2 / 3 / 4 | L |

### G. Self (自身の状態 / 自身のHP / 自身のAP・PP) — gates
| Condition | Type |
|---|---|
| Self (target is myself) / Other than self | L |
| Self is buffed / Self is debuffed | L |
| 1st / 2nd / 3rd / 4th / 5th action (my Nth turn in this skirmish) | L |
| Own HP ≤ 25 / 50 / 75 % | L |
| Own HP ≥ 25 / 50 / 75 / 100 %, Own HP < 100 % | L |
| Own AP = 0, ≤ 1/2/3, ≥ 1/2/3/4 | L |
| Own PP = 0, ≤ 1/2/3, ≥ 1/2/3/4 | L |

### H. Incoming attack type (攻撃属性) — mainly for passives (guard, cover, counter)
| Condition | Type |
|---|---|
| When attacked physically / magically | L |
| When hit by a row attack / a column attack / an all-target attack | L |
| When attacked by Infantry / Cavalry / Flying / Armored / Scout / Archer / Caster / Elf / Bestral / Angel | L |

### I. Enemy composition (敵兵種の有無) — gates
| Condition | Type |
|---|---|
| Enemy squad contains ⟨type⟩ (10 variants) | L |
| Enemy squad contains no ⟨type⟩ (10 variants) | L |

### J. Highest / lowest stat — all sorts
| Condition | Type |
|---|---|
| Highest ⟨stat⟩ [enemy/ally] | P |
| Lowest ⟨stat⟩ [enemy/ally] | P |

The stats are Max HP, Max AP, Max PP, Physical Attack, Magical Attack, Physical Defence, Magical
Defence, Initiative (speed), Accuracy, Evasion, Crit rate and Guard rate. The wiki warns that these
are *prioritize* conditions, not limits [T].

**Patterns worth copying:**

- Nearly every attribute comes as a matched pair: a limit with thresholds (≤/≥ 25/50/75%) and a sort
  (highest/lowest).
- Thresholds are coarse, in fixed steps. There is no free numeric input, which keeps the UI simple.
- Conditions split into three families:
  - **Target filters/sorts**: categories A–E and J.
  - **Global gates**: F, G and I, which turn the whole row on or off.
  - **Event gates**: H, for reactions.

---

## 3. UI / UX

- **Where you edit:** Character List → a character → their loadout/tactics. You can also edit from
  the unit screen at any time, even mid-stage, through the "Organize" (編成) command. That includes
  right when an encounter preview is showing [S]
  ([AppMedia](https://appmedia.jp/?p=77500972);
  [Game8](https://game8.co/games/Unicorn-Overlord/archives/447561)).
- **How you edit:**
  - Each row is one tile: skill name, a red (active) or blue (passive) marker, Condition 1 and
    Condition 2.
  - Pick a blank condition slot to open a categorised list (the categories in §2).
  - Reorder rows to set priority.
  - Use "Add a Tactic" to add duplicate rows of a skill, which gives you OR logic.
  - Use the On/Off toggle to disable a row without deleting it [S]
    ([Game8](https://game8.co/games/Unicorn-Overlord/archives/447561);
    [TheGamer](https://www.thegamer.com/unicorn-overlord-tactics-complete-guide/)).
- **Optimize:** one button (the "−" button on Switch, according to Game8) fills in tactics, and
  equipment if you want, automatically [S]
  ([Gematsu](https://gematsu.com/2024/02/unicorn-overlord-details-more-characters-battle-stages-skills-and-tactics);
  [Game8](https://game8.co/games/Unicorn-Overlord/archives/447561)). Reviewers say many players lean
  on it for most of a roster of about 50 characters [S]
  ([FullCleared](https://fullcleared.com/reviews/unicorn-overlord-review/)).
- **Tactics Templates:** you can save a character's configuration to a template slot and apply it
  again later, which lets you test alternatives [S]
  ([Game8](https://game8.co/games/Unicorn-Overlord/archives/447561);
  [TheGamer](https://www.thegamer.com/unicorn-overlord-tactics-complete-guide/)). I could not confirm
  how many slots there are, or whether templates can be applied across characters or classes [U].
- **Battle preview (forecast):**
  - Before a fight you see the enemy classes and the predicted damage and outcome.
  - "Organize" jumps straight into tactics editing.
  - When you return, the forecast updates. This is the main feedback loop [S]
    ([RPG Site](https://www.rpgsite.net/news/15481-unicorn-overlord-highlights-tactics-priority-and-battle-stages-along-with-several-new-non-human-allies)).
- **Beginner support:**
  - Each skill has a sensible default condition.
  - Optimize fills in a whole setup.
  - The battle preview shows the result before you commit.
  - Difficulty levels go down to "Casual", which patch 1.01 made easier still [S]
    ([Fandom: Patch Notes](https://unicornoverlord.fandom.com/wiki/Patch_Notes)).
  - Patch 1.04 (April 2024) improved the information shown on the formation and battle screens [S]
    (same source).
- **Sharing:** I found no in-game way to export or share tactics. Players share setups as screenshots
  and text in guides and forums [U].

---

## 4. Reception, and comparison with Gambits and DA:O tactics

### 4.1 FFXII Gambits (2006)

- A gambit is **Target + Condition → Action**. Examples: "Ally: HP < 70% → Cura" and "Foe: nearest →
  Attack". The list is re-evaluated from the top on every turn, and the **first gambit with a met,
  actionable condition runs** [S]
  ([FF Wiki: Gambits](https://finalfantasy.fandom.com/wiki/Gambits)).
- Each gambit row has an on/off toggle. The whole system can also be switched off, and a manual
  command always overrides gambits [S] (same source).
- Characters gain up to 12 slots through License Board augments. Conditions are items you buy or
  find, so the vocabulary grows as you progress [S] (same source).
- **Hidden "no redundant action" rules** [S] (same source):
  - Do not re-cast a buff the target already has.
  - Do not revive someone who is not KO'd.
  - Two characters will not both cast the same buff or revive on the same target.
- **UO compared with Gambits:**
  - UO has **two conditions per row** and a separate passive/reaction layer [S]
    ([FullCleared](https://fullcleared.com/reviews/unicorn-overlord-review/);
    [Boss Rush](https://bossrush.net/2025/10/boss-rush-banter-final-fantasy-xiis-gambit-system-deserves-to-be-imitated/)).
  - UO allows **no manual intervention** during a skirmish, so your "programming" fully decides the
    result. FFXII lets you override at any time [S] (same sources).

### 4.2 Dragon Age: Origins tactics (2009)

- A row is **Condition (on Self / Ally / Enemy) → Action**. The list is checked top-down,
  continuously, in and out of combat.
  - If a condition is true *and* the action can run, the character does it and starts again from the
    top.
  - If the action cannot run (no mana, cooldown, target unreachable), the check moves to the next
    row [S]
    ([Dragon Age Wiki: Tactics (Origins)](https://dragonage.fandom.com/wiki/Tactics_(Origins))).
- Some conditions *set the target* ("Enemy: lowest health", "Enemy: clustered"). Later rows can then
  act on "the current target" [S] (same source). This is a two-step target + action pattern.
- **Slots:** 2 at level 1, plus more at levels 3, 6, 10, 15, 20, 25 and 30, plus more from the Combat
  Tactics skill [S] (same source).
- **Presets** depend on class and skills (Healer, Defender, …). There are 3 custom preset slots. A
  separate **Behaviour** setting (Default / Aggressive / Ranged / Passive / Cautious / Defensive)
  decides what a character does when no row fires [S] (same source). **This two-layer split (coarse
  behaviour plus fine rules) is very close to our panel plus rules.**
- Common criticism [U, general knowledge]:
  - Slots were scarce early on.
  - Debugging was opaque, because there was no "why did they do that" display.
  - Later games simplified the system: Dragon Age II kept a reduced version and Inquisition dropped
    most of it, which many fans regretted.

### 4.3 Why UO's system is praised

- **Depth on demand.** You can ignore it entirely (Optimize) or min-max, and both work [S]
  ([FullCleared](https://fullcleared.com/reviews/unicorn-overlord-review/)).
- **Preparation is the game.** Because skirmishes are automatic, building a squad and writing its
  tactics is where the player's decisions happen. The developers intended this [S]
  ([OneMoreGame interview](https://onemoregame.ph/2024/04/vanillaware-interview-unicorn-overlord/);
  [Inverse interview](https://www.inverse.com/gaming/unicorn-overlord-interview-vanillaware)).
- **Fast, readable feedback.** Skirmishes are short, and the forecast shows the result of a tactics
  change before you commit [S].
- **Vocabulary that fits the game's rock-paper-scissors.** Class-type conditions line up directly
  with class counters, for example "Hunter → prioritize flying" and "Knight's lance → prioritize
  infantry" [S]
  ([RPG Site](https://www.rpgsite.net/news/15481-unicorn-overlord-highlights-tactics-priority-and-battle-stages-along-with-several-new-non-human-allies)).

### 4.4 Criticisms

- **Hidden semantics.**
  - Players expect condition order to be "C1 first", but for two sorts Condition 2 dominates [T].
  - The difference between limit and prioritize is easy to miss [S].
  - The default target order (nearest front-row target first) is never explained [T].
- **Rows that can never run.** A "Prioritize X" row is always true, so everything below it silently
  never runs [S] ([Tobold](https://tobolds.blogspot.com/2024/07/unicorn-overlord-tips.html?m=1)).
- **Scale and tedium.** With 50+ characters, careful tuning becomes a chore, and players fall back on
  Optimize [S] ([FullCleared](https://fullcleared.com/reviews/unicorn-overlord-review/)).
- **No OR** inside a row, and no "remember my target" between turns [T].
- **Misinformation.** Popular English guides contradict each other on how conditions are ordered
  ([Prima](https://primagames.com/gaming/unicorn-overlord-tactics-and-conditions-explained) vs
  [Game8](https://game8.co/games/Unicorn-Overlord/archives/447561) vs the testing above). This shows
  the system needed better in-game explanation [T].

---

## 5. Design takeaways for `cinematic_director` (WH3)

### 5.1 Can it work here? Yes, with four adaptations [D]

| UO assumption | WH3 reality | Adaptation |
|---|---|---|
| Discrete turns; the list is re-evaluated each turn | Continuous real time | Re-evaluate on a **tick** (about 1–2 s per group, staggered) and also on **events** (the unit enters melee, starts routing, a target dies). |
| Each action is atomic | Orders take seconds to minutes to pay off (charges, marches) | Give each rule a **`commit` time** (minimum seconds before a rule of the same or lower priority may replace it) plus **hysteresis** (a rule turns on at HP < 40% but only turns off at HP > 55%). **Interrupt** rules marked `urgent` (rout, low HP, "being shot while waiting") can break a commitment. Without this, units jitter, which ruins the cinematic camera. |
| 3×2 grid; "row" and "front/back" | Open field | Replace rows with **distance, side and arc** predicates: within X m, in front of or behind our line, near our lord. |
| A single character | Groups (main line, missile, cavalry/fliers, lord & heroes) and individual units | Rules live **per role group**, with optional per-unit overrides. Group orders go through `script_ai_planner` (attack / defend / move / patrol). Per-unit rules (abilities, heroes) go through the unit controller. |
| Fixed two conditions, no OR | — | Keep the **two-stage pipeline** but allow N filters and **ordered sort keys** (first key = primary, *unlike* UO). Duplicate rows still give OR. |

### 5.2 Proposed rule format [D]

The evaluation model copies UO and Gambits: an ordered list, **first match wins**, and **gate →
filter → sort → act**.

```
RULE := {
  id       = "cav_hunt_missiles",
  role     = "cavalry",          -- main | missile | cavalry | lordheroes | unit:<key> | ability:<key>
  when     = { ... },            -- GATES on self/group/global state (all must hold; empty = always)
  pool     = "enemy",            -- enemy | ally | self | point
  filter   = { ... },            -- LIMITS on candidates (AND). Empty pool -> rule fails -> next rule
  sort     = { ... },            -- PRIORITIZE keys, applied in order (first = primary). Never fails
  action   = "attack",           -- attack | rush | defend | move | patrol | hold | retreat_to | cast:<ability>
  params   = { radius=..., ... },
  commit   = 12,                 -- seconds before same/lower-priority rules may replace it
  cap      = 2,                  -- max own units assigned to the same target (Gambits-style de-dup)
  urgent   = false,              -- true = may pre-empt a committed higher-priority rule
}
```

**Vocabulary mapped to the state we can read [D]:**

| Family (UO analogue) | Gate / filter / sort predicates |
|---|---|
| HP (C, G) | `hp<0.4`, `hp>=0.75`, `group_avg_hp<0.5`, sort `hp_asc` / `hp_desc` |
| Unit class (B, I) | `class:missile`, `class:cavalry`, `large`, `flying` (can fly), `general`, `hero`, `caster`, `artillery`, `monster`; gate `enemy_has:flying`, `enemy_lacks:missile` |
| Situation (A, H) | `in_melee`, `not_in_melee`, `under_missile_fire`, `routing`, `not_routing`, `moving_fast` (from velocity), `engaged_with:<ally-selector>` |
| Ammo (D, AP/PP analogue) | `ammo<0.1`, `ammo>0` |
| Headcount (F) | `men<0.3` (fraction of starting men), `enemies_within(200)>=3`, `allies_alive>=5`, sort `men_desc` |
| Space (replaces rows) | `dist<300`, `dist_to_lord<150`, `behind_enemy_line`, `on_flank`; sort `closest` / `farthest` / `nearest_to_lord` / `nearest_to_our_line` |
| Time (UO "Nth action", day/night) | `t>60` (seconds since battle start), `phase:deploy/approach/engaged/mop_up` |
| Cost (AP/PP) | for spells: `winds>=cost`, `ability_ready` |

**Text form for the out-of-battle config file [D].** Pipes separate the fields. Lua tables work just
as well, since the mod is Lua.

```
# role      | gates                 | pool:filters                                  | sort            | action          | commit cap
cavalry     | hp>=0.5               | enemy: class:missile & !in_melee & dist<300   | closest         | attack          | 15 2
```

### 5.3 Twenty example rules [D]

Each group lists its rules **top to bottom by priority**, with a fallback at the bottom (the UO
lesson).

**Main line**
1. `main | group_avg_hp<0.35 & enemy_avg_hp>0.6 | — | — | retreat_to lord (defend radius 80) | commit 20, urgent` — fall back and regroup on the lord when clearly losing.
2. `main | — | ally: class:missile & under_melee_attack | closest | defend that ally (radius 60) | commit 10, cap 1` — peel enemies off our archers. This is UO's "cover back-row allies".
3. `main | — | enemy: large & dist<150 | closest | attack, sending only units tagged anti_large | cap 2` — spears meet monsters and cavalry.
4. `main | — | enemy: !routing & !flying | nearest_to_our_line | attack (as a formation group) | commit 20` — the default fallback: advance and engage.

**Missile**
5. `missile | ammo<=0 | enemy: in_melee_with_our_main | hp_asc | attack (melee) | commit 30` — out of ammo, so join the melee on a weak, engaged enemy.
6. `missile | — | enemy: dist<60 & !in_melee & class:melee_cav_or_monster | closest | move away 80 m from it (kite) | commit 6, urgent` — skirmish preset only.
7. `missile | — | enemy: class:missile & dist<range | hp_desc | attack | commit 12` — win the ranged duel first.
8. `missile | — | enemy: in_melee_with_our_main & !large_and_shielded | men_desc | attack | commit 10` — "support" preset: shoot into blobs our infantry is holding, but only when friendly fire is acceptable (see battle_tactics.md §2.6).
9. `missile | — | enemy: dist<range | closest | attack` — fallback.

**Cavalry / fliers**
10. `cavalry | hp>=0.5 | enemy: class:missile & !in_melee & dist<300 | closest | attack | commit 15, cap 2` — hunt missile units (the example from the brief).
11. `cavalry | hp>=0.5 | enemy: in_melee_with_our_main & !anti_large & !braced | rear_exposed_desc, closest | attack (rear charge) | commit 12, cap 2` — hammer and anvil.
12. `cavalry | — | enemy: class:artillery | closest | attack | cap 1` — fliers only (`self.flying`).
13. `cavalry | hp<0.3 | — | — | retreat_to lord | urgent, commit 20` — preserve damaged cavalry.
14. `cavalry | — | enemy: routing & dist<250 | hp_asc | rush | commit 8` — run down routers (mop-up phase).
15. `cavalry | — | point: our flank, 120 m out | — | defend position (radius 120) | commit 10` — "reserve" fallback.

**Lord & heroes**
16. `hero.caster | hp<0.4 | — | — | retreat_to lord (defend radius 40) | urgent, commit 15` — the example from the brief.
17. `lord | hp<0.5 & enemies_within(80)>=2 | — | — | retreat_to our missile line | urgent` — "stay back" variant.
18. `hero.melee | hp>=0.6 | enemy: (hero or general) & dist<200 | general_first, hp_asc | attack | cap 1` — duel enemy characters, preferring their general.

**Spells / abilities**
19. `ability:hex | winds>=cost & ability_ready | enemy: large & in_melee_with(ally: elite) & dist<range | hp_desc | cast | commit 4` — the example from the brief: debuff the monster that is grinding our best unit.
20. `ability:heal | ability_ready | ally: hp<0.6 & in_melee & men>0.3 | hp_asc | cast | cap 1` — Gambits-style de-dup means only one healer targets each unit.
21. `ability:vortex | ability_ready | enemy: men_dense & !in_melee & no_ally_within(40) | men_desc | cast` — friendly-fire guard.

### 5.4 Default rule sets that mirror the panel presets [D]

Each existing dropdown option becomes a **template**, meaning an ordered rule list. In the table,
"R#" refers to the rules in §5.3. Bold rows show the defining difference of that preset.

| Panel setting | Template contents (top → bottom) |
|---|---|
| Army: **balanced** | R1, R2, R3, R4 |
| Army: **aggressive** | R3, R4 with `commit 30`; drop R1; **R2 only if the archers' HP < 50%** |
| Army: **defensive** | R1, R2, R3 limited to `dist<80`, then fallback = defend the deployment point (radius 60) |
| Army: **hold** | R1 (urgent only), then `defend position (radius 20)` |
| Missiles: **support** | R5, R8, R7, R9 |
| Missiles: **skirmish** | R6 (urgent), R7, R9, R5 |
| Missiles: **hold** | R5, then `attack only dist<range` without moving (defend radius 10) |
| Cavalry: **flank** | R13, R12, R10, R11, R14, R15 |
| Cavalry: **with army** | R13, R11 limited to `dist<150`, then `defend ally:main (radius 100)` |
| Cavalry: **reserve** | R13, R14, **R11 only after `t>90` or `group_avg_hp(main)<0.6`**, R15 |
| Lord & heroes: **fight** | R16, R18, then `attack (enemy: in_melee_with_our_main, closest)` |
| Lord & heroes: **stay back** | R16, R17, then `defend ally:main_center (radius 60)` |
| Spells: **all / attack / support / off** | enable or disable rule groups tagged `offence` (R19, R21) and `support` (R20) |

**"Optimize" analogue [D]:** an **Auto** option that picks the templates from the two army
compositions at deployment. Examples:

- The enemy has more than 30% fliers: missile rules get `sort: flying first`.
- The enemy has many missile units and we have fast cavalry: Cavalry → flank, with R10 on top.
- We have little missile power: Missiles → hold.

This mirrors UO's "Optimize" and DA:O's class presets. Most players will stay on Auto.

### 5.5 Minimal in-battle UI [D]

- **Keep the collapsible panel as it is.** It has one dropdown per group, now labelled as templates
  ("Cavalry: Flank ▾"). Add **Auto** as the first entry. No rule editing happens in battle. This
  follows the UO layering, with Optimize first and the full editor later, and the DA:O Behaviour +
  Preset split.
- **A "why" line per group.** Under each dropdown, show in small text the rule that is currently
  firing and its target, for example "Cavalry › R10 hunt missiles → Crossbowmen (220 m)". This is
  the real-time equivalent of UO's battle forecast. It removes the "why did my unit do that" problem
  that hurt DA:O and makes the system learnable. It also helps with debugging.
- **Per-rule toggles (optional, expanded view):** a checkbox list of the template's rules, the
  equivalent of FFXII/UO On/Off. You can turn off "Run down routers" without editing anything.
- **Custom templates:**
  - A config file outside battle, either Lua or the pipe format in §5.2.
  - Each template has a `name`, a `role`, a description and an ordered `rules` list.
  - Every template in the file shows up as another dropdown entry. That gives sharing for free:
    players can paste a block into a forum post.
  - Loading options [U]:
    - Load the file via Lua `io` / `loadfile`, if the WH3 script sandbox allows it.
    - Use Mod Configuration Tool (MCT) settings.
    - Ship the templates inside the pack as a script file.

  The `io` availability in the WH3 Lua environment needs checking in-game.
- **Validator, run on load and shown as a warning toast:**
  - Flag any rule placed after an unconditional or sort-only rule as "unreachable". This fixes UO's
    "Prioritize" trap automatically.
  - Flag AND filters that are always empty, such as `class:missile & class:cavalry`, unless the
    unit really is missile cavalry.
  - Flag templates with no fallback.

### 5.6 Implementation notes [D]

- **Evaluation order per tick:**
  1. Run `urgent` rules for each unit in the group.
  2. Skip groups whose current rule is still inside its `commit` window.
  3. For the rest, walk the rules: gates, then filters on the candidate pool, then sorts. Assign
     targets greedily while respecting `cap`.
  4. Issue a planner order only if the target or action **changed**. Re-issuing the same order
     resets WH3 pathing and causes stutter.
- **Sort semantics:** apply the sort keys as a single composite key, with the first key as primary.
  This is more intuitive than UO's "last condition wins" behaviour. Document it in the config header.
- **Default candidate order** (before sorts): the closest unit first. This matches UO's implicit
  default and makes "no sort" behave predictably.
- **Hysteresis helpers:** write thresholds as `hp<0.4~0.55`, meaning the rule enters below 0.40 and
  leaves above 0.55.
- **Cinematic coupling:** the camera can read the firing rule id. When a high-drama rule starts (R10
  cavalry hunting archers, R11 rear charge, R19 hex), the director can cut to that unit. The rule
  system then works as a source of story beats as well as AI.

---

## Sources

- Gematsu, official system details: https://gematsu.com/2024/02/unicorn-overlord-details-more-characters-battle-stages-skills-and-tactics
- RPG Site, official Tactics/Priority preview: https://www.rpgsite.net/news/15481-unicorn-overlord-highlights-tactics-priority-and-battle-stages-along-with-several-new-non-human-allies
- uol_db wiki (JP), 作戦について: full condition list and target-selection algorithm: https://wikiwiki.jp/uol_db/%E4%BD%9C%E6%88%A6%E3%81%AB%E3%81%A4%E3%81%84%E3%81%A6
- AppMedia (JP), 作戦の設定方法, plus a user test of condition order in the comments: https://appmedia.jp/?p=77500972
- TheGamer, Complete Guide to Tactics: https://www.thegamer.com/unicorn-overlord-tactics-complete-guide/
- Game8, How to Create Tactics Templates: https://game8.co/games/Unicorn-Overlord/archives/447561
- Prima Games, Tactics and conditions explained (claims order is random; contradicted above): https://primagames.com/gaming/unicorn-overlord-tactics-and-conditions-explained
- GameFAQs thread, "Does the number of the condition make a difference?": https://gamefaqs.gamespot.com/boards/426397-unicorn-overlord/80757827
- Tobold's Blog, Unicorn Overlord tips: https://tobolds.blogspot.com/2024/07/unicorn-overlord-tips.html?m=1
- Fandom, List of Tactics (default skill conditions): https://unicornoverlord.fandom.com/wiki/List_of_Tactics
- Fandom, Battle Stages: https://unicornoverlord.fandom.com/wiki/Battle_Stages
- Fandom, Patch Notes: https://unicornoverlord.fandom.com/wiki/Patch_Notes
- FullCleared review: https://fullcleared.com/reviews/unicorn-overlord-review/
- Boss Rush, "FFXII's gambit system deserves to be imitated": https://bossrush.net/2025/10/boss-rush-banter-final-fantasy-xiis-gambit-system-deserves-to-be-imitated/
- OneMoreGame, Vanillaware interview: https://onemoregame.ph/2024/04/vanillaware-interview-unicorn-overlord/
- Inverse, Vanillaware interview: https://www.inverse.com/gaming/unicorn-overlord-interview-vanillaware
- Final Fantasy Wiki, Gambits: https://finalfantasy.fandom.com/wiki/Gambits
- Dragon Age Wiki, Tactics (Origins): https://dragonage.fandom.com/wiki/Tactics_(Origins)

**Not reachable from this environment:** Fextralife wiki (DNS failure), Reddit (blocked), the
GameFAQs and Neoseeker pages (403), and the uol_db sub-pages on battle flow and passive triggers (bot
check). Claims that would normally come from those sources are tagged [U] or [T].
