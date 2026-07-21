---@class addonTableChattynator
local addonTable = select(2, ...)

local rightInset = 3

-- 3.3.5: no FontString:SetTextScale. Scale in-place via SetFont. Callers SetFontObject
-- first, so GetFont() returns the base height and the scale never compounds on reuse.
local function ApplyTextScale(fontString, scale)
  local fontObj = (addonTable.Messages and addonTable.Messages.font and _G[addonTable.Messages.font]) or _G["ChatFontNormal"]
  local face, height, flags
  if fontObj and fontObj.GetFont then
    face, height, flags = fontObj:GetFont()
  else
    face, height, flags = "Fonts\\FRIZQT__.TTF", 14, ""
  end
  if face and height then
    local targetHeight = height * (scale or 1)
    if targetHeight < 6 then targetHeight = 6 end
    fontString:SetFont(face, targetHeight, flags or "")
  end
end

local function ApplyHTMLFont(html, fontName, scale)
  html:SetFontObject(fontName)
  local fontObj = _G[fontName] or _G["ChatFontNormal"]
  if fontObj and fontObj.GetFont then
    local face, height, flags = fontObj:GetFont()
    if face and height then
      local targetHeight = height * (scale or 1)
      if targetHeight < 6 then targetHeight = 6 end
      pcall(html.SetFont, html, "p", face, targetHeight, flags or "")
    end
  end
end

-- Per-line hyperlink handlers. 3.3.5 SimpleHTML fires OnHyperlink* as
-- (self, linkData, linkMarkup, mouseButton, ...); linkData is the body SetHyperlink/SetItemRef
-- consume. Click routes through SetItemRef with ChattynatorHyperlinkHandler as owner so the
-- URLs.lua SetItemRef hook still fires. Wired onto each frame once by msgFrameInitializer.
local function msgOnHyperlinkEnter(self, linkData)
  -- 3.3.5 GameTooltip:SetHyperlink throws on unsupported link types (player/channel/BNplayer/url),
  -- and whisper/channel lines carry |Hplayer:...|h -- gate through the fail-soft allowlisted setter.
  addonTable.SafeSetTooltipHyperlink(GameTooltip, self, "ANCHOR_CURSOR", linkData)
end

local function msgOnHyperlinkLeave()
  GameTooltip:Hide()
end

local function msgOnHyperlinkClick(self, linkData, linkMarkup, mouseButton, downOrArg)
  local button = ((mouseButton == "LeftButton" or mouseButton == "RightButton") and mouseButton)
    or ((downOrArg == "LeftButton" or downOrArg == "RightButton") and downOrArg)
    or (IsShiftKeyDown() and "LeftButton")
    or "RightButton"
  if type(linkData) == "string" then
    SetItemRef(linkData, linkMarkup or linkData, button, ChattynatorHyperlinkHandler or self)
  end
end

-- Runs ONCE per newly-created SimpleHTML (arg6 of the Compat frame pool).
local function msgFrameInitializer(frame)
  frame:SetScript("OnHyperlinkEnter", msgOnHyperlinkEnter)
  frame:SetScript("OnHyperlinkLeave", msgOnHyperlinkLeave)
  frame:SetScript("OnHyperlinkClick", msgOnHyperlinkClick)
end

-- Pool resetter: must clear anchors like the default resetter, or a pooled frame's stale
-- SetPoints can re-anchor into a cycle ("dependent on this" crash).
local function msgFrameResetter(pool, frame)
  frame:Hide()
  frame:ClearAllPoints()
  frame:SetText("")
end

---@class DisplayScrollingMessages: Frame
addonTable.Display.ScrollingMessagesMixin = {}

