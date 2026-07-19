---@class addonTableChattynator
local addonTable = select(2, ...)

addonTable.CallbackRegistry = CreateFromMixins(CallbackRegistryMixin)
addonTable.CallbackRegistry:OnLoad()
addonTable.CallbackRegistry:GenerateCallbackEvents(addonTable.Constants.Events)

function addonTable.Core.MigrateSettings()
  local windowsToRemove = {}
  local allWindows = addonTable.Config.Get(addonTable.Config.Options.WINDOWS)
  for index, window in ipairs(allWindows) do
    window.tabs = tFilter(window.tabs, function(t) return not t.isTemporary end, true)
    for _, tab in ipairs(window.tabs) do
      tab.filters = tab.filters or {}
      tab.whispersTemp = {}
      tab.addons = tab.addons or {}
    end
    if #window.tabs == 0 then
      table.insert(windowsToRemove, index)
    end
  end
  if #windowsToRemove > 0 then
    for i = #windowsToRemove, 1, -1 do
      table.remove(allWindows, windowsToRemove[i])
    end
  end
  local buttonPositionMap = {
    left_always = "outside_left",
    left_hover = "inside_left",
    top_hover = "inside_tabs",
  }
  local position = addonTable.Config.Get(addonTable.Config.Options.BUTTON_POSITION)
  if buttonPositionMap[position] then
    addonTable.Config.Set(addonTable.Config.Options.BUTTON_POSITION, buttonPositionMap[position])
    if position:match("hover") then
      addonTable.Config.Set(addonTable.Config.Options.SHOW_BUTTONS_ON_HOVER, true)
    end
  end
  if addonTable.Config.Get(addonTable.Config.Options.SHOW_BUTTONS) == "unset" then
    addonTable.Config.Set(addonTable.Config.Options.SHOW_BUTTONS, addonTable.Config.Get("show_buttons_on_hover") and "hover" or "always")
  end
  if addonTable.Config.Get(addonTable.Config.Options.COMBAT_LOG_MIGRATION) == 0 then
    if addonTable.Config.Get(addonTable.Config.Options.SHOW_COMBAT_LOG) then
      local blank = addonTable.Config.GetEmptyTabConfig("COMBAT_LOG")
      blank.backgroundColor = "262626"
      blank.tabColor = "c97c48"
      blank.custom = "combat_log"
      table.insert(allWindows[1].tabs, blank)
    end
    addonTable.Config.Set(addonTable.Config.Options.COMBAT_LOG_MIGRATION, 1)
  end
  addonTable.Skins.InstallOptions()
end

local incompatibleAddons = {
  "Prat-3.0",
  "BasicChatMods",
  "alaChat",
  "Chatter",
  "DejaChat",
  "ls_Glass",
  "XanChat",
  "MinimalistChat",
}

function addonTable.Core.CompatibilityWarnings()
  for _, addon in ipairs(incompatibleAddons) do
    if C_AddOns.IsAddOnLoaded(addon) then
      local _, title = C_AddOns.GetAddOnInfo(addon)
      local text =  addonTable.Locales.DISABLE_ADDON_X:format(title)
      addonTable.Utilities.Message(text)
      addonTable.Dialogs.ShowConfirm(text, DISABLE, IGNORE, function()
        C_AddOns.DisableAddOn(addon, UnitGUID("player"))
        ReloadUI()
      end)
      break
    end
  end
end

local hidden = CreateFrame("Frame")
hidden:Hide()
addonTable.hiddenFrame = hidden

