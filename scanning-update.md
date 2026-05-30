# Scanning System Improvements

Analysis of aux's scanning engine (`core/Scan.lua`) compared to Auctionator and TSM's `LibAuctionScan-1.0`, with concrete recommendations for improving reliability on WoW 3.3.5a (ChromieCraft).

---

## Context

aux uses a cooperative threading model (`Control.lua`) to drive scanning. Queries are submitted via `when(CanSendAuctionQuery, submit)`, results are awaited via an `AUCTION_ITEM_LIST_UPDATE` event listener with a 5-second timeout, and page data is processed recursively via `scan_page(i)`.

The primary failure mode reported: full scans (`getAll = true`) and page-by-page scans are less reliable than equivalent scans in Auctionator or TSM. Items are missed, scans stall, or duplicate pages cause unnecessary re-queries.

---

## 1. Delayed Data-Availability Check for GetAll Scans

### Problem

When aux sends a `getAll` query (`QueryAuctionItems(..., true)`), it listens for `AUCTION_ITEM_LIST_UPDATE` and immediately begins processing in `accept_results()` → `scan_page()`. On 3.3.5a servers, the client may fire this event before all auction data is actually populated in memory. This results in `GetAuctionItemLink("list", i)` returning nil for items that haven't loaded yet.

In `core/Scan.lua:183-186` (fast_extract path):
```lua
local link = GetAuctionItemLink('list', i)
if link then
    -- process item
end
```

Items with nil links are silently skipped and permanently lost from the scan.

### How TSM Solves This

`LibAuctionScan.lua:646-665` — After sending the getAll query, TSM does NOT process data on the first `AUCTION_ITEM_LIST_UPDATE`. Instead, it starts a polling frame:

```lua
dataAvailableFrame.totalDelay = 20  -- max 20 seconds to wait
dataAvailableFrame.delay = 2        -- first check after 2 seconds

local function DataAvailableFrameUpdate(self, elapsed)
    self.delay = self.delay - elapsed
    if self.delay <= 0 then
        if GetNumAuctionItems("list") > 50 then
            -- data is ready
            scanFrame.numShown, scanFrame.totalNum = GetNumAuctionItems("list")
            self:Hide()
            scanFrame:Show()
        else
            self.delay = 1  -- check again in 1 second
        end
    end
end
```

This gives the server up to 20 seconds to fully populate the client's auction cache before processing begins. The `> 50` check is the heuristic: a getAll response always has more than 50 items, so if we still see ≤ 50, the data hasn't arrived yet.

### Recommendation

After receiving `AUCTION_ITEM_LIST_UPDATE` for a getAll query, delay processing by polling until `GetNumAuctionItems("list")` stabilizes (same value on two consecutive checks, 0.5s apart) or exceeds 50. Maximum wait: 15 seconds.

In aux's model, this means replacing the immediate `accept_results()` call with a `when()` condition that verifies data readiness:

```lua
-- In wait_for_results(), for getAll queries:
-- Instead of accepting on first AUCTION_ITEM_LIST_UPDATE,
-- wait until GetNumAuctionItems > 50 and is stable
```

---

## 2. Per-Item Retry in GetAll Processing

### Problem

aux processes getAll results in chunks of 2000 (`state.get_all_chunk`), yielding one frame between chunks via `wait(later(0), scan_page, i + 1)`. Within each chunk, if `GetAuctionItemLink` returns nil for an item, that item is skipped forever. There is no retry mechanism.

`core/Scan.lua:183-186`:
```lua
local link = GetAuctionItemLink('list', i)
if link then
    -- ... extract and process
end
-- if link is nil, we just fall through to scan_page(i + 1)
```

### How TSM Solves This

`LibAuctionScan.lua:606-638` — TSM processes at most 200 items per frame, and has a per-item retry counter:

```lua
for i=1, 200 do
    local link = GetAuctionItemLink("list", self.num)
    local _, _, quantity, _, _, _, _, _, buyout = GetAuctionItemInfo("list", self.num)
    if self.tries == 0 or (link and quantity and buyout) then
        self.num = self.num + 1
        self.tries = 3
        if link then
            private:AddAuctionRecord(self.num)
        end
    else
        self.tries = self.tries - 1
        break  -- stop processing this frame, retry next frame
    end
end
```

Key design:
- Each item gets **3 attempts** across separate frames
- If data isn't ready, processing pauses and resumes next frame
- After 3 failures, the item is skipped (graceful degradation)
- Only 200 items per frame keeps the UI responsive

### Recommendation

Restructure the getAll processing loop in `scan_page()` to:
1. Reduce chunk size from 2000 to 200-500
2. Track a retry counter per-position
3. On nil link: decrement retry counter, break out of chunk, resume next frame
4. After 3 retries on same position: skip and continue

This ensures items that load asynchronously (common on private servers with network jitter) are captured rather than lost.

---

## 3. Soft Retry Before Hard Re-Query

### Problem

When aux receives page data, `wait_for_results()` checks if the data is usable. If `owner_data_complete()` fails or the event times out (5 seconds), aux re-sends the entire query. There is no intermediate step — no attempt to simply re-read the already-loaded page data after a brief delay.