function addonTable.Display.ScrollingMessagesMixin:MyOnLoad()
  self:SetHyperlinkPropagateToParent(true)
  self:SetClipsChildren(true)
  self:SetFlattensRenderLayers(true)

  self.scrollIndex = 1

  self.visibleLines = {}

  self.currentFadeOffsetTime = 0
  self.accumulatedTime = 0
  self.timestampOffset = GetTime() - time()

  -- 3.3.5: use the namespaced pools; the native pool can drop the resetter and render stale regions.
  self.pool = Chattynator335_CreateFontStringPool(self, "BACKGROUND", 0, addonTable.Messages.font)
  self.barPool = Chattynator335_CreateTexturePool(self, "BACKGROUND")

  -- Message lines are SimpleHTML so the client hit-tests item/spell/player links and wraps
  -- natively (a plain Frame/FontString has no OnHyperlink* before Cataclysm). Timestamps and
  -- bars stay FontStrings/Textures. 6-arg pool bypass so arg6 (the initializer) runs -- the
  -- native 4-arg pool drops args 5/6.
  self.msgPool = Chattynator335_CreateFramePool("SimpleHTML", self, nil, msgFrameResetter, false, msgFrameInitializer)

  -- 3.3.5 does not implicitly enable wheel input when an OnMouseWheel script is set; without
  -- this the handler below is inert.
  self:EnableMouseWheel(true)

  self:SetScript("OnMouseWheel", function(_, delta)
    self.currentFadeOffsetTime = GetTime()
    local multiplier = 1
    if IsShiftKeyDown() then
      multiplier = 1000
    elseif IsControlKeyDown() then
      multiplier = 5
    end
    if delta > 0 then
      self:ScrollByAmount(1 * multiplier)
    else
      self:ScrollByAmount(-1 * multiplier)
    end
  end)

  addonTable.CallbackRegistry:RegisterCallback("SettingChanged", function(_, settingName)
    if settingName == addonTable.Config.Options.ENABLE_MESSAGE_FADE or settingName == addonTable.Config.Options.MESSAGE_FADE_TIME then
      self:UpdateAlphas()
    end
  end)
end

function addonTable.Display.ScrollingMessagesMixin:Reset()
  self.scrollIndex = 1
  self.currentFadeOffsetTime = 0
end

function addonTable.Display.ScrollingMessagesMixin:ScrollByAmount(amount)
  self.scrollIndex = math.max(1, self.scrollIndex + amount)
  self.scrollCallback()

  self:Render()
end

function addonTable.Display.ScrollingMessagesMixin:PageUp()
  self:ScrollByAmount(1)
end

function addonTable.Display.ScrollingMessagesMixin:PageDown()
  self:ScrollByAmount(-1)
end

function addonTable.Display.ScrollingMessagesMixin:ScrollToBottom()
  self.scrollIndex = 1
  self.scrollCallback()
  self:Render()
end

function addonTable.Display.ScrollingMessagesMixin:AtBottom()
  return self.scrollIndex == 1
end

function addonTable.Display.ScrollingMessagesMixin:SetOnScrollChangedCallback(callback)
  self.scrollCallback = callback
end

function addonTable.Display.ScrollingMessagesMixin:Clear()
  for _, fs in ipairs(self.visibleLines) do
    fs.timestamp = nil
    fs.bar = nil
  end
  self.visibleLines = {}
  self.pool:ReleaseAll()
  self.msgPool:ReleaseAll() -- release the SimpleHTML message frames too
  self.barPool:ReleaseAll()
end

function addonTable.Display.ScrollingMessagesMixin:SetFilter(filterFunc)
  self.filterFunc = filterFunc
end

