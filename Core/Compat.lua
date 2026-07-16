--[[--------------------------------------------------------------------------
  Chattynator/Core/Compat.lua -- 3.3.5a (Project Ascension) engine shim.

  Loaded FIRST in the TOC: several files call retail globals at file/module
  scope, where a nil-index/nil-call aborts the chunk before any handler is
  defined (and for Constants / CallbackRegistry, kills the whole addon):
    * Core/Locales.lua:3        CopyTable(...)
    * Core/Constants.lua:12/13  CreateTextureMarkup(...) in a table constructor
    * Core/Initialize.lua:4     CreateFromMixins(CallbackRegistryMixin):OnLoad()
    * Core/Messages.lua:1061    if ChatFrameUtil.ProcessMessageEventFilters
    * API/Modifiers.lua:7       EventUtil.ContinueOnAddOnLoaded(...)
    * Skins/Main.lua:102        C_AddOns.GetAddOnEnableState(...) ~= Enum...All

  Policy: fill ONLY what is absent; never clobber an existing client global.
    * ensureGlobal -- whole-value guard (scalars/functions/single instances).
    * fillMissing  -- per-KEY guard for namespace/prototype tables (a partial
      client table keeps its keys and gains the ones it lacks).
    * rawget/rawset everywhere, so a metatable'd _G is not tripped.
    * Modern functions we CALL are probed at load with real arg shapes; a broken
      client factory is wrapped-with-fallback (colors) or bypassed via a distinct
      name (Chattynator335_CreateFramePool / Chattynator335_CreateTextureMarkup).
    * Partial retail namespaces make retail branches live, so generated-table
      indexes / mixin calls are guarded (empty Enum sub-tables; C_EventUtils
      deny-lists retail-only events).

  Signature-divergent APIs that EXIST on 3.3.5 are patched at the call site, not
  here. This file only fills globals that are entirely absent.
----------------------------------------------------------------------------]]

local _addonName, _addonTable = ... -- TOC load passes (name, addonTable); unused here.

-- Idempotence: run once even if the file is loaded twice.
if rawget(_G, "Chattynator335_CompatLoaded") then
  return
end
rawset(_G, "Chattynator335_CompatLoaded", true)

local _G = _G
local rawget, rawset = rawget, rawset
local select, pairs, ipairs, type, setmetatable, getmetatable, tonumber, tostring =
  select, pairs, ipairs, type, setmetatable, getmetatable, tonumber, tostring
local floor, format = math.floor, string.format
local tinsert, tremove, tconcat = table.insert, table.remove, table.concat

-- Record which names were shimmed (absent) vs found native, for /chatty diag.
-- Stored on the shared addonTable (absent under a standalone dofile).
local compatReport = { shims = {}, native = {} }
if type(_addonTable) == "table" then
  _addonTable.CompatReport = compatReport
end

-- Define a global ONLY if absent (scalar / function / single-instance globals).
local function ensureGlobal(name, value)
  if rawget(_G, name) == nil then
    rawset(_G, name, value)
    compatReport.shims[name] = true
  else
    compatReport.native[name] = true
  end
end

-- Per-KEY fill for TABLE-VALUED (namespace / prototype) shims. Recurses ONE level
-- so a pre-existing PARTIAL sub-table gets its missing keys filled (never skipped
-- wholesale). rawget/rawset throughout so a metatable'd target is not tripped.
local function fillMissing(target, defaults)
  for k, v in pairs(defaults) do
    local cur = rawget(target, k)
    if cur == nil then
      rawset(target, k, v)
    elseif type(v) == "table" and type(cur) == "table" then
      for k2, v2 in pairs(v) do
        if rawget(cur, k2) == nil then
          rawset(cur, k2, v2)
        end
      end
    end
  end
end

-- Ensure a namespace table exists (empty) then per-key fill it.
local function ensureNamespace(name, members)
  if rawget(_G, name) == nil then
    rawset(_G, name, {})
    compatReport.shims[name] = true
  else
    compatReport.native[name] = true
  end
  if members then
    fillMissing(rawget(_G, name), members)
  end
  return rawget(_G, name)
end

-- Delegate to a bare global by NAME (nil-safe: absent global => returns nil, never
-- a nil-call at load). Used for the C_* thin members that wrap documented globals.
local function wrapGlobal(name)
  return function(...)
    local g = rawget(_G, name)
    if g then
      return g(...)
    end
  end
end

--==============================================================================
-- GROUP A -- load-order-critical namespaces / mixins
--==============================================================================

-- ChatFrameUtil -- empty table so `if ChatFrameUtil.X` / `ChatFrame_X or
-- ChatFrameUtil.X` degrades to the legacy/nil path (Messages:1061 crash site).
ensureNamespace("ChatFrameUtil")

-- Mixin / CreateFromMixins / CreateAndInitFromMixin. Present on Ascension;
-- filled defensively for stripped profiles.
local function shimMixin(object, ...)
  for i = 1, select("#", ...) do
    local mixin = select(i, ...)
    if mixin then
      for k, v in pairs(mixin) do
        object[k] = v
      end
    end
  end
  return object
end
ensureGlobal("Mixin", shimMixin)
ensureGlobal("CreateFromMixins", function(...)
  return shimMixin({}, ...)
end)
ensureGlobal("CreateAndInitFromMixin", function(mixin, ...)
  local o = shimMixin({}, mixin)
  if type(o.Init) == "function" then
    o:Init(...)
  end
  return o
end)

