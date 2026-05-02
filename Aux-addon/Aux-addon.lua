module 'aux'

include 'T'

local info = require 'aux.util.info'
local money = require 'aux.util.money'
local cache = require 'aux.core.cache'
local history = require 'aux.core.history'
local stack = require 'aux.core.stack'
local post = require 'aux.core.post'
local scan = require 'aux.core.scan'
local search_tab = require 'aux.tabs.search'

_G.aux_scale = 1

_G.aux = {
	character = {},
	faction = {},
	realm = {},
	account = {},
}

M.print = vararg-function(arg)
	DEFAULT_CHAT_FRAME:AddMessage(LIGHTYELLOW_FONT_COLOR_CODE .. '<aux> ' .. join(map(arg, tostring), ' '))
end

local event_frame = CreateFrame'Frame'
for event in pairs(temp-S('ADDON_LOADED', 'VARIABLES_LOADED', 'PLAYER_LOGIN', 'AUCTION_HOUSE_SHOW', 'AUCTION_HOUSE_CLOSED')) do
	event_frame:RegisterEvent(event)
end

do
	local handlers, handlers2 = {}, {}
	function M.set_LOAD(f)
		tinsert(handlers, f)
	end
	function M.set_LOAD2(f)
		tinsert(handlers2, f)
	end
	event_frame:SetScript('OnEvent', function()
		if event == 'ADDON_LOADED' then
			if arg1 == 'Blizzard_AuctionUI' then
				Blizzard_AuctionUI()
			elseif arg1 == 'Blizzard_CraftUI' then
				Blizzard_CraftUI()
			elseif arg1 == 'Blizzard_TradeSkillUI' then
				Blizzard_TradeSkillUI()
			end
		elseif event == 'VARIABLES_LOADED' then
			for _, f in pairs(handlers) do f() end
		elseif event == 'PLAYER_LOGIN' then
			for _, f in pairs(handlers2) do f() end
			print('loaded - /aux')
		else
			_M[event]()
		end
	end)
end

do
	local cache = {}
	function LOAD()
		cache.account = aux.account
		do
			local key = format('%s|%s', GetCVar'realmName', UnitName'player')
			aux.character[key] = aux.character[key] or {}
			cache.character = aux.character[key]
		end
		do
			local key = GetCVar'realmName'
			aux.realm[key] = aux.realm[key] or {}
			cache.realm = aux.realm[key]
		end
	end
	function LOAD2()
		do
			local key = format('%s|%s', GetCVar'realmName', UnitFactionGroup'player')
			aux.faction[key] = aux.faction[key] or {}
			cache.faction = aux.faction[key]
		end
	end
	for scope in pairs(temp-S('character', 'faction', 'realm', 'account')) do
		local scope = scope
		M[scope .. '_data'] = function(key, init)
			if not cache[scope]
				then error('Cache not ready', 2)
			end
				if type(cache[scope][key]) ~= 'table' then
					cache[scope][key] = {}
				end
				if type(init) == 'table' then
					for k, v in pairs(init) do
						if cache[scope][key][k] == nil then
							cache[scope][key][k] = v
						end
					end
				end
				return cache[scope][key]
		end
	end
end

tab_info = {}
function M.TAB(name)
	local tab = O('name', name)
	local env = getfenv(2)
	function env.set_OPEN(f) tab.OPEN = f end
	function env.set_CLOSE(f) tab.CLOSE = f end
	function env.set_USE_ITEM(f) tab.USE_ITEM = f end
	function env.set_CLICK_LINK(f) tab.CLICK_LINK = f end
	tinsert(tab_info, tab)
end

do
	local index
	function get_active_tab() return tab_info[index] end
	function get_active_tab_index() return index end
	function on_tab_click(i)
		CloseDropDownMenus()
		do (index and active_tab.CLOSE or nop)() end
		index = i
		do (index and active_tab.OPEN or nop)() end
		local cd = aux.character[format('%s|%s', GetCVar'realmName', UnitName'player')]
		if type(cd) == 'table' then
			cd.last_tab = i
		end
	end
end

local function aux_extract_item(text)
	if not text then return end
	local item_id, suffix_id, name
	if strfind(text, '^item:%d+') then
		item_id = tonumber(select(3, strfind(text, '^item:(%d+)'))) or 0
		suffix_id = tonumber(select(3, strfind(text, '^item:%-?%d+:%-?%d+:%-?%d+:%-?%d+:%-?%d+:%-?%d+:(%-?%d+)'))) or 0
		name = GetItemInfo(text) or GetItemInfo(item_id)
	elseif strfind(text, '|Hitem:%-?%d+') then
		local pid, psuffix, _, _, pname = info.parse_link(text)
		item_id = tonumber(pid) or 0
		suffix_id = tonumber(psuffix) or 0
		name = pname or GetItemInfo(text)
		if not name and item_id > 0 then
			name = GetItemInfo(item_id)
		end
	end
	if item_id and item_id > 0 then
		return item_id, suffix_id or 0, name
	end
