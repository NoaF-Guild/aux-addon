module 'aux.core.shortcut'

include 'T'
include 'aux'

local info = require 'aux.util.info'

hooksecurefunc('ContainerFrameItemButton_OnModifiedClick', function(self, button)
	if not AuxFrame or not AuxFrame:IsShown() then return end
	if not (IsAltKeyDown() or IsControlKeyDown()) then return end
	if button ~= 'LeftButton' then return end

	local bag = self:GetParent():GetID()
	local slot = self:GetID()
	local item_info = info.container_item(bag, slot)
	if item_info and get_tab() and get_tab().USE_ITEM then
		get_tab().USE_ITEM(item_info)
	end
end)
