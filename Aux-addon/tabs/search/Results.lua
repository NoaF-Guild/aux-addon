module 'aux.tabs.search'

local info = require 'aux.util.info'
local filter_util = require 'aux.util.filter'
local scan_util = require 'aux.util.scan'
local scan = require 'aux.core.scan'
local cache = require 'aux.core.cache'
local history = require 'aux.core.history'
local money = require 'aux.util.money'
local gui = require 'aux.gui'



local hide_buyout_popup
local buyout_popup_hooked

local function announce_bid_or_buyout(verb, r, qty, price)
	if not r then return end
	local link = r.link
	if not link and r.item_id then
		link = '|cffffffff[item:' .. r.item_id .. ']|r'
	end
	local tex = r.texture and ('|T' .. r.texture .. ':0|t ') or ''
	print(verb .. ' ' .. tex .. (link or '') .. ' x' .. (qty or 1) .. ' for ' .. money.to_string(price or 0, true, true))
end

local function estimate_total_cost(seed_record, desired)
	local search = current_search
	if not search or not search.table or not seed_record or not desired then return end
	local candidates = T
	for _, r in ipairs(search.table.records or T) do
		if r and r.item_key == seed_record.item_key and r.buyout_price and r.buyout_price > 0 and not cache.is_player(r.owner) then
			tinsert(candidates, r)
		end
	end
	if getn(candidates) == 0 then return end
	sort(candidates, function(a,b)
		return (a.buyout_price / max(a.aux_quantity or 1, 1)) < (b.buyout_price / max(b.aux_quantity or 1, 1))
	end)
    local remaining = desired
    local total = 0
    for _, r in ipairs(candidates) do
        if remaining <= 0 then break end
        total = total + (r.buyout_price or 0)
        remaining = remaining - (r.aux_quantity or 1)
    end
    return total, remaining <= 0, remaining
end

local function update_buyout_cancel_ui()
	if not aux_buyout_popup or not aux_buyout_popup.cancelBtn then return end
	aux_buyout_popup.cancelBtn:SetText('Cancel')
	aux_buyout_popup.cancelBtn:SetScript('OnClick', hide_buyout_popup)
end

local function update_buyout_popup_cost()
	local dlg = aux_buyout_popup
	if not dlg or not dlg.record then return end
	local qtyText = (dlg.editbox and dlg.editbox.GetText) and (dlg.editbox:GetText() or '') or ''
	local qty = tonumber(qtyText)
	qty = qty and max(1, floor(qty)) or nil

	-- If no quantity is entered, don't show a dummy 'Total cost: -' line.
	if not qty then
		dlg.costText:Hide()
		dlg.noteText:ClearAllPoints()
		dlg.noteText:SetPoint('TOP', dlg.editbox, 'BOTTOM', 0, -12)
		dlg.noteText:SetText('Quantity is in items.')
		return
	end

	-- Restore default layout when quantity becomes valid.
	dlg.costText:Show()
	dlg.costText:ClearAllPoints()
	dlg.costText:SetPoint('TOP', dlg.editbox, 'BOTTOM', 0, -12)
	dlg.noteText:ClearAllPoints()
	dlg.noteText:SetPoint('TOP', dlg.costText, 'BOTTOM', 0, -4)

	local total, ok = estimate_total_cost(dlg.record, qty)
	if total then
		dlg.costText:SetText('Total cost: ' .. money.to_string(total, true, true))
		dlg.noteText:SetText(ok and 'Quantity is in items.' or 'Quantity is in items. Not enough auctions to reach target.')
	else
		dlg.costText:SetText('Total cost: -')
		dlg.noteText:SetText('Quantity is in items.')
	end
end

	hide_buyout_popup = function()
	if aux_buyout_popup then
		local s = aux_buyout_popup.buyout_state
		if s then
			if s.scan_id then scan.abort(s.scan_id) end
			s.scan_id = nil
		end
		aux_buyout_popup.buyout_state = nil
		aux_buyout_popup.in_progress = false
		if aux_buyout_popup.buyoutBtn and aux_buyout_popup.buyoutBtn.Enable then
			aux_buyout_popup.buyoutBtn:Enable()
		end
		aux_buyout_popup:Hide()
	end
	if aux_buyout_overlay then aux_buyout_overlay:Hide() end
	end

