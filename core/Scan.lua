module 'aux.core.scan'

include 'T'
include 'aux'

local info = require 'aux.util.info'
local history = require 'aux.core.history'

local PAGE_SIZE = 50


KM_NULL_STATE  = 0
KM_PREQUERY    = 1
KM_INQUERY     = 2
KM_POSTQUERY   = 3
KM_ANALYZING   = 4

do
	local scan_states = {}

	function M.start(params)
		local old_state = scan_states[params.type]
		if old_state then
			abort(old_state.id)
		end
		do (params.on_scan_start or nop)() end
		local thread_id = thread(scan)
		scan_states[params.type] = {
			id = thread_id,
			params = params,
		}
		return thread_id
	end

	function M.abort(scan_id)
		local aborted = T
		for type, state in pairs(scan_states) do
			if not scan_id or state.id == scan_id then
				kill_thread(state.id)
				scan_states[type] = nil
				tinsert(aborted, state)
			end
		end
		for _, state in pairs(aborted) do
			do (state.params.on_abort or nop)() end
		end
	end

	function M.stop()
		state.stopped = true
	end

	function complete()
		local on_complete = state.params.on_complete
		scan_states[state.params.type] = nil
		do (on_complete or nop)() end
	end

	function get_state()
		for _, state in pairs(scan_states) do
			if state.id == thread_id then
				return state
			end
		end
	end
end

function get_query()
	if state.params.type == 'list' then
		return state.params.queries[state.query_index]
	else
		return empty
	end
end

function total_pages(total_auctions)
	if query and query.blizzard_query and query.blizzard_query.get_all then
		return 1
	end
	return ceil(total_auctions / PAGE_SIZE)
end

function last_page(total_auctions)
	if query and query.blizzard_query and query.blizzard_query.get_all then
		return 0
	end
	local last_page = max(total_pages(total_auctions) - 1, 0)
	local last_page_limit = query.blizzard_query.last_page or last_page
	return min(last_page_limit, last_page)
end

function scan()
	if state.params.type ~= 'list' then
		return scan_page()
	end

	
	
	state.dup_query = state.dup_query or {prevPage=nil, numDupPages=0}

	state.query_index = state.query_index and state.query_index + 1 or 1
	if query and not state.stopped then
		state.processing_state = KM_PREQUERY
		state.page_is_last = nil
		do (state.params.on_start_query or nop)(state.query_index) end
		if query.blizzard_query then
			if (query.blizzard_query.first_page or 0) <= (query.blizzard_query.last_page or huge) then
				state.page = query.blizzard_query.first_page or 0
				state.processing_state = KM_PREQUERY
				return submit_query()
			end
		else
			state.page = nil
			return scan_page()
		end
	end
	return complete()
end

do
	local function submit()
		state.processing_state = KM_INQUERY
		state.last_list_query = GetTime()
		local blizzard_query = query.blizzard_query or T
		QueryAuctionItems(
			blizzard_query.name,
			blizzard_query.min_level,
			blizzard_query.max_level,
			blizzard_query.slot,
			blizzard_query.class,
			blizzard_query.subclass,
			state.page,
			blizzard_query.usable,
				blizzard_query.quality,
				blizzard_query.get_all
		)
		state.processing_state = KM_POSTQUERY
		return wait_for_results()
	end
	function submit_query()
		if state.stopped then return end
		return when(CanSendAuctionQuery, submit)
	end
end

function scan_page(i)
	i = i or 1

	if not state.page then
		_,  state.total_auctions = GetNumAuctionItems(state.params.type)
	end

		local page_size = PAGE_SIZE
		if state.params.type == 'list' and query.blizzard_query and query.blizzard_query.get_all and state.total_auctions then
			page_size = state.total_auctions
		end
		if state.params.type == 'list' and i > page_size then
		do (state.params.on_page_scanned or nop)() end
		
		
		if query.blizzard_query and state.page and state.total_auctions and state.page >= last_page(state.total_auctions) then
			state.page_is_last = true
		end
			if query.blizzard_query and query.blizzard_query.get_all then
				if state.get_all_pages and state.get_all_page ~= state.get_all_pages then
					state.get_all_page = state.get_all_pages
					do (state.params.on_page_loaded or nop)(state.get_all_page, state.get_all_pages, 0) end
				end
			end
			if query.blizzard_query and not state.page_is_last and not query.blizzard_query.get_all then
			state.page = (state.page or 0) + 1
			state.processing_state = KM_PREQUERY
			return submit_query()
		else
			do (state.params.on_end_query or nop)(query, state.total_auctions, state.page, state.page_is_last) end
			return scan()
		end
	elseif state.params.type ~= 'list' and i > state.total_auctions then
		return complete()
	end

	local auction_info
	if state.params.type == 'list' and state.params.fast_extract then
		local link = GetAuctionItemLink('list', i)
		if link then
			local item_id, suffix_id = info.parse_link(link)
			local name, texture, count, _, _, _, _, _, buyout_price, _, _, owner, sale_status = GetAuctionItemInfo('list', i)
			auction_info = O(
				'item_key', (tonumber(item_id) or 0) .. ':' .. (tonumber(suffix_id) or 0),
				'item_id', tonumber(item_id) or 0,
				'suffix_id', tonumber(suffix_id) or 0,
				'link', link,
				'name', name,
				'texture', texture,
				'count', count,
				'aux_quantity', count,
				'buyout_price', buyout_price,
				'owner', owner,
				'sale_status', sale_status or 0
			)
		end
	else
		auction_info = info.auction(i, state.params.type)
	end
	if auction_info and (auction_info.owner or state.params.ignore_owner or aux_ignore_owner) then
		auction_info.index = i
		auction_info.page = state.page
		auction_info.blizzard_query = query.blizzard_query
		auction_info.query_type = state.params.type
		if not state.params.skip_history then
			history.process_auction(auction_info)
		end
		if not query.validator or query.validator(auction_info) then
			do (state.params.on_auction or nop)(auction_info) end
		end
	end

		if query.blizzard_query and query.blizzard_query.get_all then
			local chunk = state.get_all_chunk or 200
			if chunk > 0 and (i % chunk) == 0 then
				state.get_all_page = (state.get_all_page or 0) + 1
				do (state.params.on_page_loaded or nop)(state.get_all_page, state.get_all_pages or 1, 0) end
				return wait(later(0), scan_page, i + 1)
			end
		end
		return scan_page(i + 1)
