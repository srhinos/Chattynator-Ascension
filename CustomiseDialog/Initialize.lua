---@class addonTableChattynator
local addonTable = select(2, ...)


function addonTable.CustomiseDialog.Initialize()
  -- Create shortcut to open Chattynator options from the Blizzard addon options
  -- panel
  local optionsFrame = CreateFrame("Frame")

  -- 3.3.5: GameFontNormalHuge3 is a retail font (absent here -> "Couldn't find inherited node"
  -- crash). Use a stock font.
  local instructions = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  instructions:SetPoint("CENTER", optionsFrame)
  instructions:SetText(WHITE_FONT_COLOR:WrapTextInColorCode(addonTable.Locales.TO_OPEN_OPTIONS_X))

  local version = C_AddOns.GetAddOnMetadata("Chattynator", "Version")
  local versionText = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  versionText:SetPoint("CENTER", optionsFrame, 0, 28)
  versionText:SetText(WHITE_FONT_COLOR:WrapTextInColorCode(addonTable.Locales.VERSION_COLON_X:format(version)))

  local header = optionsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge") -- 3.3.5: GameFontNormalHuge3 is retail; stock font
  header:SetScale(3)
  header:SetPoint("CENTER", optionsFrame, 0, 30)
  header:SetText(LINK_FONT_COLOR:WrapTextInColorCode(addonTable.Locales.CHATTYNATOR))

  -- 3.3.5: C_XMLUtil and both probed templates are retail-only; use stock UIPanelButtonTemplate
  -- and size it manually (fontString width + padding) in place of DynamicResizeButton_Resize.
  local button = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
  button:SetText(addonTable.Locales.OPEN_OPTIONS)
  button.padding = 40
  button:SetWidth(button:GetFontString():GetStringWidth() + button.padding)
  button:SetHeight(22)
  button:SetPoint("CENTER", optionsFrame, 0, -30)
  button:SetScale(2)
  button:SetScript("OnClick", function()
    addonTable.CustomiseDialog:Toggle()
  end)


  -- 3.3.5: the retail Settings API is absent -> stock InterfaceOptions. OnCommit/OnDefault/
  -- OnRefresh map to the panel's okay/cancel/default/refresh hooks.
  optionsFrame.name = addonTable.Locales.CHATTYNATOR
  optionsFrame.okay = function() end
  optionsFrame.cancel = function() end
  optionsFrame.default = function() end
  optionsFrame.refresh = function() end
  if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(optionsFrame)
  end
end