local function ensure_buyout_popup()
	if aux_buyout_popup or not frame or not AuxFrame or not AuxFrame.content then return end
	local overlay = CreateFrame('Frame', nil, AuxFrame.content)
	overlay:SetAllPoints(AuxFrame.content)
		overlay:SetFrameStrata('DIALOG')
		overlay:SetFrameLevel(90)
	overlay:EnableMouse(true)
	overlay:SetBackdrop({bgFile='Interface\\Tooltips\\UI-Tooltip-Background'})
	overlay:SetBackdropColor(0.13, 0.13, 0.13, 0.85)
		overlay:SetScript('OnMouseDown', function() end)
	overlay:Hide()
	aux_buyout_overlay = overlay

		local dlg = CreateFrame('Frame', nil, AuxFrame.content)
		dlg:SetSize(420, 280)
		dlg:SetFrameStrata('DIALOG')
		dlg:SetFrameLevel(100)
		dlg:SetToplevel(true)
	gui.set_window_style(dlg)
	dlg:EnableMouse(true)
	dlg:SetScript('OnHide', function() overlay:Hide() end)
	dlg:EnableKeyboard(true)
	dlg:SetScript('OnKeyDown', function(_, key)
		if key == 'ESCAPE' then hide_buyout_popup() end
	end)
	if dlg.SetPropagateKeyboardInput then dlg:SetPropagateKeyboardInput(true) end
	dlg:Hide()
	aux_buyout_popup = dlg

		-- Close the quantity popup automatically when the main Aux window closes.
		if AuxFrame and not buyout_popup_hooked then
			buyout_popup_hooked = true
			AuxFrame:HookScript('OnHide', hide_buyout_popup)
		end

	local icon = dlg:CreateTexture(nil, 'ARTWORK')
	icon:SetSize(32, 32)
	icon:SetPoint('TOPLEFT', 16, -16)
	dlg.icon = icon
	local icon_border = CreateFrame('Frame', nil, dlg)
	icon_border:SetPoint('TOPLEFT', icon, 'TOPLEFT', -1, 1)
	icon_border:SetPoint('BOTTOMRIGHT', icon, 'BOTTOMRIGHT', 1, -1)
	icon_border:SetBackdrop{bgFile=[[Interface\Buttons\WHITE8X8]], edgeFile=[[Interface\Buttons\WHITE8X8]], edgeSize=1, tile=true, insets={left=0,right=0,top=0,bottom=0}}
	icon_border:SetBackdropColor(0, 0, 0, 0)
	icon_border:SetBackdropBorderColor(color.panel.border())
	dlg.icon_border = icon_border

	local nameText = dlg:CreateFontString(nil, 'ARTWORK')
	gui.apply_font(nameText, 'text')
	nameText:SetPoint('TOPLEFT', icon, 'TOPRIGHT', 10, -2)
	nameText:SetPoint('TOPRIGHT', dlg, 'TOPRIGHT', -16, -20)
	nameText:SetJustifyH('LEFT')
	nameText:SetHeight(18)
	dlg.nameText = nameText

	local qtyLabel = dlg:CreateFontString(nil, 'ARTWORK')
	gui.apply_font(qtyLabel, 'text')
	qtyLabel:SetTextColor(color.text.enabled())
	qtyLabel:SetPoint('TOP', dlg, 'TOP', 0, -68)
	qtyLabel:SetJustifyH('CENTER')
	qtyLabel:SetText('Buyout quantity (items):')
	dlg.qtyLabel = qtyLabel

		local eb = gui.editbox(dlg)
		eb:SetWidth(180)
		eb:SetPoint('TOP', qtyLabel, 'BOTTOM', 0, -8)
		eb:SetHeight(25)
		eb:SetAutoFocus(true)
		eb:SetNumeric(true)
		eb.escape = hide_buyout_popup
		eb.enter = function() dlg.buyoutBtn:Click() end
		eb.change = update_buyout_popup_cost
		dlg.editbox = eb

	local costText = dlg:CreateFontString(nil, 'ARTWORK')
	gui.apply_font(costText, 'numbers')
	costText:SetTextColor(color.text.enabled())
	costText:SetPoint('TOP', eb, 'BOTTOM', 0, -12)
	costText:SetJustifyH('CENTER')
	costText:SetText('Total cost: -')
	dlg.costText = costText

	local noteText = dlg:CreateFontString(nil, 'ARTWORK')
	gui.apply_font(noteText, 'text')
	noteText:SetTextColor(color.text.enabled())
	noteText:SetPoint('TOP', costText, 'BOTTOM', 0, -4)
	noteText:SetJustifyH('CENTER')
	noteText:SetText('Quantity is in items.')
	dlg.noteText = noteText

		local progressText = dlg:CreateFontString(nil, 'ARTWORK')
	gui.apply_font(progressText, 'text')
	progressText:SetTextColor(color.text.enabled())
		progressText:SetPoint('BOTTOM', dlg, 'BOTTOM', 0, 16)
	progressText:SetJustifyH('CENTER')
	progressText:SetText('')
	dlg.progressText = progressText

		local buyoutBtn = gui.button(dlg)
		buyoutBtn:SetSize(110, 24)
		buyoutBtn:SetPoint('BOTTOM', dlg, 'BOTTOM', -70, 54)
	buyoutBtn:SetText('Buyout')
		buyoutBtn:SetFrameLevel(dlg:GetFrameLevel() + 5)
	dlg.buyoutBtn = buyoutBtn

		local cancelBtn = gui.button(dlg)
		cancelBtn:SetSize(110, 24)
		cancelBtn:SetPoint('LEFT', buyoutBtn, 'RIGHT', 20, 0)
		cancelBtn:SetText('Cancel')
		cancelBtn:SetScript('OnClick', hide_buyout_popup)
		cancelBtn:SetFrameLevel(dlg:GetFrameLevel() + 5)
		dlg.cancelBtn = cancelBtn
		update_buyout_cancel_ui()

		buyoutBtn:SetScript('OnClick', function()
			local search = current_search
			if not search or not search.table or not search.table.records then return end

			local function ref_value(item_key)
				return history.fast_value(item_key) or history.value(item_key)
			end

			local function update_ui()
				local s = dlg.buyout_state
				if not s then return end
				dlg.progressText:SetText('Progress: ' .. s.bought .. ' / ' .. s.qty .. ' items')
				dlg.costText:SetText('Total cost: ' .. money.to_string(s.spent, true, true))
			end

			local function finish()
				local s = dlg.buyout_state
				if not s then return end
				if s.remaining > 0 then
					dlg.noteText:SetText('Quantity is in items. Not enough auctions to reach target.')
				else
					dlg.noteText:SetText('Buyout requested.')
					hide_buyout_popup()
				end
				dlg.buyout_state = nil
				dlg.in_progress = false
				if buyoutBtn.Enable then buyoutBtn:Enable() end
			end

			local function start_state()
				local record = dlg.record
				if not record then return end
				local qty = tonumber(dlg.editbox:GetText() or '')
				qty = qty and max(1, floor(qty)) or nil
				if not qty then return end
				local candidates = T
				for _, r in ipairs(search.table.records or T) do
					if r and r.item_key == record.item_key and r.buyout_price and r.buyout_price > 0 and r.index and not cache.is_player(r.owner) then
						tinsert(candidates, r)
					end
				end
				if getn(candidates) == 0 then
					dlg.noteText:SetText('No buyout auctions found.')
					return
				end
				sort(candidates, function(a, b)
					return (a.buyout_price / max(a.aux_quantity or 1, 1)) < (b.buyout_price / max(b.aux_quantity or 1, 1))
				end)
				dlg.buyout_state = O('qty', qty, 'remaining', qty, 'bought', 0, 'spent', 0, 'i', 1, 'candidates', candidates)
				dlg.progressText:SetText('Progress: 0 / ' .. qty .. ' items')
				dlg.costText:SetText('Total cost: -')
				dlg.noteText:SetText('Quantity is in items.')
			end

			local function ah_session_open()
				return AuxFrame and AuxFrame:IsShown() and true or false
			end

			local function find_in_listing(r)
				if not r or not r.query_type then return end
				local total = GetNumAuctionItems(r.query_type)
				if not total or total <= 0 then return end
				local origin = r.index or 1
				if scan_util.test(r, origin) then return origin end
				local span = max(origin, total - origin)
				for offset = 1, span do
					local lo = origin - offset
					local hi = origin + offset
					if lo >= 1 and scan_util.test(r, lo) then return lo end
					if hi <= total and scan_util.test(r, hi) then return hi end
				end
			end

			local process_next
			local function buy_at(s, r, q, index)
				place_bid('list', index, r.buyout_price, function(confirmed)
					if dlg.buyout_state ~= s then return end
					if not confirmed then
						s.i = s.i + 1
						update_ui()
						if not ah_session_open() then
							dlg.buyout_state = nil
							dlg.in_progress = false
							if buyoutBtn.Enable then buyoutBtn:Enable() end
							return
						end
						return process_next()
					end
					local price = r.buyout_price or 0
					local actual_q = min(s.remaining, q)
					s.spent = s.spent + price
					s.bought = s.bought + actual_q
					s.remaining = s.remaining - q
					search.table:RemoveAuctionRecord(r)
					s.i = s.i + 1
					update_ui()
					announce_bid_or_buyout('Buyout', r, actual_q, price)
					if not ah_session_open() then
						dlg.buyout_state = nil
						dlg.in_progress = false
						if buyoutBtn.Enable then buyoutBtn:Enable() end
						return
					end
					process_next()
				end)
			end

			process_next = function()
				local s = dlg.buyout_state
				if not s then return end
				if not ah_session_open() then
					dlg.buyout_state = nil
					dlg.in_progress = false
					if buyoutBtn.Enable then buyoutBtn:Enable() end
					return
				end
				if s.remaining <= 0 or s.i > getn(s.candidates) then
					return finish()
				end
				local r = s.candidates[s.i]
				if not r then return finish() end
				local q = max(r.aux_quantity or 1, 1)
				local unit = ceil((r.buyout_price or 0) / q)
				local ref = ref_value(r.item_key)
				if ref and ref > 0 and unit > ref * 3 and s.confirm_i ~= s.i then
					s.confirm_i = s.i
					local pct = floor(unit * 100 / ref + 0.5)
					dlg.noteText:SetText('Warning: next auction is ' .. pct .. '% of Value. Click Buyout again to continue.')
					update_ui()
					dlg.in_progress = false
					if buyoutBtn.Enable then buyoutBtn:Enable() end
					return
				end
				s.confirm_i = nil

				if not search.table:ContainsRecord(r) or cache.is_player(r.owner) then
					s.i = s.i + 1
					return process_next()
				end

				local local_index = find_in_listing(r)
				if local_index then
					return buy_at(s, r, q, local_index)
				end

				s.scan_id = scan_util.find(
					r,
					search.status_bar,
					function()
						finish()
					end,
					function()
						search.table:RemoveAuctionRecord(r)
						s.i = s.i + 1
						process_next()
					end,
					function(index)
						if not scan_util.test(r, index) or not search.table:ContainsRecord(r) then
							search.table:RemoveAuctionRecord(r)
							s.i = s.i + 1
							return process_next()
						end
						buy_at(s, r, q, index)
					end
				)
			end

			if dlg.in_progress then return end
			if not dlg.buyout_state then
				start_state()
			end
			if not dlg.buyout_state then return end
			dlg.in_progress = true
			if buyoutBtn.Disable then buyoutBtn:Disable() end
			process_next()
		end)
