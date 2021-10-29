
local _addonName, _addon = ...;

local TAV = LibStub("AceAddon-3.0"):NewAddon("AtlastTextureViewer");
local TAV_Defaults = {
	["global"] = {	
		["settings"] = {
				["passiveBorders"] = true,
				["backgroundColor"] = {["r"] = 0.25, ["g"] = 0.25, ["b"] = 0.25, ["a"] = 1},
				["showIssues"] = false;
			}
		,["AtlasInfo"] = nil
	}
}

local MAX_NUM_ISSUES = 30;
local FORMAT_ISSUE_OVERFLOW = "+%s more issues.";
local FORMAT_INVALID_ATLAS = "Atlas %s not found through API";
local FORMAT_INVALID_TEXTURE = "No valid atlas info for %s\nNo texture size could be calculated.";
local DATA_URL = "https://www.townlong-yak.com/framexml/live/Helix/AtlasInfo.lua";
local SAVE_VARIABLE_COPY_INFO = "Copy paste the list from " .. DATA_URL .. " here instead of this message. Make sure to include the opening and closing brackets.";

local RESULT_PRIORITY = {
	["none"] = 0
	,["fileName"] = 1
	,["atlasName"] = 2
	,["folderName"] = 3
}

function TAV:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("ATVDB", TAV_Defaults, true);
	self.atlasInfo = _addon.data;
	
	-- Check every atlas if the API knows it exists
	-- If not we store it ourselves if the user wants to see it anyway
	self.backupInfo = {};

	for file, list in pairs(self.atlasInfo) do
		local isvalid = false;
		for atlas, info in pairs(list) do
			if (not TAV:GetAtlasInfo(atlas)) then
				local reformat =  {["missing"] = true, ["fileName"] = file, ["width"] = info[1], ["height"] = info[2], ["leftTexCoord"] = info[3], ["rightTexCoord"] = info[4], ["topTexCoord"] = info[5], ["bottomTexCoord"] = info[6], ["tilesHorizontally"] = info[7], ["tilesVertically"] = info[8]};
				self.backupInfo[atlas] = reformat;
			else
			 isvalid = true;
			end
		end
	end

	-- Remove old data
	if (self.db.global.AtlasInfo) then
		self.db.global.AtlasInfo = nil;
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
		-- Delete all imported atlas info and turn keys into an itterative list
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
			local entryInfo = {["display"] = displayName or texture, ["name"] = name or texture, ["path"] = path, ["texture"] = texture, ["priority"] = RESULT_PRIORITY.none};
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
		TAV_ScrollFrameScrollChild.selected = self.filteredList[1].texture;
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
		return RESULT_PRIORITY.fileName;
	end
	-- Atlas name
	for key, name in ipairs(self.atlasInfo[info.texture]) do
		if (name:lower():find(searchString, nil, not usePatterns)) then
			return RESULT_PRIORITY.atlasName;
		end
	end
	-- File path
	if (info.path) then
		if (info.path:lower():find(searchString, nil, not usePatterns)) then
			return RESULT_PRIORITY.folderName;
		end
	end
	
	return RESULT_PRIORITY.none;
end

function TAV:UpdateDisplayList(searchString, usePatterns)
	wipe(self.bufferList);
	for k, info in ipairs(self.displayList) do
		info.priority = self:GetSearchPriority(info, searchString, usePatterns);
		if (info.priority  > RESULT_PRIORITY.none) then
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

