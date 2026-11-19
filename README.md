# Forever Route

Leveling routes for WoW Forever, 1 to 60, for all 56 race and class combinations, Alliance and Horde. A step card, an
arrow and map pins tell you what to accept, kill, hand in and train, and how to get to the next zone. Install it and
play: your plan loads by itself, quests you've already done are skipped, and it works at any level.

![The human paladin plan, 1 to 60](docs/img/journey.gif)

## The card

**The next thing to do, always on screen.** It reads your quest log live, counts kills and loot, ticks steps off as you
play, and fits in hand-ins you finished early when you pass by. Skip a quest or a dungeon and the route keeps up.
The **?** on the card says why it picked a step, and the game's 3D navigation marker shows where to go.

![The card, step by step](docs/img/card.gif)

## Pick your own zone

**Bored of a zone? Pick another.** "Where to?" (the route window, or `/fr paths`) lists the zones you could go to
now, with the XP each still has for you and the level that gets you to. Pick one and the route takes you there. If a
zone's quests need an earlier part you haven't done, those steps come first when they're close by, and a chain you
carry that's about to turn gray is pointed out before you leave. PLANNED NEXT takes you back to your plan, wherever
you wandered.

![Picking a zone](docs/img/where-to.gif)

## How the plans are made

Routes aren't hand-written. A planner builds them from the quest data and the game's own terrain, and every plan is
played from 1 to 60 by simulated players before it ships - including ones that wander off to other zones.

**It picks the next zone** by planning out every zone that fits your level:

![Choosing the next zone](docs/img/planner-choice.gif)

**It keeps the quests worth doing**, and says why the rest were cut or left for later:

![Picking a zone's quests](docs/img/quest-pick.gif)

**It finds the fastest way there** across one network of roads, boats, the tram, flights, class teleports and the
Skyborne skyship:

![Finding a trip](docs/img/travel.gif)

**Every plan, checked** - hours to 60, no grinding:

![Every plan, checked](docs/img/plans.gif)

## Getting started

Install Forever Route from CurseForge or from [Releases](https://github.com/noopz/ForeverRoute/releases) and log in.
The plan for your race and class loads by itself and starts you on the best part of it for your level and where you
are. Open any flight master's map once so the addon knows your flight paths.

| Command | What it does |
|---|---|
| `/fr` | Show or hide the card |
| `/fr list` | The whole route |
| `/fr paths` | Where to? - the zones you could go to now |
| `/fr dungeons` | Side trips: class quests, bonus items, dungeons |
| `/fr skip` · `/fr back` · `/fr undo` | Move through the steps by hand |
| `/fr logcheck` | Quests in your log the route won't use |
| `/fr why` | Why the addon did what it just did |
| `/fr report` | Copy a bug report to paste to us (anonymous) |
| `/fr news` | What changed in recent versions |
| `/fr options` | Settings |

What changed in each release: [CHANGELOG.md](CHANGELOG.md). Something look wrong? `/fr report` and an issue here.

This repository holds the addon and its built-in plans. The planner that builds the plans and its simulator are not
public.

Forever Route by noopz. [CC BY-NC-SA 4.0](LICENSE): share and adapt it with credit, never sell it. The quest data it is
built from is GPL-3.0 (QuestieDB); see [NOTICE](NOTICE). Contributions: [CONTRIBUTING.md](CONTRIBUTING.md).
