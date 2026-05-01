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

| State    | Halo  | Meaning                                                              |
|----------|-------|----------------------------------------------------------------------|
| healing  | blue  | HPS in > DPS in — you are gaining HP from heals                      |
| none     | -     | both flows quiet                                                     |
| light    | yellow | net drain is below the warning thresholds (slow attrition)           |
| warning  | orange | warning TTD or warning drain rate (sustained drain on long fights) |
| critical | red   | imminent danger (TTD <= 5s) or heavy burst (>= 3% HP per second)     |

State logic is the **max severity** of two computations: TTD-based
("you will die in N seconds") and drain-rate-based ("you are losing
X% of max HP per second"). TTD catches burst danger; drain catches
sustained attrition that TTD alone under-flags on long fights with
high-HP characters.

A 0.5s hysteresis prevents flicker between zones; the `healing` state
needs 1.5s of sustained recovery before it commits.

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

| Command                                        | Description                          |
|------------------------------------------------|--------------------------------------|
| `/ae`                                          | open the config panel                |
| `/ae lock` / `/ae unlock`                      | toggle drag mode for all blocks      |
| `/ae reset`                                    | reset blocks to default (with confirm) |
| `/ae block list`                               | list all blocks and their widgets    |
| `/ae block add <h\|v> <widget1> [widget2] ...` | create a block at screen center      |
| `/ae block remove <id>`                        | delete a block by id                 |
| `/ae pressure`                                 | print pressure config                |
| `/ae debug pressure on\|off`                   | toggle a 1Hz chat-print of state values |
| `/ae help`                                     | list all commands                    |

### Widget catalog

Pass any of these as arguments to `/ae block add`:

| Widget id | What it shows                                          |
|-----------|--------------------------------------------------------|
| `health`  | Player HP (with the pressure halo + incoming-heal segment) |
| `mana`    | Player mana                                            |
| `rage`    | Player rage                                            |
| `energy`  | Player energy (smoothed via 10 Hz poll)                |
| `runic`   | Player runic power (hidden if not unlocked)            |
| `combo`   | Combo points on current target (filled pips only)      |
| `dps_in`  | Numeric: damage taken per second (session)             |
| `hps_in`  | Numeric: healing received per second (session)         |
| `dps_out` | Numeric: damage dealt per second (player + pets/totems) |
| `hps_out` | Numeric: healing dealt per second (player + pets/totems) |

## Compatibility

- Tested on Project Ascension. Should work on other WotLK 3.3.5a
  private servers — Aegis uses standard Blizzard API only.
- Plays nicely with Bartender4, ElvUI, Stuf, X-Perl, ShadowedUF
  (their player frame can be hidden while Aegis takes over).
- No protected API calls, no taint sources.
- No library dependencies in v1.

## Bug reports

Open an issue with the addon version (visible via `/ae about`), the
realm and client build, and steps to reproduce.

## License

MIT. See LICENSE.
