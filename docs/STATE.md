# Game state in memory

Where the original game (Zone.com build of Lemonade Tycoon Deluxe) keeps its state. `Lemonade.exe` always loads at 0x400000 and these live in its own data sections, so the addresses are fixed. Found by playing scripted days and diffing memory snapshots (November 2026). Values are 32-bit little-endian integers unless noted.

## Player block (0x63d5a0)

| Address | Meaning | Example |
|---|---|---|
| 0x63d5a4 | cup price, cents | 120 = $1.20 |
| 0x63d5a8 | recipe: lemons per pitcher | 4 |
| 0x63d5ac | recipe: cups of sugar per pitcher | 3 |
| 0x63d5b0 | recipe: ice cubes per cup | 3 |
| 0x63d5e4 | stock: lemons | 12 |
| 0x63d5e8 | stock: sugar | 12 |
| 0x63d5ec | stock: ice | 50 |
| 0x63d5f0 | stock: cups | 75 |
| 0x63d5f8 | cash, cents (also mirrored at 0x53c7c8) | 2840 = $28.40 |

## Calendar and weather (0x53c7e0)

| Address | Meaning | Example |
|---|---|---|
| 0x53c7e4, e8, ec | weather for morning, midday, afternoon (icon codes: 0 sunny, 3 cloudy, 5 rain seen so far) | 3 3 3 |
| 0x53c7f0 | day number, counting from 0 | 2 = Day 3 |
| 0x53c7f4, f8, fc | temperature for the three periods, °C; the forecast before the day, actual values while it runs | 28 32 30 = 82–89 °F |
| 0x53c804 | 1 while the day is running | |

## Today's results (0x63d580)

| Address | Meaning |
|---|---|
| 0x63d580 | cups sold today |
| 0x63d584 | today's profit, cents (starts negative: the pitcher cost) |
| 0x63d590 | missed sales today |

## Locations (0x5b9260)

Ten 32-byte records in display order: rent in cents, a name pointer, the location's id, then four object pointers. Rents read 0, 1000, 3000, 3000, 4000, 5000, 5000, 10000, 10000, 15000, matching the rent screen.

## Still to find

Current location, popularity and satisfaction (per location), time of day, upgrades and staff owned, advertising, and the screen being shown.
