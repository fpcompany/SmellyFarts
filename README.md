# SmellyFarts

A World of Warcraft addon that plays a sound when an enemy player dies. Works
on retail Midnight (Interface 120100) and WoW Forever (Interface 16001).

Each kill plays one of these:

- Fart
- Wet fart
- Wilhelm scream
- Minecraft oof
- Roblox oof

Everyone in the party running SmellyFarts hears the same sound for the same
death. The sound is picked from who died and the server time (in 3-minute
windows), so no messages are sent between players. A given enemy keeps the
same sound for up to 3 minutes, then gets a new one.

## How deaths are noticed

The combat log is closed to addons, so SmellyFarts watches the enemy players
the client lets addons see (your target, focus, nameplates and arena
opponents) and plays a sound when one of them goes from alive to dead. An
enemy that dies with none of those on them (no nameplate shown, not
targeted) can't be noticed.

## Minimap button

- **Left-click:** turn SmellyFarts on or off
- **Shift + middle-click:** sound test panel
- **Drag:** move it around the minimap

## Commands

| Command | What it does |
| --- | --- |
| `/farts` or `/farts toggle` | Turn SmellyFarts on or off |
| `/farts on`, `/farts off` | Turn it on or off |
| `/farts test` | Play a random sound |
| `/farts sounds` | Open the sound test panel |
| `/farts debug` | Print what it sees in chat |

`/smellyfarts` works the same as `/farts`.
