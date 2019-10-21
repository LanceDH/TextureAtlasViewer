﻿
local _addonName, _addon = ...;

local TAV = LibStub("AceAddon-3.0"):NewAddon("AtlastTextureViewer");
local TAV_Defaults = {
	["global"] = {	
		["settings"] = {
				["passiveBorders"] = true
				,["backgroundColor"] = {["r"] = 0.25, ["g"] = 0.25, ["b"] = 0.25, ["a"] = 1}
			}
		,["AtlasInfo"] = nil
	}
}

local FORMAT_INVALID_ATLAS = "Invalid atlas name %s";
local FORMAT_INVALID_TEXTURE = "No valid atlas info for %s\nNo texture size could be calculated.";
local DATA_URL = "https://www.townlong-yak.com/framexml/live/Helix/AtlasInfo.lua";
local SAVE_VARIABLE_COPY_INFO = "Copy paste the list from " .. DATA_URL .. " here instead of this message. Make sure to include the opening and closing brackets.";

function TAV:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("ATVDB", TAV_Defaults, true);
	self.atlasInfo = self.db.global.AtlasInfo;
	
	if (not self.atlasInfo) then
		self.db.global.AtlasInfo = SAVE_VARIABLE_COPY_INFO;
		self.atlasInfo = self.db.global.AtlasInfo;
	end
	
	self.settings =  self.db.global.settings;
end