end

function accept_results()
	local num_batch_auctions
	num_batch_auctions, state.total_auctions = GetNumAuctionItems(state.params.type)
	state.processing_state = KM_ANALYZING
		if query.blizzard_query and query.blizzard_query.get_all then
			state.page_is_last = true
			state.get_all_chunk = state.params.chunk_size or 2000
			state.get_all_pages = max(ceil((state.total_auctions or 0) / state.get_all_chunk), 1)
			state.get_all_page = 0
			return scan_page()
		end
	
	state.page_is_last = (num_batch_auctions or 0) < PAGE_SIZE
	if query.blizzard_query and state.page and state.total_auctions and state.page >= last_page(state.total_auctions) then
		state.page_is_last = true
	end
	
	if state.params.type == 'list' and state.dup_query and check_for_duplicate_page(state.dup_query, state.page) then
		return submit_query()
	end
	do
		(state.params.on_page_loaded or nop)(
			state.page - (query.blizzard_query.first_page or 0) + 1,
			last_page(state.total_auctions) - (query.blizzard_query.first_page or 0) + 1,
			total_pages(state.total_auctions) - 1
		)
	end
	return scan_page()
end



function check_for_duplicate_page(q, pagenum)
	local numOnPage = GetNumAuctionItems('list')
	local thisPage = {numOnPage = numOnPage, items = {}, pagenum = pagenum}

	if q.prevPage and q.prevPage.pagenum == pagenum then
		return false
	end

	if numOnPage == 0 then
		q.prevPage = thisPage
		return false
	end

	local prevPage = q.prevPage
	local dupPageFound = true
	local allItemsIdentical = true

	for i = 1, numOnPage do
		local name, _, count, _, _, _, minBid, _, buyoutPrice, bidAmount = GetAuctionItemInfo('list', i)
		local idstr = (name or '') .. '_' .. (count or 0) .. '_' .. (minBid or 0) .. '_' .. (buyoutPrice or 0) .. '_' .. (bidAmount or 0)
		thisPage.items[i] = idstr

		if not prevPage or idstr ~= prevPage.items[i] then
			dupPageFound = false
		end
		if i > 1 and allItemsIdentical and thisPage.items[i] ~= thisPage.items[i-1] then
			allItemsIdentical = false
		end
	end

	if prevPage and prevPage.numOnPage ~= thisPage.numOnPage then
		dupPageFound = false
	elseif dupPageFound and allItemsIdentical then
		
		dupPageFound = false
	end

	if dupPageFound then
		q.numDupPages = (q.numDupPages or 0) + 1
		
		if q.numDupPages > 3 then
			q.prevPage = thisPage
			q.numDupPages = 0
			return false
		end
		return true
	end

	q.prevPage = thisPage
	q.numDupPages = 0
	return false
end

function wait_for_results()
    local updated, last_update
    local listener_id = event_listener('AUCTION_ITEM_LIST_UPDATE', function()
        last_update = GetTime()
        updated = true
    end)
    local timeout = later(5, state.last_list_query)
    local ignore_owner = state.params.ignore_owner or aux_ignore_owner
	return when(function()
		if not last_update and timeout() then
			return true
		end
		if last_update and GetTime() - last_update > 5 then
			return true
		end
		
		if updated and (ignore_owner or owner_data_complete()) then
			return true
		end
		updated = false
	end, function()
		kill_listener(listener_id)
		if not last_update and timeout() then
			return submit_query()
		else
			return accept_results()
		end
	end)
end

function owner_data_complete()
    for i = 1, PAGE_SIZE do
        local auction_info = info.auction(i, 'list')
        if auction_info and not auction_info.owner then
	        return false
        end
    end
    return true
end