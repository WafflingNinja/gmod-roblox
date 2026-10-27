# Making money (plan, nothing built yet)

Rule: sell fun and convenience, never power. A sandbox dies when paying players win fights. Everything here fits an all-ages rating.

## How players pay
Players always pay in **Robux**. You get roughly **70%** of the price (Roblox keeps ~30%), paid out later as Robux.

| Kind | What it is | Good for |
|---|---|---|
| **Game pass** | Bought once, owned forever | Perks: colors, slots, VIP |
| **Developer product** | Can be bought again and again | Tips/donations, one-off fun |
| **Private server** | Monthly, the buyer gets their own server | Friends building together. Biggest earner for Gmod-style games |
| **Premium Payouts** | Free. Roblox pays you when Premium players spend time in your game | Nothing to build |

Creating a pass: Creator Hub > your experience > **Monetization > Passes > Create**. Roblox's own steps mention no fee. Price is up to you.

## Pass ideas (price in Robux)

| Pass | What it does | Price | Effort |
|---|---|---|---|
| **Physgun Colors** | Pick the beam / glow color of your physgun and gravity gun | 99 | small |
| **More Dupe Slots** | 10 -> 30 saved dupes | 99 | small |
| **Builder+** | Prop limit 150 -> 250 (watch server lag) | 149 | small |
| **VIP** | Gold name tag in chat, golden physgun, VIP spawn pad | 199 | medium |
| **NPC Pack** | NPC limit 10 -> 20, plus extra NPC skins | 149 | medium |
| **Sports Car** | An extra fast car in the Cars tab | 149 | medium |

Developer products: **Tip the dev** at 25 / 100 / 500 Robux. Fun to add a thank-you line from RostikPro12308.

Private servers: turn them on in the experience settings, **50-100 Robux a month**.

## Don't
- Guns that do more damage, more health, anything that wins PvP.
- Paid random rewards ("loot boxes"). Strict rules, banned in some countries. The voice line is fine as a joke.
- Paid access to the whole game. It cuts the player count to almost nothing.

## Making sure nobody pays and gets nothing
The pass itself is safe: once someone buys it, Roblox records that they own it forever. Even if our script breaks that day, they still own it, and the perk shows up the next time they join once it's fixed.

How the code will do it (server only):
1. When a player joins: ask Roblox "does this player own pass X?" (`UserOwnsGamePassAsync`), retry if Roblox doesn't answer, and give the perk.
2. When someone buys in-game (`PromptGamePassPurchaseFinished`): give the perk right away, no rejoin needed.
3. Everything a pass changes goes through one module (`Services/Passes.luau`), so each perk is checked in one place.

### Testing it before anyone pays
1. **In Studio:** buying in Studio is a test purchase. You aren't charged. Check the perk shows up right away.
2. **Rejoin test:** Studio test purchases don't make you really own the pass. To test "owned on join", make a throwaway pass priced **1 Robux**, buy it for real (you have 41), check you get the perk after rejoining, then delete it.
3. **Two accounts:** Team Test or a friend. One owns the pass and one doesn't. Check only the owner gets it.
4. **First real sale:** watch the server log (F9 > Server) the first time. Each grant prints `Passes: <name> -> <player>`.

## Ads with Robux
- 1 Ad Credit = about 263 Robux, about $1 of ads. You need some passes sold first.
- Creator Hub > Billing & payments > Payment settings > **Robux** tab > enter the amount > Buy. Can't be undone.
- The minimum used to be 10 credits per purchase, about 2,630 Robux. Check the screen.

## Order to do it
1. Private servers (no code).
2. Physgun Colors + Tip the dev (small, tests the whole pass flow).
3. VIP.
4. The rest, if people buy.