function TAV:OnEnable()
	TAV_DisplayContainer:ApplySettings(self.settings);

	-- No data imported yet
	if(type(self.atlasInfo) == "string") then
		TAV_DisplayContainer:SetImportOverlayShown(true, true);
		return;
	end

	-- Unfiltered list with easy access to names
	self.displayList = {};
	-- Buffer list for searching to allow pcall to error with no visual results
	self.bufferList = {};
	-- Filteres list that will be displayed
	self.filteredList = {};
	
	local toReplace = {};
	for texture, atlasInfo in pairs(self.atlasInfo) do
		-- Delete all imported atlas info and turn keys into an intterative list
		wipe(toReplace);
		for key in pairs(atlasInfo) do
			if (type(key) == "string") then
				tinsert(toReplace, key);
			end
		end
		for k, key in ipairs(toReplace) do
			atlasInfo[key] = nil;
			tinsert(atlasInfo, key);
		end
		
		-- Only show ones that actually have atlases to them
		if (#atlasInfo) then
			local path, name = texture:match("(.+)/(.+)");
			local displayName = name;
			if (displayName) then
				displayName = displayName:gsub("(%l)(%u)", "%1 %2");
			end
			local entryInfo = {["display"] = displayName or texture, ["name"] = name or texture, ["path"] = path, ["texture"] = texture, ["priority"] = 0};
			tinsert(self.displayList, entryInfo);
			tinsert(self.filteredList, entryInfo);
		end
	end
	
	table.sort(self.filteredList, function(a, b) 
			if (a.name == b.name) then
				return a.texture < b.texture; 
			end
			
			return a.name < b.name; 
		end);
		
	-- Show first in the list
	if (#self.filteredList > 0) then
		TAV_DisplayContainer:DisplayTexture(self.filteredList[1].texture);
	end
end

function  TAV:ClearData()
	if (not self.displayList) then 
		return false;
	end

	self.db.global.AtlasInfo = SAVE_VARIABLE_COPY_INFO;
	
	wipe(self.displayList);
	wipe(self.bufferList);
	wipe(self.filteredList);
	
	self.atlasInfo = "";
	
	TAV_ScrollFrame:RefreshButtons();
	
	return true;
end

function  TAV:GetSearchPriority(info, searchString, usePatterns)
	-- File name
	if (info.name:lower():find(searchString, nil, not usePatterns)) then
		return 1;
	end
	-- Atlas name
	for key, name in ipairs(self.atlasInfo[info.texture]) do
		if (name:lower():find(searchString, nil, not usePatterns)) then
			return 2;
		end
	end
	-- File path
	if (info.path) then
		if (info.path:lower():find(searchString, nil, not usePatterns)) then
			return 3;
		end
	end
	
	return 0;
end

function TAV:UpdateDisplayList(searchString, usePatterns)
	wipe(self.bufferList);
	for k, info in ipairs(self.displayList) do
		info.priority = self:GetSearchPriority(info, searchString, usePatterns);
		if (info.priority  > 0) then
			tinsert(self.bufferList, info);
		end
	end

	wipe(self.filteredList);
	
	for k, info in ipairs(self.bufferList) do
		tinsert(self.filteredList, info);
	end
	
	table.sort(self.filteredList, function(a, b) 
			if (a.priority ~= b.priority) then
				return a.priority < b.priority;
			end
			if (a.name ~= b.name) then
				return a.name < b.name; 
			end
			return a.texture < b.texture; 
		end);
	
	wipe(self.bufferList);
end

-------------------------------------------------
-- TAV_ScrollFrameMixin
-------------------------------------------------
-- Init()
-- RefreshButtons()
-- OnShow()

TAV_ScrollFrameMixin = {};

function TAV_ScrollFrameMixin:Init()
	if (self.initialized) then
		return;
	end

	self.update =  self.RefreshButtons;
	
	HybridScrollFrame_CreateButtons(self, "TAV_ListButtonTemplate", 0, 0);
	HybridScrollFrame_SetDoNotHideScrollBar(self, true);
	
	self.initialized = true;
end

function TAV_ScrollFrameMixin:RefreshButtons()
	local buttons = HybridScrollFrame_GetButtons(self);
	local offset = HybridScrollFrame_GetOffset(self);
	
	local toDisplay = TAV.filteredList or {};

	for i = 1, #buttons do
		local listIndex = offset + i;
		local button = buttons[i];
		
		if (toDisplay and listIndex <= #toDisplay) then
			local info = toDisplay[listIndex];
			button:Update(info);
		else
			button.texture = nil;
			button:Hide();
		end
	end
	
	local numDisplayed = math.min(#buttons, #toDisplay);
	local buttonHeight = buttons[1]:GetHeight();
	local displayedHeight = numDisplayed * buttonHeight;
	local totalHeight = #toDisplay * buttonHeight;
	HybridScrollFrame_Update(self, totalHeight, displayedHeight);
end

function TAV_ScrollFrameMixin:OnShow()
	self:Init();
	self:RefreshButtons();
end

-------------------------------------------------
-- TAV_DisplayContainerMixin
-------------------------------------------------
-- OnLoad()
-- ApplySettings()
-- OnSearchChanged()
-- NameMatchesCurrentSearch()
-- PatternCheckBoxOnClicK(value)
-- ToggleBorders()
-- BackgroundButtonOnClick()
-- SetBackgroundColor(r, g, b, a)
-- Reset()
-- UpdateOverlays()	-- Keep the overlays and change their visuals
-- CreateOverlays()	-- Recreate all overlays completely
-- DisplayTexture(texture)
-- OnMouseWheel(delta)
-- OnDragStart()
-- OnDragStop()
-- HideAtlasInfo()
-- ShowAtlasInfo(name, atlasInfo)
-- SetImportOverlayShown(show, hideButtons)

TAV_DisplayContainerMixin = {}

function TAV_DisplayContainerMixin:OnLoad()
	self.currentScale = 1;
	self.scaleMax = 3;
	self.scaleMin = 0.1;
	self.scaleStep = 0.1;
	self.width = 100;
	self.height = 100;
	
	self.AlertIndicator.dataIssues = {};
	
	self.overlayPool = CreateFramePool("BUTTON", self.Child, "TAV_AtlasFrameTemplate");
	self:RegisterForDrag("LeftButton");
	
	self.backgroundColor = CreateColor(.25, .25, .25, 1);
	
	-- Color select info
	local info = {};
	info.swatchFunc = function() local r, g, b = ColorPickerFrame:GetColorRGB(); self:SetBackgroundColor(r, g, b, 1 - OpacitySliderFrame:GetValue()) end;
	info.hasOpacity = true;
	info.opacityFunc = function() local r, g, b = ColorPickerFrame:GetColorRGB(); self:SetBackgroundColor(r, g, b, 1 - OpacitySliderFrame:GetValue()) end;
	info.cancelFunc = function(previousColor) self:SetBackgroundColor(previousColor.r, previousColor.g, previousColor.b, 1-previousColor.opacity) end;
	self.BGColorButton.info = info;
	
	-- Overlay setup
	self.Overlay.Link:SetText(DATA_URL);
	local before = [[Since there is no official way to get the info of all available textures and their atlases, data must be manually provided.

To do so, follow these steps:
  1. Log out of your character. This is important!
  2. Go into your saved variables folder.
       (WoW/WTF/Account/<Your Account>/SavedVariables)
  3. Open the file TextureAtlasViewer.lua in a text editor.
  4. There you will find the variable ["AtlasInfo"] =.
  5. Visit the following URL:]]
	self.Overlay.InfoBefore:SetText(before);
	local after=[[  6. Copy the entire table after 'AtlasInfo ='.
       Be sure to include the opening and closing brackets!
  7. Pasted it in the saved variables file so it looks like this: 
       ["AtlasInfo"] = { <a lot of data here> },
  8. SAVE the file and close it.
  9. You can now log back in and use the Add-on.
  
To update your data in the future, follow the same steps.]]
	self.Overlay.InfoAfter:SetText(after);
end

function TAV_DisplayContainerMixin:ApplySettings(settings)
	self.ToggleBordersButton.Icon:SetTexture(settings.passiveBorders and "Interface/LFGFRAME/BattlenetWorking9" or "Interface/LFGFRAME/BattlenetWorking4");
	self:SetBackgroundColor(settings.backgroundColor.r, settings.backgroundColor.g, settings.backgroundColor.b, settings.backgroundColor.a)
end

function TAV_DisplayContainerMixin:OnSearchChanged()
	local searchBox = TAV_CoreFrame.LeftInset.SearchBox;
	local text = searchBox:GetText() or "";

	text = text:lower();
	if not pcall(function() TAV:UpdateDisplayList(text, self.enablePatterns) end) then 
		searchBox:SetTextColor(1, 0.25, 0.25, 1);
		return; 
	else
		searchBox:SetTextColor(1, 1, 1, 1);
	end

	self.searchString = text;
	TAV_ScrollFrame:RefreshButtons();
	
	TAV_DisplayContainer:UpdateOverlays();
end

function TAV_DisplayContainerMixin:ClearDataButtonOnClick()
	if (not TAV:ClearData()) then return; end
	PlaySound(857);
	self:DisplayTexture();
	self:SetImportOverlayShown(true, true);
end

function TAV_DisplayContainerMixin:NameMatchesCurrentSearch(name)
	if (not name or not self.searchString or self.searchString == "") then return false; end
	
	return name:lower():find(self.searchString, nil, not self.enablePatterns);
end

function TAV_DisplayContainerMixin:PatternCheckBoxOnClicK(value)
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
	self.enablePatterns = value;
	self:OnSearchChanged();
end

function TAV_DisplayContainerMixin:ToggleBorders()
	TAV.settings.passiveBorders = not TAV.settings.passiveBorders;
	self.ToggleBordersButton.Icon:SetTexture(TAV.settings.passiveBorders and "Interface/LFGFRAME/BattlenetWorking9" or "Interface/LFGFRAME/BattlenetWorking4");
	self:UpdateOverlays();
end

function TAV_DisplayContainerMixin:BackgroundButtonOnClick()
	local info = self.BGColorButton.info;
	if (info) then
		info.r, info.g, info.b = self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b;
		info.opacity = 1 - self.backgroundColor.a;
		OpenColorPicker(info);
	end
end

function TAV_DisplayContainerMixin:SetBackgroundColor(r, g, b, a)
	self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b, self.backgroundColor.a = r, g, b, a;
	self.BGColorButton.Preview:SetColorTexture(r, g, b, 1);
	self.Child.Background:SetColorTexture(r, g, b, a);
	
	local savedBGColor = TAV.settings.backgroundColor;
	savedBGColor.r, savedBGColor.g, savedBGColor.b, savedBGColor.a = r, g, b, a;
end

function TAV_DisplayContainerMixin:Reset()
	self.currentScale = 1;
	self.Child:SetSize(self.width, self.height);
	self.Child:ClearAllPoints();
	self.Child:SetPoint("CENTER");
	self:CreateOverlays();
end

function TAV_DisplayContainerMixin:UpdateOverlays()
	-- Keep the overlays, but change their appearences
	for overlay in self.overlayPool:EnumerateActive() do
		overlay:UpdateColor();
		overlay:UpdatePosition();
	end
end

function TAV_DisplayContainerMixin:CreateOverlays()
	-- Recreate all the overlays completely
	self.overlayPool:ReleaseAll();
	local atlasNames = TAV.atlasInfo[self.texture];
	if (not atlasNames) then return; end
	
	for k, name in ipairs(atlasNames) do
		if (type(name) == "string") then
			local info = C_Texture.GetAtlasInfo(name);
			if (info) then 
				local overlay = self.overlayPool:Acquire();
				overlay:Init(name, info);
			end
		end
	end
end

function TAV_DisplayContainerMixin:DisplayTexture(texture)
	if (self.texture == texture) then return; end
	self.texture = texture;
	self.width = 256;
	self.height = 256

	wipe(self.AlertIndicator.dataIssues);
	
	if (not texture) then return; end
	
	local atlasNames = TAV.atlasInfo[texture];
	if (not atlasNames or #atlasNames == 0) then 
		return;
	end
	
	local firstValidAtlas;
	-- Loop over all atlases and check for any issues
	for i = 1, #atlasNames do
		local info = C_Texture.GetAtlasInfo(atlasNames[i]);
		if (info) then
			firstValidAtlas = info;
		else
			tinsert(self.AlertIndicator.dataIssues, FORMAT_INVALID_ATLAS:format(atlasNames[i]));
		end
	end
	
	if (firstValidAtlas) then 
		-- Calcultate texture size based on width and coords of one of the atlases
		self.width = firstValidAtlas.width / (firstValidAtlas.rightTexCoord - firstValidAtlas.leftTexCoord);
		self.height = firstValidAtlas.height / (firstValidAtlas.bottomTexCoord - firstValidAtlas.topTexCoord);
	else
		tinsert(self.AlertIndicator.dataIssues, FORMAT_INVALID_TEXTURE:format(texture));
	end
	
	self.AlertIndicator:SetShown(#self.AlertIndicator.dataIssues > 0);

	self:Reset();
	self:HideAtlasInfo();
	self.Child.Texture:SetTexture(texture);
	self.Child:Show();
	self.Child:SetSize(self.width, self.height);
	self.FilePathBox:SetText(texture);
	PlaySound(836);
	
	self:SetImportOverlayShown(false);
end

function TAV_DisplayContainerMixin:OnMouseWheel(delta)
	if (self.isDragging) then return; end
	-- Calculate the original normalized position of the container's center on the child frame
	local centerX, centerY = self:GetCenter();
	local childCenterX, childCenterY = self.Child:GetCenter();
	local originalWidth, originalHeight = self.Child:GetSize();
	local offsetX = (childCenterX - centerX) / originalWidth;
	local offsetY = (childCenterY - centerY) / originalHeight;
	-- Change the size of the child
	self.currentScale = self.currentScale + (self.scaleStep * delta);
	self.currentScale = min(self.scaleMax, max(self.scaleMin, self.currentScale));
	local newWidth = self.width * self.currentScale;
	local newHeight = self.height * self.currentScale;
	self.Child:SetSize(newWidth,newHeight);
	-- Reposition child so the container's center is on the same normalized position
	self.Child:ClearAllPoints();
	self.Child:SetPoint("CENTER", self, offsetX * newWidth, offsetY * newHeight)
	
	self:UpdateOverlays();
	if (self.mousedOverFrame) then
		self.mousedOverFrame:OnEnter();
	end
end

function TAV_DisplayContainerMixin:OnDragStart()
	if (not self.Child:IsShown()) then return; end

	self.Child:StartMoving();
	GameTooltip:Hide();
	self.isDragging = true;
end

function TAV_DisplayContainerMixin:OnDragStop()
	if (not self.isDragging) then return; end
	
	self.Child:StopMovingOrSizing();
	local selfX, selfY = self:GetCenter();
	local childX, childY = self.Child:GetCenter();
	self.Child:ClearAllPoints();
	self.Child:SetPoint("CENTER", self, childX-selfX, childY-selfY)
	self.isDragging = false;
	
	if (self.mousedOverFrame) then
		self.mousedOverFrame:OnEnter();
	end
end

function TAV_DisplayContainerMixin:HideAtlasInfo()
	TAV_InfoPanel:Hide();
	self.selectedAtlas = nil;
	self:UpdateOverlays();
end

function TAV_DisplayContainerMixin:ShowAtlasInfo(name, atlasInfo)
	if (not name or not atlasInfo) then return; end
	
	TAV_InfoPanel.Name:SetText(name);
	TAV_InfoPanel.Width:SetText(atlasInfo.width);
	TAV_InfoPanel.Height:SetText(atlasInfo.height);
	TAV_InfoPanel.Left:SetText(atlasInfo.leftTexCoord);
	TAV_InfoPanel.Right:SetText(atlasInfo.rightTexCoord);
	TAV_InfoPanel.Top:SetText(atlasInfo.topTexCoord);
	TAV_InfoPanel.Bottom:SetText(atlasInfo.bottomTexCoord);
	TAV_InfoPanel.IconHorizontalTile:SetAtlas(atlasInfo.tilesHorizontally and "ParagonReputation_Checkmark" or "communities-icon-redx")
	TAV_InfoPanel.IconVerticalTile:SetAtlas(atlasInfo.tilesVertically and "ParagonReputation_Checkmark" or "communities-icon-redx")
	TAV_InfoPanel:Show();
end

function TAV_DisplayContainerMixin:SetImportOverlayShown(show, hideButtons)
	if (not show and (not TAV.displayList or #TAV.displayList == 0)) then
		return;
	end
	self.Overlay:SetShown(show);

	self.Overlay.ClearDataButton:SetShown(not hideButtons);
	TAV_CoreFrame.LeftInset.InfoButton:SetShown(not hideButtons);
end

-------------------------------------------------
-- TAV_ListButtonMixin
-------------------------------------------------
-- Update(info)
-- OnClick()

TAV_ListButtonMixin = {};

function TAV_ListButtonMixin:Update(info)
	self.texture = info.texture;
	self:Show();
	self.Text:SetText(info.display);
	local color = NORMAL_FONT_COLOR;
	if (info.priority == 2) then
		color = WHITE_FONT_COLOR;
	elseif (info.priority == 3) then
		color = GRAY_FONT_COLOR;
	end
	self.Text:SetVertexColor(color:GetRGB());
	
	self.SelectedOverlay:SetShown(self.texture == self:GetParent().selected);
end

function TAV_ListButtonMixin:OnClick()
	TAV_DisplayContainer:DisplayTexture(self.texture);
	self:GetParent().selected = self.texture;
	self:GetParent():GetParent():RefreshButtons();
end

-------------------------------------------------
-- TAV_AtlasFrameMixin
-------------------------------------------------
-- OnLoad()
-- SetBorderHighlighted(value)
-- OnClick()
-- OnEnter()
-- OnLeave()
-- OnDragStart()
-- OnDragStop()
-- UpdateColor()
-- UpdatePosition()
-- Init(name, info)
-- 

TAV_AtlasFrameMixin = {};

function TAV_AtlasFrameMixin:OnLoad()
	self:RegisterForDrag("LeftButton");
end

function TAV_AtlasFrameMixin:SetBorderHighlighted(value)
	local alpha = TAV.settings.passiveBorders and 0.15 or 0;
	alpha = value and 0.5 or alpha;
	
	self.Top:SetAlpha(alpha);
	self.Bottom:SetAlpha(alpha);
	self.Left:SetAlpha(alpha);
	self.Right:SetAlpha(alpha);
end

function TAV_AtlasFrameMixin:OnClick()
	TAV_DisplayContainer.selectedAtlas = self.name;
	TAV_DisplayContainer:ShowAtlasInfo(self.name, self.info);
	TAV_DisplayContainer:UpdateOverlays();
	PlaySound(857);
end

function TAV_AtlasFrameMixin:OnEnter()
	if (self:GetParent():GetParent().isDragging) then
		return;
	end
	-- Calculate the offset so the tooltip is always positioned inside the container
	local offsetX = max(0, self:GetRight() - TAV_DisplayContainer:GetRight());
	local offsetY = max(0, self:GetTop() - TAV_DisplayContainer:GetTop());
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -offsetX, -offsetY);
	GameTooltip:SetText(self.name or "Unknown", 1, 1, 1, nil, true);
	GameTooltip:Show();
	self:GetParent():GetParent().mousedOverFrame = self;
	self:SetBorderHighlighted(true);
end

function TAV_AtlasFrameMixin:OnLeave()
	GameTooltip:Hide();
	self:GetParent():GetParent().mousedOverFrame = nil;
	self:SetBorderHighlighted(self.shouldHighlight);
end

function TAV_AtlasFrameMixin:OnDragStart()
	TAV_DisplayContainer:OnDragStart();
end

function TAV_AtlasFrameMixin:OnDragStop()
	TAV_DisplayContainer:OnDragStop();
end

function TAV_AtlasFrameMixin:UpdateColor()
	local color = WHITE_FONT_COLOR;
	self.shouldHighlight = false;
	if(self.name == TAV_DisplayContainer.selectedAtlas) then
		color = YELLOW_FONT_COLOR;
		self.shouldHighlight = true;
	elseif (TAV_DisplayContainer:NameMatchesCurrentSearch(self.name)) then
		color = GREEN_FONT_COLOR;
		self.shouldHighlight = true;
	end

	self:SetBorderHighlighted(self.shouldHighlight);
	self.Top:SetVertexColor(color:GetRGB());
	self.Bottom:SetVertexColor(color:GetRGB());
	self.Left:SetVertexColor(color:GetRGB());
	self.Right:SetVertexColor(color:GetRGB());
	self.Highlight:SetVertexColor(color:GetRGB());
end

function TAV_AtlasFrameMixin:UpdatePosition()
	local info = self.info;
	local parent = self:GetParent()
	local width, height = parent:GetSize();
	self:SetPoint("TOPLEFT", parent, info.leftTexCoord * width, -info.topTexCoord * height);
	self:SetPoint("BOTTOMRIGHT", parent, -(1 - info.rightTexCoord) * width, (1-info.bottomTexCoord) * height);
end

function TAV_AtlasFrameMixin:Init(name, info)
	if(not name or not info) then return; end

	self.name = name;
	self.info = info;
	self:UpdatePosition()
	self:UpdateColor();
	self:Show();
end

-------------------------------------------------
-- Slash Command
-------------------------------------------------

SLASH_TAVSLASH1 = '/tav';
SLASH_TAVSLASH2 = '/textureatlasviewer';
local function slashcmd()
	if (InCombatLockdown()) then return; end

	TAV_CoreFrame:Show();
end
SlashCmdList["TAVSLASH"] = slashcmd