end

local function aux_route_use_item(item_id, suffix_id, name)
	if not active_tab then return false end
	local target = active_tab
	if target.name ~= 'Post' and target.name ~= 'Search' then
		for _, t in ipairs(tab_info) do
			if t.name == 'Search' then target = t; break end
		end
	end
	if not target or not target.USE_ITEM then return false end
	if target.name == 'Post' then
		if item_id and item_id > 0 then
			target.USE_ITEM(item_id, suffix_id or 0)
			return true
		end
		return false
	end
	if not name and item_id and item_id > 0 then
		name = GetItemInfo(item_id)
	end
	if name then
		target.USE_ITEM(nil, nil, nil, nil, name)
		return true
	end
	return false
end

local aux_orig_SetItemRef = SetItemRef

SetItemRef = vararg-function(arg)
	if not arg[1] then
		return (aux_orig_SetItemRef or nop)(unpack(arg))
	end
	if (AuxFrame and AuxFrame:IsShown()) and (IsShiftKeyDown() or IsAltKeyDown()) and strfind(arg[1], 'item:%-?%d+') then
		local item_id, suffix_id, name = aux_extract_item(arg[1])
		if item_id and aux_route_use_item(item_id, suffix_id, name) then
			return
		end
	end
	if arg[3] ~= 'RightButton' or not index(active_tab, 'CLICK_LINK') or not strfind(arg[1], '^item:%d+') then
		return (aux_orig_SetItemRef or nop)(unpack(arg))
	end
	local item_info = info.item(tonumber(select(3, strfind(arg[1], '^item:(%d+)'))))
	if item_info then
		return active_tab.CLICK_LINK(item_info)
	end
end

HandleModifiedItemClick = vararg-function(arg)
	if not (AuxFrame and AuxFrame:IsShown()) then return end
	if not arg[1] or not strfind(arg[1], 'item:%-?%d+') then return end
	if not (IsShiftKeyDown() or IsAltKeyDown()) then return end
	local item_id, suffix_id, name = aux_extract_item(arg[1])
	if item_id then
		aux_route_use_item(item_id, suffix_id, name)
	end
end

M.orig = setmetatable({[_G]=T}, {__index=function(self, key) return self[_G][key] end})
M.hook = vararg-function(arg)
	local name, object, handler
	if arg.n == 3 then
		name, object, handler = unpack(arg)
	else
		object, name, handler = _G, unpack(arg)
	end
	handler = handler or getfenv(3)[name]
	orig[object] = orig[object] or T
	assert(not orig[object][name], '"' .. name .. '" is already hooked into.')
	orig[object][name], object[name] = object[name], handler
	return hook
end

do
	local locked
	function M.get_bid_in_progress() return locked end
	function M.place_bid(type, index, amount, on_success)
		if locked then return end
		local money = GetMoney()
		PlaceAuctionBid(type, index, amount)
		if money >= amount then
			locked = true
			local send_signal, signal_received = signal()
			thread(when, signal_received, function()
				do (on_success or nop)() end
				locked = false
			end)
			thread(when, later(5), send_signal)
			event_listener('CHAT_MSG_SYSTEM', function(kill)
				if arg1 == ERR_AUCTION_BID_PLACED then
					send_signal()
					kill()
				end
			end)
		end
	end
end

do
	local locked
	function M.get_cancel_in_progress() return locked end
	function M.cancel_auction(index, on_success)
		if locked then return end
		locked = true
		CancelAuction(index)
		local send_signal, signal_received = signal()
		thread(when, signal_received, function()
			do (on_success or nop)() end
			locked = false
		end)
		thread(when, later(5), send_signal)
		event_listener('CHAT_MSG_SYSTEM', function(kill)
			if arg1 == ERR_AUCTION_REMOVED then
				send_signal()
				kill()
			end
		end)
	end
end

function LOAD2()
	AuxFrame:SetScale(aux_scale)
end

function AUCTION_HOUSE_SHOW()
	AuctionFrame:Hide()
	AuxFrame:Show()
	local cd = aux.character[format('%s|%s', GetCVar'realmName', UnitName'player')] or empty
	local desired = tonumber(cd.last_tab) or 1
	if desired < 1 or desired > getn(tab_info) then desired = 1 end
	if set_tab then
		set_tab(desired)
	else
		on_tab_click(desired)
	end