end



function prompt_buyout_quantity(record)
	if not record then return end
	ensure_buyout_popup()
	if not aux_buyout_popup or not aux_buyout_overlay then return end
	aux_buyout_popup.record = record
	if aux_buyout_popup.editbox and aux_buyout_popup.editbox.Enable then
		aux_buyout_popup.editbox:Enable()
	end
	if aux_buyout_popup.buyoutBtn then
		aux_buyout_popup.buyoutBtn:SetText('Buyout')
		aux_buyout_popup.buyoutBtn:Enable()
	end
	local item = info.item(record.item_id)
	aux_buyout_popup.icon:SetTexture(item and item.texture or nil)
	aux_buyout_popup.nameText:SetText(item and item.name or 'Item')
	aux_buyout_popup.editbox:SetText('')
	-- Name should follow Text font role and item quality color.
	local q = item and item.quality
	if q then
		local r, g, b = GetItemQualityColor(q)
		aux_buyout_popup.nameText:SetTextColor(r, g, b)
	else
		aux_buyout_popup.nameText:SetTextColor(color.text.enabled())
	end
	aux_buyout_popup.costText:Hide()
	aux_buyout_popup.noteText:ClearAllPoints()
	aux_buyout_popup.noteText:SetPoint('TOP', aux_buyout_popup.editbox, 'BOTTOM', 0, -12)
	aux_buyout_popup.noteText:SetText('Quantity is in items.')
	aux_buyout_overlay:Show()
	aux_buyout_popup:ClearAllPoints()
	aux_buyout_popup:SetPoint('CENTER', AuxFrame.content, 'CENTER', 0, 0)
	aux_buyout_popup:Show()
	aux_buyout_popup.editbox:SetFocus()