-- CallbackRegistryMixin -- vendored pure-Lua SharedXML mixin; hard dep of ~15
-- files (Initialize.lua:4 builds the bus at file scope). A callback is invoked
-- as func(owner, ...); owner is nil for anonymous 2-arg registrations.
-- TriggerEvent on an event with no listeners is a silent no-op (no retail
-- event-name assert, which would false-trip on the addon's own event set).
do
  local CallbackRegistryMixin = {}

  function CallbackRegistryMixin:OnLoad()
    self.callbacks = self.callbacks or {}
  end

  function CallbackRegistryMixin:GenerateCallbackEvents(events)
    self.Event = self.Event or {}
    if type(events) == "table" then
      for _, event in ipairs(events) do
        self.Event[event] = event
      end
    end
  end

  -- RegisterCallback(event, func, owner). Keyed by owner when given (re-register
  -- with the same owner replaces), else by func (anonymous callbacks coexist).
  function CallbackRegistryMixin:RegisterCallback(event, func, owner)
    if type(func) ~= "function" then
      return
    end
    self.callbacks = self.callbacks or {}
    local list = self.callbacks[event]
    if not list then
      list = {}
      self.callbacks[event] = list
    end
    list[owner or func] = { func = func, owner = owner }
    return owner
  end

  function CallbackRegistryMixin:UnregisterCallback(event, owner)
    local list = self.callbacks and self.callbacks[event]
    if list then
      list[owner] = nil
    end
  end

  function CallbackRegistryMixin:IsEventRegistered(event)
    local list = self.callbacks and self.callbacks[event]
    return list ~= nil and next(list) ~= nil
  end

  function CallbackRegistryMixin:TriggerEvent(event, ...)
    local list = self.callbacks and self.callbacks[event]
    if not list then
      return
    end
    -- snapshot so a handler may (un)register during dispatch
    local snapshot = {}
    for _, entry in pairs(list) do
      snapshot[#snapshot + 1] = entry
    end
    for _, entry in ipairs(snapshot) do
      entry.func(entry.owner, ...)
    end
  end

  -- Prototype table -- per-key fill so a client that ships a partial one keeps it.
  if rawget(_G, "CallbackRegistryMixin") == nil then
    rawset(_G, "CallbackRegistryMixin", CallbackRegistryMixin)
  else
    fillMissing(rawget(_G, "CallbackRegistryMixin"), CallbackRegistryMixin)
  end
end

-- Enum -- populated, never {} wholesale. AddOnEnableState must carry a real .All
-- (Skins/Main.lua:102 compares against it at file scope). The other sub-tables
-- exist only so a stray `Enum.X.Y` yields nil, not an index error.
do
  local Enum = ensureNamespace("Enum")
  fillMissing(Enum, {
    AddOnEnableState = { None = 0, Some = 1, All = 2 },
    ChatChannelRuleset = {},
    PlayerMentorshipStatus = {},
    ClubStreamType = {},
    TitleIconVersion = {},
    TextSizeType = {},
  })
end

--==============================================================================
-- GROUP D -- color factory + ColorMixin (defined early: the A/C color globals
-- below need makeColor). Includes GenerateHexColorNoAlpha and
-- CreateColorFromRGBHexString (Chattynator-only).
--==============================================================================
local function toByte(v)
  -- clamp to [0,255]: white stores as 255/255 = 1.00000006 in float32, which
  -- would otherwise overflow "%02x" to 3 hex chars.
  v = floor((v or 0) * 255 + 0.5)
  if v < 0 then return 0 end
  if v > 255 then return 255 end
  return v
end

local ColorMixin = {}
function ColorMixin:SetRGBA(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
function ColorMixin:SetRGB(r, g, b) self:SetRGBA(r, g, b, 1) end
function ColorMixin:GetRGB() return self.r, self.g, self.b end
function ColorMixin:GetRGBA() return self.r, self.g, self.b, self.a end
function ColorMixin:GetRGBAsBytes() return toByte(self.r), toByte(self.g), toByte(self.b) end
function ColorMixin:GetRGBAAsBytes()
  return toByte(self.r), toByte(self.g), toByte(self.b), toByte(self.a ~= nil and self.a or 1)
end
function ColorMixin:IsRGBEqualTo(other) return self.r == other.r and self.g == other.g and self.b == other.b end
function ColorMixin:IsEqualTo(other) return self:IsRGBEqualTo(other) and self.a == other.a end
function ColorMixin:GenerateHexColor()
  return format("%02x%02x%02x%02x", toByte(self.a ~= nil and self.a or 1), toByte(self.r), toByte(self.g), toByte(self.b))
end
function ColorMixin:GenerateHexColorMarkup()
  -- |cAARRGGBB open code (Modifiers/ClassColors.lua:8).
  return "|c" .. self:GenerateHexColor()
end
function ColorMixin:GenerateHexColorNoAlpha()
  -- 6-hex RRGGBB; round-trips CreateColorFromRGBHexString (Tabs.lua:355/376).
  return format("%02x%02x%02x", toByte(self.r), toByte(self.g), toByte(self.b))
end
function ColorMixin:WrapTextInColorCode(text)
  return "|c" .. self:GenerateHexColor() .. (text or "") .. "|r"
end

local colorMeta = { __index = ColorMixin }
local function makeColor(r, g, b, a)
  return setmetatable({ r = r, g = g, b = b, a = a }, colorMeta)
end

-- Per-key fill ONE color instance with our ColorMixin methods (normal-index read
-- so inherited methods count as present; rawset write lands on the instance).
local function fillColorInstance(c)
  if type(c) ~= "table" then
    return c
  end
  for m, fn in pairs(ColorMixin) do
    if c[m] == nil then
      rawset(c, m, fn)
    end
  end
  return c
end

-- Global ColorMixin: per-key fill (a client partial ColorMixin keeps its own).
if rawget(_G, "ColorMixin") == nil then
  rawset(_G, "ColorMixin", ColorMixin)
else
  fillMissing(rawget(_G, "ColorMixin"), ColorMixin)
end

-- Test-driven color factory: absent -> ours; present+complete -> theirs;
-- present-but-partial/erroring -> wrap-with-fallback + per-key fill; primary
-- probe fails -> ours. Ascension's CreateColor yields instances missing
-- GenerateHexColorMarkup/... -> wrap-with-fallback.
local function ensureColorFactory(name, ourFactory, probes)
  local client = rawget(_G, name)
  if client == nil then
    rawset(_G, name, ourFactory)
    return
  end
  if type(client) ~= "function" then
    return
  end
  local primaryOk, primaryProbe, allProbesPass = false, nil, true
  for i, args in ipairs(probes) do
    local ok, probe = pcall(client, args[1], args[2], args[3], args[4])
    local usable = ok and type(probe) == "table"
    if i == 1 then
      primaryOk, primaryProbe = usable, probe
    end
    if not usable then
      allProbesPass = false
    end
  end
  if not primaryOk then
    rawset(_G, name, ourFactory)
    return
  end
  -- Reject an overflow-buggy native GenerateHexColor: Ascension's corrupts the
  -- whole color when any component >= 1.0 (white = 1.00000006 in float32), turning
  -- it near-black. fillColorInstance only fills MISSING methods, so compare the
  -- native probe's hex against ours and swap to our clamping factory on mismatch.
  if type(primaryProbe.GenerateHexColor) == "function" then
    local a = probes[1]
    local nativeOk, nativeHex = pcall(primaryProbe.GenerateHexColor, primaryProbe)
    local ourOk, ourColor = pcall(ourFactory, a[1], a[2], a[3], a[4])
    local ourHex = ourOk and type(ourColor) == "table"
      and type(ourColor.GenerateHexColor) == "function" and ourColor:GenerateHexColor() or nil
    if ourHex and (not nativeOk or nativeHex ~= ourHex) then
      rawset(_G, name, ourFactory)
      return
    end
  end
  local instancesComplete = true
  for m in pairs(ColorMixin) do
    if primaryProbe[m] == nil then
      instancesComplete = false
      break
    end
  end
  if allProbesPass and instancesComplete then
    return
  end
  rawset(_G, name, function(...)
    local ok, c = pcall(client, ...)
    if not ok or type(c) ~= "table" then
      c = ourFactory(...)
    end
    return fillColorInstance(c)
  end)
end

-- CreateColor (+ the byte / 8-hex variants).
-- 3.3.5: Ascension's native CreateColor/GenerateHexColor corrupts any colour with a
-- component >1.0 -- and white is 255/255 = 1.00000006 in float32 (ChatTypeInfo), so it
-- collapses to near-black (SAY -> 01010101). It is correct at exactly 1.0 and the >1.0
-- threshold is opaque, so probe-and-swap is unreliable; bypass the native entirely and
-- always use our clamping factory. Fixes the settings colour dropdowns and the dimmed
-- white chat text (both go through this conversion).
rawset(_G, "CreateColor", function(r, g, b, a)
  return makeColor(r, g, b, a ~= nil and a or 1)
end)
ensureColorFactory("CreateColorFromBytes", function(r, g, b, a)
  return makeColor((r or 0) / 255, (g or 0) / 255, (b or 0) / 255, (a ~= nil and a or 255) / 255)
end, {
  { 255, 255, 255, 255 },
})
ensureColorFactory("CreateColorFromHexString", function(hexColor) -- 8-digit AARRGGBB
  if type(hexColor) == "string" and #hexColor == 8 then
    local function hex(i) return tonumber(hexColor:sub(i, i + 1), 16) / 255 end
    return makeColor(hex(3), hex(5), hex(7), hex(1))
  end
end, {
  { "ffffffff" },
})

-- CreateColorFromRGBHexString -- 6-digit RRGGBB (Tabs.lua:288/289); distinct from
-- the 8-digit CreateColorFromHexString. Tolerates a leading |cff / # prefix.
ensureColorFactory("CreateColorFromRGBHexString", function(hexColor)
  if type(hexColor) ~= "string" then
    return makeColor(1, 1, 1, 1)
  end
  hexColor = hexColor:gsub("^|c", ""):gsub("^#", "")
  if #hexColor == 8 then
    hexColor = hexColor:sub(3) -- drop the AA of an AARRGGBB
  end
  if #hexColor >= 6 then
    local function hex(i) return (tonumber(hexColor:sub(i, i + 1), 16) or 0) / 255 end
    return makeColor(hex(1), hex(3), hex(5), 1)
  end
  return makeColor(1, 1, 1, 1)
end, {
  { "ff8040" },
})

ensureGlobal("WrapTextInColorCode", function(text, colorHexString)
  return "|c" .. (colorHexString or "") .. (text or "") .. "|r"
end)

-- ColorMixin-ify the plain {r,g,b} FrameXML color globals so every ColorMixin
-- method is callable on them. Virgin plain tables get colorMeta; a partial client
-- instance gets its missing methods filled per-key.
local function colorMixinify(color)
  if type(color) ~= "table" or color.r == nil then
    return
  end
  if getmetatable(color) == nil and color.GetRGBA == nil then
    setmetatable(color, colorMeta)
  end
  fillColorInstance(color)
  if color.a == nil then
    color.a = 1
  end
end

-- Color globals Chattynator reads. Retail-standard shades; ensureGlobal never
-- clobbers, so a real client's native constants win and only the truly-absent
-- ones (WHITE/BLUE/LIGHTBLUE/LIGHTGRAY/LINK) get our defaults.
local colorDefaults = {
  WHITE_FONT_COLOR      = { 1.00, 1.00, 1.00 },
  HIGHLIGHT_FONT_COLOR  = { 1.00, 1.00, 1.00 },
  NORMAL_FONT_COLOR     = { 1.00, 0.82, 0.00 },
  GRAY_FONT_COLOR       = { 0.50, 0.50, 0.50 },
  GRAYGRAY_FONT_COLOR   = { 0.50, 0.50, 0.50 },
  LIGHTGRAY_FONT_COLOR  = { 0.75, 0.75, 0.75 },
  DISABLED_FONT_COLOR   = { 0.50, 0.50, 0.50 },
  RED_FONT_COLOR        = { 1.00, 0.10, 0.10 },
  GREEN_FONT_COLOR      = { 0.10, 1.00, 0.10 },
  YELLOW_FONT_COLOR     = { 1.00, 1.00, 0.00 },
  ORANGE_FONT_COLOR     = { 1.00, 0.60, 0.00 },
  BLUE_FONT_COLOR       = { 0.20, 0.40, 1.00 },
  LIGHTBLUE_FONT_COLOR  = { 0.60, 0.80, 1.00 },
  LINK_FONT_COLOR       = { 0.30, 0.70, 1.00 },
}
for name, rgb in pairs(colorDefaults) do
  ensureGlobal(name, makeColor(rgb[1], rgb[2], rgb[3], 1))
  colorMixinify(rawget(_G, name))
end
-- RAID_CLASS_COLORS / CUSTOM_CLASS_COLORS entries are plain {r,g,b[,colorStr]} on
-- 3.3.5; mixin them so the class-color path can call GenerateHexColorMarkup /
-- WrapTextInColorCode on them.
for _, tblName in ipairs({ "RAID_CLASS_COLORS", "CUSTOM_CLASS_COLORS" }) do
  local classColors = rawget(_G, tblName)
  if type(classColors) == "table" then
    for _, c in pairs(classColors) do
      colorMixinify(c)
    end
  end
end

--==============================================================================
-- GROUP B -- C_* namespace shims (thin tables over documented classic globals)
--==============================================================================

-- C_ChatInfo -- real members over classic globals; retail-only members stubbed so
-- hooksecurefunc(C_ChatInfo, "UncensorChatLine"/...) (Messages 196/324) succeeds
-- and the censor path stays inert. GetChannelRuleset and InChatMessagingLockdown
-- are DELIBERATELY absent: a nil-returning stub is truthy, which would make the
-- retail lockdown/ruleset branches live (Messages:1256, Buttons.lua:76).

-- Inline %b{} raid-icon + group-expression replacer, ported from the client's
-- ChatFrame_ReplaceIconAndGroupExpressions (framexml:3407-3414). Guarded so an
-- absent ICON_TAG_LIST/GROUP_TAG_LIST degrades to the message unchanged.
local function replaceIconAndGroupExpressions(message, noIconReplacement, noGroupReplacement)
  if type(message) ~= "string" then
    return message
  end
  local ICON_TAG_LIST = rawget(_G, "ICON_TAG_LIST")
  local ICON_LIST = rawget(_G, "ICON_LIST")
  local GROUP_TAG_LIST = rawget(_G, "GROUP_TAG_LIST")
  for tag in message:gmatch("%b{}") do
    local term = tag:gsub("[{}]", ""):lower()
    local pattern = tag:gsub("(%W)", "%%%1") -- escape the {tag} for use as a gsub pattern
    if not noIconReplacement and ICON_TAG_LIST and ICON_LIST and ICON_TAG_LIST[term] and ICON_LIST[ICON_TAG_LIST[term]] then
      -- 3.3.5: ICON_LIST[i] is ALREADY the full texture-markup prefix
      -- ("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_N:"), so the stock code
      -- emits ICON_LIST[i] .. "0|t" (framexml:3412). A hardcoded prefix would
      -- double-prepend and garble every {skull}/{star}.
      message = message:gsub(pattern,
        ICON_LIST[ICON_TAG_LIST[term]] .. "0\124t")
    elseif not noGroupReplacement and GROUP_TAG_LIST and GROUP_TAG_LIST[term] then
      -- group-name expansion is a retail roster feature; leave the tag as-is on
      -- 3.3.5 (cosmetic, no crash).
    end
  end
  return message
end

-- CanChatGroupPerformExpressionExpansion: true for group chat, false for whispers.
local function canChatGroupPerformExpressionExpansion(chatGroup)
  if chatGroup == "WHISPER" or chatGroup == "WHISPER_INFORM"
    or chatGroup == "BN_WHISPER" or chatGroup == "BN_WHISPER_INFORM" then
    return false
  end
  return true
end

ensureNamespace("C_ChatInfo", {
  SendChatMessage = wrapGlobal("SendChatMessage"),
  GetChatTypeIndex = wrapGlobal("GetChatTypeIndex"),
  ChatFrame_AddMessageEventFilter = wrapGlobal("ChatFrame_AddMessageEventFilter"),
  ChatFrame_GetMessageEventFilters = wrapGlobal("ChatFrame_GetMessageEventFilters"),
  ChatFrame_RemoveMessageEventFilter = wrapGlobal("ChatFrame_RemoveMessageEventFilter"),
  RegisterAddonMessagePrefix = wrapGlobal("RegisterAddonMessagePrefix"),
  SendAddonMessage = wrapGlobal("SendAddonMessage"),
  -- retail-only members: no-ops / era-correct constants
  UncensorChatLine = function() end,
  SwapChatChannelsByChannelIndex = function() end,
  IsChatLineCensored = function() return false end,
  IsTimerunningPlayer = function() return false end,
  GetChatLineText = function() return "" end,
  -- 3.3.5: GetChannelRuleset is DELIBERATELY absent. A nil-returning stub is truthy, so
  -- the `C_ChatInfo.GetChannelRuleset and ...` guard at Messages:1256 would not short-
  -- circuit and the YOU_CHANGED channel-change notice would be dropped. Omitting it makes
  -- the guard go false so the notice shows. (GetChannelRulesetForChannelID is KEPT -- it
  -- is called unguarded at Messages:1072/1076.)
  GetChannelRulesetForChannelID = function() return nil end,
  GetChannelInfoFromIdentifier = function(identifier)
    local zoneChannelID = 0
    local getChannelName = rawget(_G, "GetChannelName")
    if getChannelName then
      -- GetChannelName(name) -> channel, channelName, instanceID
      local _, _, instanceID = getChannelName(identifier)
      zoneChannelID = instanceID or 0
    end
    return { zoneChannelID = zoneChannelID }
  end,
  ReplaceIconAndGroupExpressions = replaceIconAndGroupExpressions,
  CanChatGroupPerformExpressionExpansion = canChatGroupPerformExpressionExpansion,
})
-- Bare-global fallbacks Messages:1329 tries FIRST (never clobber a native one).
ensureGlobal("ChatFrame_ReplaceIconAndGroupExpressions", replaceIconAndGroupExpressions)
ensureGlobal("ChatFrame_CanChatGroupPerformExpressionExpansion", canChatGroupPerformExpressionExpansion)

-- C_EventUtils.IsEventValid -- genuine validation. On a real 3.3.5 client
-- RegisterEvent on an unknown event errors, so the cached pcall-probe returns
-- false. A permissive client (a partial-backport that silently accepts unknown
-- names) would probe-true, so an explicit deny-set of known retail-only events
-- short-circuits to false first.
do
  local RETAIL_ONLY = {
    CHAT_MSG_COMMUNITIES_CHANNEL = true,
    CHAT_MSG_VOICE_TEXT = true,
    CLUB_REMOVED = true,
    CLUB_ADDED = true,
    NEWCOMER_GRADUATION = true,
    NOTIFY_CHAT_SUPPRESSED = true,
    CAUTIONARY_CHAT_MESSAGE = true,
    CHAT_REGIONAL_STATUS_CHANGED = true,
  }
  local cache = {}
  local probe
  ensureNamespace("C_EventUtils", {
    IsEventValid = function(event)
      if type(event) ~= "string" then
        return false
      end
      local cached = cache[event]
      if cached ~= nil then
        return cached
      end
      local result
      if RETAIL_ONLY[event] then
        result = false
      else
        if not probe then
          probe = _G.CreateFrame and _G.CreateFrame("Frame")
        end
        if probe and probe.RegisterEvent then
          local ok = pcall(probe.RegisterEvent, probe, event)
          if ok and probe.UnregisterEvent then
            pcall(probe.UnregisterEvent, probe, event)
          end
          result = ok and true or false
        else
          result = true -- no probe frame available: assume valid (best effort)
        end
      end
      cache[event] = result
      return result
    end,
  })
end

-- C_AddOns -- thin table over the classic globals. GetAddOnEnableState /
-- IsAddOnLoadable are synthesized from GetAddOnInfo (no era global); the extra
-- per-character arg on DisableAddOn / GetAddOnEnableState is dropped.
-- Skins/Main.lua:102/105 hits all three added members at file scope.
ensureNamespace("C_AddOns", {
  IsAddOnLoaded = function(name)
    local loaded = _G.IsAddOnLoaded and _G.IsAddOnLoaded(name)
    return loaded, loaded -- 3.3.5 loads are synchronous: finished == loaded
  end,
  GetAddOnInfo = wrapGlobal("GetAddOnInfo"),
  GetAddOnMetadata = wrapGlobal("GetAddOnMetadata"),
  GetNumAddOns = wrapGlobal("GetNumAddOns"),
  IsAddOnLoadOnDemand = wrapGlobal("IsAddOnLoadOnDemand"),
  LoadAddOn = wrapGlobal("LoadAddOn"),
  EnableAddOn = wrapGlobal("EnableAddOn"),
  DisableAddOn = function(name) -- drop the 2nd per-char arg the 3.3.5 global ignores
    if _G.DisableAddOn then
      return _G.DisableAddOn(name)
    end
  end,
  GetAddOnDependencies = function(...)
    if _G.GetAddOnDependencies then
      return _G.GetAddOnDependencies(...)
    end
  end,
  IsAddOnLoadable = function(name)
    if not _G.GetAddOnInfo then
      return false
    end
    local _, _, _, _, loadable = _G.GetAddOnInfo(name)
    return loadable and true or false
  end,
  GetAddOnEnableState = function(a, b)
    -- retail arg order varies ((addon,char) or (char,addon)); resolve the addon
    -- identifier by whichever GetAddOnInfo recognises. Return the Enum value.
    local AddOnEnableState = rawget(_G, "Enum").AddOnEnableState
    local getInfo = _G.GetAddOnInfo
    if not getInfo then
      return AddOnEnableState.None
    end
    local name = a
    if getInfo(a) == nil and getInfo(b) ~= nil then
      name = b
    end
    local _, _, _, enabled = getInfo(name)
    return enabled and AddOnEnableState.All or AddOnEnableState.None
  end,
})

-- C_CVar -- thin table over the classic CVar globals. SetCVar pcall-guarded so
-- setting an unknown Cata+ cvar (Overrides.lua:140 whisperMode) cannot crash.
ensureNamespace("C_CVar", {
  GetCVar = wrapGlobal("GetCVar"),
  GetCVarBool = wrapGlobal("GetCVarBool"),
  GetCVarDefault = wrapGlobal("GetCVarDefault"),
  GetCVarInfo = wrapGlobal("GetCVarInfo"),
  RegisterCVar = wrapGlobal("RegisterCVar"),
  SetCVar = function(cvar, value, raiseEvent)
    local setCVar = rawget(_G, "SetCVar")
    if not setCVar then
      return
    end
    pcall(setCVar, cvar, value, raiseEvent)
  end,
})

-- C_Timer -- per-method OnUpdate fallback. Ascension ships a PARTIAL C_Timer (its
-- own .After) without NewTicker/NewTimer, so each method is built over one private
-- scheduler and filled only if the client lacks it. Driver frame is lazy.
do
  local scheduled = {}
  local driver
  local function onUpdate()
    local now = _G.GetTime()
    local i = 1
    while i <= #scheduled do
      local e = scheduled[i]
      if now >= e.at then
        tremove(scheduled, i)
        pcall(e.fn)
        if e.interval and (e.iterations == nil or e.iterations > 1) then
          if e.iterations then e.iterations = e.iterations - 1 end
          e.at = now + e.interval
          tinsert(scheduled, e)
        end
      else
        i = i + 1
      end
    end
  end
  local function schedule(e)
    if not driver then
      driver = _G.CreateFrame("Frame")
      driver:SetScript("OnUpdate", onUpdate)
    end
    tinsert(scheduled, e)
    return e
  end
  local function cancelClosure(e)
    return function()
      for i = #scheduled, 1, -1 do
        if scheduled[i] == e then tremove(scheduled, i) end
      end
      e.cancelled = true
    end
  end
  local ctimerShim = {
    After = function(seconds, fn)
      schedule({ at = _G.GetTime() + (seconds or 0), fn = fn })
    end,
    NewTimer = function(seconds, fn)
      local e = schedule({ at = _G.GetTime() + (seconds or 0), fn = fn })
      return { Cancel = cancelClosure(e), IsCancelled = function() return e.cancelled == true end }
    end,
    NewTicker = function(seconds, fn, iterations)
      -- clamp the reschedule interval so a 0-interval ticker cannot re-hit in the
      -- same onUpdate pass (GetTime is cached at loop top).
      local e = schedule({
        at = _G.GetTime() + (seconds or 0), fn = fn,
        interval = math.max(tonumber(seconds) or 0, 0.01), iterations = iterations,
      })
      return { Cancel = cancelClosure(e), IsCancelled = function() return e.cancelled == true end }
    end,
  }
  ensureNamespace("C_Timer", ctimerShim)
end

-- C_StringUtil + pure-Lua StripHyperlinks. Every C_StringUtil site in Messages is
-- `if C_StringUtil and C_StringUtil.X`-guarded; Filtering:253 uses
-- `(StripHyperlinks or C_StringUtil.StripHyperlinks)(title)`, so the bare global
-- must exist.
local function stripHyperlinks(text)
  if type(text) ~= "string" then
    return text
  end
  -- |Hlink|hDISPLAY|h -> DISPLAY, then drop color / texture escapes.
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  text = text:gsub("|H.-|h(.-)|h", "%1")
  text = text:gsub("|T.-|t", "")
  text = text:gsub("|K.-|k", "")
  return text
end
ensureGlobal("StripHyperlinks", stripHyperlinks)
local function removeContiguousSpaces(text)
  if type(text) ~= "string" then return text end
  return (text:gsub("%s+", " "))
end
ensureNamespace("C_StringUtil", {
  StripHyperlinks = stripHyperlinks,
  RemoveContiguousSpaces = function(text) return removeContiguousSpaces(text) end,
  EscapeLuaFormatString = function(text)
    if type(text) ~= "string" then return text end
    return (text:gsub("%%", "%%%%"))
  end,
})

-- C_EncodingUtil -- pure-Lua JSON serialize/deserialize so the historical archive
-- keeps batching (Messages 36/43/65/75/680). Every call site is guarded, so this
-- restores a feature rather than fixing a crash. The archive is produced and
-- consumed only by this shim, so only self-consistency matters, not byte-for-byte
-- retail-JSON parity.
do
  local escapes = {
    ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r',
    ['\t'] = '\\t', ['\b'] = '\\b', ['\f'] = '\\f',
  }
  local function encodeString(s)
    s = s:gsub('[%z\1-\31\\"]', function(c)
      return escapes[c] or format("\\u%04x", string.byte(c))
    end)
    return '"' .. s .. '"'
  end
  local function encode(v)
    local t = type(v)
    if v == nil then
      return "null"
    elseif t == "boolean" then
      return v and "true" or "false"
    elseif t == "number" then
      return format("%.14g", v)
    elseif t == "string" then
      return encodeString(v)
    elseif t == "table" then
      local count, arr = 0, true
      for _ in pairs(v) do count = count + 1 end
      if count == 0 then
        return "[]"
      end
      for i = 1, count do
        if v[i] == nil then arr = false break end
      end
      if arr then
        for k in pairs(v) do
          if type(k) ~= "number" or k % 1 ~= 0 or k < 1 or k > count then arr = false break end
        end
      end
      local parts = {}
      if arr then
        for i = 1, count do parts[i] = encode(v[i]) end
        return "[" .. tconcat(parts, ",") .. "]"
      end
      for k, val in pairs(v) do
        parts[#parts + 1] = encodeString(tostring(k)) .. ":" .. encode(val)
      end
      return "{" .. tconcat(parts, ",") .. "}"
    end
    return "null"
  end

  local function decode(s)
    local pos = 1
    local decodeValue
    local function skipWhite()
      local _, e = s:find("^[ \t\r\n]+", pos)
      if e then pos = e + 1 end
    end
    local function decodeString()
      pos = pos + 1 -- skip opening quote
      local buf = {}
      while true do
        local c = s:sub(pos, pos)
        if c == "" then error("unterminated JSON string") end
        if c == '"' then pos = pos + 1 break end
        if c == "\\" then
          local n = s:sub(pos + 1, pos + 1)
          if n == "n" then buf[#buf + 1] = "\n"; pos = pos + 2
          elseif n == "t" then buf[#buf + 1] = "\t"; pos = pos + 2
          elseif n == "r" then buf[#buf + 1] = "\r"; pos = pos + 2
          elseif n == "b" then buf[#buf + 1] = "\b"; pos = pos + 2
          elseif n == "f" then buf[#buf + 1] = "\f"; pos = pos + 2
          elseif n == "/" then buf[#buf + 1] = "/"; pos = pos + 2
          elseif n == '"' then buf[#buf + 1] = '"'; pos = pos + 2
          elseif n == "\\" then buf[#buf + 1] = "\\"; pos = pos + 2
          elseif n == "u" then
            local code = tonumber(s:sub(pos + 2, pos + 5), 16) or 0
            if code < 0x80 then
              buf[#buf + 1] = string.char(code)
            elseif code < 0x800 then
              buf[#buf + 1] = string.char(0xC0 + floor(code / 0x40), 0x80 + (code % 0x40))
            else
              buf[#buf + 1] = string.char(0xE0 + floor(code / 0x1000),
                0x80 + (floor(code / 0x40) % 0x40), 0x80 + (code % 0x40))
            end
            pos = pos + 6
          else
            buf[#buf + 1] = n; pos = pos + 2
          end
        else
          buf[#buf + 1] = c; pos = pos + 1
        end
      end
      return tconcat(buf)
    end
    decodeValue = function()
      skipWhite()
      local c = s:sub(pos, pos)
      if c == '"' then
        return decodeString()
      elseif c == "{" then
        pos = pos + 1
        local obj = {}
        skipWhite()
        if s:sub(pos, pos) == "}" then pos = pos + 1; return obj end
        while true do
          skipWhite()
          local key = decodeString()
          skipWhite()
          pos = pos + 1 -- skip ':'
          obj[key] = decodeValue()
          skipWhite()
          local sep = s:sub(pos, pos)
          pos = pos + 1
          if sep == "}" then break end
          if sep ~= "," then error("bad JSON object separator") end
        end
        return obj
      elseif c == "[" then
        pos = pos + 1
        local arr = {}
        skipWhite()
        if s:sub(pos, pos) == "]" then pos = pos + 1; return arr end
        while true do
          arr[#arr + 1] = decodeValue()
          skipWhite()
          local sep = s:sub(pos, pos)
          pos = pos + 1
          if sep == "]" then break end
          if sep ~= "," then error("bad JSON array separator") end
        end
        return arr
      elseif c == "t" then
        pos = pos + 4; return true
      elseif c == "f" then
        pos = pos + 5; return false
      elseif c == "n" then
        pos = pos + 4; return nil
      else
        local numStr = s:match("^%-?%d[%d%.eE%+%-]*", pos)
        if not numStr then error("bad JSON value at " .. pos) end
        pos = pos + #numStr
        return tonumber(numStr)
      end
    end
    return decodeValue()
  end

  ensureNamespace("C_EncodingUtil", {
    SerializeJSON = function(value) return encode(value) end,
    DeserializeJSON = function(str)
      if type(str) ~= "string" then return nil end
      local ok, result = pcall(decode, str)
      if ok then return result end
      return nil
    end,
  })
end

-- C_Club -- retail communities API, dead on 3.3.5. Guard table prevents a stray
-- index-nil (the community-resolution sites in Messages never fire).
ensureNamespace("C_Club")

--==============================================================================
-- GROUP C -- retail global functions absent on 3.3.5
--==============================================================================

-- Ambiguate(name, context) -- strips a trailing realm. 3.3.5 names carry no realm,
-- so this is a near no-op (Messages 517/885/887, Tabs 564).
ensureGlobal("Ambiguate", function(name)
  if type(name) ~= "string" then
    return name
  end
  return (name:gsub("%-.*$", ""))
end)

-- assertsafe -- soft no-op assert (Messages 967/1052; must never hard-error).
ensureGlobal("assertsafe", function(cond, msg)
  -- soft: swallow (a real client would log).
end)

-- SafePack / SafeUnpack (Messages 1430). Preserve embedded nils via .n.
ensureGlobal("SafePack", function(...)
  return { n = select("#", ...), ... }
end)
ensureGlobal("SafeUnpack", function(packed)
  if type(packed) ~= "table" then
    return
  end
  return unpack(packed, 1, packed.n or #packed)
end)

-- GetAlternativeDefaultLanguage -> GetDefaultLanguage() or '' (Messages 329/503).
ensureGlobal("GetAlternativeDefaultLanguage", function()
  local getDefault = rawget(_G, "GetDefaultLanguage")
  return (getDefault and getDefault()) or ""
end)

-- EventUtil.ContinueOnAddOnLoaded -- fire immediately if the addon is already
-- loaded, else on the matching ADDON_LOADED. A genuine file-scope crash site
-- (API/Modifiers.lua:7), so EventUtil must exist before that file loads.
ensureNamespace("EventUtil", {
  ContinueOnAddOnLoaded = function(addOnName, callback)
    if type(callback) ~= "function" then
      return
    end
    if _G.IsAddOnLoaded and _G.IsAddOnLoaded(addOnName) then
      callback()
      return
    end
    if not _G.CreateFrame then
      return
    end
    local f = _G.CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, loadedName)
      if loadedName == addOnName then
        self:UnregisterEvent("ADDON_LOADED")
        callback()
      end
    end)
  end,
})

-- RemoveExtraSpaces / RemoveNewlines -- one-line gsub shims (Messages
-- 1291/1302/1335). ensureGlobal so a client shipping them keeps its own.
ensureGlobal("RemoveExtraSpaces", function(text)
  if type(text) ~= "string" then return text end
  return (text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end)
ensureGlobal("RemoveNewlines", function(text)
  if type(text) ~= "string" then return text end
  return (text:gsub("[\r\n]+", " "))
end)

-- tIndexOf / tFilter / FindInTableIf / tCompare -- pure-Lua TableUtil
-- reimplementations (feature-detect; add only if absent).
ensureGlobal("tIndexOf", function(tbl, item)
  if type(tbl) ~= "table" then return nil end
  for i = 1, #tbl do
    if tbl[i] == item then return i end
  end
  return nil
end)
ensureGlobal("tFilter", function(tbl, predicate, isIndexTable)
  local out = {}
  if type(tbl) ~= "table" then return out end
  if isIndexTable then
    for i = 1, #tbl do
      if predicate(tbl[i]) then out[#out + 1] = tbl[i] end
    end
  else
    for k, v in pairs(tbl) do
      if predicate(v) then out[k] = v end
    end
  end
  return out
end)
ensureGlobal("FindInTableIf", function(tbl, predicate)
  if type(tbl) ~= "table" then return nil end
  for k, v in pairs(tbl) do
    if predicate(v) then return k, v end
  end
  return nil
end)
-- FindValueInTableIf -- returns the VALUE then key (Fonts.lua:111).
ensureGlobal("FindValueInTableIf", function(tbl, predicate)
  if type(tbl) ~= "table" then return nil end
  for k, v in pairs(tbl) do
    if predicate(v) then return v, k end
  end
  return nil
end)
-- 3.3.5: GetFonts (retail list of registered font faces) is absent (Fonts.lua:111
-- nil-call). Its only consumer is a secondary font-family dedup; the addon's own
-- fonts[key] table (Fonts.lua:104) is the primary dedup, so an empty list is safe.
ensureGlobal("GetFonts", function() return {} end)
do
  local function deepCompare(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
      if not deepCompare(v, b[k]) then return false end
    end
    for k in pairs(b) do
      if a[k] == nil then return false end
    end
    return true
  end
  ensureGlobal("tCompare", function(a, b)
    return deepCompare(a, b)
  end)
end
-- GetKeysArray -- retail SharedXML TableUtil helper, absent on 3.3.5.
-- Config.lua:320 calls it unguarded, so the profile dropdown would nil-call on
-- open without this shim.
ensureGlobal("GetKeysArray", function(tbl)
  local keys = {}
  if type(tbl) == "table" then
    for k in pairs(tbl) do
      keys[#keys + 1] = k
    end
  end
  return keys
end)

-- GMError -- soft no-op (Messages 1195/1236/1252). A geterrorhandler route would
-- turn a missing-GlobalString warning into a hard error.
ensureGlobal("GMError", function(...)
end)

-- securecallfunction(func, ...) -- retail taint-safe call; 3.3.5 has no taint, so a
-- plain forward. Compat loads BEFORE the Libs\ block, so this exists when
-- CallbackHandler-1.0 captures it as a file-scope upvalue.
ensureGlobal("securecallfunction", function(func, ...)
  if type(func) == "function" then
    return func(...)
  end
end)

-- CallErrorHandler(...) -- retail/MoP+ helper, absent on 3.3.5 (era idiom is
-- geterrorhandler()(...)). Used as the xpcall error-handler in API/Main.lua and
-- Skins/Main.lua; a nil handler would double-fault when a user modifier errored.
ensureGlobal("CallErrorHandler", function(...)
  local handler = geterrorhandler and geterrorhandler()
  if handler then
    return handler(...)
  end
end)

-- CreateFontFamily -- retail (10.1.5+) multi-alphabet font builder, absent on
-- 3.3.5 (one alphabet per client). Collapse to a single CreateFont on the roman
-- member. Fonts.lua:117/124 builds every message font through it. On CJK/Cyrillic
-- clients the non-roman alphabets collapse to the roman face.
ensureGlobal("CreateFontFamily", function(name, members)
  local createFont = rawget(_G, "CreateFont")
  local font = createFont and createFont(name)
  if not font then
    return
  end
  local chosen
  if type(members) == "table" then
    for _, m in ipairs(members) do
      if not chosen then chosen = m end
      if m.alphabet == "roman" then chosen = m break end
    end
  end
  if chosen and chosen.file and font.SetFont then
    font:SetFont(chosen.file, chosen.height or 12, chosen.flags or "")
  end
  -- if the shared font metatable lacks the method (Group E augments it), attach it
  -- to the instance.
  if font.GetFontObjectForAlphabet == nil then
    font.GetFontObjectForAlphabet = function(self) return self end
  end
  return font
end)

-- CopyTable -- deep copy (Locales.lua:3, Config, Messages, CustomiseDialog); the
-- addon's first baseline crash without Compat. ensureGlobal never overrides.
ensureGlobal("CopyTable", function(src)
  local copy = {}
  if type(src) == "table" then
    for k, v in pairs(src) do
      if type(v) == "table" then
        copy[k] = _G.CopyTable(v)
      else
        copy[k] = v
      end
    end
  end
  return copy
end)

-- CreateTextureMarkup -- nil-tolerant reimplementation. The bypass name
-- Chattynator335_CreateTextureMarkup routes past the client's nil-intolerant
-- native; the bare name is also filled for the stock-3.3.5 sites (Constants.lua:12/13,
-- Buttons.lua:116, GW2.lua:11).
local function compatCreateTextureMarkup(file, fileWidth, fileHeight, width, height, left, right, top, bottom, xOffset, yOffset)
  return format("|T%s:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d|t",
    tostring(file),
    height or 0, width or 0, xOffset or 0, yOffset or 0,
    fileWidth or 0, fileHeight or 0,
    floor((left or 0) * (fileWidth or 0) + 0.5),
    floor((right or 0) * (fileWidth or 0) + 0.5),
    floor((top or 0) * (fileHeight or 0) + 0.5),
    floor((bottom or 0) * (fileHeight or 0) + 0.5))
end
ensureGlobal("CreateTextureMarkup", compatCreateTextureMarkup)
rawset(_G, "Chattynator335_CreateTextureMarkup", compatCreateTextureMarkup) -- namespaced; no client collision

-- CreateInterpolator / InterpolatorUtil -- OnUpdate-driven animator. Callers do
-- CreateInterpolator(easing):Interpolate(from, to, duration, onStep[, onDone])
-- (Tabs 38/527/540, Buttons 23/216/237). Easing maps t in [0,1] -> eased t.
ensureNamespace("InterpolatorUtil", {
  InterpolateLinear = function(t) return t end,
  InterpolateEaseIn = function(t) return t * t end,
  InterpolateEaseOut = function(t) return t * (2 - t) end,
  InterpolateEaseInOut = function(t)
    if t < 0.5 then return 2 * t * t end
    return -1 + (4 - 2 * t) * t
  end,
})
ensureGlobal("CreateInterpolator", function(interpolateFunc)
  interpolateFunc = interpolateFunc or function(t) return t end
  local interp = { _func = interpolateFunc }
  function interp:Interpolate(from, to, duration, onStep, onDone)
    from = from or 0
    to = to or 0
    duration = duration or 0
    if not self._frame and _G.CreateFrame then
      self._frame = _G.CreateFrame("Frame")
    end
    local frame = self._frame
    if not frame then
      -- no frame surface: jump straight to the end value.
      if onStep then onStep(to) end
      if onDone then onDone() end
      return
    end
    if duration <= 0 then
      frame:SetScript("OnUpdate", nil)
      frame:Hide()
      if onStep then onStep(to) end
      if onDone then onDone() end
      return
    end
    local elapsed = 0
    frame:Show()
    frame:SetScript("OnUpdate", function(_, dt)
      elapsed = elapsed + (dt or 0)
      local t = elapsed / duration
      if t >= 1 then
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
        if onStep then onStep(to) end
        if onDone then onDone() end
      else
        local eased = self._func(t)
        if onStep then onStep(from + (to - from) * eased) end
      end
    end)
  end
  return interp
end)

-- CreateFramePool -- 6-arg wrapper honoring arg5 (forbidden) + arg6
-- (frameInitializer, run once on Acquire of a NEW frame). The bypass name
-- Chattynator335_CreateFramePool defeats the client's BfA-era 4-arg native (which
-- silently drops args 5/6); the bare name is filled for the stock-3.3.5 sites
-- (Initialize.lua:158, Tabs.lua:152).
local function compatFramePoolHideAndClearAnchors(pool, obj)
  if obj.Hide then obj:Hide() end
  if obj.ClearAllPoints then obj:ClearAllPoints() end
end
local function compatCreateFramePool(frameType, parent, frameTemplate, resetterFunc, forbidden, frameInitializer)
  local pool = {
    frameType = frameType or "Frame",
    parent = parent,
    frameTemplate = frameTemplate,
    resetterFunc = resetterFunc or compatFramePoolHideAndClearAnchors, -- retail default resetter
    frameInitializer = frameInitializer,
    forbidden = forbidden, -- accepted positionally (no 3.3.5 forbidden concept)
    activeObjects = {},
    inactiveObjects = {},
    numActiveObjects = 0,
  }
  function pool:Acquire()
    local obj = tremove(self.inactiveObjects)
    local isNew = false
    if not obj then
      obj = _G.CreateFrame(self.frameType, nil, self.parent, self.frameTemplate)
      isNew = true
      if self.frameInitializer then
        self.frameInitializer(obj)
      end
    end
    self.activeObjects[obj] = true
    self.numActiveObjects = self.numActiveObjects + 1
    return obj, isNew
  end
  function pool:Release(obj)
    if not self.activeObjects[obj] then
      return false
    end
    self.activeObjects[obj] = nil
    self.numActiveObjects = self.numActiveObjects - 1
    if self.resetterFunc then
      self.resetterFunc(self, obj)
    end
    tinsert(self.inactiveObjects, obj)
    return true
  end
  function pool:ReleaseAll()
    for obj in pairs(self.activeObjects) do
      self:Release(obj)
    end
  end
  function pool:EnumerateActive()
    return pairs(self.activeObjects)
  end
  function pool:GetNumActive()
    return self.numActiveObjects
  end
  return pool
end
ensureGlobal("CreateFramePool", compatCreateFramePool)
rawset(_G, "Chattynator335_CreateFramePool", compatCreateFramePool) -- namespaced; no client collision

-- CreateFontStringPool / CreateTexturePool -- SharedXML object pools the message
-- renderer builds at ScrollingMessages:MyOnLoad (self.pool / self.barPool). Native
-- on Ascension, so ensureGlobal never clobbers -- but the renderer calls them
-- unconditionally, so a client lacking them would nil-call at OnLoad. Guarded
-- fallback over the retail ObjectPool contract: Acquire()->obj,isNew / Release /
-- ReleaseAll / EnumerateActive / GetNumActive.
local function compatObjectPool(creationFunc, resetterFunc)
  local pool = { activeObjects = {}, inactiveObjects = {}, numActiveObjects = 0 }
  function pool:Acquire()
    local obj = tremove(self.inactiveObjects)
    local isNew = false
    if not obj then
      obj = creationFunc(self)
      isNew = true
    end
    self.activeObjects[obj] = true
    self.numActiveObjects = self.numActiveObjects + 1
    return obj, isNew
  end
  function pool:Release(obj)
    if not self.activeObjects[obj] then
      return false
    end
    self.activeObjects[obj] = nil
    self.numActiveObjects = self.numActiveObjects - 1
    if resetterFunc then
      resetterFunc(self, obj)
    end
    if obj.Hide then obj:Hide() end
    -- 3.3.5: retail CreateFontStringPool's default resetter is
    -- FramePool_HideAndClearAnchors. Only hiding left reused FontStrings with their
    -- old SetPoints, so the renderer's bottom-anchor chain re-anchored into a cycle
    -- -> "dependent on this" crash on scroll. Clear anchors on release.
    if obj.ClearAllPoints then obj:ClearAllPoints() end
    tinsert(self.inactiveObjects, obj)
    return true
  end
  function pool:ReleaseAll()
    for obj in pairs(self.activeObjects) do
      self:Release(obj)
    end
  end
  function pool:EnumerateActive() return pairs(self.activeObjects) end
  function pool:GetNumActive() return self.numActiveObjects end
  return pool
end
-- inheritsFrom must be a template NAME string; the renderer passes a Font OBJECT as
-- the 4th arg (harmless -- SetFontObject is re-applied post-Acquire), so forward it
-- only when it is actually a string template.
local function compatCreateFontStringPool(parent, layer, subLayer, template, resetterFunc)
  return compatObjectPool(function()
    return parent:CreateFontString(nil, layer, type(template) == "string" and template or nil)
  end, resetterFunc)
end
local function compatCreateTexturePool(parent, layer, subLayer, template, resetterFunc)
  return compatObjectPool(function()
    return parent:CreateTexture(nil, layer, type(template) == "string" and template or nil)
  end, resetterFunc)
end
ensureGlobal("CreateFontStringPool", compatCreateFontStringPool)
ensureGlobal("CreateTexturePool", compatCreateTexturePool)
-- 3.3.5: namespaced bypasses (mirror Chattynator335_CreateFramePool). Ascension's
-- native FontString/Texture pools may drop the resetter -> stale reused regions ->
-- corrupt chat, so the renderer routes through these known-good compat pools.
rawset(_G, "Chattynator335_CreateFontStringPool", compatCreateFontStringPool)
rawset(_G, "Chattynator335_CreateTexturePool", compatCreateTexturePool)

--==============================================================================
-- GROUP E -- frame / region metatable polyfills (only-if-absent; never clobber)
--==============================================================================
-- 3.3.5 widgets of one type share a metatable; getmetatable(instance).__index is a
-- table we can augment. Fill a method only if the type's __index lacks it (normal-
-- index read so an inherited native counts as present; rawset write so a client
-- __newindex is never tripped).
do
  local function ensureWidgetMethod(instance, name, fn)
    if type(instance) ~= "table" and type(instance) ~= "userdata" then
      return
    end
    local mt = getmetatable(instance)
    local idx = mt and mt.__index
    if type(idx) == "table" and idx[name] == nil then
      rawset(idx, name, fn)
    end
  end

  -- hyperlink propagation + render-layer flattening are 8.x/10.x frame methods
  -- with no 3.3.5 equivalent -> no-op (ScrollingMessages 10/12, Main 8/23).
  local function noop() end

  -- AdjustPointsOffset(dx, dy) -- re-anchor every point by the delta (Skins/*,
  -- Tabs 89-133). Works on Frame/Button and Texture/FontString.
  local function adjustPointsOffset(self, dx, dy)
    dx, dy = dx or 0, dy or 0
    if not (self.GetNumPoints and self.GetPoint and self.SetPoint) then
      return
    end
    local n = self:GetNumPoints()
    for i = 1, n do
      local point, relativeTo, relativePoint, x, y = self:GetPoint(i)
      self:SetPoint(point, relativeTo, relativePoint, (x or 0) + dx, (y or 0) + dy)
    end
  end

  -- SetShown(bool) -- native for frames; regions (FontString/Texture) lack it.
  local function setShown(self, shown)
    if shown then
      if self.Show then self:Show() end
    else
      if self.Hide then self:Hide() end
    end
  end

  -- SetTextScale(scale) -- FontString; scales the font height so callers do not
  -- nil-call.
  local function setTextScale(self, scale)
    if type(scale) ~= "number" or not (self.GetFont and self.SetFont) then
      return
    end
    local face, height, flags = self:GetFont()
    if face and height then
      self._compatBaseTextHeight = self._compatBaseTextHeight or height
      self:SetFont(face, self._compatBaseTextHeight * scale, flags)
    end
  end

  -- SetIgnoreParentAlpha (retail 9.0) -- cosmetic parent-alpha opt-out with no
  -- 3.3.5 equivalent -> no-op (the shared noop). Reached on Frame and Texture.

  -- SetColorTexture (Legion 7.0) -- retail-only; the era equivalent is the
  -- SetTexture(r,g,b[,a]) colour overload. Route to it (only-if-absent).
  local function setColorTexture(self, r, g, b, a)
    if self.SetTexture then
      self:SetTexture(r, g, b, a)
    end
  end

  -- GetUnboundedStringWidth (retail BfA) -- un-wrapped width; tab labels are
  -- single-line so GetStringWidth is the exact era equivalent.
  local function getUnboundedStringWidth(self)
    return (self.GetStringWidth and self:GetStringWidth()) or 0
  end

  -- GetLineHeight (Legion) -> font pixel size + line spacing. ScrollingMessages:
  -- Render (201) calls it every render to compute the visible line count; unshimmed
  -- it nil-crashes the whole chat render.
  local function getLineHeight(self)
    local height
    if self.GetFont then
      height = select(2, self:GetFont())
    end
    if type(height) ~= "number" then
      height = 14 -- numeric fallback: never return nil (Render divides by it)
    end
    local spacing = (self.GetSpacing and self:GetSpacing()) or 0
    if type(spacing) ~= "number" then spacing = 0 end
    return height + spacing
  end

  -- GetParentKey (Legion/BfA) -> nil on 3.3.5 (no widget carries a parentKey).
  -- Overrides.lua:175's ChatEdit_UpdateHeader colour hook calls it unguarded on
  -- every edit-box FontString; nil means "unnamed region" so the hook colours it
  -- (era-correct).
  local function getParentKey() return nil end

  -- SetScale/GetScale on REGIONS (frames have them natively; regions do not on
  -- 3.3.5). No-op store so header:SetScale(3) (Initialize.lua:20) + GW2.lua:240
  -- fail-soft instead of nil-crashing; the scale is not visually applied, but
  -- GetScale reads back the stored value so read-after-set stays consistent.
  local function setScale(self, scale)
    if type(scale) == "number" then self._compatRegionScale = scale end
  end
  local function getScale(self)
    return self._compatRegionScale or 1
  end

  -- ClearHighlightTexture (retail 9.0.1) absent on 3.3.5; era way to drop a state
  -- texture is SetHighlightTexture(nil).
  local function clearHighlightTexture(self)
    if self.SetHighlightTexture then self:SetHighlightTexture(nil) end
  end

  -- ClearNormalTexture / ClearPushedTexture (retail 9.0.1) absent on 3.3.5; era
  -- idiom is SetNormalTexture(nil)/SetPushedTexture(nil).
  local function clearNormalTexture(self)
    if self.SetNormalTexture then self:SetNormalTexture(nil) end
  end
  local function clearPushedTexture(self)
    if self.SetPushedTexture then self:SetPushedTexture(nil) end
  end

  -- IsMouseMotionFocus (retail) -> GetMouseFocus() == self. Tab SetSelected/OnLeave
  -- hooks call it to avoid resetting tab alpha while hovered. GetMouseFocus is
  -- nil-guarded so a client without a focus system degrades to false.
  local function isMouseMotionFocus(self)
    local getMouseFocus = rawget(_G, "GetMouseFocus")
    return getMouseFocus ~= nil and getMouseFocus() == self
  end

  local frameMethodDefs = {
    SetHyperlinkPropagateToParent = noop,
    SetFlattensRenderLayers = noop,
    SetClipsChildren = noop,               -- retail 9.0 child-clip method -> no-op
    AdjustPointsOffset = adjustPointsOffset,
    SetShown = setShown,
    SetIgnoreParentAlpha = noop,           -- cosmetic no-op (retail 9.0)
    ClearHighlightTexture = clearHighlightTexture, -- retail 9.0 -> SetHighlightTexture(nil)
    ClearNormalTexture = clearNormalTexture,   -- retail 9.0.1 -> SetNormalTexture(nil)
    ClearPushedTexture = clearPushedTexture,   -- retail 9.0.1 -> SetPushedTexture(nil)
    IsMouseMotionFocus = isMouseMotionFocus,   -- retail -> GetMouseFocus() == self
    SetPropagateMouseMotion = noop,        -- retail 10.1 -> no-op (GW2 hover tracker)
    SetPropagateMouseClicks = noop,        -- retail 9.0 -> no-op (GW2 hover tracker)
  }
  if type(_G.CreateFrame) == "function" then
    for _, wtype in ipairs({
      "Frame", "Button", "CheckButton", "Slider", "EditBox", "ScrollFrame", "StatusBar",
      "SimpleHTML", -- the message line is a SimpleHTML; probe it so it gets the same only-if-absent fill (pcall-guarded if the type is uninstantiable).
    }) do
      local ok, probe = pcall(_G.CreateFrame, wtype)
      if ok and probe then
        for name, fn in pairs(frameMethodDefs) do
          ensureWidgetMethod(probe, name, fn)
        end
        if probe.Hide then probe:Hide() end
      end
    end
    -- reach widget types CreateFrame cannot instantiate through singleton instances
    for _, globalName in ipairs({ "ChatFrame1", "UIParent", "WorldFrame", "Minimap" }) do
      local inst = rawget(_G, globalName)
      for name, fn in pairs(frameMethodDefs) do
        ensureWidgetMethod(inst, name, fn)
      end
    end
  end

  -- GetFontObjectForAlphabet (retail multi-alphabet accessor) -> self on 3.3.5 (one
  -- alphabet per client). Reached through the shared Font metatable so every font
  -- object gains it. Fonts.lua calls it on ChatFontNormal (80) and every family (133).
  do
    local function getFontObjectForAlphabet(self) return self end
    for _, name in ipairs({ "ChatFontNormal", "GameFontNormal", "GameFontHighlight", "SystemFont_Shadow_Med1" }) do
      local fo = rawget(_G, name)
      if type(fo) == "table" or type(fo) == "userdata" then
        local mt = getmetatable(fo)
        if mt and type(mt.__index) == "table" then
          if rawget(mt.__index, "GetFontObjectForAlphabet") == nil then
            rawset(mt.__index, "GetFontObjectForAlphabet", getFontObjectForAlphabet)
          end
        elseif type(fo) == "table" and rawget(fo, "GetFontObjectForAlphabet") == nil then
          rawset(fo, "GetFontObjectForAlphabet", getFontObjectForAlphabet)
        end
      end
    end
  end

  -- Regions (Texture / FontString): SetShown + AdjustPointsOffset; Texture also
  -- SetColorTexture + SetIgnoreParentAlpha; FontString also SetTextScale +
  -- GetUnboundedStringWidth + SetIgnoreParentAlpha. Both also GetParentKey +
  -- SetScale/GetScale; FontString also GetLineHeight.
  local parent = rawget(_G, "UIParent")
  if type(parent) == "table" then
    if parent.CreateTexture then
      local tex = parent:CreateTexture()
      ensureWidgetMethod(tex, "SetShown", setShown)
      ensureWidgetMethod(tex, "AdjustPointsOffset", adjustPointsOffset)
      ensureWidgetMethod(tex, "SetColorTexture", setColorTexture)
      ensureWidgetMethod(tex, "SetIgnoreParentAlpha", noop)
      ensureWidgetMethod(tex, "GetParentKey", getParentKey)
      ensureWidgetMethod(tex, "SetScale", setScale)
      ensureWidgetMethod(tex, "GetScale", getScale)
    end
    if parent.CreateFontString then
      local fs = parent:CreateFontString()
      ensureWidgetMethod(fs, "SetShown", setShown)
      ensureWidgetMethod(fs, "AdjustPointsOffset", adjustPointsOffset)
      ensureWidgetMethod(fs, "SetTextScale", setTextScale)
      ensureWidgetMethod(fs, "GetUnboundedStringWidth", getUnboundedStringWidth)
      ensureWidgetMethod(fs, "SetIgnoreParentAlpha", noop)
      ensureWidgetMethod(fs, "GetLineHeight", getLineHeight)
      ensureWidgetMethod(fs, "GetParentKey", getParentKey)
      ensureWidgetMethod(fs, "SetScale", setScale)
      ensureWidgetMethod(fs, "GetScale", getScale)
    end
  end

  -- The tab-flash + chat-fade AnimationGroups use retail Alpha setters absent on
  -- 3.3.5 -- SetChildKey, SetFromAlpha/SetToAlpha (7.0.3+; era delta is SetChange)
  -- on the Animation, SetToFinalAlpha (7.0+) on the group. No-op them so the skinner
  -- completes; the flash/fade simply does not animate.
  if type(_G.CreateFrame) == "function" then
    local ok, probe = pcall(_G.CreateFrame, "Frame")
    if ok and probe and probe.CreateAnimationGroup then
      local grp = probe:CreateAnimationGroup()
      if grp then
        ensureWidgetMethod(grp, "SetToFinalAlpha", noop) -- AnimationGroup
        -- SetPlaying(bool) is retail (8.0); era API is Play()/Stop().
        ensureWidgetMethod(grp, "SetPlaying", function(self, playing)
          if playing then
            if self.Play then self:Play() end
          elseif self.Stop then
            self:Stop()
          end
        end)
        if grp.CreateAnimation then
          local anim = grp:CreateAnimation("Alpha")
          if anim then
            ensureWidgetMethod(anim, "SetChildKey", noop)
            ensureWidgetMethod(anim, "SetFromAlpha", noop)
            ensureWidgetMethod(anim, "SetToAlpha", noop)
          end
        end
      end
      if probe.Hide then probe:Hide() end
    end
  end
end

-- Shared valid-tooltip-hyperlink allowlist + fail-soft setter.
-- On 3.3.5 GameTooltip:SetHyperlink THROWS "Unknown link type" for any type the client does
-- not support (player, channel, BNplayer, url, and every retail type). Messages.lua emits
-- |Hplayer:...|h for every whisper/channel line, so hovering one crashed the per-line renderer.
-- Every tooltip-hyperlink caller routes through SafeSetTooltipHyperlink. Absent under a
-- standalone dofile (no addonTable).
if type(_addonTable) == "table" then
  -- true = supported by the 3.3.5 client SetHyperlink; false = unsupported / retail-only.
  local VALID_TOOLTIP_LINKS = {
    achievement = true, api = false, battlepet = false, battlePetAbil = false,
    calendarEvent = false, channel = false, clubFinder = false, clubTicket = false,
    community = false, conduit = true, currency = true, death = false,
    dungeonScore = true, enchant = false, garrfollower = false, garrfollowerability = false,
    garrmission = false, instancelock = true, item = true, journal = false,
    keystone = true, levelup = false, lootHistory = false, mawpower = true,
    outfit = false, player = false, playerCommunity = false, BNplayer = false,
    BNplayerCommunity = false, quest = true, shareachieve = false, shareitem = false,
    sharess = false, spell = true, storecategory = false, talent = true,
    talentbuild = false, trade = false, transmogappearance = false, transmogillusion = false,
    transmogset = false, unit = true, urlIndex = false, worldmap = false,
  }
  _addonTable.VALID_TOOLTIP_LINKS = VALID_TOOLTIP_LINKS

  -- Gate + fail-soft SetHyperlink. Returns true iff the tooltip was populated + shown.
  -- (1) allowlist the link TYPE, then (2) pcall the call anyway (an allowlisted-but-client-
  -- unsupported type, or a malformed body, can still error), hiding the tooltip on failure so
  -- we never leave an owned-but-empty tooltip stuck on screen.
  function _addonTable.SafeSetTooltipHyperlink(tooltip, owner, anchor, link)
    if type(link) ~= "string" then
      return false
    end
    local linkType = link:match("^(.-):") or link
    if not VALID_TOOLTIP_LINKS[linkType] then
      return false
    end
    tooltip:SetOwner(owner, anchor)
    local ok = pcall(tooltip.SetHyperlink, tooltip, link)
    if ok then
      tooltip:Show()
      return true
    end
    tooltip:Hide()
    return false
  end
end
