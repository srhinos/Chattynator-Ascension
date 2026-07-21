---@class addonTableChattynator
local addonTable = select(2, ...)

local E, S, B, LSM, CH
local hoverColor = {r = 1, g = 1, b = 1}

local function ConvertTags(tags)
  local result = {}
  for _, tag in ipairs(tags) do
    result[tag] = true
  end
  return result
end

local enableHooks = false

local intensity = 0.6

local toUpdate = {}

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function()
  eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
  C_Timer.After(0.1, function()
    enableHooks = true
  end)
  for _, func in ipairs(toUpdate) do
    func()
  end
end)

-- Active only when ElvUI is the loaded skin. Textures are .tga; retail-only skin methods
-- (GetUnboundedStringWidth) are shimmed in Core/Compat.lua.
local skinners = {
  Button = function(frame)
    if S and S.HandleButton then
      S:HandleButton(frame)
    end
  end,
  ButtonFrame = function(frame)
    if S and S.HandlePortraitFrame then
      S:HandlePortraitFrame(frame)
    elseif S and S.HandleFrame then
      S:HandleFrame(frame)
    else
      frame:SetTemplate("Transparent")
    end
  end,
  SearchBox = function(frame)
    if S and S.HandleEditBox then
      S:HandleEditBox(frame)
    end
  end,
  EditBox = function(frame)
    if S and S.HandleEditBox then
      S:HandleEditBox(frame)
    end
  end,
  ChatEditBox = function(editBox)
    for _, texName in ipairs({"Left", "Right", "Mid", "FocusLeft", "FocusRight", "FocusMid"}) do
      local tex = _G[editBox:GetName() .. texName]
      if tex then
        tex:SetParent(addonTable.hiddenFrame)
      end
    end
    editBox:SetHeight(22)
    if S and S.HandleEditBox then
      S:HandleEditBox(editBox)
    end
    if editBox.backdrop then
      editBox.backdrop:SetPoint("TOPLEFT", 1, 0)
      editBox.backdrop:SetPoint("RIGHT", -1, 0)
    end
    local font = (CH and CH.db and CH.db.font) or (E and E.db and E.db.general and E.db.general.font) or "Friz Quadrata TT"
    local fontOutline = (CH and CH.db and CH.db.fontOutline) or "NONE"
    local _, size = editBox:GetFont()
    if LSM and editBox.FontTemplate then
      editBox:FontTemplate(LSM:Fetch('font', font), size or 12, fontOutline)
    end
    if addonTable.allChatFrames and addonTable.allChatFrames[1] and addonTable.allChatFrames[1].UpdateEditBox then
      addonTable.allChatFrames[1]:UpdateEditBox()
    end
  end,
  TabButton = function(frame)
    if S and S.HandleTab then
      S:HandleTab(frame)
    end
  end,
  ChatButton = function(button, tags)
    button:SetSize(26, 28)
    button:ClearNormalTexture()
    button:ClearPushedTexture()
    button:ClearHighlightTexture()

    button:HookScript("OnEnter", function()
      if not enableHooks then
        return
      end
      if button.Icon then
        button.Icon:SetVertexColor(hoverColor.r, hoverColor.g, hoverColor.b)
      end
    end)

    button:HookScript("OnLeave", function()
      if not enableHooks then
        return
      end
      if button.Icon then
        button.Icon:SetVertexColor(intensity, intensity, intensity)
      end
    end)
    if button.Icon then
      button.Icon:SetVertexColor(intensity, intensity, intensity)
    end
  end,
  ChatTab = function(tab)
    tab:SetHeight(22)
    tab:SetNormalFontObject("GameFontNormal")
    if tab:GetFontString() == nil then
      tab:SetText(" ")
    end
    tab.glow = tab:CreateTexture(nil, "BORDER")
    tab.glow:SetTexture("Interface\\AddOns\\Chattynator\\Assets\\ElvUIChatTabNewMessageFlash")
    tab.glow:SetPoint("BOTTOMLEFT", 8, -2)
    tab.glow:SetPoint("BOTTOMRIGHT", -8, -2)
    tab.glow:SetAlpha(0)
    if tab:GetFontString() then
      tab:GetFontString():SetWordWrap(false)
      tab:GetFontString():SetNonSpaceWrap(false)
      local tabFont = (CH and CH.db and CH.db.tabFont) or (E and E.db and E.db.general and E.db.general.font) or "Friz Quadrata TT"
      local tabFontSize = (CH and CH.db and CH.db.tabFontSize) or 12
      local tabFontOutline = (CH and CH.db and CH.db.tabFontOutline) or "NONE"
      if LSM and tab:GetFontString().FontTemplate then
        tab:GetFontString():FontTemplate(LSM:Fetch('font', tabFont), tabFontSize, tabFontOutline)
      end
      local fsWidth
      if tab.minWidth then
        fsWidth = tab:GetFontString():GetUnboundedStringWidth() + addonTable.Constants.TabPadding
      else
        fsWidth = math.max(tab:GetFontString():GetUnboundedStringWidth(), not tab:GetText():find("|K") and addonTable.Constants.MinTabWidth or 70) + addonTable.Constants.TabPadding
      end
      tab:GetFontString():SetWidth(fsWidth)
      tab:SetWidth(fsWidth)
    end
    local SetText = tab.SetText
    local text = tab:GetText()
    hooksecurefunc(tab, "SetText", function(_, cleanText)
      if not enableHooks then
        return
      end
      text = cleanText
      if tab:GetFontString() then
        local fsWidth
        if tab.minWidth then
          fsWidth = tab:GetFontString():GetUnboundedStringWidth() + addonTable.Constants.TabPadding
        else
          fsWidth = math.max(tab:GetFontString():GetUnboundedStringWidth(), not tab:GetText():find("|K") and addonTable.Constants.MinTabWidth or 70) + addonTable.Constants.TabPadding
        end
        tab:GetFontString():SetWidth(fsWidth)
        tab:SetWidth(fsWidth)
      end
    end)
    hooksecurefunc(tab, "SetSelected", function(_, state)
      if not enableHooks then
        return
      end
      local tabSelector = (CH and CH.db and CH.db.tabSelector) or "NONE"
      local rgb = (E and E.media and E.media.rgbvaluecolor) or {1, 1, 1}
      if state then
        if tab:GetFontString() then
          tab:GetFontString():SetTextColor(1, 1, 1)
        end
        if tabSelector ~= 'NONE' and CH and CH.TabStyles then
          local hexColor = E:RGBToHex(tab.color.r, tab.color.g, tab.color.b) or '|cff4cff4c'
          tab:SetFormattedText(CH.TabStyles[tabSelector] or CH.TabStyles.ARROW1, hexColor, text, hexColor)
        else
          SetText(tab, text)
        end
      else
        tab:SetText(text)
        if tab:GetFontString() then
          tab:GetFontString():SetTextColor(unpack(rgb))
        end
      end
    end)
    if tab.selected ~= nil then
      tab:SetSelected(tab.selected)
    end

    hooksecurefunc(tab, "SetColor", function(_, r, g, b)
      if tab.glow then
        tab.glow:SetVertexColor(r, g, b)
      end
      tab:SetSelected(tab.selected)
    end)
    if tab.color then
      tab:SetColor(tab.color.r, tab.color.g, tab.color.b)
    end

    tab.FlashAnimation = tab:CreateAnimationGroup()
    tab.FlashAnimation:SetLooping("BOUNCE")
    local alpha2 = tab.FlashAnimation:CreateAnimation("Alpha")
    alpha2:SetChildKey("glow")
    if addonTable.Compat335SetupAlphaAnim then
      addonTable.Compat335SetupAlphaAnim(tab.FlashAnimation, alpha2)
    end
    alpha2:SetFromAlpha(0)
    alpha2:SetToAlpha(1)
    alpha2:SetDuration(0.8)
    alpha2:SetOrder(1)
    hooksecurefunc(tab, "SetFlashing", function(_, state)
      if not enableHooks then
        return
      end
      tab.FlashAnimation:SetPlaying(state)
    end)
    table.insert(toUpdate, function()
      tab:SetText(text)
      if tab.selected ~= nil then
        tab:SetSelected(tab.selected)
      end
    end)
    if tab.selected ~= nil then
      tab:SetSelected(tab.selected)
    end
  end,
  ChatFrame = function(frame)
    if frame:GetID() == 1 then
      local function AnchorDataPanel()
        if not (E and E.db and E.db.chat) then return end
        local position = addonTable.Config.Get(addonTable.Config.Options.EDIT_BOX_POSITION)
        local isAbove = E.db.chat.LeftChatDataPanelAnchor == 'ABOVE_CHAT'
        if LeftChatPanel then
          LeftChatPanel:SetParent(addonTable.hiddenFrame)
        end
        if LeftChatDataPanel then
          LeftChatDataPanel:ClearAllPoints()
          LeftChatDataPanel:SetParent(frame)
          LeftChatDataPanel:SetPoint(isAbove and "BOTTOMLEFT" or "TOPLEFT", frame, isAbove and "TOPLEFT" or "BOTTOMLEFT", E.db.chat.hideChatToggles and -1 or 18, position == "bottom" and not isAbove and 22 or 0)
          LeftChatDataPanel:SetPoint(isAbove and "BOTTOMRIGHT" or "TOPRIGHT", frame, isAbove and "TOPRIGHT" or "BOTTOMRIGHT", 1, position == "bottom" and not isAbove and 22 or 0)
          LeftChatDataPanel:SetHeight(23)
        end
        if LeftChatToggleButton then
          LeftChatToggleButton:SetParent(frame)
        end
        local panelEnabled = E.db.datatexts and E.db.datatexts.panels and E.db.datatexts.panels.LeftChatDataPanel and E.db.datatexts.panels.LeftChatDataPanel.enable
        frame:SetClampRectInsets(0, 0, panelEnabled and isAbove and 25 or 0, panelEnabled and position == "top" and not isAbove and -25 or 0)
        if frame.UpdateEditBox then
          frame:UpdateEditBox()
        end
      end
      local function PositionPanel()
        AnchorDataPanel()
        addonTable.CallbackRegistry:RegisterCallback("SettingChanged", function(_, settingName)
          if not enableHooks then
            return
          end
          if settingName == addonTable.Config.Options.EDIT_BOX_POSITION then
            AnchorDataPanel()
          end
        end)
      end
      local LayoutModule = E:GetModule('Layout')
      if LayoutModule then
        if not LeftChatDataPanel then
          if LayoutModule.CreateChatPanels then
            hooksecurefunc(LayoutModule, "CreateChatPanels", PositionPanel)
          end
        else
          PositionPanel()
        end
        if LayoutModule.RepositionChatDataPanels then
          hooksecurefunc(LayoutModule, "RepositionChatDataPanels", AnchorDataPanel)
        end
        if LayoutModule.RefreshChatMovers then
          hooksecurefunc(LayoutModule, "RefreshChatMovers", AnchorDataPanel)
        end
      end
    end
    local panelBackdrop = (E and E.db and E.db.chat and E.db.chat.panelBackdrop) or "HIDEBOTH"
    if panelBackdrop ~= "HIDEBOTH" then
      if frame.CreateBackdrop then
        frame:CreateBackdrop('Transparent')
      end
      local panelColor = (CH and CH.db and CH.db.panelColor) or {r = 0.1, g = 0.1, b = 0.1, a = 0.8}
      if frame.backdrop and frame.backdrop.SetBackdropColor then
        frame.backdrop:SetBackdropColor(panelColor.r, panelColor.g, panelColor.b, panelColor.a)
      end
    end
  end,
  TopTabButton = function(frame)
    if S and S.HandleTab then
      S:HandleTab(frame)
    end
  end,
  TrimScrollBar = function(frame)
    if S and S.HandleTrimScrollBar then
      S:HandleTrimScrollBar(frame)
    end
  end,
  CheckBox = function(frame)
    if S and S.HandleCheckBox then
      S:HandleCheckBox(frame)
    end
  end,
  Slider = function(frame)
    if S and S.HandleStepSlider then
      S:HandleStepSlider(frame)
    end
  end,
  InsetFrame = function(frame)
    if frame.NineSlice then
      frame.NineSlice:SetTemplate("Transparent")
    elseif S and S.HandleInsetFrame then
      S:HandleInsetFrame(frame)
    else
      frame:SetTemplate("Transparent")
    end
  end,
  Dropdown = function(button)
    if S and S.HandleDropDownBox then
      S:HandleDropDownBox(button)
    end
  end,
  Dialog = function(frame)
    if frame.StripTextures then
      frame:StripTextures()
    end
    if frame.SetTemplate then
      frame:SetTemplate('Transparent')
    end
  end,
  ResizeWidget = function(frame, tags)
    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetVertexColor(intensity, intensity, intensity)
    tex:SetTexture("Interface\\AddOns\\Chattynator\\Assets\\resize.tga")
    tex:SetTexCoord(0, 1, 1, 0)
    tex:SetAllPoints()
    frame:SetScript("OnEnter", function()
      tex:SetVertexColor(59/255, 210/255, 237/255)
    end)
    frame:SetScript("OnLeave", function()
      tex:SetVertexColor(1, 1, 1)
    end)
  end,
}

