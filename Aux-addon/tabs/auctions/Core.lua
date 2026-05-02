module 'aux.tabs.auctions'

include 'T'
include 'aux'

local scan_util = require 'aux.util.scan'
local scan = require 'aux.core.scan'
local money = require 'aux.util.money'
local filter_util = require 'aux.util.filter'
local info = require 'aux.util.info'

TAB 'Auctions'

auction_records = T

function LOAD()
	event_listener('AUCTION_OWNED_LIST_UPDATE', scan_auctions)
end

function OPEN()
    frame:Show()
    GetOwnerAuctionItems()
end

function CLOSE()
    frame:Hide()
end

function update_listing()
    listing:SetDatabase(auction_records)
end

function update_total_sold()
	if not total_sold_text then return end
	local sold_total = 0
	local posted_total = 0
	for _, record in ipairs(auction_records) do
		local price = (record.high_bid or 0) > 0 and record.high_bid or ((record.buyout_price or 0) > 0 and record.buyout_price or (record.start_price or 0))
		posted_total = posted_total + (price or 0)
		if (record.sale_status or 0) == 1 then
			sold_total = sold_total + (price or 0)
		end
	end
	local has_sold = sold_total > 0

	if has_sold and total_post_text then
		total_sold_text:ClearAllPoints()
		total_sold_text:SetPoint('LEFT', totals_frame, 'LEFT', 0, 0)
		total_sold_text:SetJustifyH('LEFT')
		total_sold_text:SetText('Total sold: ' .. money.to_string(sold_total, true, true))

		total_post_text:ClearAllPoints()
		total_post_text:SetPoint('RIGHT', totals_frame, 'RIGHT', 0, 0)
		total_post_text:SetJustifyH('RIGHT')
		total_post_text:SetText('Total posted: ' .. money.to_string(posted_total, true, true))
		total_post_text:Show()
	else
		total_sold_text:ClearAllPoints()
		total_sold_text:SetPoint('LEFT', totals_frame, 'LEFT', 0, 0)
		total_sold_text:SetPoint('RIGHT', totals_frame, 'RIGHT', 0, 0)
		total_sold_text:SetJustifyH('LEFT')
		total_sold_text:SetText('Total posted: ' .. money.to_string(posted_total, true, true))
		if total_post_text then
			total_post_text:SetText('')
			total_post_text:Hide()
		end
	end
end

function M.scan_auctions()

    status_bar:update_status(0, 0)
    status_bar:set_text('Scanning auctions...')

    wipe(auction_records)
    update_listing()
    scan.start{
        type = 'owner',
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

local list_scan_id

local function start_list_scan(queries, label)
	if list_scan_id then
		scan.abort(list_scan_id)
		list_scan_id = nil
	end
	status_bar:update_status(0, 0)
	status_bar:set_text(label or 'Scanning auctions...')
	local current_query = 0
	local total_queries = getn(queries)
	list_scan_id = scan.start{
		type = 'list',
		ignore_owner = true,
		queries = queries,
		on_start_query = function()
			current_query = current_query + 1
		end,
		on_page_loaded = function(page, total_pages)
			total_pages = max(total_pages, 1)
			page = min(page, total_pages)
			if total_queries > 1 then
				status_bar:update_status((current_query - 1) / total_queries, page / total_pages)
				status_bar:set_text(format('%s %d / %d (Page %d / %d)', label or 'Scanning', current_query, total_queries, page, total_pages))
			else
				status_bar:update_status(page / total_pages, 0)
				status_bar:set_text(format('%s Page %d / %d', label or 'Scanning', page, total_pages))
			end
		end,
		on_complete = function()
			status_bar:update_status(1, 1)
			status_bar:set_text('Scan complete')
		end,
		on_abort = function()
			status_bar:update_status(1, 1)
			status_bar:set_text('Scan aborted')
		end,
	}
end

function full_scan()
	start_list_scan({O('blizzard_query', T)}, 'Full Scan')
end

function fast_scan()
	local history_data = faction_data'history' or T
	local queries = T
	local added = T
	local limit = 200
	for item_key, _ in pairs(history_data) do
		local item_id = tonumber(strmatch(item_key, '^(%d+)'))
		if item_id and not added[item_id] then
			local item = info.item(item_id)
			if item and item.name then
				local q = filter_util.query(item.name .. '/exact')
				q.blizzard_query.first_page = 0
				q.blizzard_query.last_page = 0
				tinsert(queries, O('validator', q.validator, 'blizzard_query', q.blizzard_query))
				added[item_id] = true
			end
		end
		if getn(queries) >= limit then break end
	end
	if getn(queries) == 0 then
		status_bar:update_status(1, 1)
		status_bar:set_text('Fast Scan: no history items')
		return
	end
	start_list_scan(queries, 'Fast Scan')
end

do
    local scan_id = 0
    local IDLE, SEARCHING, FOUND = T, T, T
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
            function() state = IDLE; listing:RemoveAuctionRecord(record) end,
            function(index)
                state = FOUND
                found_index = index

                cancel_button:SetScript('OnClick', function()
                    if scan_util.test(record, index) and listing:ContainsRecord(record) then
                        cancel_auction(index, function() listing:RemoveAuctionRecord(record) end)
                    end
                end)
                cancel_button:Enable()
            end
        )
    end

    function on_update()
        if state == IDLE or state == SEARCHING then
            cancel_button:Disable()
        end

        if state == SEARCHING then return end

        local selection = listing:GetSelection()
        if not selection then
            state = IDLE
        elseif selection and state == IDLE then
            find_auction(selection.record)
        elseif state == FOUND and not scan_util.test(selection.record, found_index) then
            cancel_button:Disable()
            if not cancel_in_progress then state = IDLE end
        end
    end
end