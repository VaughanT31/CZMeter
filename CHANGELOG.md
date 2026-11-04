# Changelog

## 0.3.0

- **Always show me:** a new option in each window's menu (the cog), on by default. Your own row stays in sight: when your DPS is below the rows in view, or the window is too short to reach you, your row takes the bottom line, at your real rank. Turn it off to see only the top rows.

## 0.2.1

- Combat log options: the "I've cleared my logs" button no longer sits on top of the hours logged line.

## 0.2.0

First public release.

**The meter**
- Live bars and numbers through boss fights and Mythic+ keys, built on the game's own meter data so totals match Blizzard's.
- Every metric: damage, healing, absorbs, damage taken, avoidable damage, interrupts, dispels, deaths and damage into each enemy.
- Current fight, overall total or any earlier pull, plus your group's best try on the last boss.
- Players and Enemies tabs, My DPS, a Top setting for how many rows show, and copy to chat.
- Your own row is outlined and always on the list, even below the cut.
- Item level badges next to each player, read out of combat.
- Pick which columns show (rank, spec icon, item level, per second, share) from Columns in the window menu. Share is off by default to leave room for names.
- Short (1.2M) or full (1,234,567) numbers out of combat.

**Player details**
- Click a player's row for their breakdown in that window's metric and fight: total, per second, share and rank.
- Spells, Targets and Defense tabs. Hover a spell for overkill and targets, and avoidable hits show in red.
- Your own details open any time; other players' open once combat ends.

**Windows**
- Up to 6 windows, each with its own metric, so one can show damage and another healing.
- Drag a window near another and it snaps to that edge. Snapped windows move and lock as one group, and Ungroup pulls them apart.
- Fixed height windows that scroll with the mouse wheel, or windows that grow with the number of rows.

**Skins**
- Default, Minimal and Classic built in. Change any look setting and a custom copy is saved for you.
- Export a skin as a text string to share, and import a friend's.

**Options**
- `/cz options`, the minimap button, or Esc > Options > AddOns.
- Display, Window, Bars, Text, Skins and Combat log pages, with "Editing group" to change every snapped window at once.
- Test bars fill every window with 25 made-up players, so skins can be tried anywhere.
- Optional clearing of the meter when a key starts or when you enter a new dungeon or raid.

**Combat log**
- Can start itself in raids and Mythic+ (or every dungeon and raid), with a warning if Advanced Combat Logging is off.
- Stops a log it started when you leave the instance or log out, and never touches a log you started yourself.
- Counts the hours it has logged and reminds you to clear old files from your Logs folder (after 10 hours by default, or never).

**Also**
- Light on your frame rate: a few redraws a second in combat, and none out of combat unless something changed.
- Minimap button: left click opens the options, right click shows or hides the meter, drag to move it.
- CZ Meter shows its own icon in the AddOns list.

## 0.1.1

- Much smaller window: every button now sits on one line, and the Players and Enemies tabs share a line with the column headings.

## 0.1.0

- First test version: the meter window with live bars, metric switcher, history, best try, your own row, enemy totals and copy.