local function SkinFrame(details)
  local func = skinners[details.regionType]
  if func then
    func(details.region, details.tags and ConvertTags(details.tags) or {})
  end
end

local function SetConstants()
  addonTable.Constants.ButtonFrameOffset = 0
end

local function LoadSkin()
  E = unpack(ElvUI)
  S = E:GetModule("Skins")
  B = E:GetModule('Bags')
  LSM = E.Libs.LSM
  CH = E:GetModule('Chat')
  if E and E.media and E.media.rgbvaluecolor then
    hoverColor = {r = E.media.rgbvaluecolor[1], g = E.media.rgbvaluecolor[2], b = E.media.rgbvaluecolor[3]}
  else
    hoverColor = {r = 1, g = 1, b = 1}
  end
  local fontVal = (CH and CH.db and CH.db.font) or (E and E.db and E.db.general and E.db.general.font) or "Friz Quadrata TT"
  local options = {fontVal, "Friz Quadrata TT"}
  for _, font in ipairs(options) do
    if LSM and LSM:Fetch("font", font, true) then
      addonTable.Core.OverwriteDefaultFont(font)
      break
    end
  end
end

if addonTable.Skins.IsAddOnLoading("ElvUI") then
  addonTable.Skins.RegisterSkin(addonTable.Locales.ELVUI, "elvui", LoadSkin, SkinFrame, SetConstants, {
  }, true)
end