function  TAV:GetAtlasInfo(atlasName)
	-- Check if we know it's missing and made backup data;
	if (self.backupInfo[atlasName]) then
		return self.backupInfo[atlasName];
	end

	-- Try Classic API
	if (WOW_PROJECT_ID == WOW_PROJECT_CLASSIC) then
		local fileName, width, height, leftTexCoord, rightTexCoord, topTexCoord, bottomTexCoord, tilesHorizontally, tilesVertically = GetAtlasInfo(atlasName);
		if (not fileName) then return; end
		return { ["fileName"] = fileName, ["width"] = width, ["height"] = height, ["leftTexCoord"] = leftTexCoord, ["rightTexCoord"] = rightTexCoord, ["bottomTexCoord"] = bottomTexCoord, ["topTexCoord"] = topTexCoord, ["tilesHorizontally"] = tilesHorizontally, ["tilesVertically"] = tilesVertically };
	end
	
	-- Retail API
	return C_Texture.GetAtlasInfo(atlasName);
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
-- SetDisplayScale(scale, userInput)
-- Reset()
-- UpdateOverlays()	-- Keep the overlays and change their visuals
-- CreateOverlays()	-- Recreate all overlays completely
-- DisplayTexture(texture)
-- UpdateChildSize() -- Apply scaling to the child and update the overlays
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
	local width, height = self:GetSize();
	self.autoScaleWidth = width - 40;
	self.autoScaleHeight = height - 40;
	
	TAV_ControlsPanel.ScaleSlider:SetMinMaxValues(self.scaleMin, self.scaleMax);
	TAV_ControlsPanel.ScaleSlider:SetValue(self.currentScale);
	TAV_ControlsPanel.ScaleSlider:SetValueStep(self.scaleStep);
	TAV_ControlsPanel.ScaleSlider:SetObeyStepOnDrag(true);
	
	self.dataIssues = {};
	
	self.overlayPool = CreateFramePool("BUTTON", self.Child, "TAV_AtlasFrameTemplate");
	self:RegisterForDrag("LeftButton");
	
	self.backgroundColor = CreateColor(.25, .25, .25, 1);
	
	-- Color select info
	local info = {};
	info.swatchFunc = function() local r, g, b = ColorPickerFrame:GetColorRGB(); self:SetBackgroundColor(r, g, b, 1 - OpacitySliderFrame:GetValue()) end;
	info.hasOpacity = true;
	info.opacityFunc = function() local r, g, b = ColorPickerFrame:GetColorRGB(); self:SetBackgroundColor(r, g, b, 1 - OpacitySliderFrame:GetValue()) end;
	info.cancelFunc = function(previousColor) self:SetBackgroundColor(previousColor.r, previousColor.g, previousColor.b, 1-previousColor.opacity) end;
	TAV_ControlsPanel.BGColorButton.info = info;
	
	-- Overlay setup
	self.Overlay.Link:SetText(DATA_URL);
	local before = [[Since there is no official way to get the info of all available textures and their atlases, data must be manually provided.
As of version 9.0.01, a default set of data is provided with the add-on.

If you wish to manually update your data to a different version, follow these steps:
  1. Go into your add-on folder.
       (WoW/_retail_/Interface/AddOns/TextureAtlasViewer)
  2. Open the file Data.lua in a text editor.
  3. Some commented text will provide addition information
  4. Visit the following URL:]]
	self.Overlay.InfoBefore:SetText(before);
	local after=[[  5. Copy the entire text block starting with 'local AtlasInfo =' and ending at the last closing brackets
  6. Do not include the last line which says 'return AtlasInfo'
  7. Replace the block of text in the file in between the two comment blocks.
  8. SAVE the file and close it.
  9. /reload your ui in game
  ]]
  
  local patchNr, buildNr = GetBuildInfo();
  local colorCode = (tonumber(_addon.dataBuild) < tonumber(buildNr)) and "ffff5555" or "ff55ff55";
  
	after = after .. "\n\nClient build nr: |cffffffff" .. buildNr .. "|r\nData build nr: |c"..colorCode .. _addon.dataBuild .."|r";
	self.Overlay.InfoAfter:SetText(after);
end

function TAV_DisplayContainerMixin:ApplySettings(settings)
	TAV_ControlsPanel.ToggleBordersButton.Icon:SetTexture(settings.passiveBorders and "Interface/LFGFRAME/BattlenetWorking9" or "Interface/LFGFRAME/BattlenetWorking4");
	self:SetBackgroundColor(settings.backgroundColor.r, settings.backgroundColor.g, settings.backgroundColor.b, settings.backgroundColor.a)
