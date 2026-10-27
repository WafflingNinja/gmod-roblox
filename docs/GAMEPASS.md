# Passes and tips

Rule: sell fun and convenience, never power. A sandbox dies when paying players win fights. Everything here fits an all-ages rating.

**Status (2026-10-27):** icons made, passes being created in Creator Hub **off sale**. No pass code exists yet. Do not put anything on sale until its perk is built and tested (steps below).

## How players pay
Players always pay in **Robux**. You get roughly **70%** of the price (Roblox keeps ~30%).

| Kind | What it is | Good for |
|---|---|---|
| **Game pass** | Bought once, owned forever | Perks |
| **Developer product** | Can be bought again and again | Tips |
| **Private server** | Monthly, the buyer gets their own server | Friends building together. No code: turn on in experience settings, 50-100 Robux/month |
| **Premium Payouts** | Free. Roblox pays for time Premium players spend in the game | Nothing to build |

Creating a pass: Creator Hub > experience > **Monetization > Passes > Create**. Tips: **Monetization > Developer Products**. Roblox's own steps mention no creation fee.

## The list (fill in the IDs)

Icons are in `C:\Users\rosti\Desktop\gamepass-icons` (512x512, made by a Pillow script, original art).

| Kind | Name | Description | Price | Icon | ID |
|---|---|---|---|---|---|
| Pass | Physgun Colors | Pick any color for your physgun and gravity gun beam. | 99 | `1_physgun_colors.png` | |
| Pass | More Dupe Slots | Save up to 30 builds instead of 10. | 99 | `2_more_dupe_slots.png` | |
| Pass | Builder+ | Spawn 100 more props (250 instead of 150). | 149 | `3_builder_plus.png` | |
| Pass | VIP | Gold VIP name tag, golden physgun and a VIP spawn pad. | 199 | `4_vip.png` | |
| Pass | NPC Pack | Spawn twice as many NPCs (20 instead of 10). | 149 | `5_npc_pack.png` | |
| Pass | Sports Car | Unlocks a fast sports car in the Cars tab. | 149 | `6_sports_car.png` | |
| Product | Tip 25 | Say thanks to the dev! | 25 | `7_tip_25.png` | |
| Product | Tip 100 | Big thanks to the dev! | 100 | `7_tip_100.png` | |
| Product | Tip 500 | Legendary thanks to the dev! | 500 | `7_tip_500.png` | |

## Build spec (for the next session)

The user will paste the IDs. Then build, run `scripts/check.sh`, and walk the user through the tests.

**`Shared/PassCatalog.luau`** (pure data, lune-tested): pass key -> `{ id, name }`, product key -> `{ id, name }`. IDs as numbers.

**`Services/Passes.luau`** (server):
- On join (and for players already in game at init): `MarketplaceService:UserOwnsGamePassAsync` per pass, in `pcall` with retry and backoff. Store as Player attributes `Pass_<key> = true` (replicated, the client reads them for UI).
- `MarketplaceService.PromptGamePassPurchaseFinished`: if purchased and the id is ours, set the attribute right away.
- `Passes.has(player, key): boolean` for the other services.
- `MarketplaceService.ProcessReceipt` for the tips: look up the product, thank the player (toast + a RostikPro12308 voice line via `NpcSay` with `nil` model), return `PurchaseGranted`. Unknown product: `NotProcessedYet`. Tips grant nothing, so no DataStore is needed.
- Print `Passes: <key> -> <player>` on every grant.
- Clean up on `PlayerRemoving` (nothing stored outside attributes).

**Where each perk hooks in** (server decides; never trust the client):

| Pass | Change |
|---|---|
| Physgun Colors | New remote `SetBeamColor(paletteIndex)`: rate limit, typeof, index in `Config.PALETTE`, `Passes.has`. Store on the Player attribute `BeamColor`. `PhysgunService` / `GravityGunService` pass it to `Hold.start` instead of `BEAM_COLOR`. Client: color row in the Q menu, shown only with the pass. |
| More Dupe Slots | `DupeService`: slot limit per player (`Config.DUPE_SLOTS` vs 30). The codec and labels must handle 30. Check the DataStore size limit. |
| Builder+ | `Ownership.canSpawn` and `DupeService` cap check: 250 for owners. Watch server physics with several owners. |
| VIP | Chat tag via `TextChatService.OnIncomingMessage` (client) from the `Pass_vip` attribute; gold beam color (VIP overrides Colors); a VIP spawn pad on each map (`MapCatalog`). |
| NPC Pack | `NpcService.canSpawn`: per-player cap 20 for owners (server cap 40 stays). |
| Sports Car | New `car_sports` in `PropCatalog` with `pass = "sports_car"`. `SpawnService` refuses it without the pass. The Q menu shows it with a lock and a buy button (`MarketplaceService:PromptGamePassPurchase`). |

Add each new remote to `default.project.json`, `docs/SECURITY.md` and `docs/ARCHITECTURE.md`.

**Buy buttons:** an M menu "Store" page listing every pass with its icon, price and Buy/Owned state, plus the three tips.

## Testing before anything goes on sale
1. **In Studio:** buying in Studio is a test purchase. Nothing is charged. Check every perk works right away.
2. **Rejoin test:** Studio test purchases don't make you really own the pass. Make a throwaway pass priced **1 Robux**, buy it for real, check the perk after rejoining, then delete it.
3. **Two accounts:** Team Test or a friend. One owns the pass and one doesn't. Check only the owner gets it.
4. **Then** put the passes on sale, one at a time. Watch F9 > Server for `Passes:` lines the first time someone buys.

A bought pass is safe even if a script breaks: Roblox records the ownership forever, and the perk shows up on the next join once it's fixed.

## Don't
- Pay-to-win: more gun damage, more health.
- Paid random rewards (loot boxes). Strict rules, banned in some countries. The voice line is fine as a joke.
- Paid access to the whole game.

## Ads with Robux
- 1 Ad Credit = about 263 Robux (about $1 of ads). It was 285 before RDC 2026.
- Creator Hub > Billing & payments > Payment settings > **Robux** tab. Can't be undone. The minimum used to be 10 credits.
- The parent's credit card is saved in Ads Manager. To remove it: Billing & payments > Payment settings > the card's `...` > Remove. End any running campaign first. Ask the parent before any card payment.