function addonTable.Display.ScrollingMessagesMixin:UpdateAlphas(elapsed)
  if elapsed then
    self.accumulatedTime = self.accumulatedTime + elapsed
    if self.animationsPending then
      local any = false
      for _, fs in ipairs(self.visibleLines) do
        if fs.animationTime ~= fs.animationFinalTime then
          any = true
          fs.animationTime = math.min(fs.animationFinalTime, fs.animationTime + elapsed)
          local alpha = fs.animationStart + (1 - (1 - fs.animationTime/fs.animationFinalTime) ^ 2) * fs.animationDestination
          fs:SetAlpha(alpha)
          fs.timestamp:SetAlpha(alpha)
          if fs.bar then
            fs.bar:SetAlpha(alpha)
          end
          fs:SetShown(alpha > 0)
        end
      end

      if not any then
        self.animationsPending = false
      end
    end
    if self.accumulatedTime < 1 then
      return

    else
      self.accumulatedTime = 0
    end
  end

  local fadeTime = addonTable.Config.Get(addonTable.Config.Options.MESSAGE_FADE_TIME)
  local fadeEnabled = addonTable.Config.Get(addonTable.Config.Options.ENABLE_MESSAGE_FADE)
  local currentTime = GetTime()

  local any = false
  local faded = false
  for i = #self.visibleLines, 1, -1 do
    local fs = self.visibleLines[i]
    if fs then
      local alpha = fs:GetAlpha()
      fs:SetShown(alpha > 0)
      fs.timestamp:SetShown(alpha > 0)
      if fs.bar then
        fs.bar:SetShown(alpha > 0)
      end

      if fadeEnabled and self.scrollIndex == 1 and math.max(fs.timestampValue + self.timestampOffset, self.currentFadeOffsetTime) + fadeTime - currentTime < 0 then
        if not faded and self.accumulatedTime == 0 and alpha ~= 0 and (fs.animationFinalAlpha ~= 0 or fs.animationFinalTime == 0) then
          faded = true
          any = true
          fs.animationTime = 0
          fs.animationStart = alpha
          fs.animationFinalTime = 3
          fs.animationDestination = 0 - alpha
          fs.animationFinalAlpha = 0
        end
      elseif not fadeEnabled then
        fs.animationFinalAlpha = nil
        fs.animationTime = nil
        fs.animationStart = nil
        fs.animationFinalTime = nil
        fs.animationDestination = nil
        fs:SetAlpha(1)
        fs:Show()
        fs.timestamp:SetAlpha(1)
        fs.timestamp:Show()
        if fs.bar then
          fs.bar:SetAlpha(1)
          fs.bar:Show()
        end
      elseif alpha == 1 then
        any = true
      end
    end
  end

  if any then
    self.animationsPending = true
    self:SetScript("OnUpdate", self.UpdateAlphas)
  end
end

