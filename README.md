# Aegis

A player HUD for **WoW WotLK 3.3.5a** (Project Ascension). Health, the
resources you actually use (mana, rage, energy, runic power), combo
points, and an **incoming-pressure indicator** that previews your
time-to-death and net HP trajectory in combat.

Built around movable, configurable **blocks** containing predefined
**widgets**. Default install ships two blocks placed symmetrically
around the player character at screen center.

## Why pressure tracking?

Combat awareness in WoW depends on knowing whether you're stable,
recovering, or on the way out. The default unit frame shows your HP
fraction but nothing about your trajectory: it cannot tell you that
the net of incoming damage minus incoming healing means you'll die in
35 seconds at the current rate, or that you're losing 1.5% of your
max HP per second on a long fight.

Aegis renders that signal as a **colored halo** around the health
bar:

| State    | Halo   | Meaning                                                              |
|----------|--------|----------------------------------------------------------------------|
| healing  | blue   | HPS in > DPS in — you are gaining HP from heals                      |
| none     | -      | both flows quiet                                                     |
| light    | yellow | net drain is below the warning thresholds (slow attrition)           |
| warning  | orange | warning TTD or warning drain rate (sustained drain on long fights)   |
| critical | red    | imminent danger (TTD <= 5s) or heavy burst (>= 3% HP per second)     |

State logic is the **max severity** of two computations: TTD-based
("you will die in N seconds") and drain-rate-based ("you are losing
X% of max HP per second"). TTD catches burst danger; drain catches
sustained attrition that TTD alone under-flags on long fights with
high-HP characters.

A 0.5s hysteresis prevents flicker between zones; the `healing` state
needs 1.5s of sustained recovery before it commits.

The displayed TTD readout uses **direct HP measurement** with a
rolling-peak baseline over the last 5 seconds: when HP rises above the
window's peak (a heal lands), the peak resets and the rate
recomputes from there. Direct HP measurement also catches damage and
heals the combat log misses (Ascension custom mechanics, environmental,
untracked auras).

## Customization

Open the settings panel with `/ae` (or `/aegis`). Three tabs:

**Pressure** — TTD ladders (warning / critical), drain ladders (% of
max HP/s), sliding-window length, hysteresis, healing sustain, and the
critical-entry sound toggle.

**Visual** — per-bar text format (HP, mana, rage, energy, runic):
`Value` / `Percent` / `Value + Percent` / `None`. Combo-point count
overlay. Halo out-of-combat gating. TTD master toggle and position
(above/below the bar in vertical mode). Default style for new blocks.

**Blocks** — per-row editor, no slash command needed:

  - **Orientation toggle**: `Horiz.` (wide bars stacked top-to-bottom)
    or `Vert.` (tall bars side-by-side).
  - **Style dropdown**: `Standard` (flat) or `Glossy` (gradient overlay).
  - **Curve dropdown** (vertical blocks only): `Normal`, `Left (`, or
    `Right )` — bars use a parenthesis-shaped texture that wraps around
    the player character.
  - **Widget chip strip** with `<` / `>` to reorder, `x` to remove.
  - **`+ Add widget`** dropdown to append from the catalog.
  - **Scale slider** (0.5x .. 2.0x) and **Gap slider** (-30 .. 30 px;
    negative gaps overlap widgets — useful for curved bars where the
    transparent texture padding leaves visible space at gap=0).
  - **Delete** button.
  - **Footer**: `+ Add empty block`, `Move blocks` (toggle drag mode —
    block positions read live as `CENTER ±x, ±y` while dragged for easy
    mirroring), and `Reset to defaults`.

Most visual settings apply **live** without a `/reload`.

## Install

Download the latest release zip from the
[Releases page](https://github.com/spyspott3d/Aegis/releases).
Extract it into `World of Warcraft/Interface/AddOns/` so the path
looks like `Interface/AddOns/Aegis/Aegis.toc`. Launch the client.

At login, type `/ae about` in chat to confirm the addon is loaded.

## Default layout

Two blocks symmetric around screen center:

- **left block**: combo points, health, mana
- **right block**: rage, energy, runic power

Resources you do not have on a given character (e.g. runic power
before unlock on Project Ascension) hide automatically — empty bars
are not drawn.

## Commands

The settings panel covers everything; the slash commands are
shortcuts and are still supported.

| Command                                        | Description                              |
|------------------------------------------------|------------------------------------------|
| `/ae`                                          | toggle the settings panel                |
| `/ae lock` / `/ae unlock`                      | toggle drag mode for all blocks          |
| `/ae reset`                                    | reset blocks to default (with confirm)   |
| `/ae block list`                               | list all blocks and their widgets        |
| `/ae block add <h\|v> <widget1> [widget2] ...` | create a block at screen center          |
| `/ae block remove <id>`                        | delete a block by id                     |
| `/ae pressure`                                 | print pressure config                    |
| `/ae debug pressure on\|off`                   | toggle a 1Hz chat-print of state values  |
| `/ae about`                                    | print version + author                   |
| `/ae help`                                     | list all commands                        |

### Widget catalog

Pass any of these as arguments to `/ae block add`, or pick them from
the `+ Add widget` dropdown in the Blocks tab:

| Widget id | What it shows                                          |
|-----------|--------------------------------------------------------|
| `health`  | Player HP (with the pressure halo + incoming-heal segment) |
| `mana`    | Player mana                                            |
| `rage`    | Player rage                                            |
| `energy`  | Player energy (smoothed via 10 Hz poll)                |
| `runic`   | Player runic power (hidden if not unlocked)            |
| `combo`   | Combo points on current target (vertical column in vertical blocks, row in horizontal) |
| `dps_in`  | Numeric: damage taken per second (session)             |
| `hps_in`  | Numeric: healing received per second (session)         |
| `dps_out` | Numeric: damage dealt per second (player + pets/totems) |
| `hps_out` | Numeric: healing dealt per second (player + pets/totems) |

In a vertical block, consecutive text widgets (`dps_in` / `hps_in` /
`dps_out` / `hps_out`) automatically stack in a single column to the
right of the bars instead of taking their own column each.

## Compatibility

- Tested on Project Ascension. Should work on other WotLK 3.3.5a
  private servers — Aegis uses standard Blizzard API only.
- Plays nicely with Bartender4, ElvUI, Stuf, X-Perl, ShadowedUF
  (their player frame can be hidden while Aegis takes over).
- No protected API calls, no taint sources.
- No library dependencies.

## Bug reports

Open an issue with the addon version (visible via `/ae about`), the
realm and client build, and steps to reproduce.

## License

MIT. See LICENSE.
