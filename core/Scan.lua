module 'aux.core.scan'

include 'T'
include 'aux'

local info = require 'aux.util.info'
local history = require 'aux.core.history'

local PAGE_SIZE = 50

local function scan_debug(msg)
	if _G.aux_scan_debug then
		print('[AUX SCAN] ' .. msg)
	end
end


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
	scan_debug('scan() entered, type=' .. tostring(state.params.type) .. ' query_index=' .. tostring(state.query_index) .. ' stopped=' .. tostring(state.stopped))
	if state.params.type ~= 'list' then
		return scan_page()
	end

	SortAuctionClearSort('list')

	state.dup_query = state.dup_query or {prevPage=nil, numDupPages=0}

	state.query_index = state.query_index and state.query_index + 1 or 1
	scan_debug('scan() query_index=' .. state.query_index .. ' queries=' .. getn(state.params.queries or T))
	if query and not state.stopped then
		state.processing_state = KM_PREQUERY
		state.page_is_last = nil
		do (state.params.on_start_query or nop)(state.query_index) end
		if query.blizzard_query then
			if (query.blizzard_query.first_page or 0) <= (query.blizzard_query.last_page or huge) then
				state.page = query.blizzard_query.first_page or 0
				state.processing_state = KM_PREQUERY
				scan_debug('scan() -> submit_query() page=' .. state.page)
				return submit_query()
			end
		else
			state.page = nil
			return scan_page()
		end
	end
	scan_debug('scan() -> complete()')
	return complete()
end

	do
	local function submit()
		state.processing_state = KM_INQUERY
		state.last_list_query = GetTime()
		local blizzard_query = query.blizzard_query or T
		scan_debug('submit() QueryAuctionItems page=' .. tostring(state.page) .. ' get_all=' .. tostring(blizzard_query.get_all) .. ' name=' .. tostring(blizzard_query.name))
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
		local is_getall = query.blizzard_query and query.blizzard_query.get_all
		-- For getAll queries the engine also requires the 2nd return value of
		-- CanSendAuctionQuery (canQueryAll); querying when it is false fails
		-- silently (no AUCTION_ITEM_LIST_UPDATE), which previously hung the scan.
		local ready = is_getall
			and function() local can, can_all = CanSendAuctionQuery(); return can and can_all end
			or CanSendAuctionQuery
		scan_debug('submit_query() waiting for CanSendAuctionQuery getall=' .. tostring(is_getall))
		return when(ready, function()
			scan_debug('CanSendAuctionQuery ready, submitting')
			return submit()
		end)
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
		if i == page_size + 1 then
			scan_debug('scan_page() finished page, total_auctions=' .. tostring(state.total_auctions) .. ' items_processed=' .. tostring(state.items_processed) .. ' page_is_last=' .. tostring(state.page_is_last))
		end
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
			if query.blizzard_query and query.blizzard_query.get_all then
				if state.items_processed and state.total_auctions and state.items_processed < state.total_auctions then
					print('GetAll returned ' .. state.items_processed .. ' of ' .. state.total_auctions .. ' auctions — data may be incomplete')
				end
			end
			do (state.params.on_end_query or nop)(query, state.total_auctions, state.page, state.page_is_last) end
			return scan()
		end
	elseif state.params.type ~= 'list' and i > state.total_auctions then
		return complete()
	end

	local auction_info
	if state.params.type == 'list' and state.params.fast_extract then
		local link = GetAuctionItemLink('list', i)
		if not link and query.blizzard_query and query.blizzard_query.get_all then
			-- Per-item retry for getAll: retry up to 3 times across separate frames
			state.get_all_retries = state.get_all_retries or {}
			state.get_all_retries[i] = (state.get_all_retries[i] or 0) + 1
			if state.get_all_retries[i] <= 3 then
				if state.get_all_retries[i] == 1 then
					scan_debug('scan_page() getAll retry item ' .. i .. ' retry=' .. state.get_all_retries[i])
				end
				return wait(later(0), scan_page, i)
			end
			-- After 3 retries, skip this item
			scan_debug('scan_page() getAll SKIP item ' .. i .. ' after 3 retries')
			state.get_all_retries[i] = nil
		end
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
	if auction_info and query.blizzard_query and query.blizzard_query.get_all then
		state.items_processed = (state.items_processed or 0) + 1
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
				scan_debug('scan_page() getAll chunk boundary, get_all_page=' .. state.get_all_page .. '/' .. (state.get_all_pages or '?'))
				do (state.params.on_page_loaded or nop)(state.get_all_page, state.get_all_pages or 1, 0) end
				return wait(later(0), scan_page, i + 1)
			end
		end
		return scan_page(i + 1)
end

