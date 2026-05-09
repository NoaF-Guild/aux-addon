module 'aux.tabs.search'

local filter_util = require 'aux.util.filter'
local gui = require 'aux.gui'

-- Internal mutable storage. We never re-assign these identifiers after load
-- because the Aux module system forbids it.
recent_searches = {}
favorite_searches = {}

-- References to persisted SavedVariables tables (realm scope).
local persisted_recent_searches
local persisted_favorite_searches

local function copy_into(dst, src)
	wipe(dst)
	if type(src) ~= 'table' then return end
	for i = 1, getn(src) do
		dst[i] = src[i]
	end
end

local function persist_saved_searches()
	-- Copy our internal mutable lists back into the persisted tables so they
	-- get written to SavedVariables on logout/reload.
	if persisted_recent_searches then
		copy_into(persisted_recent_searches, recent_searches)
	end
	if persisted_favorite_searches then
		copy_into(persisted_favorite_searches, favorite_searches)
	end
end

local function icon_tag_from_search(search)
	-- If the prettified string contains an item link, show its icon.
	local text = (search and search.prettified) or ''
	local item_id = tonumber(strmatch(text, 'Hitem:(%d+):')) or tonumber(strmatch(text, 'item:(%d+):'))

	-- Fallback: if the user typed an item name (no link), try to resolve it via
	-- Aux's item name -> itemID cache (populated from WDB scans).
	if not item_id then
		-- Use only the first query chunk (before ';') for icon purposes.
		local first = strmatch(text, '^(.-);') or text
		-- Strip WoW color codes and brackets, then trim.
		first = gsub(first, '|c%x%x%x%x%x%x%x%x', '')
		first = gsub(first, '|r', '')
		first = gsub(first, '%[', '')
		first = gsub(first, '%]', '')
		first = strtrim(first)
		if first ~= '' and aux_item_ids then
			item_id = aux_item_ids[strlower(first)]
		end
	end
	if item_id then
		local tex = GetItemIcon(item_id)
		if tex then
			return '|T' .. tex .. ':14:14:0:0|t '
		end
	end
	return ''
end

function LOAD2()
	persisted_recent_searches = realm_data('recent_searches')
	persisted_favorite_searches = realm_data('favorite_searches')
	-- Copy persisted data into our mutable tables.
	copy_into(recent_searches, persisted_recent_searches)
	copy_into(favorite_searches, persisted_favorite_searches)
end

function update_search_listings()
	-- recent_searches / favorite_searches are initialized in LOAD2()
	local favorite_search_rows = T
	for i = 1, getn(favorite_searches) do
		local search = favorite_searches[i]
		local name = icon_tag_from_search(search) .. strsub(search.prettified, 1, 250)
		tinsert(favorite_search_rows, O(
			'cols', A(O('value', name)),
			'search', search,
			'index', i
		))
	end
	favorite_searches_listing:SetData(favorite_search_rows)

	local recent_search_rows = T
	for i = 1, getn(recent_searches) do
		local search = recent_searches[i]
		local name = icon_tag_from_search(search) .. strsub(search.prettified, 1, 250)
		tinsert(recent_search_rows, O(
			'cols', A(O('value', name)),
			'search', search,
			'index', i
		))
	end
	recent_searches_listing:SetData(recent_search_rows)
end

function new_recent_search(filter_string, prettified)
	tinsert(recent_searches, 1, O(
		'filter_string', filter_string,
		'prettified', prettified
	))
	while getn(recent_searches) > 50 do
		tremove(recent_searches)
	end
	update_search_listings()
	persist_saved_searches()
end

handlers = {
	OnClick = function(st, data, _, button)
		if not data then return end
		if button == 'LeftButton' and IsShiftKeyDown() then
			filter = data.search.filter_string
		elseif button == 'RightButton' and IsShiftKeyDown() then
			add_filter(data.search.filter_string)
		elseif button == 'LeftButton' then
			filter = data.search.filter_string
			execute()
		elseif button == 'RightButton' then
			local u = update_search_listings
			if st == recent_searches_listing then
				tinsert(favorite_searches, 1, data.search)
				u()
				persist_saved_searches()
			elseif st == favorite_searches_listing then
				gui.menu(
					'Move Up', function() move_up(favorite_searches, data.index); u(); persist_saved_searches() end,
					'Move Down', function() move_down(favorite_searches, data.index); u(); persist_saved_searches() end,
					'Delete', function() tremove(favorite_searches, data.index); u(); persist_saved_searches() end
				)
			end
		end
	end,
	OnEnter = function(st, data, self)
		if not data then return end
		GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
		GameTooltip:AddLine(gsub(data.search.prettified, ';', '\n\n'), 255/255, 254/255, 250/255, true)
		GameTooltip:Show()
	end,
	OnLeave = function()
		GameTooltip:ClearLines()
		GameTooltip:Hide()
	end
}

function add_favorite(filter_string)
	local queries, error = filter_util.queries(filter_string)
	if queries then
		tinsert(favorite_searches, 1, O(
			'filter_string', filter_string,
			'prettified', join(map(queries, function(query) return query.prettified end), ';')
		))
		update_search_listings()
		persist_saved_searches()
	else
		print('Invalid filter:', error)
	end
end

function move_up(list, index)
	if list[index - 1] then
		list[index], list[index - 1] = list[index - 1], list[index]
	end
end

function move_down(list, index)
	if list[index + 1] then
		list[index], list[index + 1] = list[index + 1], list[index]
	end
end