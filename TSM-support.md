# TSM Integration for Aux-addon

## Problem Statement

When both **aux-addon** and **TradeSkillMaster (TSM)** are installed, TSM's auction house tabs do not appear inside aux-addon's custom UI. This forces users to click the **"Blizzard UI"** button to temporarily reveal `AuctionFrame` just to access TSM functionality, then switch back.

### Root Cause

- **aux-addon** intercepts `AUCTION_HOUSE_SHOW` and hides `AuctionFrame`, showing its own `AuxFrame`.
- **TSM** creates content frames **parented to `AuctionFrame`**. When `AuctionFrame` is hidden, all child frames disappear.

## Goal

Seamlessly embed TSM auction modules as tabs inside `AuxFrame` when TSM is present, while maintaining full native TSM functionality when the user switches to the Blizzard UI.

## Architecture Overview

```
┌─────────────────────────────────────────────┐
│  AuctionFrame (Blizzard, normally hidden)   │
│  ┌───────────────────────────────────────┐  │
│  │ AuctionFrameTab1 (Browse)             │  │
│  │ AuctionFrameTab2 (Bids)               │  │
│  │ AuctionFrameTab3 (Auctions)           │  │
│  │ AuctionFrameTab4 (TSM_Shopping)       │◄─┼── TSM creates these
│  │ AuctionFrameTab5 (TSM_Auctioning)     │◄─┼── when modules register
│  └───────────────────────────────────────┘  │
│  ┌───────────────────────────────────────┐  │
│  │ TSM content frames (parented here)    │◄─┼── hidden when AuxFrame shown
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  AuxFrame (aux-addon custom UI)             │
│  ┌───────────────────────────────────────┐  │
│  │ Search | Post | Auctions | Bids      │  │
│  │ | Scan | [TSM Shopping] [TSM AH] ... │◄─┼── new: Aux tabs for TSM
│  └───────────────────────────────────────┘  │
│  ┌───────────────────────────────────────┐  │
│  │ AuxFrame.content (render area)        │  │
│  │  ┌─────────────────────────────────┐  │  │
│  │  │ TSM frame (reparented here)    │◄─┼── shown when TSM tab active
│  │  └─────────────────────────────────┘  │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

## Integration Strategy

### 1. Soft Dependency

Add `OptionalDeps: TradeSkillMaster` to `Aux-addon.toc`. This ensures aux loads **after** TSM core, but does **not** error if TSM is absent.

### 2. Hook TSM Registration

TSM modules register auction tabs via:

```lua
TSM:RegisterAuctionFunction(moduleName, callbackShow, callbackHide)
```

This function (in `TradeSkillMaster/Auction/AuctionFrame.lua`):
1. Creates a content `Frame` parented to `AuctionFrame`
2. Creates an `AuctionFrameTabN` button on the Blizzard tab bar
3. Stores the frame reference in `private.auctionTabs[]`
4. The content frame has `.tab.isTSMTab == moduleName`

**Our hook** intercepts this call, captures the created frame, and registers a corresponding Aux tab.

### 3. Frame Reparenting

When an Aux tab for a TSM module is selected:
- **Reparent** the TSM content frame from `AuctionFrame` to `AuxFrame.content`
- **Show** the frame — TSM's `OnShow` script auto-calls `callbackShow(self)`
- Frame is already `SetAllPoints()` within its new parent, so it fills AuxFrame.content

When the Aux tab is deselected or AuxFrame hides:
- **Hide** the frame — TSM's `OnHide` script auto-calls `callbackHide()`

When user clicks **"Blizzard UI"** button:
- **Reparent** all TSM frames back to `AuctionFrame`
- This restores native TSM behavior instantly

### 4. State Synchronization

| Event | Action |
|-------|--------|
| `AUCTION_HOUSE_SHOW` | AuxFrame shown; TSM frames reparented to AuxFrame.content if any Aux TSM tab is active |
| `AUCTION_HOUSE_CLOSED` | AuxFrame hidden; TSM frames stay wherever they are |
| Click TSM Aux tab | Show that TSM frame inside AuxFrame.content |
| Click non-TSM Aux tab | Hide all TSM frames |
| Click "Blizzard UI" | Reparent all TSM frames to `AuctionFrame`; show native Blizzard UI |

## Data Flow

```
TSM:RegisterAuctionFunction()
    └── private:CreateTSMAHTab()           (original TSM code)
            └── creates frame F on AuctionFrame
            └── creates tab button T
    └── [HOOK] aux_tsm.on_tsm_register()
            └── scans AuctionFrame:GetChildren()
            └── finds F where F.tab.isTSMTab == moduleName
            └── stores F in aux_tsm.frames[moduleName]
            └── calls TAB(moduleName)      (aux-addon tab API)
                    └── creates Aux tab
                    └── sets OPEN/CLOSE handlers