end

function AUCTION_HOUSE_CLOSED()
	post.stop()
	stack.stop()
	scan.abort()
	AuxFrame:Hide()
end

function Blizzard_AuctionUI()
	AuctionFrame:UnregisterEvent('AUCTION_HOUSE_SHOW')
	AuctionFrame:SetScript('OnHide', nil)
	hook('ShowUIPanel', vararg-function(arg)
		if arg[1] == AuctionFrame then
			return AuctionFrame:Show()
		end
		return orig.ShowUIPanel(unpack(arg))
	end)
	hook 'SetItemRef' 'AuctionFrameAuctions_OnEvent'
	hooksecurefunc('HandleModifiedItemClick', HandleModifiedItemClick)
end

do
	local function cost_label(cost)
		local label = LIGHTYELLOW_FONT_COLOR_CODE .. '(Total Cost: ' .. FONT_COLOR_CODE_CLOSE
		label = label .. (cost and money.to_string2(cost, nil, LIGHTYELLOW_FONT_COLOR_CODE) or GRAY_FONT_COLOR_CODE .. '---' .. FONT_COLOR_CODE_CLOSE)
		label = label .. LIGHTYELLOW_FONT_COLOR_CODE .. ')' .. FONT_COLOR_CODE_CLOSE
		return label
	end
	local function hook_quest_item(f)
		f:SetScript('OnMouseUp', function()
			if arg1 == 'RightButton' then
				if active_tab then
					if set_tab then set_tab(1) else on_tab_click(1) end
					search_tab.filter = _G[this:GetName() .. 'Name']:GetText() .. '/exact'
					search_tab.execute(nil, false)
				end
			end
		end)
	end
	function Blizzard_CraftUI()
		hook('CraftFrame_SetSelection', vararg-function(arg)
			local ret = temp-A(orig.CraftFrame_SetSelection(unpack(arg)))
			local id = GetCraftSelectionIndex()
			local total_cost = 0
			for i = 1, GetCraftNumReagents(id) do
				local link = GetCraftReagentItemLink(id, i)
				if not link then
					total_cost = nil
					break
				end
				local item_id, suffix_id = info.parse_link(link)
				local count = select(3, GetCraftReagentInfo(id, i))
				local _, price, limited = cache.merchant_info(item_id)
				local key = item_id .. ':' .. suffix_id
				-- Prefer the most recent daily/last value for profession cost; fall back to historical.
				local value = (price and not limited and price > 0) and price or history.daily_value(key) or history.value(key) or history.historical(key)
				if not value then
					total_cost = nil
					break
				else
					total_cost = total_cost + value * count
				end
			end
			CraftReagentLabel:SetText(SPELL_REAGENTS .. ' ' .. cost_label(total_cost))
			return unpack(ret)
		end)
		for i = 1, 8 do
			hook_quest_item(_G['CraftReagent' .. i])
		end
	end
	function Blizzard_TradeSkillUI()
		hook('TradeSkillFrame_SetSelection', vararg-function(arg)
			local ret = temp-A(orig.TradeSkillFrame_SetSelection(unpack(arg)))
			local id = GetTradeSkillSelectionIndex()
			local total_cost = 0
			for i = 1, GetTradeSkillNumReagents(id) do
				local link = GetTradeSkillReagentItemLink(id, i)
				if not link then
					total_cost = nil
					break
				end
				local item_id, suffix_id = info.parse_link(link)
				local count = select(3, GetTradeSkillReagentInfo(id, i))
				local _, price, limited = cache.merchant_info(item_id)
				local key = item_id .. ':' .. suffix_id
				-- Prefer the most recent daily/last value for profession cost; fall back to historical.
				local value = (price and not limited and price > 0) and price or history.daily_value(key) or history.value(key) or history.historical(key)
				if not value then
					total_cost = nil
					break
				else
					total_cost = total_cost + value * count
				end
			end
			TradeSkillReagentLabel:SetText(SPELL_REAGENTS .. ' ' .. cost_label(total_cost))
			return unpack(ret)
		end)
		for i = 1, 8 do
			hook_quest_item(_G['TradeSkillReagent' .. i])
		end
	end
end

AuctionFrameAuctions_OnEvent = vararg-function(arg)
    if AuctionFrameAuctions:IsVisible() then
	    return orig.AuctionFrameAuctions_OnEvent(unpack(arg))
    end
end
