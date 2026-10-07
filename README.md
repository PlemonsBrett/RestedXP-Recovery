# RestedXP Recovery

A companion addon for **RestedXP on WoW Forever** that detects when the active leveling guide assumes quest state your character does not actually have.

The motivating case is joining a segmented guide midway through leveling. A guide named `18-22`, for example, can contain turn-ins or quest-chain steps that assume quests were accepted or completed in earlier guide sections. Skipping those unavailable steps can leave the character increasingly behind the route's expected XP and quest state.

## v0.4.0: adaptive recovery prototype

The addon now implements the four planned phases:

- inspecting the active RestedXP guide from the character's current guide step;
- finding quests that the guide expects to already be in the character's quest log;
- examining prerequisites for upcoming quest accepts;
- recursively walking `preQuestGroup` (AND) and `preQuestSingle` (OR) prerequisites using the quest database RestedXP already integrates with;
- ignoring prerequisites the character has already turned in;
- preferring an OR prerequisite branch the character has already started, otherwise choosing the branch with the fewest estimated outstanding quests;
- finding RestedXP guide sections that contain the missing quest when RestedXP has indexed them;
- extracting only the relevant accept, objective, turn-in, and nearby navigation steps into a temporary recovery guide;
- preserving the original guide checkpoint, rebuilding an active recovery route after `/reload`, and resuming automatically when its quest-state requirements are met;
- detecting explicit XP gates (and late-guide level deficits), ranking suitable unfinished quests, and offering a separate opt-in XP recovery route.

Recovery never edits RestedXP's installed guide tables or stores their text in saved variables. Generated routes are cloned in memory from guide content already installed by the player.

## Requirements

- WoW Forever
- RestedXP Guides
- Questie (currently required for prerequisite graph data)

RestedXP itself uses Questie's database for its missing-prerequisite warnings, which is why this prototype uses the same source rather than shipping a separate quest database.

## Install for testing

1. Download or clone this repository.
2. Copy the inner `RestedXP_Recovery` folder into the WoW Forever client's `Interface/AddOns` directory.
3. Make sure **RestedXP Guides**, **Questie**, and **RestedXP Recovery** are enabled on the character-selection AddOns screen.
4. Log into the character and run `/reload` after changing addon files.

## Commands

- `/rxpr scan` — scan the active RestedXP guide and print a recovery plan.
- `/rxpr info` — show whether RestedXP, the active guide, and prerequisite database were detected.
- `/rxpr last` — print the last recovery plan again.
- `/rxpr recover` — scan and load the prerequisite recovery route.
- `/rxpr resume` — cancel the temporary route and return to the original guide.
- `/rxpr xp` — report the next XP deficit and recommended optional quests.
- `/rxpr xprecover` — load the recommended optional quests as a temporary route.
- `/rxpr autoprompt on|off` — toggle the guide-load recovery prompt.

## Best first test

Use a character that started a RestedXP guide above level 1 and is known to be missing prior-chain quests. Load the guide section where the mismatch occurs, then run:

```text
/rxpr info
/rxpr scan
/rxpr recover
```

Choose **Continue Normally** first if the proposed quest list is wrong. Quest IDs are intentionally included so false positives can be traced back to the guide and prerequisite graph. Test `/rxpr resume` before relying on a long recovery route.

## How recovery works

The recovery flow is:

1. Compare actual character quest state with the state assumed by the selected guide.
2. Resolve missing prerequisite chains recursively.
3. Locate the corresponding steps in already-installed RestedXP guides.
4. Build a temporary recovery route from those existing steps.
5. Resume the selected guide once its assumed quest state is satisfied.
6. Separately detect an XP deficit and offer efficient optional XP recovery when prerequisite repair alone will not close the level gap.

No paid RestedXP guide content is copied into this repository.

## Development checks

The planner, route builder, XP selector, Questie adapter, persistence handoff, and original-guide resume behavior have standalone tests:

```sh
cd tests
lua run.lua
lua integration_smoke.lua
```

The tests use only standard Lua. A real client test is still required for RestedXP rendering, quest automation, and compatibility with the exact installed Forever releases.

## Recovery safeguards

- Dynamic recovery is opt-in; declining remembers that guide checkpoint.
- Source guide steps are deep-cloned before filtering, so the installed RestedXP guide remains untouched.
- Other quests' actions and guide-control/XP directives are removed from copied steps.
- The original guide group, name, key, step, and stable step ID are retained per character.
- `/rxpr resume` is always available if a source guide lacks a usable turn-in segment.

## Status

Experimental. The pure logic and compatibility adapters are tested, but v0.4.0 still needs in-game validation against the specific RestedXP and Questie Forever builds used by testers. Route extraction intentionally favors safety over copying broad guide sections, so complicated conditional or multi-quest steps may require further filtering fixes.
