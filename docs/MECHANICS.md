# How Lemonade Tycoon Deluxe works

This is the reference for rebuilding the game with the same rules. Sources are marked: **measured** values come from playing the original under Wine (Zone.com build), **help** comes from the game's own help pages, and **open** marks what still needs measuring.

## The daily loop

1. **Morning.** The game shows the date, a temperature range, three weather icons (morning, midday, afternoon) and one news headline. The forecast can be wrong: "what you see every morning is a forecast, and as such, it may (and will) differ" (help).
2. **Plan.** The player buys supplies, sets the recipe and price, optionally pays for advertising, hires staff, buys upgrades or moves to another location.
3. **The day plays out** in an isometric view of the location. Customers walk by, some stop, buy and react with speech bubbles. The panel counts cups sold, running profit and four reaction types: happy, unhappy with the recipe, waited too long, and too expensive. Fast-forward and Skip buttons exist (measured).
4. **Evening report** ("Yesterday's Results"): cups and revenue, stock used and lost, gross profit and margin, rent, marketing, earnings, customer satisfaction, missed sales, spoiled stock, and a medal message on a new profit record (measured).

## Money

- A career starts with **$40.00** cash, recorded as share capital (measured).
- A pitcher's lemons and sugar are paid for when it is mixed. Each cup sold also uses one cup and the recipe's ice (measured: day-one stock used of $4.40 equals two pitchers of lemons and sugar plus 14 cups and 28 cubes).
- Lemonade left in the pitcher at closing is thrown away silently, inside "stock used" (measured).
- Rent and advertising are charged per day. The game stops the day if you can't pay ("You don't have enough money to pay your rent", help text). Going broke ends the career with a "Bankruptcy!" screen.
- Reports: Profit & Loss (current, last and best month), a Balance Sheet (cash, stock at cost, equipment at purchase price, share capital, profit/loss), and monthly charts of temperature, visitors, sales and revenue.

## Supplies

Packs get cheaper per unit as they grow (measured):

| Item | Small | Medium | Large |
|---|---|---|---|
| Lemons | 12 for $4.80 ($0.40) | 24 for $7.20 ($0.30) | 48 for $9.60 ($0.20) |
| Sugar (cups) | 12 for $4.80 ($0.40) | 20 for $7.00 ($0.35) | 50 for $15.00 ($0.30) |
| Ice (cubes) | 50 for $1.00 ($0.020) | 200 for $3.00 ($0.015) | 500 for $5.00 ($0.010) |
| Cups | 75 for $1.00 ($0.013) | 225 for $2.35 ($0.010) | 400 for $3.75 ($0.009) |

Spoilage (help, ice measured): **ice melts completely every night**, lemons last a few days, sugar a couple of weeks, cups never spoil. Each stand has a storage limit (help; **open**: the limits).

## Recipe

A pitcher takes some lemons and some cups of sugar; each cup served gets some ice cubes. The starting recipe is 4 lemons, 2 sugar, 2 ice.

- **Ice stretches the pitcher**: 2 ice gives 12 cups per pitcher, 4 ice gives 16 (measured), which fits *cups per pitcher = 8 + 2 × ice*. **Open**: whether lemons and sugar also change the yield.
- **Cost per cup** is the pitcher's lemons and sugar divided by its yield, plus that cup's ice and the cup itself (measured: $0.19 for 4/2/4 with medium packs, matching the screen).
- **Taste is about balance.** Too much ice dilutes the lemonade: going from 2 to 4 ice with the same lemons and sugar on a 100 °F day dropped satisfaction from 77% to 35% with "Customers complained about your recipe" (measured). The help says to keep lemon and sugar balanced and add ice when it's hot. **Open**: the ideal ratios by temperature.

## Price and demand

- The price moves in $0.10 steps from a $1.00 default; the screen shows profit per cup (measured).
- Hot, sunny days bring more buyers and tolerate higher prices; cold and rainy days the reverse (help). The Mall is indoors and reverses the weather effect (help).
- Customer types differ in budget: kids are price-sensitive, business people pay when thirsty (help). Each location has its own mix.
- Missed sales count customers who left over price or waiting time (help, measured).
- **Open**: the demand curve (visitors as a function of temperature, weather, location, popularity and advertising) and each type's price tolerance. The next sessions should hold everything constant but price on comparable days.

## Popularity and satisfaction

Each location tracks both separately (help):