end

function TAV_DisplayContainerMixin:OnSearchChanged()
	local searchBox = TAV_CoreFrame.LeftInset.SearchBox;
	local text = searchBox:GetText() or "";

	text = text:lower();
	text = text:gsub(" ", "");
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
	TAV_ControlsPanel.ToggleBordersButton.Icon:SetTexture(TAV.settings.passiveBorders and "Interface/LFGFRAME/BattlenetWorking9" or "Interface/LFGFRAME/BattlenetWorking4");
	self:UpdateOverlays();
end

function TAV_DisplayContainerMixin:BackgroundButtonOnClick()
	local info = TAV_ControlsPanel.BGColorButton.info;
	if (info) then
		info.r, info.g, info.b = self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b;
		info.opacity = 1 - self.backgroundColor.a;
		OpenColorPicker(info);
	end
end

function TAV_DisplayContainerMixin:SetBackgroundColor(r, g, b, a)
	self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b, self.backgroundColor.a = r, g, b, a;
	TAV_ControlsPanel.BGColorButton.Preview:SetColorTexture(r, g, b, 1);
	self.Child.Background:SetColorTexture(r, g, b, a);
	
	local savedBGColor = TAV.settings.backgroundColor;
	savedBGColor.r, savedBGColor.g, savedBGColor.b, savedBGColor.a = r, g, b, a;
end

function TAV_DisplayContainerMixin:SetSDisplayScale(scale, userInput)
	if (not userInput) then return; end
	scale = min(self.scaleMax, max(self.scaleMin, scale));
	self.currentScale = scale;
	self:UpdateChildSize();
	local roundedScale = Round(scale * 100);
	local display = PERCENTAGE_STRING:format(roundedScale);
	TAV_ControlsPanel.ScaleSlider.Text:SetText(display);
	TAV_ControlsPanel.ScaleSlider:SetValue(scale);
end

function TAV_DisplayContainerMixin:Reset()

	self:TrySetTextureSize();

	local scale = 1;
	if (self.height > self.autoScaleHeight or self.width > self.autoScaleWidth) then
		local widthScale = floor(self.autoScaleWidth / self.width / self.scaleStep) * self.scaleStep;
		local heightScale = floor(self.autoScaleHeight / self.height  / self.scaleStep) * self.scaleStep;
		scale = max(self.scaleMin, min(widthScale, heightScale));
	end
	self:SetSDisplayScale(scale, true);
	self.Child:ClearAllPoints();
	self.Child:SetPoint("CENTER");
	self:CreateOverlays();

	self.AlertIndicator.Icon:SetDesaturated(TAV.settings.showIssues);
	self.AlertIndicator.enabled = TAV.settings.showIssues;
end

function TAV_DisplayContainerMixin:UpdateOverlays()
	if (not self.overlayPool) then return; end
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
			local info = TAV:GetAtlasInfo(name);
			if (info and (not info.missing or TAV.settings.showIssues)) then 
				local overlay = self.overlayPool:Acquire();
				overlay:Init(name, info);
			end
		end
	end
end

