# Aux-addon (WoW 3.3.5a)

Auction House UI replacement.

**Version:** 2.2.1 
**Authors:** shirsig, Jdi

## Key changes

### Hotkeys
- **Shift OR Alt** inserts the item into Aux search (modified item click).
- **Right-click bag item** while Aux is open: routes to the active tab (Post = select for listing, Search = exact search). Hold Shift/Ctrl/Alt to bypass and use/equip normally.
- Row actions (works with **Shift OR Alt**):
  - **Search tab**: Left Click = buyout, Right Click = bid
  - **Bids tab**: Left Click = buyout, Right Click = bid
  - **Auctions tab**: Click = cancel

### Tooltip: Value + Historical
- **Value**: last Fast/Full Scan minimum buyout per item.
- **Historical**: historical value from stored scan history.

### Scan tab
- **Full Scan**: classic Aux scan (page-by-page, full stats).
- **Fast Scan (Auctionator-like)**: fast per-category scan (no QueryAll) intended to avoid freezes/disconnects.
- Shows last scan timestamp and live progress (page, pages scanned, elapsed, ETA).
- Stop button appears only while a scan is running.

### Scanning internals
- Scan state machine (KM_PREQUERY/KM_INQUERY/KM_POSTQUERY/KM_ANALYZING).
- Last-page detection: if a page returns **< 50** results, the query is treated as finished.
- Duplicate-page protection (retries if the server returns the same page again).

### Buyout X items + cancel
- **Shift + Left Click** on a result row opens a quantity popup with item icon/name, total cost preview and progress.
- Buys the cheapest matching lots until the requested amount is reached or no more lots.
- Safety: if the next lot is >= **300%** of Value, the series stops and requires a second confirmation.
- Cancel Buyout stops the series immediately.

### Multi Buyout (Search tab)
- Button in Search results: **Multi Buyout**.
- Uses the same quantity popup and safety rules.

### Auctions tab
- Shows **Total sold** at the bottom (sum of sold auctions in the current owner scan).
- Fixes Time Left display for owner auctions:
  - Active auctions show time remaining
  - Sold auctions show **Sold**
  - Expired auctions show **Expired**
- Sold/unsold/expired auctions are not merged into the same row group.

## Installation
1. Put the folder **Aux-addon** into `Interface\AddOns\`.
2. Restart WoW or `/reload`.