end

function LOAD()
	new_search()
end

do
	local id = 0
	function get_search_scan_id()
		return id
	end
	function set_search_scan_id(v)
		id = v
	end
end

function update_real_time(enable)
	if enable then
		range_button:Hide()
		real_time_button:Show()
		search_box:SetPoint('LEFT', real_time_button, 'RIGHT', 4, 0)
	else
		real_time_button:Hide()
		range_button:Show()
		search_box:SetPoint('LEFT', last_page_input, 'RIGHT', 4, 0)
	end
end

do
	local searches = {}
	local search_index = 1

	function get_current_search()
		return searches[search_index]
	end

	function update_search(index)
		searches[search_index].status_bar:Hide()
		searches[search_index].table:Hide()
		searches[search_index].table:SetSelectedRecord()

		search_index = index

		searches[search_index].status_bar:Show()
		searches[search_index].table:Show()

		search_box:SetText(searches[search_index].filter_string or '')
		first_page_input:SetText(searches[search_index].first_page and searches[search_index].first_page + 1 or '')
		last_page_input:SetText(searches[search_index].last_page and searches[search_index].last_page + 1 or '')
		if search_index == 1 then
			previous_button:Disable()
		else
			previous_button:Enable()
		end
		if search_index == getn(searches) then
			next_button:Hide()
			range_button:SetPoint('LEFT', previous_button, 'RIGHT', 4, 0)
			real_time_button:SetPoint('LEFT', previous_button, 'RIGHT', 4, 0)
		else
			next_button:Show()
			range_button:SetPoint('LEFT', next_button, 'RIGHT', 4, 0)
			real_time_button:SetPoint('LEFT', next_button, 'RIGHT', 4, 0)
		end
		update_real_time(searches[search_index].real_time)
		update_start_stop()
		update_continuation()
	end

	function new_search(filter_string, first_page, last_page, real_time)
		while getn(searches) > search_index do
			tremove(searches)
		end
		local search = O('records', T, 'filter_string', filter_string, 'first_page', first_page, 'last_page', last_page, 'real_time', real_time)
		tinsert(searches, search)
		if getn(searches) > 5 then
			tremove(searches, 1)
			tinsert(status_bars, tremove(status_bars, 1))
			tinsert(tables, tremove(tables, 1))
			search_index = 4
		end

		search.status_bar = status_bars[getn(searches)]
		search.status_bar:update_status(1, 1)
		search.status_bar:set_text('')

		search.table = tables[getn(searches)]
		search.table:SetSort(1, 2, 3, 4, 5, 6, 7, 8, 9)
		search.table:Reset()
		search.table:SetDatabase(search.records)

		update_search(getn(searches))
	end

	function clear_control_focus()
		search_box:ClearFocus()
		first_page_input:ClearFocus()
		last_page_input:ClearFocus()
	end

	function previous_search()
		clear_control_focus()
		update_search(search_index - 1)
		subtab = RESULTS
	end

	function next_search()
		clear_control_focus()
		update_search(search_index + 1)
		subtab = RESULTS
	end
