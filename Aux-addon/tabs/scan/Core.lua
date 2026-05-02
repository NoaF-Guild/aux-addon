module 'aux.tabs.scan'

include 'T'
include 'aux'

local scan = require 'aux.core.scan'
local history = require 'aux.core.history'
local filter_util = require 'aux.util.filter'
local info = require 'aux.util.info'

TAB 'Scan'

local list_scan_id

local scan_start_time
local pages_scanned
local current_query
local total_queries
local last_total_pages
local max_pages_per_query
local scan_queries_ref

local function update_last_scan_text()
    if not last_scan_text then return end
    local t = aux and aux.last_scan_time
    if t and tonumber(t) then
        last_scan_text:SetText('Last scan: ' .. date('%Y-%m-%d %H:%M', t))
		local age = time() - t
		if age <= (3 * 24 * 60 * 60) then
			last_scan_text:SetTextColor(0.25, 1.0, 0.25)
		else
			last_scan_text:SetTextColor(1.0, 0.25, 0.25)
		end
    else
        last_scan_text:SetText('Last scan: --')
		last_scan_text:SetTextColor(color.label.enabled())
    end
end

local function set_scanning(active)
	if stop_scan_button then
		if active then stop_scan_button:Show() else stop_scan_button:Hide() end
	end
	if full_scan_button then
		if active then full_scan_button:Disable() else full_scan_button:Enable() end
	end
	if fast_scan_button then
		if active then fast_scan_button:Disable() else fast_scan_button:Enable() end
	end
end

local function format_duration(seconds)
    if not seconds or seconds < 0 then return '--' end
    seconds = floor(seconds + 0.5)
    local h = floor(seconds / 3600)
    local m = floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then
        return format('%dh %dm %ds', h, m, s)
    elseif m > 0 then
        return format('%dm %ds', m, s)
    else
        return format('%ds', s)
    end
end

local function set_progress(page, total_pages, label)
    if not scan_status_bar then return end
	if max_pages_per_query then
		total_pages = max_pages_per_query
	else
		total_pages = max(total_pages or 1, 1)
	end
	page = min(max(page or 0, 0), total_pages)

	local overall = 0
	local total_est = nil
	if max_pages_per_query then
		local tq = (scan_queries_ref and getn(scan_queries_ref)) or total_queries or 0
		tq = max(tq, current_query or 0)
		if tq > 0 then
			total_est = tq * max_pages_per_query
			if pages_scanned and pages_scanned > total_est then
				total_est = pages_scanned
			end
			overall = pages_scanned and pages_scanned > 0 and (pages_scanned / total_est) or 0
		end
	elseif total_queries and total_queries > 0 then
		overall = ((current_query - 1) + (page / total_pages)) / total_queries
	end
	scan_status_bar:update_status(overall, page / total_pages)
    scan_status_bar:set_text(format('%s Page %d / %d', label or 'Scanning', page, total_pages))

    local elapsed = (scan_start_time and (GetTime() - scan_start_time)) or 0
    local avg = (pages_scanned and pages_scanned > 0) and (elapsed / pages_scanned) or nil
	local remaining = nil
	if avg and total_est and pages_scanned then
		remaining = max(total_est - pages_scanned, 0)
	elseif avg and last_total_pages then
		remaining = (total_queries - current_query) * last_total_pages + (total_pages - page)
	end
    if scan_pages_text then
        local scanned = pages_scanned or 0
		if total_est then
			scan_pages_text:SetText(format('Pages scanned: %d / %d', scanned, total_est))
		else
			scan_pages_text:SetText(format('Pages scanned: %d', scanned))
		end
    end
    if scan_time_text then
        local eta = remaining and avg and (remaining * avg) or nil
        scan_time_text:SetText(format('Elapsed: %s   ETA: %s', format_duration(elapsed), format_duration(eta)))
    end
end

function stop_scan()
	scan.abort(list_scan_id)
end