`core/Scan.lua:314-342`:
```lua
local timeout = later(5, state.last_list_query)
return when(function()
    if not last_update and timeout() then return true end  -- timeout → requery
    if updated and (ignore_owner or owner_data_complete()) then return true end
end, function()
    if not last_update and timeout() then
        return submit_query()  -- hard retry only
    else
        return accept_results()
    end
end)
```

This is wasteful: re-querying takes another 4+ seconds of server throttle time, when often the data just needs another 100-200ms to finish loading.

### How TSM Solves This

`LibAuctionScan.lua:392-413` — TSM uses a two-tier retry:

```lua
if dataIsBad or IsDuplicatePage() then
    if status.retries < status.options.maxRetries then  -- default: 3
        if status.hardRetry then
            -- Hard retry: re-send the query
            status.retries = status.retries + 1
            status.timeDelay = 0
            status.hardRetry = nil
            private:SendQuery()
        else
            -- Soft retry: wait 100ms, then re-read same page
            status.timeDelay = status.timeDelay + BASE_DELAY  -- 0.10s
            CreateTimeDelay("updateDelay", BASE_DELAY, private.ScanAuctions)
            -- Escalate to hard retry after 2 seconds of soft retries
            if status.timeDelay >= status.options.retryDelay then  -- default: 2s
                status.hardRetry = true
            end
        end
        return
    end
end
```

Flow:
1. Data incomplete → wait 100ms, re-read (soft retry)
2. Still incomplete after 2 seconds → re-send query (hard retry)
3. Still incomplete after 3 hard retries → give up on this page, move on

### Recommendation

Add a soft-retry phase to `wait_for_results()`. After `AUCTION_ITEM_LIST_UPDATE` fires but data is incomplete (owner nil, link nil), wait 100-200ms and re-check. Only escalate to a full re-query after 2 seconds of failed soft retries. This avoids burning a full 4-second query throttle slot when the data just needs a moment to propagate.

In aux's threading model:
```lua
-- Pseudo-code for the soft-retry loop:
-- wait(later(0.1), function()
--     if data_is_good() then accept_results()
--     elseif soft_retry_time > 2.0 then submit_query()  -- hard retry
--     else wait(later(0.1), ...)  -- soft retry again
--     end
-- end)
```

---

## 4. Clear Sort Before Scanning

### Problem

aux does not reset the auction house sort order before beginning a scan. If the player (or another addon) has set a custom sort on the Browse tab, pages may be returned in a non-default order. This has two consequences:

1. **Duplicate page detection becomes unreliable** — `check_for_duplicate_page()` compares item fingerprints between consecutive pages. If the sort changes mid-scan (due to server-side reordering), a legitimate new page may appear identical to the previous one, or vice versa.

2. **Page boundaries shift** — Sorting by different columns changes which auctions appear on which page. Items can be missed or double-counted.

### How Auctionator and TSM Solve This

Auctionator (`AuctionatorScan.lua:1058`):
```lua
SortAuctionClearSort("list");
```

TSM (`LibAuctionScan.lua:285-291`):
```lua
SortAuctionsAscending("buyout")
SortAuctionsAscending("name")
```

Both explicitly set a known sort state before scanning begins. `SortAuctionClearSort` removes all sort criteria, reverting to the server's default ordering. TSM goes further by setting a specific deterministic order (name + buyout ascending).

### Recommendation

Call `SortAuctionClearSort("list")` at the beginning of `scan()` in `core/Scan.lua`, before the first `submit_query()`. This is a single line addition with zero downside:

```lua
-- In scan(), before first query:
SortAuctionClearSort("list")
```

This ensures all scans start from a known state regardless of what the user or other addons have done to the browse tab.

---

## 5. Reduce GetAll Chunk Size

### Problem

aux processes getAll results in chunks of 2000 items (`core/Scan.lua:235`):
```lua
state.get_all_chunk = state.params.chunk_size or 2000
```

Each chunk runs synchronously within a single frame before yielding via `wait(later(0), scan_page, i + 1)`. Processing 2000 items in one frame means:
- 2000 × `GetAuctionItemLink()` calls
- 2000 × `GetAuctionItemInfo()` calls
- 2000 × table allocations (via `O(...)` in fast_extract)
- Significant frame spike (100-300ms depending on hardware)

### How TSM Solves This

TSM processes **200 items per OnUpdate frame** (`LibAuctionScan.lua:610`):
```lua
for i=1, 200 do
    ...
end
```

This keeps each frame's workload small (~10-15ms), maintaining a responsive UI throughout the scan. Combined with the per-item retry mechanism (point 2), smaller chunks also provide natural retry boundaries.

### Recommendation

Reduce the default `get_all_chunk` from 2000 to **500**. This balances:
- UI responsiveness (each chunk takes ~25-50ms instead of ~150-300ms)
- Scan speed (500 items × 60fps = 30,000 items/sec throughput)
- Retry granularity (if an item fails, we only wait one frame to retry, not the whole 2000-item batch)