function addonTable.Display.ScrollingMessagesMixin:Render(newMessages)
  if self.currentFadeOffsetTime == 0 then
    self.currentFadeOffsetTime = GetTime()
  end

  if newMessages == nil then
    self:Clear()
  end
  local tmp = self.pool:Acquire()
  -- 3.3.5 SetClipsChildren is a no-op, so overflow lines flow out the top instead of being
  -- clipped. Divide by the true per-line pitch and floor so we only fetch what fits.
  local lineHeight = tmp:GetLineHeight()
  local pitch = lineHeight + (addonTable.Messages.spacing or 0)
  local lines = math.max(1, math.floor(self:GetHeight() / pitch))
  self.pool:Release(tmp)

  local index = 1
  local messages = {}
  while (newMessages and self.scrollIndex == 1 and index <= newMessages) or (not newMessages and #messages < self.scrollIndex + lines - 1) do
    local m = addonTable.Messages:GetMessageRaw(index)
    if not m then
      break
    end
    if m.recordedBy == addonTable.Data.CharacterName and (not self.filterFunc or self.filterFunc(m)) then
      m = addonTable.Messages:GetMessageProcessed(index)
      table.insert(messages, m)
    end
    index = index + 1
  end

  if #messages > 0 then
    local start = math.min(#messages, self.scrollIndex)
    while #self.visibleLines > 0 and #self.visibleLines >= lines - math.min(lines, #messages) do
      local fs = table.remove(self.visibleLines)
      if fs.timestamp then
        self.pool:Release(fs.timestamp)
        fs.timestamp = nil
      end
      if fs.bar then
        self.barPool:Release(fs.bar)
        fs.bar = nil
      end
      self.msgPool:Release(fs) -- message frame is a SimpleHTML now
    end
    for i = start + math.min(#messages, lines) - 1, start, -1 do
      local m = messages[i]
      if m then
        -- Message line is a SimpleHTML from self.msgPool; ApplyHTMLFont mirrors ApplyTextScale.
        local fs = self.msgPool:Acquire()
        -- SimpleHTML wraps at its explicit width, not an anchor-derived one -- anchor LEFT+BOTTOM
        -- for position and SetWidth to the same inner width the measure uses, so wrap and measured
        -- height agree.
        local innerWidth = math.max(1, self:GetWidth() - (addonTable.Messages.inset + 3) - 1)
        fs:SetPoint("LEFT", self, addonTable.Messages.inset + 3, 0)
        fs:SetPoint("BOTTOM", self, 0, 2)
        fs:SetWidth(innerWidth)
        fs:SetText(m.text)
        -- SimpleHTML applies font/color/justify only if set AFTER SetText.
        ApplyHTMLFont(fs, addonTable.Messages.font, addonTable.Messages.scalingFactor)
        fs:SetTextColor(m.color.r, m.color.g, m.color.b)
        fs:SetJustifyH("LEFT")
        -- SimpleHTML exposes no GetStringHeight on 3.3.5, but the frame needs an explicit height so
        -- its TOP edge is defined for the next line's BOTTOM->TOP anchor. Measure the wrapped height
        -- with a companion FontString at the same font and inner width.
        local measure = self.pool:Acquire()
        measure:SetFontObject(addonTable.Messages.font)
        ApplyTextScale(measure, addonTable.Messages.scalingFactor)
        measure:SetNonSpaceWrap(true)
        measure:SetWidth(innerWidth) -- same width as the SimpleHTML so measured height matches the rendered wrap
        measure:SetText(m.text)
        local stringHeight = measure:GetStringHeight()
        self.pool:Release(measure)
        -- Fall back to one line height if the measure returns nil/0, so a failed measure degrades
        -- to single-line spacing instead of collapsing to height 0 (which drops the TOP anchor).
        fs:SetHeight((stringHeight and stringHeight > 0) and stringHeight or lineHeight)
        fs:SetAlpha(1)
        fs.animationTime = nil
        fs.animationStart = nil
        fs.animationFinalTime = nil
        fs.animationDestination = nil
        fs.animationFinalAlpha = nil
        fs:Show()
        if self.visibleLines[1] then
          self.visibleLines[1]:SetPoint("BOTTOM", fs, "TOP", 0, addonTable.Messages.spacing)
        end
        local timestamp = self.pool:Acquire()
        timestamp:SetFontObject(addonTable.Messages.font)
        timestamp:SetTextColor(0.6, 0.6, 0.6)
        timestamp:SetJustifyH("LEFT")
        timestamp:SetPoint("LEFT")
        timestamp:SetPoint("TOP", fs)
        ApplyTextScale(timestamp, addonTable.Messages.scalingFactor) -- no SetTextScale on 3.3.5; scale in-place
        timestamp:Show()
        timestamp:SetText(date(addonTable.Messages.timestampFormat, m.timestamp))
        timestamp:SetAlpha(1)
        fs.timestampValue = m.timestamp
        fs.timestamp = timestamp
        if addonTable.Config.Get(addonTable.Config.Options.SHOW_TIMESTAMP_SEPARATOR) then
          local bar = self.barPool:Acquire()
          bar:Show()
          bar:SetTexture("Interface\\AddOns\\Chattynator\\Assets\\Fade.tga") -- 3.3.5 loads only TGA/BLP, not PNG
          bar:SetPoint("RIGHT", fs, "LEFT", -4, 0)
          bar:SetPoint("TOP", fs)
          bar:SetPoint("BOTTOM", fs, 0, 1)
          bar:SetWidth(2)
          bar:SetAlpha(1)
          fs.bar = bar
        end
        table.insert(self.visibleLines, 1, fs)
      end
    end

    -- Wrapped lines have variable height, so the single-line `lines` count over-fills and spills
    -- out the top (no SetClipsChildren on 3.3.5). Walk newest->oldest summing actual heights and
    -- release every oldest line past the budget. Releasing from the oldest end never dangles an
    -- anchor since older lines anchor down to newer ones. Keep >= 1 line.
    local budget = self:GetHeight() - 2 -- 2 = the bottom inset the newest line is anchored at
    local used, keep = 0, #self.visibleLines
    for idx = 1, #self.visibleLines do
      local h = self.visibleLines[idx]:GetHeight()
      if idx > 1 and used + h > budget then
        keep = idx - 1
        break
      end
      used = used + h + (addonTable.Messages.spacing or 0)
    end
    while #self.visibleLines > keep do
      local old = table.remove(self.visibleLines)
      if old.timestamp then
        self.pool:Release(old.timestamp)
        old.timestamp = nil
      end
      if old.bar then
        self.barPool:Release(old.bar)
        old.bar = nil
      end
      self.msgPool:Release(old)
    end

    self:UpdateAlphas()
  end
end
