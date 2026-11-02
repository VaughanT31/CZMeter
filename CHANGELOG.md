# Changelog

## 0.2.0

- More than one window: open up to 6, each with its own metric, so one can show damage and another healing. New windows come from the window menu, the options or `/cz new`.
- Windows stick together: drag one near another and it snaps to that edge. Stuck windows move and lock as one group, and Ungroup pulls them apart.
- Fixed height windows that scroll with the mouse wheel, so a full raid fits. "Grow with the number of rows" keeps the old behaviour, and dragging a growing window's height with the grip gives it a fixed height instead.
- Skins: Default, Minimal and Classic come built in. Change any look setting and a custom copy is saved for you.
- Share skins with friends as text strings: export one, paste one in to import it.
- Options panel (`/cz options`): Display, Window, Bars, Text, Skins and Combat log pages, with an "Editing group" switch to change every window in a group at once.
- Test bars fill every window with made-up rows, so skins and a 25 player list can be tried anywhere.
- The combat log can start itself in raids and Mythic+ (or all dungeons), and you get a warning if Advanced Combat Logging is off.
- Optional clearing of the meter when a Mythic+ key starts or when you enter a new dungeon or raid.
- Full numbers (1,234,567) out of combat, if you prefer them to 1.2M.
- Clear meter history moved into the window menu.
- Lighter on your frame rate: windows no longer redraw on every meter update from the game (it fires many times a second in a busy fight). They redraw a few times a second in combat, and out of combat only when something changed. The player details panel redraws at most once a second.
- Fixed the fight timer staying near 0:00 in combat. It now only restarts when a boss pull begins mid-combat.
- Combat log disk space: CZ Meter stops a log it started when you log out too, counts the hours it has logged, and reminds you to clear old files from your Logs folder after 10 hours (change or turn off on the Combat log page).
- Player details: click a player's row to open their breakdown for that window's metric and fight. The header shows total, per second, share and rank. Spells lists each ability with its share (hover for overkill and targets), Targets adds up damage per target where the game gives it, and Defense shows damage taken, avoidable damage, absorbs, healing, interrupts, dispels and deaths with a rank for each, plus the spells that hit them hardest. Other players open once combat ends; your own row opens any time.
- Pick which columns show (rank, spec icon, item level, per second, share) from Columns in each window's menu, or on the Text page of the options. Share is now off by default, which leaves more room for names.
- Minimap button: left click opens the options, right click shows or hides the meter, drag it around the minimap. It can be turned off on the Display page.
- CZ Meter now shows its own icon in the AddOns list.

## 0.1.1

- Much smaller window: every button now sits on one line, and the Players and Enemies tabs share a line with the column headings.

## 0.1.0

- First test version: the meter window with live bars, metric switcher, history, best try, your own row, enemy totals and copy.