end

function update_continuation()
	if current_search.continuation then
		resume_button:Show()
		search_box:SetPoint('RIGHT', resume_button, 'LEFT', -4, 0)
	else
		resume_button:Hide()
		search_box:SetPoint('RIGHT', start_button, 'LEFT', -4, 0)
	end
end

function discard_continuation()
	scan.abort(search_scan_id)
	current_search.continuation = nil
	update_continuation()
end

function update_start_stop()
	if current_search.active then
		stop_button:Show()
		start_button:Hide()
	else
		start_button:Show()
		stop_button:Hide()
	end
end

function start_real_time_scan(query, search, continuation)

	local ignore_page
	if not search then
		search = current_search
		query.blizzard_query.first_page = tonumber(continuation) or 0
		query.blizzard_query.last_page = tonumber(continuation) or 0
		ignore_page = not tonumber(continuation)
	end

	local next_page
	local new_records = T
	search_scan_id = scan.start{
		type = 'list',
		queries = {query},
		on_scan_start = function()
			search.status_bar:update_status(.9999, .9999)
			search.status_bar:set_text('Scanning last page ...')
		end,
		on_page_loaded = function(_, _, last_page)
			next_page = last_page
			if last_page == 0 then
				ignore_page = false
			end
		end,
		on_auction = function(auction_record)
			if not ignore_page then
				tinsert(new_records, auction_record)
			end
		end,
		on_complete = function()
			local map = temp-T
			for _, record in pairs(search.records) do
				map[record.sniping_signature] = record
			end
			for _, record in pairs(new_records) do
				map[record.sniping_signature] = record
			end
			release(new_records)
			new_records = values(map)

			if getn(new_records) > 30000 then
				StaticPopup_Show('AUX_SEARCH_TABLE_FULL')
			else
				search.records = new_records
				search.table:SetDatabase(search.records)
			end

			query.blizzard_query.first_page = next_page
			query.blizzard_query.last_page = next_page
			start_real_time_scan(query, search)
		end,
		on_abort = function()
			search.status_bar:update_status(1, 1)
			search.status_bar:set_text('Scan paused')

			search.continuation = next_page or not ignore_page and query.blizzard_query.first_page or true

			if current_search == search then
				update_continuation()
			end

			search.active = false
			update_start_stop()
		end,
	}