function accept_results()
	local num_batch_auctions
	num_batch_auctions, state.total_auctions = GetNumAuctionItems(state.params.type)
	scan_debug('accept_results() num_batch=' .. tostring(num_batch_auctions) .. ' total_auctions=' .. tostring(state.total_auctions) .. ' get_all=' .. tostring(query.blizzard_query and query.blizzard_query.get_all))
	state.processing_state = KM_ANALYZING
		if query.blizzard_query and query.blizzard_query.get_all then
			state.page_is_last = true
			state.get_all_chunk = state.params.chunk_size or 500
			state.get_all_pages = max(ceil((state.total_auctions or 0) / state.get_all_chunk), 1)
			state.get_all_page = 0
			state.items_processed = 0
			scan_debug('accept_results() getAll chunk=' .. state.get_all_chunk .. ' pages=' .. state.get_all_pages)
			return scan_page()
		end
	
	state.page_is_last = (num_batch_auctions or 0) < PAGE_SIZE
	if query.blizzard_query and state.page and state.total_auctions and state.page >= last_page(state.total_auctions) then
		state.page_is_last = true
	end
	
	if state.params.type == 'list' and state.dup_query and check_for_duplicate_page(state.dup_query, state.page) then
		scan_debug('accept_results() duplicate page detected, re-querying')
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
	scan_debug('check_for_duplicate_page() pagenum=' .. tostring(pagenum) .. ' numOnPage=' .. numOnPage)
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
	local numLinks = 0
	local prevLink

	for i = 1, numOnPage do
		local name, _, count, _, _, _, minBid, minInc, buyoutPrice, bidAmount, _, owner = GetAuctionItemInfo('list', i)
		local link = GetAuctionItemLink('list', i) or ''
		local idstr = link .. '_' .. (count or 0) .. '_' .. (minBid or 0)
			.. '_' .. (minInc or 0) .. '_' .. (buyoutPrice or 0) .. '_' .. (bidAmount or 0)
			.. '_' .. (owner or '')
		thisPage.items[i] = idstr

		if not prevLink then
			prevLink = link
		elseif prevLink ~= link then
			prevLink = link
			numLinks = numLinks + 1
		end

		if not prevPage or idstr ~= prevPage.items[i] then
			dupPageFound = false
		end
	end

	if prevPage and prevPage.numOnPage ~= thisPage.numOnPage then
		dupPageFound = false
	elseif dupPageFound and numLinks <= 1 and prevPage and prevPage.numOnPage == numOnPage then
		-- All items have the same link: probably a wall of identical postings, not a true duplicate
		dupPageFound = false
	end

	if dupPageFound then
		q.numDupPages = (q.numDupPages or 0) + 1
		scan_debug('check_for_duplicate_page() DUPLICATE FOUND numDupPages=' .. q.numDupPages)

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
    local is_getall = query.blizzard_query and query.blizzard_query.get_all
    scan_debug('wait_for_results() started, last_list_query=' .. tostring(state.last_list_query) .. ' get_all=' .. tostring(is_getall))

    if is_getall then
        -- getAll path (modeled on TSM LibAuctionScan): do NOT depend on
        -- AUCTION_ITEM_LIST_UPDATE (it is unreliable / sometimes never fires
        -- for getAll on this core). Instead poll GetNumAuctionItems('list')
        -- until data is available, with a hard timeout. NEVER resubmit a
        -- getAll query on timeout -- accept whatever is present and move on,
        -- otherwise the scan loops forever (the "fast scan hangs" bug).
        local GETALL_TIMEOUT = 20
        local getall_last_num, getall_stable_time
        local waiting_printed, ready_printed = false, false
        return when(function()
            local num = GetNumAuctionItems('list')
            if num and num > 50 then
                -- wait for the count to stabilize for 0.5s before accepting
                if not getall_last_num or getall_last_num ~= num then
                    if not ready_printed then
                        scan_debug('wait_for_results() getAll num=' .. num .. ' waiting for stability')
                        ready_printed = true
                    end
                    getall_last_num = num
                    getall_stable_time = GetTime()
                elseif GetTime() - getall_stable_time >= 0.5 then
                    scan_debug('wait_for_results() getAll stable num=' .. num)
                    return true
                end
            elseif not waiting_printed then
                scan_debug('wait_for_results() getAll num=' .. tostring(num) .. ' <=50, polling...')
                waiting_printed = true
            end
            if GetTime() - state.last_list_query > GETALL_TIMEOUT then
                scan_debug('wait_for_results() getAll ' .. GETALL_TIMEOUT .. 's timeout, accepting')
                return true
            end
        end, function()
            scan_debug('wait_for_results() getAll callback: accepting results')
            return accept_results()
        end)
    end

    -- Normal paged scans: original event-driven behavior.
    local updated, last_update
    local listener_id = event_listener('AUCTION_ITEM_LIST_UPDATE', function()
        scan_debug('AUCTION_ITEM_LIST_UPDATE fired')
        last_update = GetTime()
        updated = true
    end)
    local timeout = later(5, state.last_list_query)
    local ignore_owner = state.params.ignore_owner or aux_ignore_owner
	return when(function()
		if not last_update and timeout() then
			scan_debug('wait_for_results() timeout (no update), returning true')
			return true
		end
		if last_update then
			if GetTime() - last_update > 5 then
				scan_debug('wait_for_results() normal 5s post-update timeout')
				return true
			end
			if updated and (ignore_owner or owner_data_complete()) then
				scan_debug('wait_for_results() normal data ready')
				return true
			end
		end
		updated = false
	end, function()
		kill_listener(listener_id)
		if not last_update and timeout() then
			scan_debug('wait_for_results() callback: timeout -> submit_query()')
			return submit_query()
		else
			scan_debug('wait_for_results() callback: accepting results')
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