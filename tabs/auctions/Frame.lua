module 'aux.tabs.auctions'

local gui = require 'aux.gui'
local auction_listing = require 'aux.gui.auction_listing'

frame = CreateFrame('Frame', nil, AuxFrame)
frame:SetAllPoints()
frame:SetScript('OnUpdate', on_update)
frame:Hide()

frame.listing = gui.panel(frame)
frame.listing:SetPoint('TOP', frame, 'TOP', 0, -8)
frame.listing:SetPoint('BOTTOMLEFT', AuxFrame.content, 'BOTTOMLEFT', 0, 0)
frame.listing:SetPoint('BOTTOMRIGHT', AuxFrame.content, 'BOTTOMRIGHT', 0, 0)

listing = auction_listing.new(frame.listing, 20, auction_listing.auctions_columns)
listing.group_key_fn = function(record) return record.item_key .. ':' .. (record.sale_status or 0) end
listing:SetSort(1, 2, 3, 4, 5, 6, 7, 8)
listing:Reset()
listing:SetHandler('OnDatabaseChanged', function() update_total_sold() end)
listing:SetHandler('OnClick', function(row, button)
    if (IsShiftKeyDown() or IsAltKeyDown()) and listing:GetSelection().record == row.record then
        cancel_button:Click()
    end
end)
listing:SetHandler('OnSelectionChanged', function(rt, datum)
    if not datum then return end
    find_auction(datum.record)
end)

do
	status_bar = gui.status_bar(frame)
    status_bar:SetWidth(265)
    status_bar:SetHeight(25)
    status_bar:SetPoint('TOPLEFT', AuxFrame.content, 'BOTTOMLEFT', 0, -6)
    status_bar:update_status(1, 1)
    status_bar:set_text('')
end
do
    local btn = gui.button(frame)
    btn:SetPoint('TOPLEFT', status_bar, 'TOPRIGHT', 5, 0)
    btn:SetText('Cancel')
    btn:Disable()
    cancel_button = btn
end
do
    local btn = gui.button(frame)
    btn:SetPoint('TOPLEFT', cancel_button, 'TOPRIGHT', 5, 0)
    btn:SetText('Refresh')
    btn:SetScript('OnClick', GetOwnerAuctionItems)
	refresh_button = btn
end

-- Totals text (sold/posted) shown between Refresh and Blizzard UI buttons.
do
	local f = CreateFrame('Frame', nil, frame)
	f:SetPoint('TOPLEFT', refresh_button, 'TOPRIGHT', 10, 0)
	f:SetPoint('BOTTOMRIGHT', blizzard_ui_button, 'BOTTOMLEFT', -10, 0)
	totals_frame = f
end

do
	local text = totals_frame:CreateFontString(nil, 'ARTWORK')
	-- Fixed size (not tied to font settings).
	text:SetFont(gui.get_font(), 12, 'NONE')
	text:SetJustifyH('LEFT')
	text:SetJustifyV('CENTER')
	-- Default (single line) layout: vertically centered.
	text:SetPoint('LEFT', totals_frame, 'LEFT', 0, 0)
	text:SetPoint('RIGHT', totals_frame, 'RIGHT', 0, 0)
	text:SetTextColor(color.label.enabled())
	total_sold_text = text
end

do
	local text = totals_frame:CreateFontString(nil, 'ARTWORK')
	-- Fixed size (not tied to font settings).
	text:SetFont(gui.get_font(), 12, 'NONE')
	text:SetJustifyH('LEFT')
	text:SetJustifyV('CENTER')
	-- Position is applied dynamically from update_total_sold().
	text:SetTextColor(color.label.enabled())
	text:Hide()
	total_post_text = text
end