end

function start_search(queries, continuation)
	local current_query, current_page, total_queries, start_query, start_page

	local search = current_search

	total_queries = getn(queries)

	if continuation then
		start_query, start_page = unpack(continuation)
		for i = 1, start_query - 1 do
			tremove(queries, 1)
		end
		queries[1].blizzard_query.first_page = (queries[1].blizzard_query.first_page or 0) + start_page - 1
		search.table:SetSelectedRecord()
	else
		start_query, start_page = 1, 1
	end


	search_scan_id = scan.start{
		type = 'list',
		queries = queries,
		on_scan_start = function()
			search.status_bar:update_status(0, 0)
			if continuation then
				search.status_bar:set_text('Resuming scan...')
			else
				search.status_bar:set_text('Scanning auctions...')
			end
		end,
		on_page_loaded = function(_, total_scan_pages)
			current_page = current_page + 1
			total_scan_pages = total_scan_pages + (start_page - 1)
			total_scan_pages = max(total_scan_pages, 1)
			current_page = min(current_page, total_scan_pages)
			search.status_bar:update_status((current_query - 1) / getn(queries), current_page / total_scan_pages)
			if total_queries and total_queries > 1 then
				search.status_bar:set_text(format('Scanning %d / %d (Page %d / %d)', current_query, total_queries, current_page, total_scan_pages))
			else
				search.status_bar:set_text(format('Scanning Page %d / %d', current_page, total_scan_pages))
			end
		end,
		on_page_scanned = function()
			search.table:SetDatabase()
		end,
		on_start_query = function(query)
			current_query = current_query and current_query + 1 or start_query
			current_page = current_page and 0 or start_page - 1
		end,
		on_auction = function(auction_record, ctrl)
			if getn(search.records) < 30000 then
				tinsert(search.records, auction_record)
				if getn(search.records) == 30000 then
					StaticPopup_Show('AUX_SEARCH_TABLE_FULL')
				end
			end
		end,
		on_complete = function()
			search.status_bar:update_status(1, 1)
			search.status_bar:set_text('Scan complete')

			if current_search == search and frame.results:IsVisible() and getn(search.records) == 0 then
				subtab = SAVED
			end

			search.active = false
			update_start_stop()
		end,
		on_abort = function()
			search.status_bar:update_status(1, 1)
			search.status_bar:set_text('Scan paused')

			if current_query then
				search.continuation = {current_query, current_page + 1}
			else
				search.continuation = {start_query, start_page}
			end
			if current_search == search then
				update_continuation()
			end

			search.active = false
			update_start_stop()
		end,
	}