User clicks TSM tab in Aux
    └── aux tab OPEN handler
            └── aux_tsm.show_module(moduleName)
                    └── reparents F to AuxFrame.content
                    └── F:Show()           (triggers TSM OnShow → callbackShow)

User clicks non-TSM tab in Aux
    └── aux tab CLOSE handler
            └── F:Hide()                   (triggers TSM OnHide → callbackHide)

User clicks "Blizzard UI"
    └── Frame.lua blizzard_ui_button OnClick
            └── [HOOK] aux_tsm.restore_native()
                    └── reparents all F back to AuctionFrame
                    └── AuctionFrame:Show()
```

## Implementation Files

### `core/Tsm_integration.lua` (new)

Main integration module. Implements:
- `on_tsm_register(moduleName)` — hook callback
- `show_module(moduleName)` — reparent + show
- `hide_module(moduleName)` — hide
- `restore_native()` — return all frames to AuctionFrame
- Registration of Aux tabs via `TAB()` API

### `Aux-addon.toc` (edit)

Add `OptionalDeps: TradeSkillMaster` and include `core/Tsm_integration.lua` after `core/Tooltip.lua`.

### `Frame.lua` (minor edit)

The "Blizzard UI" button's `OnClick` needs a hook point to call `restore_native()` before showing `AuctionFrame`.

## Design Constraints

1. **No hard dependency on TSM** — use runtime checks (`TSM and TSM.RegisterAuctionFunction`) and `OptionalDeps`
2. **No modification of TSM files** — all integration is from aux side via hooks and reparenting
3. **Preserve native TSM behavior** — when Blizzard UI is active, TSM works exactly as stock
4. **Handle late registration** — TSM modules may load after AH opens; hook must be live
5. **Handle multiple modules** — Shopping, Auctioning, Crafting, etc. each get their own Aux tab
6. **Frame strata safe** — reparented frames must remain interactive within AuxFrame

## Testing Checklist

- [ ] Load with TSM absent — no errors, normal Aux behavior
- [ ] Load with TSM present — TSM tabs appear in Aux
- [ ] Click TSM tab in Aux — TSM module shows and is functional
- [ ] Click non-TSM Aux tab — TSM module hides cleanly
- [ ] Click "Blizzard UI" — native TSM tabs work on Blizzard frame
- [ ] Click "Close" on AuxFrame — no TSM orphans or errors
- [ ] Open AH again after Blizzard UI — Aux tabs still include TSM
- [ ] Multiple TSM modules — each appears as separate Aux tab

## Future Enhancements (out of scope)

- Collapse multiple TSM modules into a single "TSM" dropdown tab to save horizontal space
- TSM frame scaling to match AuxFrame's `aux_scale` setting
- TSM minimap button / menu integration

## References

- `TradeSkillMaster/Auction/AuctionFrame.lua` — TSM tab creation
- `TradeSkillMaster/Core/Modules.lua` — `TSMAPI:NewModule()` and `auctionTab` field
- `aux-addon/Aux-addon.lua` — `TAB()` API, `on_tab_click()`, event handling
- `aux-addon/Frame.lua` — `AuxFrame` creation, tab container, "Blizzard UI" button
