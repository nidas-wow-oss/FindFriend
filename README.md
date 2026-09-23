# Find Friend

A compass arrow that points to a party or raid member, for World of Warcraft
3.3.5a (WotLK). Made for battlegrounds: keep an arrow on your duo, on the flag
carrier, or on both at once.

## What it does

An arrow on screen points at whoever you are tracking, showing their name, the
distance to them and an estimated time to reach them. It rotates as you turn,
so "straight ahead" always means straight ahead. The arrow turns blue and
glows when you are aimed at them, and green when you are basically on top of
them.

You can track up to **3 people at the same time**, one arrow each.

## How to use it

**Double-click your target's portrait** to start tracking them. Double-click
again to stop. Double-click an arrow to remove that one. Drag any arrow to
move them all.

| Command | What it does |
| --- | --- |
| `/ff <name>` | Track that player |
| `/ff target` | Track your current target |
| `/ff off` | Stop tracking everyone |
| `/ff off <name>` | Stop tracking just that one |
| `/ff units` | Switch between meters and yards |
| `/ff icon` | Next arrow icon (or `/ff icon glow` to pick one) |
| `/ff test` | Try the arrow without needing another player |
| `/ff autoduo` | Auto-track your duo when you enter a battleground |

## Does the other person need this addon?

**If they are in your group or raid: no.** Their position comes from the
game's own API. They do not need anything installed and never know you are
tracking them. The only requirement is that you are both on the same map.

**If they are not in your group: yes.** Their position has to be sent over,
and that only works if they are running Find Friend too. It is not compatible
with Carbonite: the arrow logic was rebuilt from it, but the way positions are
exchanged is its own.

## Arrow icons

Six styles: `arrow`, `chip`, `gloss`, `glow`, `neon` and `blizz`. The first
five load `.tga` files from `Media/` that are **not included** — they are game
files, so you copy them yourself. `Media/LEEME.txt` says which ones and from
where. `blizz` uses a texture already in the game and needs nothing.

## Install

Drop the `FindFriend` folder into `Interface\AddOns`.

## Credits

The arrow logic is a reimplementation of Carbonite's **Track Player** feature
(its `Nx.HUD` module) for a standalone addon.