end

function M.execute(resume, real_time)

	if resume then
		real_time = current_search.real_time
	elseif real_time == nil then
		real_time = real_time_button:IsShown()
	end

	if resume then
		search_box:SetText(current_search.filter_string)
	end
	local filter_string, first_page, last_page = search_box:GetText(), blizzard_page_index(first_page_input:GetText()), blizzard_page_index(last_page_input:GetText())

	local queries, error = filter_util.queries(filter_string)
	if not queries then
		print('Invalid filter:', error)
		return
	elseif real_time then
		if getn(queries) > 1 then
			print('Error: The real time mode does not support multi-queries')
			return
		elseif queries[1].blizzard_query.first_page or queries[1].blizzard_query.last_page then
			print('Error: The real time mode does not support page ranges')
			return
		end
	end

	if resume then
		current_search.table:SetSelectedRecord()
	else
		if filter_string ~= current_search.filter_string then
			if current_search.filter_string then
				new_search(filter_string, first_page, last_page, real_time)
			else
				current_search.filter_string = filter_string
			end
			new_recent_search(filter_string, join(map(copy(queries), function(filter) return filter.prettified end), ';'))
		else
			current_search.records = T
			current_search.table:Reset()
			current_search.table:SetDatabase(current_search.records)
		end
		current_search.first_page = first_page
		current_search.last_page = last_page
		current_search.real_time = real_time
	end

	local continuation = resume and current_search.continuation
	discard_continuation()
	current_search.active = true
	update_start_stop()
	clear_control_focus()
	subtab = RESULTS
	if real_time then
		start_real_time_scan(queries[1], nil, continuation)
	else
		for _, query in pairs(queries) do
			query.blizzard_query.first_page = current_search.first_page
			query.blizzard_query.last_page = current_search.last_page
		end
		start_search(queries, continuation)
	end
end

do
	local scan_id = 0
	local IDLE, SEARCHING, FOUND = 1, 2, 3
	local state = IDLE
	local found_index

	function find_auction(record)
		local search = current_search

		if not search.table:ContainsRecord(record) or cache.is_player(record.owner) then
			return
		end

		scan.abort(scan_id)
		state = SEARCHING
		scan_id = scan_util.find(
			record,
			current_search.status_bar,
			function()
				state = IDLE
			end,
			function()
				state = IDLE
				search.table:RemoveAuctionRecord(record)
			end,
			function(index)
				if search.table:GetSelection() and search.table:GetSelection().record ~= record then
					return
				end

				state = FOUND
				found_index = index

				if not record.high_bidder then
					bid_button:SetScript('OnClick', function()
						if scan_util.test(record, index) and search.table:ContainsRecord(record) then
							local is_buyout = record.bid_price >= record.buyout_price and record.buyout_price > 0
							place_bid('list', index, record.bid_price, function(confirmed)
								if confirmed then
									announce_bid_or_buyout(is_buyout and 'Buyout' or 'Bid', record, record.aux_quantity or 1, record.bid_price)
								end
								if is_buyout then
									search.table:RemoveAuctionRecord(record)
								else
									info.bid_update(record)
									search.table:SetDatabase()
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
						if scan_util.test(record, index) and search.table:ContainsRecord(record) then
							place_bid('list', index, record.buyout_price, function(confirmed)
								if confirmed then
									announce_bid_or_buyout('Buyout', record, record.aux_quantity or 1, record.buyout_price)
								end
								search.table:RemoveAuctionRecord(record)
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

		local selection = current_search.table:GetSelection()
		if not selection then
			state = IDLE
		elseif selection and state == IDLE then
			find_auction(selection.record)
		elseif state == FOUND and not scan_util.test(selection.record, found_index) then
			buyout_button:Disable()
			bid_button:Disable()
			if not bid_in_progress then
				state = IDLE
			end
		end
	end
end
