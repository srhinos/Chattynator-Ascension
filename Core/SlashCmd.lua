---@class addonTableChattynator
local addonTable = select(2, ...)
addonTable.SlashCmd = {}

function addonTable.SlashCmd.Initialize()
  SlashCmdList["Chattynator"] = addonTable.SlashCmd.Handler
  SLASH_Chattynator1 = "/chattynator"
  SLASH_Chattynator2 = "/ctnr"
  SLASH_Chattynator3 = "/chatty"

  -- Retail-style /i: 3.3.5 has no INSTANCE_CHAT, so route to the current group channel by context.
  local function ResolveInstanceChannel()
    local _, instanceType = IsInInstance()
    if instanceType == "pvp" then
      return "BATTLEGROUND"
    elseif (IsInRaid and IsInRaid()) or (GetNumRaidMembers and GetNumRaidMembers() > 0) then
      return "RAID"
    elseif (GetNumPartyMembers and GetNumPartyMembers() > 0) or (IsInGroup and IsInGroup()) then
      return "PARTY"
    end
  end

  -- Primary path: the retail chat-type-switch feel. Typing "/i " (or /inst, /instance) followed
  -- by a space swaps the edit box's chat type to the resolved channel and drops the prefix,
  -- exactly like the stock /p /raid /bg. A SlashCmdList command can't do this because it only
  -- fires on Enter -- OnTextChanged fires on the space, and we own this edit box.
  ChatFrame1EditBox:HookScript("OnTextChanged", function(editBox, userInput)
    if not userInput then
      return -- our own SetText below re-fires this with userInput=false; ignore it
    end
    local token, rest = editBox:GetText():match("^(/%S+)%s(.*)$")
    if not token then
      return
    end
    token = token:lower()
    if token == "/i" or token == "/inst" or token == "/instance" then
      local channel = ResolveInstanceChannel()
      if channel then
        editBox:SetAttribute("chatType", channel)
        ChatEdit_UpdateHeader(editBox)
        rest = rest or ""
        editBox:SetText(rest)
        editBox:SetCursorPosition(#rest)
      end
    end
  end)

  -- Fallback: bare "/i" + Enter (no trailing space, so the hook above never fired).
  SlashCmdList["ChattynatorInstance"] = function(msg)
    local channel = ResolveInstanceChannel()
    if not channel then
      return -- not grouped; nothing to route to (mirrors retail's no-op)
    end
    if msg and msg:match("%S") then
      SendChatMessage(msg, channel)
    else
      addonTable.Timer335.After(0, function()
        local editBox = (ChatEdit_ChooseBoxForSend and ChatEdit_ChooseBoxForSend()) or ChatFrame1EditBox
        ChatEdit_ActivateChat(editBox)
        editBox:SetAttribute("chatType", channel)
        ChatEdit_UpdateHeader(editBox)
      end)
    end
  end
  SLASH_ChattynatorInstance1 = "/i"
  SLASH_ChattynatorInstance2 = "/inst"
  SLASH_ChattynatorInstance3 = "/instance"

  -- Chat-event probe for /chatty dump: records the last event + its arg12 GUID.
  -- A separate frame from the seized ChatFrames so it still receives events.
  local probe = CreateFrame("Frame")
  for _, e in ipairs({ "CHAT_MSG_WHISPER", "CHAT_MSG_CHANNEL", "CHAT_MSG_AFK", "CHAT_MSG_SAY", "CHAT_MSG_GUILD" }) do
    if C_EventUtils.IsEventValid(e) then
      probe:RegisterEvent(e)
    end
  end
  probe:SetScript("OnEvent", function(_, event, ...)
    addonTable.SlashCmd._lastChat = { event = event, arg12 = select(12, ...), argCount = select("#", ...) }
  end)
end

-- /chatty diag|dump render into a self-contained popup, not the chat frame: when the
-- chat display is the broken subsystem there's nothing to print to, and 3.3.5 has no OS
-- clipboard. Depends only on CreateFrame + SetBackdrop. Ctrl+C copies; ESC closes.
local outputWindow
local function ShowOutputWindow(title, body)
  local win = outputWindow
  if not win then
    win = CreateFrame("Frame", "ChattynatorDiagWindow", UIParent)
    win:SetSize(560, 440); win:SetPoint("CENTER"); win:SetFrameStrata("DIALOG")
    win:SetToplevel(true); win:SetClampedToScreen(true); win:SetMovable(true)
    win:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    win:SetBackdropColor(0, 0, 0, 0.92); win:SetBackdropBorderColor(0.5, 0.5, 0.5, 1); win:Hide()
    if UISpecialFrames then tinsert(UISpecialFrames, win:GetName()) end
    win.title = CreateFrame("Frame", nil, win)
    win.title:SetPoint("TOPLEFT", 12, -10); win.title:SetPoint("TOPRIGHT", -32, -10)
    win.title:SetHeight(20); win.title:EnableMouse(true)
    win.title:SetScript("OnMouseDown", function() win:StartMoving() end)
    win.title:SetScript("OnMouseUp", function() win:StopMovingOrSizing() end)
    win.titleText = win.title:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    win.titleText:SetPoint("LEFT")
    win.close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    win.close:SetPoint("TOPRIGHT", -2, -2); win.close:SetScript("OnClick", function() win:Hide() end)
    win.scroll = CreateFrame("ScrollFrame", "ChattynatorDiagWindowScroll", win, "UIPanelScrollFrameTemplate")
    win.scroll:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -8)
    win.scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -30, 12)
    win.editBox = CreateFrame("EditBox", "ChattynatorDiagWindowEditBox", win.scroll)
    win.editBox:SetMultiLine(true); win.editBox:SetFontObject(ChatFontNormal)
    win.editBox:SetAutoFocus(false); win.editBox:SetMaxLetters(0); win.editBox:EnableMouse(true)
    win.editBox:SetWidth(500); win.editBox:SetScript("OnEscapePressed", function() win:Hide() end)
    win.scroll:SetScrollChild(win.editBox)
    win.scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then win.editBox:SetWidth(w) end end)
    -- 3.3.5: UIPanelScrollFrameTemplate wires the scrollbar buttons but not wheel input;
    -- a ScrollFrame needs EnableMouseWheel + an OnMouseWheel handler. Clamp to range.
    win.scroll:EnableMouseWheel(true)
    win.scroll:SetScript("OnMouseWheel", function(self, delta)
      local range = self:GetVerticalScrollRange() or 0
      local new = (self:GetVerticalScroll() or 0) - delta * 24
      if new < 0 then new = 0 elseif new > range then new = range end
      self:SetVerticalScroll(new)
    end)
    -- The mouse-enabled EditBox scroll-child covers the scroll area and the wheel doesn't
    -- fall through to the parent, so also drive the scroll from the EditBox's own handler.
    win.editBox:EnableMouseWheel(true)
    win.editBox:SetScript("OnMouseWheel", function(_, delta)
      local range = win.scroll:GetVerticalScrollRange() or 0
      local new = (win.scroll:GetVerticalScroll() or 0) - delta * 24
      if new < 0 then new = 0 elseif new > range then new = range end
      win.scroll:SetVerticalScroll(new)
    end)
    outputWindow = win
  end
  win.titleText:SetText(tostring(title or "Chattynator"))
  win:Show(); win.editBox:SetText(tostring(body or "")); win.scroll:SetVerticalScroll(0)
  win.editBox:HighlightText(); win.editBox:SetFocus()