- **Popularity** is the share of people at the location who know your stand. It only rises over time and grows faster with advertising and visible upgrades. The Suburbs gives a popularity bonus.
- **Satisfaction** is the share of customers who liked your lemonade, driven by the recipe.
- Together they drive how many people come to the stand.

## Advertising

A daily amount, starting at $0 (measured; **open**: step size and the effect curve). It helps most when popularity is low, such as in a new location (help).

## Staff (daily wages)

| Staff | Wage | Effect (help) |
|---|---|---|
| Martine the Cashier | $60/day | serves customers faster |
| Simon the Lemon | $80/day | entertains the line so customers wait longer |

## Upgrades (one-time purchases)

| Upgrade | Price | Effect (help) |
|---|---|---|
| High Output Citrus Juicer | $49.99 | faster pitcher refills |
| ShadeMaker 3000 Canopy | $129.99 | keeps waiting customers happy on hot days; more visibility |
| Miracle 9000 Power Juicer | $149.99 | much faster pitcher refills |
| EZserve Cash Register | $249.99 | faster serving |
| Mr. Fridge | $249.99 | lemons stay fresh for days |
| Ice-O-Matic Ice Dispenser | $399.99 | less ice wasted |
| Classic Stand | $449.99 | more storage and visibility, serves more customers |
| High-Five Sound System | $799.99 | visibility and popularity |
| Lemon Stand | $999.99 | big storage, very visible |
| Bright Lights Neon System | $1,249.99 | draws customers from further away |
| Take2 Lemonade Dispenser | $1,599.99 | faster serving and pitcher filling |
| High Output Automatic Ice Maker | $2,599.99 | unlimited ice; needs the Lemon or Castle stand |
| Castle Stand | $9,999.99 | top stand; required for the Magic Gardens |

Prices are measured. **Open**: the size of each effect.

## Locations (daily rent)

| Location | Rent | Character (help) |
|---|---|---|
| The Suburbs | free | few customers, popularity bonus; the starting spot |
| The Park | $10 | decent crowd, cheap; many price-sensitive kids |
| Downtown | $30 | business people with money who hate waiting |
| The Train Station | $30 | commuters and tourists in a hurry |
| The Beach | $40 | excellent on hot sunny days |
| The Mall | $50 | indoors: busy on cold and rainy days |
| The Marina | $50 | rich onlookers on sunny afternoons |
| The Old Square | $100 | tourists who pay high prices; visibility matters |
| The Magic Gardens | $100 | huge but unpredictable crowds and competition; people tolerate lines; needs a top stand |
| The Hexa-Stad | $150 | huge crowds on game days; depends on the home team |

Rents are measured.

## News events

Each morning has one headline that changes conditions for a location or the whole town. The original has about 80, grouped by place: suburbs (a mayor's visit, a concert drawing people away, a crime alert), park (a free concert, escaped lions, mosquitoes), beach (a surf contest, sharks, a UV alert), downtown (a parade, sewage problems), mall (a huge sale, a boycott), marina, train station, amusement park, old square, stadium (a losing streak, kids' day), town-wide economy (a tax refund, a stock market crash), weather (a heat wave, a cold snap, smog), patience (a full moon making people impatient, free yoga classes) and lemonade trends (a lemonade mania, sweet drinks blamed for obesity). **Open**: each event's numeric effect.

## Modes and records

- **Career**: open-ended, with eight save slots. Company names are limited to nine upper-case characters (measured).
- **Challenge**: 30 days to earn the most.
- **Highlights**: best month for revenue, earnings and gross margin; longest lifespan; best day; challenge earnings; total cups sold. Online rankings (the "Lemonade Stock Exchange") used a server that no longer exists.
- Career ranks run from *Nobody*, *Work-shy* and *Under-achiever* up through *Workaholic*, *Gifted*, *Manager*, *Capitalist* and *Big Boss* to *Tycoon* (**open**: thresholds).
- The main menu shows a rotating business quote.

## Friction to fix in the remix

- Fixed 640 × 480 window, no scaling.
- Packs can only be bought one at a time, and every purchase needs a confirmation.
- Lemonade left in the pitcher and melted ice are lost without a clear warning beforehand.
- Leaving the company name empty shows "You already have a company with that name".
- Nine-character upper-case company names.
- Reaction bubbles must be clicked one by one to learn what customers think.
- No undo, no recipe presets, no restocking help.