-- Fail-soft bootstrap: run each init block under pcall so one broken subsystem can't
-- abort the whole addon. /chatty diag reports the per-block ok/FAIL recorded here.
addonTable.diag = addonTable.diag or {}
addonTable.diag.blocks = addonTable.diag.blocks or {}
addonTable.diag.order = addonTable.diag.order or {}
local function runBlock(name, fn)
  local ok, err = pcall(fn)
  addonTable.diag.blocks[name] = { ok = ok, err = ok and nil or tostring(err) }
  addonTable.diag.order[#addonTable.diag.order + 1] = name
  return ok
end

function addonTable.Core.Initialize()
  -- Default so the login path never nil-indexes it if the chatframes block below fails.
  addonTable.allChatFrames = addonTable.allChatFrames or {}

  runBlock("config", function() addonTable.Config.InitializeData() end)
  runBlock("migrate", function() addonTable.Core.MigrateSettings() end)

  runBlock("slashcmd", function() addonTable.SlashCmd.Initialize() end)


  runBlock("hyperlink", function()
    ChattynatorHyperlinkHandler:SetScript("OnHyperlinkEnter", function(_, hyperlink)
      -- Shared fail-soft setter (Compat.lua): allowlist-gated and pcall-guarded.
      addonTable.SafeSetTooltipHyperlink(GameTooltip, ChattynatorHyperlinkHandler:GetParent(), "ANCHOR_CURSOR", hyperlink)
    end)

    ChattynatorHyperlinkHandler:SetScript("OnHyperlinkLeave", function()
      GameTooltip:Hide()
    end)
  end)

  runBlock("messages", function()
    addonTable.Messages = CreateFrame("Frame")
    Mixin(addonTable.Messages, addonTable.MessagesMonitorMixin)
    addonTable.Messages:OnLoad()
  end)

  runBlock("skins", function() addonTable.Skins.Initialize() end)

  runBlock("chatframes", function()
    addonTable.allChatFrames = {}
    -- 3.3.5: the native 4-arg CreateFramePool drops args 5/6, so the arg6 initializer
    -- (Mixin+OnLoad) never runs and :Reset()/:SetID() nil-crash. Use the Compat bypass.
    addonTable.ChatFramePool = Chattynator335_CreateFramePool("Frame", ChattynatorHyperlinkHandler, nil, nil, false, function(frame)
      if not frame.OnLoad then
        Mixin(frame, addonTable.Display.ChatFrameMixin)
        frame:OnLoad()
      end
    end)
    for id, _ in pairs(addonTable.Config.Get(addonTable.Config.Options.WINDOWS)) do
      local chatFrame = addonTable.ChatFramePool:Acquire()
      chatFrame:SetID(id)
      chatFrame:Reset()
      chatFrame:Show()
      table.insert(addonTable.allChatFrames, chatFrame)
    end
  end)

  runBlock("settingcallback", function()
    addonTable.CallbackRegistry:RegisterCallback("SettingChanged", function(_, settingName)
      if settingName == addonTable.Config.Options.WINDOWS then
        local windows = addonTable.Config.Get(settingName)
        while #windows > #addonTable.allChatFrames do
          local chatFrame = addonTable.ChatFramePool:Acquire()
          chatFrame:SetID(#addonTable.allChatFrames + 1)
          chatFrame:Reset()
          chatFrame:Show()
          table.insert(addonTable.allChatFrames, chatFrame)
        end
      end
    end)
  end)

  runBlock("copyframe", function()
    -- 3.3.5: ButtonFrameTemplate is Cata+ (unknown template errors at load); build the
    -- classic-backdrop ButtonFrame via the Widgets shim.
    addonTable.CopyFrame = addonTable.Widgets.CreateButtonFrame("ChattynatorCopyChatDialog", UIParent)
    Mixin(addonTable.CopyFrame, addonTable.Display.CopyChatMixin)
    addonTable.CopyFrame:OnLoad()
  end)

  SlashCmdList["ChattynatorCopy"] = function()
    if not addonTable.allChatFrames[1] then
      return
    end
    if addonTable.CopyFrame:IsShown() then
      addonTable.CopyFrame:Hide()
    end
    addonTable.CopyFrame:LoadMessages(addonTable.allChatFrames[1].ScrollingMessages.filterFunc, addonTable.allChatFrames[1].ScrollingMessages.startingIndex)
  end
  SLASH_ChattynatorCopy1 = "/copy"

  runBlock("seizure", function() addonTable.Core.ApplyOverrides() end)
  runBlock("commandlogging", function() addonTable.Core.InitializeChatCommandLogging() end)
  runBlock("mod_shortenchannels", function() addonTable.Modifiers.InitializeShortenChannels() end)
  runBlock("mod_classcolors", function() addonTable.Modifiers.InitializeClassColors() end)
  runBlock("mod_urls", function() addonTable.Modifiers.InitializeURLs() end)
  runBlock("mod_redundanttext", function() addonTable.Modifiers.InitializeRedundantText() end)
  runBlock("customisedialog", function() addonTable.CustomiseDialog.Initialize() end)
end

function addonTable.Core.MakeChatFrame()
  local newChatFrame = addonTable.ChatFramePool:Acquire()
  table.insert(addonTable.allChatFrames, newChatFrame)
  local windows = addonTable.Config.Get(addonTable.Config.Options.WINDOWS)
  local newConfig = addonTable.Config.GetEmptyWindowConfig()
  table.insert(newConfig.tabs, addonTable.Config.GetEmptyTabConfig(GENERAL))
  table.insert(windows, newConfig)
  newChatFrame:SetID(#windows)
  newChatFrame:Show()

  return newChatFrame
end

function addonTable.Core.DeleteChatFrame(id)
  addonTable.Core.ReleaseClosedChatFrame(id)
  table.remove(addonTable.Config.Get(addonTable.Config.Options.WINDOWS), id)
  for index, frame in ipairs(addonTable.allChatFrames) do
    frame:SetID(index)
  end
end

function addonTable.Core.ReleaseClosedChatFrame(id)
  addonTable.allChatFrames[id]:SetID(0)
  addonTable.ChatFramePool:Release(addonTable.allChatFrames[id])
  table.remove(addonTable.allChatFrames, id)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, eventName, data)
  if eventName == "ADDON_LOADED" and data == "Chattynator" then
    addonTable.Core.Initialize()
    -- Wrap API.Initialize so a failure can't abort the rest of ADDON_LOADED.
    runBlock("api", function() addonTable.API.Initialize() end)
  elseif eventName == "PLAYER_LOGIN" then
    addonTable.Timer335.After(1, addonTable.Core.CompatibilityWarnings) -- 335-port (#4): own scheduler, immune to C_Timer replacement
    -- Guard: the chatframes block may have failed, leaving the pool empty.
    if addonTable.allChatFrames[1] then
      addonTable.allChatFrames[1]:UpdateEditBox()
    end
  end
end)
