module 'aux.tabs.bids'

include 'T'
include 'aux'

local info = require 'aux.util.info'
local scan_util = require 'aux.util.scan'
local scan = require 'aux.core.scan'
local money = require 'aux.util.money'

TAB 'Bids'

local function announce_bid_or_buyout(verb, r, qty, price)
	if not r then return end
	local link = r.link
	if not link and r.item_id then
		link = '|cffffffff[item:' .. r.item_id .. ']|r'
	end
	-- Render the item icon 2px taller than the chat line height.
	local _, font_h = DEFAULT_CHAT_FRAME:GetFont()
	local icon_h = floor((font_h or 14) + 2)
	local tex = r.texture and ('|T' .. r.texture .. ':' .. icon_h .. ':' .. icon_h .. ':0:-1|t ') or ''
	local verb_color = (verb == 'Buyout') and '|cff66ccff' or '|cffffd200'
	DEFAULT_CHAT_FRAME:AddMessage('|cffffffff[Auction House]:|r ' .. verb_color .. verb .. '|r ' .. tex .. (link or '') .. ' x' .. (qty or 1) .. ' for ' .. money.to_string(price or 0, true, true))
end

auction_records = {}

function LOAD()
	event_listener('AUCTION_BIDDER_LIST_UPDATE', scan_bids)
end

function OPEN()
    frame:Show()
    GetBidderAuctionItems()
end

function CLOSE()
    frame:Hide()
end

function update_listing()
    listing:SetDatabase(auction_records)
end

function M.scan_bids()

    status_bar:update_status(0, 0)
    status_bar:set_text('Scanning auctions...')

    wipe(auction_records)
    update_listing()
    scan.start{
        type = 'bidder',
        on_auction = function(auction_record)
            tinsert(auction_records, auction_record)
        end,
        on_complete = function()
            status_bar:update_status(1, 1)
            status_bar:set_text('Scan complete')
            update_listing()
        end,
        on_abort = function()
            status_bar:update_status(1, 1)
            status_bar:set_text('Scan aborted')
        end,
    }
end

do
    local scan_id = 0
    local IDLE, SEARCHING, FOUND = 1, 2, 3
    local state = IDLE
    local found_index

    function find_auction(record)
        if not listing:ContainsRecord(record) then return end

        scan.abort(scan_id)
        state = SEARCHING
        scan_id = scan_util.find(
            record,
            status_bar,
            function() state = IDLE end,
            function()
                state = IDLE
                listing:RemoveAuctionRecord(record)
            end,
            function(index)
                state = FOUND
                found_index = index

                if not record.high_bidder then
                    bid_button:SetScript('OnClick', function()
                        if scan_util.test(record, index) and listing:ContainsRecord(record) then
                            local is_buyout = record.bid_price >= record.buyout_price and record.buyout_price > 0
                            place_bid('bidder', index, record.bid_price, function(confirmed)
                                if confirmed then
                                    announce_bid_or_buyout(is_buyout and 'Buyout' or 'Bid', record, record.aux_quantity or 1, record.bid_price)
                                end
                                if is_buyout then
                                    listing:RemoveAuctionRecord(record)
                                else
                                    info.bid_update(record)
                                    listing:SetDatabase()
                                end
                            end)
                        end
                    end)
                    bid_button:Enable()
                else
	                bid_button:Disable()
                end

                if record.buyout_price > 0 then
                    buyout_button:SetScript('OnClick', function()
                        if scan_util.test(record, index) and listing:ContainsRecord(record) then
                            place_bid('bidder', index, record.buyout_price, function(confirmed)
                                if confirmed then
                                    announce_bid_or_buyout('Buyout', record, record.aux_quantity or 1, record.buyout_price)
                                end
                                listing:RemoveAuctionRecord(record)
                            end)
                        end
                    end)
                    buyout_button:Enable()
                else
	                buyout_button:Disable()
                end
            end
        )
    end

    function on_update()
        if state == IDLE or state == SEARCHING then
            buyout_button:Disable()
            bid_button:Disable()
        end

        if state == SEARCHING then return end

        local selection = listing:GetSelection()
        if not selection then
            state = IDLE
        elseif selection and state == IDLE then
            find_auction(selection.record)
        elseif state == FOUND and not scan_util.test(selection.record, found_index) then
            buyout_button:Disable()
            bid_button:Disable()
            if not bid_in_progress then state = IDLE end
        end
    end
end
set_LOAD(LOAD)
