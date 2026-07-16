---@class addonTableChattynator
local addonTable = select(2, ...)

addonTable.Constants = {
  -- 3.3.5: the WOW_PROJECT_* globals are all nil, so the retail check nil==nil'd to
  -- true and routed every retail branch. Hard-code the flavor.
  IsRetail = false,
  --IsMists = WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC,
  --IsCata = WOW_PROJECT_ID == WOW_PROJECT_CATACLYSM_CLASSIC,
  --IsWrath = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC,
  --IsEra = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC,
  IsClassic = true, -- 3.3.5: was WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE

  -- 3.3.5: native CreateTextureMarkup is signature-divergent; use the Compat bypass.
  -- .png -> .tga (client loads only TGA/BLP).
  NewTabMarkup = Chattynator335_CreateTextureMarkup("Interface\\AddOns\\Chattynator\\Assets\\NewTab.tga", 40, 40, 15, 15, 0, 1, 0, 1),
  TabDropdownMarkup = Chattynator335_CreateTextureMarkup("Interface\\AddOns\\Chattynator\\Assets\\TabDropdown.tga", 40, 40, 15, 15, 0, 1, 0, 1),
  MinTabWidth = 20,
  TabPadding = 30,
  TabSpacing = 10,

  ChannelIDs = {
    General = 1,
    Trade = 2,
    LocalDefense = 22,
    WorldDefense = 23, -- Classic only
    LookingForGroup = 26,
    NewcomerChat = 32,
    Services = 42,
  }
}
if addonTable.Constants.IsRetail then
  addonTable.Constants.ButtonFrameOffset = 5
else
  addonTable.Constants.ButtonFrameOffset = 0
end
addonTable.Constants.Events = {
  "Render",

  "SettingChanged",
  "RefreshStateChange",
  "MessageDisplayChanged",
  "ResetOneMessageCache",

  "SkinLoaded",
}

addonTable.Constants.RefreshReason = {
  Tabs = 1,
  MessageFont = 2,
  MessageWidget = 3,
  MessageModifier = 4,
  MessageColor = 5,
  Locked = 1000,
}

addonTable.Constants.MESSAGE_TYPE_TO_INPUT = {
  SAY = SLASH_SAY4,
  YELL = SLASH_YELL2,
  GUILD = SLASH_GUILD4,
  OFFICER = SLASH_OFFICER5,
  PARTY = SLASH_PARTY2,
  PARTY_LEADER = SLASH_PARTY2,
  RAID = SLASH_RAID1,
  RAID_LEADER = SLASH_RAID1,
  RAID_WARNING = SLASH_RAID_WARNING1,
  INSTANCE_CHAT = SLASH_INSTANCE_CHAT3,
  INSTANCE_CHAT_LEADER = SLASH_INSTANCE_CHAT3,
  --WHISPER = SLASH_SMART_WHISPER1,
  --BN_WHISPER = SLASH_SMART_WHISPER1,
}