function TAV_DisplayContainerMixin:TrySetTextureSize()
	wipe(self.dataIssues);
	local issueOverflow = 0;
	local issuesFound = false;
	
	if (not self.texture) then return; end
	
	local atlasNames = TAV.atlasInfo[self.texture];
	if (not atlasNames or #atlasNames == 0) then 
		return;
	end
	
	local validAtlas;
	local id = 0;
	-- Loop over all atlases and check for any issues
	for i = 1, #atlasNames do
		local info = TAV:GetAtlasInfo(atlasNames[i]);
		if (not info or info.missing) then
			-- Mark it as an issue
			issuesFound = true;
			if (#self.dataIssues < MAX_NUM_ISSUES) then
				tinsert(self.dataIssues, atlasNames[i]);
			else
				issueOverflow = issueOverflow + 1;
			end
			
			-- If user wants to include issue altases, count it as the first valid
			if (info and TAV.settings.showIssues) then
				validAtlas = info;
				id = i;
			end
		else
			validAtlas = info;
			id = i;
		end
	end
	
	-- too many issues
	if (issueOverflow > 0) then
		tinsert(self.dataIssues, FORMAT_ISSUE_OVERFLOW:format(issueOverflow));
	end
	
	if (validAtlas) then 
		-- Calcultate texture size based on width and coords of one of the atlases
		self.width = validAtlas.width / (validAtlas.rightTexCoord - validAtlas.leftTexCoord);
		self.height = validAtlas.height / (validAtlas.bottomTexCoord - validAtlas.topTexCoord);
	else
		self.width = 256;
		self.height = 256;
		tinsert(self.dataIssues, FORMAT_INVALID_TEXTURE:format(self.texture));
	end
	
	self.AlertIndicator:SetShown(issuesFound);
end

function TAV_DisplayContainerMixin:DisplayTexture(texture)
	if (self.texture == texture) then return; end
	self.texture = texture;
	self.width = 256;
	self.height = 256;
	self:Reset();
	self:HideAtlasInfo();
	self.Child.Texture:SetTexture(texture);
	self.Child:Show();
	TAV_ControlsPanel.FilePathBox:SetText(texture);
	PlaySound(836);
	
	self:SetImportOverlayShown(false);
end

function TAV_DisplayContainerMixin:UpdateChildSize()
	local newWidth = self.width * self.currentScale;
	local newHeight = self.height * self.currentScale;
	self.Child:SetSize(newWidth,newHeight);
	self:UpdateOverlays();
	return newWidth, newHeight
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
	local scale = self.currentScale + (self.scaleStep * delta);
	scale = min(self.scaleMax, max(self.scaleMin, scale));
	self:SetSDisplayScale(scale, true);
	local newWidth, newHeight = self.Child:GetSize();
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
	TAV_InfoPanel.IconHorizontalTile:SetAtlas(atlasInfo.tilesHorizontally and "ParagonReputation_Checkmark" or "communities-icon-redx");
	TAV_InfoPanel.IconVerticalTile:SetAtlas(atlasInfo.tilesVertically and "ParagonReputation_Checkmark" or "communities-icon-redx");
	TAV_InfoPanel.AlertIndicator:SetShown(atlasInfo.missing);

	TAV_InfoPanel.Lua:SetText(string.format(
		'tex:SetTexCoord(%s, %s, %s, %s)',
		atlasInfo.leftTexCoord,
		atlasInfo.rightTexCoord,
		atlasInfo.topTexCoord,
		atlasInfo.bottomTexCoord
	))

	TAV_InfoPanel.XML:SetText(string.format(
		'<TexCoords left="%s" right="%s" top="%s" bottom="%s"/>',
		atlasInfo.leftTexCoord,
		atlasInfo.rightTexCoord,
		atlasInfo.topTexCoord,
		atlasInfo.bottomTexCoord
	))

	TAV_InfoPanel:Show();
end

function TAV_DisplayContainerMixin:SetImportOverlayShown(show, hideButtons)
	if (not show and (not TAV.displayList or #TAV.displayList == 0)) then
		return;
	end
	self.Overlay:SetShown(show);

	TAV_CoreFrame.LeftInset.InfoButton:SetShown(not hideButtons);
end

function TAV_DisplayContainerMixin:OnUpdate(elapsed)
	if (self:IsMouseOver()) then
		local x, y = GetCursorPosition();
		local effectiveScale = UIParent:GetEffectiveScale();
		x = x / effectiveScale;
		y = y / effectiveScale;
		
		x = x - self.Child:GetLeft();
		y =  -y + self.Child:GetTop();
		
		local width, height = self.Child:GetSize();
	
		x = Saturate(x/width);
		y = Saturate(y/height);
		
		
		TAV_ControlsPanel.Coordinates.PosX:SetText(string.format("%.5f", x));
		TAV_ControlsPanel.Coordinates.PosY:SetText(string.format("%.5f", y));
	end
end

function TAV_DisplayContainerMixin:ToggleIssueDisplay()
	TAV.settings.showIssues = not TAV.settings.showIssues;
	self:Reset();
	self:AlertIndicatorOnEnter();
end

function TAV_DisplayContainerMixin:AlertIndicatorOnEnter()
	GameTooltip:Hide();
	GameTooltip:SetOwner(self.AlertIndicator, "ANCHOR_RIGHT");
	GameTooltip:SetText("No API info for following atlases", 1, 1, 1, nil, true);
	for k, issue in ipairs(self.dataIssues) do
		GameTooltip:AddLine(issue);
	end
	GameTooltip:AddLine("Your data might be outdated or incorrect.", 1, 0.3, 0.3);
	if (self.AlertIndicator.enabled) then
		GameTooltip:AddLine("Click to prevent potentially outdated data.", GREEN_FONT_COLOR:GetRGB());
	else
		GameTooltip:AddLine("Click to allow potentially outdated data.", GREEN_FONT_COLOR:GetRGB());
	end
	GameTooltip:Show();
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
	if (info.priority == RESULT_PRIORITY.atlasName) then
		color = HIGHLIGHT_FONT_COLOR;
	elseif (info.priority == RESULT_PRIORITY.folderName) then
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
	local display = self.name or "Unknown";
	if (not self.info or self.info.missing) then
		display = "|A:services-icon-warning:14:14|a " .. display;
	end
	GameTooltip_SetTitle(GameTooltip, display, nil, true);
	GameTooltip:Show();
	self:GetParent():GetParent().mousedOverFrame = self;
	self:SetBorderHighlighted(true);
	
	if (self.info.missing) then 
		self.Top:SetVertexColor(RED_FONT_COLOR:GetRGB());
		self.Bottom:SetVertexColor(RED_FONT_COLOR:GetRGB());
		self.Left:SetVertexColor(RED_FONT_COLOR:GetRGB());
		self.Right:SetVertexColor(RED_FONT_COLOR:GetRGB());
		self.Highlight:SetVertexColor(RED_FONT_COLOR:GetRGB());
	end
end

function TAV_AtlasFrameMixin:OnLeave()
	GameTooltip:Hide();
	self:GetParent():GetParent().mousedOverFrame = nil;
	self:SetBorderHighlighted(self.shouldHighlight);
	self:UpdateColor();
end

function TAV_AtlasFrameMixin:OnDragStart()
	TAV_DisplayContainer:OnDragStart();
end

function TAV_AtlasFrameMixin:OnDragStop()
	TAV_DisplayContainer:OnDragStop();
end

function TAV_AtlasFrameMixin:UpdateColor()
	local color = HIGHLIGHT_FONT_COLOR;
	local colorOverlay = HIGHLIGHT_FONT_COLOR;
	-- issue gets red border
	if (self.info.missing) then
		color = RED_FONT_COLOR;
	end
	
	self.shouldHighlight = false;
	if(self.name == TAV_DisplayContainer.selectedAtlas) then
		color = YELLOW_FONT_COLOR;
		self.shouldHighlight = true;
		
		if (self.info.missing) then
		color = RED_FONT_COLOR;
		
	end
	elseif (TAV_DisplayContainer:NameMatchesCurrentSearch(self.name)) then
		color = GREEN_FONT_COLOR;
		self.shouldHighlight = true;
	end
	
	---- issue always shows red overlay
	--if (self.info.missing) then
	--	colorOverlay = RED_FONT_COLOR;
	--	
	--	-- issue border overtakes selected color
	--	if (self.name == TAV_DisplayContainer.selectedAtlas) then
	--		color = RED_FONT_COLOR;
	--	end
	--end

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
local function slashcmd(msg)
	if (InCombatLockdown()) then return; end
	if (msg ~= "") then
		TAV_CoreFrame.LeftInset.SearchBox:SetText(msg);
	end
	TAV_CoreFrame:Show();
end
SlashCmdList["TAVSLASH"] = slashcmd