The `chunk_size` parameter in `scan_params` is already supported, so callers can override this if they prefer speed over smoothness.

---

## 6. Handle the 42554 GetAll Limit

### Problem

The WoW 3.3.5a client has a known limitation where `getAll` queries can only return approximately 42,554 auctions, even when `totalAuctions` reports a higher number. This is a client-side buffer limit. aux does not detect or handle this case — it processes `numBatchAuctions` items and reports success, but the data is silently incomplete.

### How TSM Solves This

`LibAuctionScan.lua:624-627`:
```lua
-- bug with getall scan only being able to return a max of 42554 auctions
if self.num ~= self.totalNum then
    DoCallback("GETALL_BUG")
end
```

TSM detects when the number of items actually processed differs from `totalAuctions` and fires a callback to notify the user/caller that the scan is incomplete.

### Recommendation

After getAll processing completes, compare `state.total_auctions` against the actual number of items processed. If they differ:

1. Log a warning (visible in the scan UI): "GetAll returned X of Y auctions — data may be incomplete"
2. Optionally: offer to run a per-category scan to fill the gap (aux already has `fast_scan_per_category()` which queries each class/subclass individually)

Detection code (in `scan_page()` after finishing getAll iteration):
```lua
if items_processed < state.total_auctions then
    -- warn: getAll limit reached
end
```

On ChromieCraft, the AH typically has 5,000-20,000 auctions, so this limit is unlikely to be hit. But on larger servers or during peak hours, it's a real concern.

---

## 7. Improve Duplicate Page Detection

### Problem

aux's `check_for_duplicate_page()` (`core/Scan.lua:261-312`) builds item fingerprints using:
```lua
local idstr = (name or '') .. '_' .. (count or 0) .. '_' .. (minBid or 0)
    .. '_' .. (buyoutPrice or 0) .. '_' .. (bidAmount or 0)
```

This is missing:
- **Item link** — two different items can share the same name (e.g., "Pattern: ..." with different item IDs)
- **Seller** — important for distinguishing otherwise-identical auctions
- **minIncrement** — part of the auction's unique identity

The "all items identical" edge case is handled (line 286-288), but the detection of "same page but items shifted" is not. If one auction expires or is bought between queries, the entire page shifts by one position, making every fingerprint different — this is a false negative (page looks new when it's actually the same data minus one item).

### How TSM Solves This

`LibAuctionScan.lua:222-248`:
```lua
for i=1, GetNumAuctionItems("list") do
    local _, _, count, _, _, _, minBid, minInc, buyout, bid, _, seller = GetAuctionItemInfo("list", i)
    local link = GetAuctionItemLink("list", i)
    local temp = private.pageTemp[i]

    if not prevLink then
        prevLink = link
    elseif prevLink ~= link then
        prevLink = link
        numLinks = numLinks + 1
    end

    if not temp or temp.count ~= count or temp.minBid ~= minBid
        or temp.minInc ~= minInc or temp.buyout ~= buyout
        or temp.bid ~= bid or temp.seller ~= seller
        or temp.link ~= link then
        return false  -- not a duplicate
    end
end

-- Extra check: if all items have the same link, it's probably
-- a wall of identical postings, not a true duplicate page
if numLinks > 1 and private.pageTemp.shown == GetNumAuctionItems("list") then
    return false
end
```

TSM compares **7 fields** per item (including link and seller) and has a smarter "all identical" heuristic based on link diversity rather than string equality.

### Recommendation

Enhance `check_for_duplicate_page()` to:

1. Include `GetAuctionItemLink("list", i)` in the fingerprint (or at least the item ID portion)
2. Include seller in the fingerprint (it's already available from the `GetAuctionItemInfo` call)
3. For the "all items identical" check: count unique links rather than comparing adjacent fingerprint strings

Updated fingerprint:
```lua
local name, _, count, _, _, _, minBid, _, buyoutPrice, bidAmount, _, owner = GetAuctionItemInfo('list', i)
local link = GetAuctionItemLink('list', i) or ''
local idstr = link .. '_' .. (count or 0) .. '_' .. (minBid or 0)
    .. '_' .. (buyoutPrice or 0) .. '_' .. (bidAmount or 0)
    .. '_' .. (owner or '')
```

This is slightly more expensive per item (one extra API call for the link), but duplicate detection only runs once per page (50 items), so the cost is negligible.

---

## Implementation Priority

| Priority | Item | Effort | Risk |
|----------|------|--------|------|
| 1 | Clear sort before scanning (#4) | Trivial (1 line) | None |
| 2 | Delayed data-availability for getAll (#1) | Small | Low — only affects getAll path |
| 3 | Per-item retry in getAll (#2) | Medium | Low — graceful degradation |
| 4 | Soft retry before hard re-query (#3) | Medium | Low — existing timeout is fallback |
| 5 | Reduce chunk size (#5) | Trivial (change default) | None |
| 6 | Improve duplicate detection (#7) | Small | Low — strictly more data in comparison |
| 7 | Handle 42554 limit (#6) | Small | None — informational only |

Items 1-5 directly address scan reliability. Items 6-7 are defensive improvements that prevent silent data loss.