local function start_list_scan(queries, label, on_end_query, max_pages, scan_params)
	scan.abort(list_scan_id)
	set_scanning(true)
	if scan_status_bar then
		scan_status_bar:update_status(0, 0)
		scan_status_bar:set_text('Starting ' .. (label or 'Scan') .. '...')
	end
    scan_queries_ref = queries
    scan_start_time = GetTime()
    pages_scanned = 0
    current_query = 0
    total_queries = getn(queries)
    last_total_pages = nil
	max_pages_per_query = max_pages

	local params = {
	        type = 'list',
        ignore_owner = true,
        queries = queries,
		skip_history = false,
		chunk_size = nil,
		on_auction = nil,
			on_scan_start = function() end,
	        on_start_query = function()
            current_query = current_query + 1
        end,
        on_page_loaded = function(page, total_pages)
            pages_scanned = pages_scanned + 1
            last_total_pages = total_pages or last_total_pages
            set_progress(page, total_pages, label)
        end,
		on_end_query = on_end_query,
        on_complete = function()
            if aux then
                aux.last_scan_time = time()
            end
            update_last_scan_text()
			list_scan_id = nil
			set_scanning(false)
            if scan_status_bar then
                scan_status_bar:update_status(1, 1)
                scan_status_bar:set_text('Scan complete')
            end
            if scan_time_text and scan_start_time then
                scan_time_text:SetText(format('Elapsed: %s   ETA: --', format_duration(GetTime() - scan_start_time)))
            end
        end,
	        on_abort = function()
			list_scan_id = nil
			set_scanning(false)
            if scan_status_bar then
                scan_status_bar:update_status(1, 1)
                scan_status_bar:set_text('Scan aborted')
            end
        end,
	}
	if type(scan_params) == 'table' then
		for k, v in pairs(scan_params) do
			params[k] = v
		end
	end
		thread(when, later(0), function()
			list_scan_id = scan.start(params)
		end)
end

function full_scan()
	start_list_scan({O('blizzard_query', T)}, 'Full Scan')
end

local function fast_scan_on_auction(r)
	if r and r.item_key and r.buyout_price and r.aux_quantity and r.buyout_price > 0 and r.aux_quantity > 0 then
		local unit = ceil(r.buyout_price / r.aux_quantity)
		local cur = history.fast_value(r.item_key)
		if not cur or unit < cur then
			history.set_fast_value(r.item_key, unit)
		end
	end
end

local function fast_scan_per_category()
	local queries = T
	local classes = T
	for _, c in ipairs({GetAuctionItemClasses()}) do
		tinsert(classes, c)
	end
	for class_index = 1, getn(classes) do
		local subs = {GetAuctionItemSubClasses(class_index)}
		if getn(subs) == 0 then
			tinsert(queries, O('blizzard_query', O('name', '', 'class', class_index, 'subclass', 0, 'first_page', 0, 'last_page', 0)))
		else
			for subclass_index = 1, getn(subs) do
				tinsert(queries, O('blizzard_query', O('name', '', 'class', class_index, 'subclass', subclass_index, 'first_page', 0, 'last_page', 0)))
			end
		end
	end
	start_list_scan(queries, 'Fast Scan', nil, nil, {
		skip_history = true,
		fast_extract = true,
		on_auction = fast_scan_on_auction,
	})
end

function fast_scan()
	local can_query, can_query_all = CanSendAuctionQuery()
	if can_query_all then
		start_list_scan({O('blizzard_query', O('get_all', true))}, 'Fast Scan', nil, nil, {
			skip_history = true,
			fast_extract = true,
			on_auction = fast_scan_on_auction,
		})
	else
		fast_scan_per_category()
	end
end

function OPEN()
    frame:Show()
    update_last_scan_text()
    if scan_status_bar then
        scan_status_bar:update_status(1, 1)
        scan_status_bar:set_text('')
    end
    if scan_pages_text then scan_pages_text:SetText('Pages scanned: 0') end
    if scan_time_text then scan_time_text:SetText('Elapsed: --   ETA: --') end
end

function CLOSE()
    frame:Hide()
end