end

-- Buffered output: /chatty diag|dump collect lines then flush to the window (color codes
-- stripped for the plain EditBox). Also mirrored to the chat display in case it IS working.
local outBuffer
local function Out(text)
  if outBuffer then
    outBuffer[#outBuffer + 1] = (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  end
  if addonTable.Messages and addonTable.Utilities and addonTable.Utilities.Message then
    pcall(addonTable.Utilities.Message, text)
  end
end
local function Flush(title)
  local body = outBuffer and table.concat(outBuffer, "\n") or ""
  outBuffer = nil
  if not pcall(ShowOutputWindow, title, body) then
    for line in body:gmatch("[^\n]+") do print(line) end -- last-resort if the window itself fails
  end
end

-- Per-feature-block pcall ok/FAIL + which globals were shimmed-vs-native + flavor.
function addonTable.SlashCmd.Diag()
  outBuffer = {}
  Out("Chattynator /chatty diag")
  local C = addonTable.Constants
  Out(("  flavor: IsClassic=%s IsRetail=%s  build=%s"):format(
    tostring(C and C.IsClassic), tostring(C and C.IsRetail), tostring(select(4, GetBuildInfo()))))

  local diag = addonTable.diag
  if diag and diag.order and #diag.order > 0 then
    Out("  init blocks (fail-soft pcall):")
    for _, name in ipairs(diag.order) do
      local b = diag.blocks[name]
      if b and b.ok then
        Out(("    |cff40ff40OK  |r %s"):format(name))
      else
        Out(("    |cffff4040FAIL|r %s: %s"):format(name, b and tostring(b.err) or "?"))
      end
    end
  else
    Out("  (no init diagnostics recorded -- Core.Initialize did not run)")
  end

  local report = addonTable.CompatReport
  if report then
    local shimmed, native = {}, {}
    for k in pairs(report.shims) do shimmed[#shimmed + 1] = k end
    for k in pairs(report.native) do native[#native + 1] = k end
    table.sort(shimmed)
    table.sort(native)
    Out(("  shimmed (%d): %s"):format(#shimmed, table.concat(shimmed, ", ")))
    if #native > 0 then
      Out(("  native/kept (%d): %s"):format(#native, table.concat(native, ", ")))
    end
  end
  Flush("Chattynator  -  /chatty diag")
end

-- Seized ChatFrame region/child/anchor tree + CHAT_FRAMES contents + arg12 of the
-- last chat event.
function addonTable.SlashCmd.Dump()
  outBuffer = {}
  Out("Chattynator /chatty dump")
  Out("  CHAT_FRAMES:")
  for i, name in pairs(CHAT_FRAMES or {}) do
    local f = _G[name]
    local parent = f and f.GetParent and f:GetParent()
    local pname = parent and ((parent.GetName and parent:GetName()) or tostring(parent)) or "nil"
    Out(("    [%s] %s parent=%s shown=%s"):format(
      tostring(i), tostring(name), tostring(pname), tostring(f and f.IsShown and f:IsShown())))
  end

  local cf = _G.ChatFrame1
  if cf then
    local parent = cf.GetParent and cf:GetParent()
    local pname = parent and ((parent.GetName and parent:GetName()) or "<hidden/anon>") or "nil"
    Out(("  ChatFrame1: parent=%s shown=%s"):format(tostring(pname), tostring(cf.IsShown and cf:IsShown())))
    if cf.GetRegions then
      local regions = { cf:GetRegions() }
      Out(("    regions: %d"):format(#regions))
      for _, r in ipairs(regions) do
        if type(r) == "table" and r.GetObjectType then
          Out(("      %s%s"):format(tostring(r:GetObjectType()),
            (r.GetParentKey and r:GetParentKey()) and (" [" .. r:GetParentKey() .. "]") or ""))
        end
      end
    end
    if cf.GetNumPoints and cf.GetPoint then
      local n = cf:GetNumPoints() or 0
      for i = 1, n do
        local p, rel, rp, x, y = cf:GetPoint(i)
        local relName = rel and ((rel.GetName and rel:GetName()) or "<anon>") or "nil"
        Out(("    anchor[%d]: %s -> %s.%s (%s, %s)"):format(
          i, tostring(p), tostring(relName), tostring(rp), tostring(x), tostring(y)))
      end
    end
  end

  local last = addonTable.SlashCmd._lastChat
  if last then
    Out(("  last chat event: %s  args=%s  arg12(GUID)=%s"):format(
      tostring(last.event), tostring(last.argCount), tostring(last.arg12)))
  else
    Out("  last chat event: (none seen yet -- fire a WHISPER/CHANNEL to populate arg12)")
  end

  -- Message line-layout metrics.
  pcall(function()
    local M = addonTable.Messages
    Out(("  layout: scale=%s spacing=%s inset=%s font=%s"):format(
      tostring(M and M.scalingFactor), tostring(M and M.spacing),
      tostring(M and M.inset), tostring(M and M.font)))
    local fo = M and M.font and _G[M.font]
    if fo and fo.GetFont then
      Out(("    font-obj px=%s"):format(tostring(select(2, fo:GetFont()))))
    end
    local cf1 = addonTable.allChatFrames and addonTable.allChatFrames[1]
    local scm = cf1 and cf1.ScrollingMessages
    if scm then
      Out(("    scm: height=%s #visibleLines=%s"):format(
        tostring(scm.GetHeight and scm:GetHeight()), tostring(scm.visibleLines and #scm.visibleLines)))
      local vl = scm.visibleLines and scm.visibleLines[1]
      if vl then
        Out(("    line[1]: GetHeight=%s GetLineHeight=%s fontPx=%s numPoints=%s text=%q"):format(
          tostring(vl.GetHeight and vl:GetHeight()),
          tostring(vl.GetLineHeight and vl:GetLineHeight()),
          tostring(select(2, vl:GetFont())),
          tostring(vl.GetNumPoints and vl:GetNumPoints()),
          tostring(vl.GetText and vl:GetText()):sub(1, 24)))
      end
    end
  end)

  Flush("Chattynator  -  /chatty dump")
end

local INVALID_OPTION_VALUE = "Wrong config value type %s (required %s)"
function addonTable.SlashCmd.Config(optionName, value1, ...)
  if optionName == nil then
    addonTable.Utilities.Message("No config option name supplied")
    for _, name in pairs(addonTable.Config.Options) do
      addonTable.Utilities.Message(name .. ": " .. tostring(addonTable.Config.Get(name)))
    end
    return
  end

  local currentValue = addonTable.Config.Get(optionName)
  if currentValue == nil then
    addonTable.Utilities.Message("Unknown config: " .. optionName)
    return
  end

  if value1 == nil then
    addonTable.Utilities.Message("Config " .. optionName .. ": " .. tostring(currentValue))
    return
  end

  if type(currentValue) == "boolean" then
    if value1 ~= "true" and value1 ~= "false" then
      addonTable.Utilities.Message(INVALID_OPTION_VALUE:format(type(value1), type(currentValue)))
      return
    end
    addonTable.Config.Set(optionName, value1 == "true")
  elseif type(currentValue) == "number" then
    if tonumber(value1) == nil then
      addonTable.Utilities.Message(INVALID_OPTION_VALUE:format(type(value1), type(currentValue)))
      return
    end
    addonTable.Config.Set(optionName, tonumber(value1))
  elseif type(currentValue) == "string" then
    addonTable.Config.Set(optionName, strjoin(" ", value1, ...))
  else
    addonTable.Utilities.Message("Unable to edit option type " .. type(currentValue))
    return
  end
  addonTable.Utilities.Message("Now set " .. optionName .. ": " .. tostring(addonTable.Config.Get(optionName)))
end

function addonTable.SlashCmd.Reset()
  CHATTYNATOR_CONFIG = nil
  ReloadUI()
end

function addonTable.SlashCmd.Version()
  addonTable.Utilities.Message(
    BLUE_FONT_COLOR:WrapTextInColorCode("Version: ") .. C_AddOns.GetAddOnMetadata("Chattynator", "Version") ..
    LIGHTGRAY_FONT_COLOR:WrapTextInColorCode(", " .. date() .. ", ") ..
    BLUE_FONT_COLOR:WrapTextInColorCode("WoW: ") .. select(4, GetBuildInfo())
  )
end

function addonTable.SlashCmd.CustomiseUI()
  addonTable.CustomiseDialog.Toggle()
end

local COMMANDS = {
  [""] = addonTable.SlashCmd.CustomiseUI,
  ["v"] = addonTable.SlashCmd.Version,
  ["version"] = addonTable.SlashCmd.Version,
  ["c"] = addonTable.SlashCmd.Config,
  ["config"] = addonTable.SlashCmd.Config,
  ["reset"] = addonTable.SlashCmd.Reset,
  ["diag"] = addonTable.SlashCmd.Diag,
  ["dump"] = addonTable.SlashCmd.Dump,
}
local HELP = {
  {"", addonTable.Locales.SLASH_HELP},
  {"diag", "per-block init status + shimmed globals + flavor"},
  {"dump", "seized chat-frame tree + CHAT_FRAMES + last event arg12"},
}

function addonTable.SlashCmd.Handler(input)
  local split = {strsplit("\a", (input:gsub("%s+","\a")))}

  local root = split[1]
  if COMMANDS[root] ~= nil then
    table.remove(split, 1)
    COMMANDS[root](unpack(split))
  else
    if root ~= "help" and root ~= "h" then
      addonTable.Utilities.Message(addonTable.Locales.SLASH_UNKNOWN_COMMAND:format(root))
    end

    for _, entry in ipairs(HELP) do
      if entry[1] == "" then
        addonTable.Utilities.Message("/ctnr - " .. entry[2])
      else
        addonTable.Utilities.Message("/ctnr " .. entry[1] .. " - " .. entry[2])
      end
    end
  end
end
