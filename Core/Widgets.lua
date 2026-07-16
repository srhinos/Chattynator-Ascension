--[[--------------------------------------------------------------------------
  Chattynator/Core/Widgets.lua -- 3.3.5a (Project Ascension) widget rebuilds.

  Loaded second in the TOC (after Core/Compat.lua). Reimplements the retail-only
  widget machinery Chattynator reaches at runtime, on stock 3.3.5 FrameXML:

    - MenuUtil.CreateContextMenu / CreateRadioMenu + a rootDescription builder
      that lowers to the stock UIDropDownMenu / EasyMenu.
    - Menu.GetManager():IsAnyMenuOpen / Menu.GetOpenMenuTags.
    - ColorPickerFrame:SetupColorPickerAndShow(info) mapped to the era contract.
    - a ButtonFrame builder (HidePortrait / HideButtonBar / SetTitle / .Inset).
    - a ScrollingEditBox wrapper over a ScrollFrame + multiline EditBox.

  Fill only absent globals; never clobber a client one. MenuUtil and Menu are
  absent, so per-key fill; ButtonFrame draws its own backdrop textures rather than
  using Ascension's broken backported SetBackdrop.
----------------------------------------------------------------------------]]

local _addonName, addonTable = ...
addonTable = addonTable or {}
addonTable.Widgets = addonTable.Widgets or {}
local widgets = addonTable.Widgets

local _G = _G
local rawget, rawset = rawget, rawset
local type, ipairs = type, ipairs

local CreateFrame = rawget(_G, "CreateFrame")
local UIParent = rawget(_G, "UIParent")

-- Set a namespace member only if absent.
local function fillMember(tbl, name, value)
  if rawget(tbl, name) == nil then
    rawset(tbl, name, value)
  end
end

--==============================================================================
-- rootDescription (MenuElementDescription) builder.
-- Root and every element are the same self-similar description type, so submenus
-- come for free. Pure data; lowered to a UIDropDownMenu list at show time.
--==============================================================================
local menuDescriptionMethods = {}
local menuDescriptionMeta = { __index = menuDescriptionMethods }

local function newMenuDescription(kind, text)
  return setmetatable({
    kind = kind or "root",
    text = text,
    entries = {},        -- child descriptions
    initializers = {},   -- AddInitializer callbacks
  }, menuDescriptionMeta)
end

local function addChild(self, child)
  self.entries[#self.entries + 1] = child
  return child
end

function menuDescriptionMethods:CreateButton(text, onClick, data)
  local e = newMenuDescription("button", text)
  e.onClick, e.data = onClick, data
  return addChild(self, e)
end

function menuDescriptionMethods:CreateTitle(text)
  return addChild(self, newMenuDescription("title", text))
end

function menuDescriptionMethods:CreateDivider()
  return addChild(self, newMenuDescription("divider"))
end

function menuDescriptionMethods:CreateCheckbox(text, isSelected, onClick, data)
  local e = newMenuDescription("checkbox", text)
  e.isSelected, e.onClick, e.data = isSelected, onClick, data
  return addChild(self, e)
end

function menuDescriptionMethods:CreateRadio(text, isSelected, onClick, data)
  local e = newMenuDescription("radio", text)
  e.isSelected, e.onClick, e.data = isSelected, onClick, data
  return addChild(self, e)
end

function menuDescriptionMethods:CreateColorSwatch(text, onClick, colorInfo)
  local e = newMenuDescription("colorswatch", text)
  e.onClick, e.colorInfo = onClick, colorInfo
  return addChild(self, e)
end

-- Mark this menu scrollable and cap its pixel height. Stock UIDropDownMenu has no
-- native scroll; ShowDropdownMenu reads these fields and pages rows via a
-- FauxScrollFrame (needed for the font and addon lists).
function menuDescriptionMethods:SetScrollMode(maxHeight)
  self.scrollMode = true
  self.maxScrollHeight = maxHeight
end

-- Per-element affordances.
function menuDescriptionMethods:SetTooltip(tooltipFunc)
  self.tooltipFunc = tooltipFunc
  return self
end
function menuDescriptionMethods:AddInitializer(initializer)
  self.initializers[#self.initializers + 1] = initializer
  return self
end
function menuDescriptionMethods:SetFinalInitializer(initializer)
  self.finalInitializer = initializer
  return self
end
function menuDescriptionMethods:GetText()
  return self.text
end
function menuDescriptionMethods:SetTitle(text)
  self.text = text
  return self
end

-- Shared with GetBasicDropdown's SetupMenu closures so the whole menu system
-- builds one rootDescription type.
widgets.CreateRootDescription = newMenuDescription

--==============================================================================
-- Lower a description tree to a stock UIDropDownMenu / EasyMenu list.
--==============================================================================
local function lowerToDropDownList(desc)
  local list = {}
  for _, e in ipairs(desc.entries) do
    local info
    if e.kind == "divider" then
      info = { text = "", notCheckable = true, disabled = true, notClickable = true }
    elseif e.kind == "title" then
      info = { text = e.text, isTitle = true, notCheckable = true }
    else
      info = { text = e.text, notCheckable = true }
      if e.kind == "checkbox" or e.kind == "radio" then
        info.notCheckable = false
        info.isNotRadio = (e.kind == "checkbox")
        info.keepShownOnClick = (e.kind == "checkbox")
        if e.isSelected then
          info.checked = function() return e.isSelected() and true or false end
        end
      end
      if e.kind == "colorswatch" then
        info.notCheckable = true
        info.hasColorSwatch = true
        if e.colorInfo then
          info.r, info.g, info.b = e.colorInfo.r, e.colorInfo.g, e.colorInfo.b
          info.hasOpacity = e.colorInfo.hasOpacity
          -- swatchFunc is the live per-change setter (fires while dragging the
          -- wheel); wire the entry's real setters, not the picker opener.
          info.swatchFunc = e.colorInfo.swatchFunc
          info.cancelFunc = e.colorInfo.cancelFunc
          info.opacityFunc = e.colorInfo.opacityFunc
        end
        -- A row-text click opens the ColorPicker.
        info.func = function() if e.onClick then e.onClick(e) end end
      elseif e.onClick then
        -- retail passes (element, menuInputData); synthesise a LeftButton click.
        info.func = function() e.onClick(e, { buttonName = "LeftButton" }) end
      end
      if #e.entries > 0 then
        info.hasArrow = true
        info.menuList = lowerToDropDownList(e)
      end
    end
    list[#list + 1] = info
  end
  return list
end

local contextDropDown

local function showMenu(desc, owner)
  local EasyMenu = rawget(_G, "EasyMenu")
  if not (EasyMenu and CreateFrame) then
    return
  end
  if not contextDropDown then
    contextDropDown = CreateFrame("Frame", "Chattynator335ContextMenu", UIParent, "UIDropDownMenuTemplate")
  end
  local list = lowerToDropDownList(desc)
  EasyMenu(list, contextDropDown, "cursor", 0, 0, "MENU")
end

--==============================================================================
-- MenuUtil (absent on 3.3.5).
--==============================================================================
if rawget(_G, "MenuUtil") == nil then
  rawset(_G, "MenuUtil", {})
end
local MenuUtil = rawget(_G, "MenuUtil")

-- Build a rootDescription, let the caller populate it, then show it.
fillMember(MenuUtil, "CreateContextMenu", function(owner, generatorFn)
  local root = newMenuDescription("root")
  if type(generatorFn) == "function" then
    generatorFn(owner, root)
  end
  showMenu(root, owner)
  return root
end)

-- Lay {label,value} pairs down as radio entries. If the owner is a dropdown
-- widget with SetupMenu, install the generator; else return it for the caller.
fillMember(MenuUtil, "CreateRadioMenu", function(owner, isSelected, onSelect, ...)
  local pairsList = { ... }
  local generator = function(_, root)
    for _, entry in ipairs(pairsList) do
      local value = entry[2]
      root:CreateRadio(entry[1],
        function() return isSelected and isSelected(value) end,
        function() if onSelect then onSelect(value) end end)
    end
  end
  if type(owner) == "table" and type(owner.SetupMenu) == "function" then
    owner:SetupMenu(generator)
  end
  return generator
end)

-- Wire a GameTooltip on hover; no-op when GameTooltip / HookScript are absent.
fillMember(MenuUtil, "HookTooltipScripts", function(frame, tooltipFunc)
  if type(frame) ~= "table" or type(frame.HookScript) ~= "function" or type(tooltipFunc) ~= "function" then
    return
  end
  local GameTooltip = rawget(_G, "GameTooltip")
  if not GameTooltip then
    return
  end
  frame:HookScript("OnEnter", function(self)
    if GameTooltip.SetOwner then GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
    tooltipFunc(GameTooltip)
    if GameTooltip.Show then GameTooltip:Show() end
  end)
  frame:HookScript("OnLeave", function()
    if GameTooltip.Hide then GameTooltip:Hide() end
  end)
end)

--==============================================================================
-- Menu open-state (replaces Menu.GetManager():IsAnyMenuOpen()).
--==============================================================================
if rawget(_G, "Menu") == nil then
  rawset(_G, "Menu", {})
end
local Menu = rawget(_G, "Menu")
do
  local manager = {
    IsAnyMenuOpen = function()
      -- DropDownList1 is the stock UIDropDownMenu list frame; its visibility
      -- reflects any open dropdown, incl. ours.
      local ddl = rawget(_G, "DropDownList1")
      if ddl and ddl.IsShown then
        return ddl:IsShown() and true or false
      end
      return false
    end,
  }
  fillMember(Menu, "GetManager", function() return manager end)
  fillMember(Menu, "GetOpenMenuTags", function() return {} end)
end

--==============================================================================
-- ColorPickerFrame:SetupColorPickerAndShow(info) -- add only the retail entry
-- point, mapping colorInfo to the era ColorPickerFrame contract. GetColorRGB()
-- (read inside the swatch/cancel funcs) is native and stays.
--==============================================================================
do
  local ColorPickerFrame = rawget(_G, "ColorPickerFrame")
  if not ColorPickerFrame and CreateFrame then
    -- defensive only; a real 3.3.5 client always ships it.
    ColorPickerFrame = CreateFrame("Frame", "ColorPickerFrame", UIParent)
  end
  if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow == nil then
    function ColorPickerFrame.SetupColorPickerAndShow(self, info)
      info = info or {}
      -- era contract: .func fires on every color change and reads GetColorRGB().
      self.func       = info.swatchFunc
      self.swatchFunc  = info.swatchFunc
      self.opacityFunc = info.opacityFunc
      self.cancelFunc  = info.cancelFunc
      self.hasOpacity  = info.hasOpacity and true or false
      self.previousValues = { r = info.r, g = info.g, b = info.b, opacity = info.opacity }
      self.extraInfo = info.extraInfo
      if self.SetColorRGB then
        self:SetColorRGB(info.r or 1, info.g or 1, info.b or 1)
      end
      if info.hasOpacity then
        -- Chattynator's swatches never set opacity, so this path is currently inert.
        self.opacity = info.opacity
        local OpacitySliderFrame = rawget(_G, "OpacitySliderFrame")
        if OpacitySliderFrame and OpacitySliderFrame.SetValue and info.opacity then
          OpacitySliderFrame:SetValue(info.opacity)
        end
      end
      local ShowUIPanel = rawget(_G, "ShowUIPanel")
      if ShowUIPanel then
        ShowUIPanel(self)
      elseif self.Show then
        self:Show()
      end
    end
  end
end

--==============================================================================
-- ButtonFrame builder. Draws its own backdrop rather than using Ascension's
-- broken SetBackdrop / NineSlice, and exposes the ButtonFrameTemplate stand-ins
-- callers use: HidePortrait / HideButtonBar / SetTitle / .Inset.
--==============================================================================
-- bg fill + four 1px edges. Edges use two SetPoints for thickness instead of
-- SetHeight/SetWidth (textures lack those on some clients). bg/edge are {r,g,b[,a]};
-- SetTexture(r,g,b,a) is era-native (SetColorTexture is retail-only).
local function drawBackdrop(frame, bg, edge, thickness)
  thickness = thickness or 1
  local background = frame:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints(frame)
  background:SetTexture(bg[1], bg[2], bg[3], bg[4] or 1)

  local edges = {
    -- name          p1a,        p1rel,        p1x,        p1y,          p2a,           p2rel,         p2x,         p2y
    { "TOPLEFT",     "TOPLEFT",     0,          0,            "BOTTOMRIGHT", "TOPRIGHT",    0,          -thickness },   -- top
    { "TOPLEFT",     "BOTTOMLEFT",  0,          thickness,    "BOTTOMRIGHT", "BOTTOMRIGHT", 0,           0 },           -- bottom
    { "TOPLEFT",     "TOPLEFT",     0,          0,            "BOTTOMRIGHT", "BOTTOMLEFT",  thickness,   0 },           -- left
    { "TOPLEFT",     "TOPRIGHT",   -thickness,  0,            "BOTTOMRIGHT", "BOTTOMRIGHT", 0,           0 },           -- right
  }
  for _, e in ipairs(edges) do
    local line = frame:CreateTexture(nil, "BORDER")
    line:SetTexture(edge[1], edge[2], edge[3], edge[4] or 1)
    line:SetPoint(e[1], frame, e[2], e[3], e[4])
    line:SetPoint(e[5], frame, e[6], e[7], e[8])
  end
  return background
end

-- Draw an own bg fill + 1px edges on an existing frame, so skinners/dialogs can
-- route here instead of Ascension's broken SetBackdrop. Pass a 0-alpha bg for a
-- border-only look.
function widgets.ApplyBackdrop(frame, bg, edge, thickness)
  if type(frame) ~= "table" or not frame.CreateTexture then
    return
  end
  return drawBackdrop(frame, bg or { 0, 0, 0, 0 }, edge or { 0, 0, 0, 1 }, thickness)
end

function widgets.CreateButtonFrame(name, parent)
  local frame = CreateFrame("Frame", name, parent or UIParent)
  frame:EnableMouse(true)

  -- dark opaque body + light-grey edge.
  drawBackdrop(frame, { 0.06, 0.06, 0.06, 0.95 }, { 0.35, 0.35, 0.35, 1 }, 1)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", frame, "TOP", 0, -6)

  -- Inset stand-in: inner content frame with its own subtle backdrop.
  local inset = CreateFrame("Frame", name and (name .. "Inset") or nil, frame)
  inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -24)
  inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
  drawBackdrop(inset, { 0.0, 0.0, 0.0, 0.35 }, { 0.25, 0.25, 0.25, 1 }, 1)
  frame.Inset = inset

  -- Close button, for parity with ButtonFrameTemplate.
  if pcall(function()
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.CloseButton = close
  end) then end

  frame.TitleText = title
  function frame:SetTitle(text) title:SetText(text or "") end
  function frame:GetTitleText() return title end
  -- No portrait / button bar drawn, so these are no-ops.
  function frame:HidePortrait() end
  function frame:HideButtonBar() end

  return frame
end

-- CopyChat.lua calls these as bare globals; delegate to the builder frame method.
if rawget(_G, "ButtonFrameTemplate_HidePortrait") == nil then
  rawset(_G, "ButtonFrameTemplate_HidePortrait", function(frame)
    if type(frame) == "table" and frame.HidePortrait then frame:HidePortrait() end
  end)
end
if rawget(_G, "ButtonFrameTemplate_HideButtonBar") == nil then
  rawset(_G, "ButtonFrameTemplate_HideButtonBar", function(frame)
    if type(frame) == "table" and frame.HideButtonBar then frame:HideButtonBar() end
  end)
end

--==============================================================================
-- ScrollingEditBox wrapper: a ScrollFrame + multiline EditBox exposing the retail
-- contract CopyChat.lua uses: GetEditBox / GetScrollBox (with ScrollToEnd) /
-- SetText / SetFontObject / SetFocus.
--==============================================================================
function widgets.CreateScrollingEditBox(name, parent)
  -- UIPanelScrollBarTemplate's scripts reach its up/down buttons via
  -- _G[name.."ScrollUp/DownButton"] and error when the Slider is unnamed;
  -- CopyChat builds this unnamed, so synthesize a unique name.
  if not name then
    widgets._scrollingEditBoxCount = (widgets._scrollingEditBoxCount or 0) + 1
    name = "ChattynatorScrollingEditBox" .. widgets._scrollingEditBoxCount
  end
  local frame = CreateFrame("Frame", name, parent or UIParent)

  local scrollFrame = CreateFrame("ScrollFrame", name .. "ScrollFrame", frame)
  scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 0) -- gutter for the scrollbar

  local editBox = CreateFrame("EditBox", name and (name .. "EditBox") or nil, scrollFrame)
  editBox:SetMultiLine(true)
  editBox:SetAutoFocus(false)
  editBox:EnableMouse(true)
  local defaultFont = rawget(_G, "ChatFontNormal") or rawget(_G, "GameFontHighlight")
  if defaultFont then
    editBox:SetFontObject(defaultFont)
  end
  scrollFrame:SetScrollChild(editBox)

  -- Drive a UIPanelScrollBarTemplate Slider manually rather than switching to
  -- UIPanelScrollFrameTemplate, whose ScrollFrame_OnLoad indexes _G[name.."ScrollBar"]
  -- and errors on this unnamed widget. Tracks the live range via OnScrollRangeChanged;
  -- shown only when content overflows.
  local scrollBar = CreateFrame("Slider", name .. "ScrollBar", scrollFrame, "UIPanelScrollBarTemplate")
  scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 2, -16)
  scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 2, 16)
  scrollBar:SetMinMaxValues(0, 0)
  scrollBar:SetValue(0)
  scrollBar:Hide()
  scrollBar:SetScript("OnValueChanged", function(self, value)
    if scrollFrame.SetVerticalScroll then scrollFrame:SetVerticalScroll(value or self:GetValue() or 0) end
  end)
  frame.ScrollBar = scrollBar

  -- Recomputed range -> resize/show/hide the thumb and finish any pending scroll-to-end.
  scrollFrame:SetScript("OnScrollRangeChanged", function(self, xrange, yrange)
    yrange = yrange or (self.GetVerticalScrollRange and self:GetVerticalScrollRange()) or 0
    scrollBar:SetMinMaxValues(0, yrange)
    local value = scrollBar:GetValue() or 0
    if frame._pendingScrollToEnd and yrange > 0 then
      value = yrange
      frame._pendingScrollToEnd = false
    elseif value > yrange then
      value = yrange
    end
    scrollBar:SetValue(value)
    if yrange > 0 then scrollBar:Show() else scrollBar:Hide() end
  end)

  -- The wheel doesn't fall through the mouse-enabled EditBox to the ScrollFrame,
  -- so handle it on the EditBox and drive the ScrollFrame from there, clamped.
  editBox:EnableMouseWheel(true)
  editBox:SetScript("OnMouseWheel", function(_, delta)
    local range = (scrollFrame.GetVerticalScrollRange and scrollFrame:GetVerticalScrollRange()) or 0
    local new = ((scrollFrame.GetVerticalScroll and scrollFrame:GetVerticalScroll()) or 0) - delta * 24
    if new < 0 then new = 0 elseif new > range then new = range end
    -- route through the scrollbar so the thumb tracks the wheel (its OnValueChanged
    -- applies the scroll); fall back to the frame directly.
    if scrollBar and scrollBar.SetValue then
      scrollBar:SetValue(new)
    elseif scrollFrame.SetVerticalScroll then
      scrollFrame:SetVerticalScroll(new)
    end
  end)

  -- Match the edit box width to the scroll frame so text wraps.
  scrollFrame:SetScript("OnSizeChanged", function(self, width)
    local w = width or (self.GetWidth and self:GetWidth())
    if w and editBox.SetWidth then editBox:SetWidth(w) end
  end)

  -- GetScrollBox() stand-in; CopyChat only calls :ScrollToEnd().
  local scrollBox = {}
  function scrollBox:ScrollToEnd()
    -- The editbox often hasn't laid out yet, so the range is still 0 and an immediate
    -- scroll no-ops; arm a pending flag for OnScrollRangeChanged to finish, or scroll
    -- now if the range is already known.
    frame._pendingScrollToEnd = true
    local range = (scrollFrame.GetVerticalScrollRange and scrollFrame:GetVerticalScrollRange()) or 0
    if range > 0 then
      if scrollBar and scrollBar.SetValue then
        scrollBar:SetValue(range)
      elseif scrollFrame.SetVerticalScroll then
        scrollFrame:SetVerticalScroll(range)
      end
      frame._pendingScrollToEnd = false
    end
  end
  function scrollBox:GetScrollFrame() return scrollFrame end

  frame.ScrollFrame = scrollFrame
  frame.EditBox = editBox
  function frame:GetEditBox() return editBox end
  function frame:GetScrollBox() return scrollBox end
  function frame:SetText(text) editBox:SetText(text or "") end
  function frame:GetText() return (editBox.GetText and editBox:GetText()) or "" end
  function frame:SetFontObject(font)
    editBox:SetFontObject(font)
    frame.fontName = font
  end
  function frame:SetFocus() editBox:SetFocus() end
  function frame:ClearFocus() if editBox.ClearFocus then editBox:ClearFocus() end end
  function frame:HighlightText(...) if editBox.HighlightText then editBox:HighlightText(...) end end

  return frame
end

--==============================================================================
-- Scroll-capable dropdown popup renderer. GetBasicDropdown's popup runs through
-- here, not EasyMenu: a reusable frame with a pool of row Buttons paged by a
-- FauxScrollFrame, so lists scroll when their generator calls SetScrollMode.
-- Rows expose `.fontString` because retail per-entry initializers reference it, so
-- the AddInitializer / SetTooltip closures run unmodified.
--==============================================================================
local MENU_ROW_HEIGHT = 18
local MENU_WIDTH = 260
local dropMenu
local ensureDropMenu, ensureRow, paintRow

local function fauxGlobal(name)
  return rawget(_G, name)
end

function ensureDropMenu()
  if dropMenu then
    return dropMenu
  end
  dropMenu = CreateFrame("Frame", "Chattynator335DropdownMenu", UIParent)
  if dropMenu.SetFrameStrata then
    dropMenu:SetFrameStrata("FULLSCREEN_DIALOG")
  end
  dropMenu:EnableMouse(true)
  drawBackdrop(dropMenu, { 0.05, 0.05, 0.05, 0.95 }, { 0.3, 0.3, 0.3, 1 }, 1)

  -- FauxScrollFrame drives paging: the rows are a fixed pool and the scrollbar
  -- just chooses the visible window.
  local faux = CreateFrame("ScrollFrame", "Chattynator335DropdownMenuFaux", dropMenu, "FauxScrollFrameTemplate")
  faux:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 4, -4)
  faux:SetPoint("BOTTOMRIGHT", dropMenu, "BOTTOMRIGHT", -24, 4)
  faux:SetScript("OnVerticalScroll", function(self, offset)
    local onScroll = fauxGlobal("FauxScrollFrame_OnVerticalScroll")
    if onScroll then
      onScroll(self, offset, MENU_ROW_HEIGHT, widgets.RefreshDropdownMenu)
    end
  end)
  dropMenu.faux = faux
  dropMenu.listAnchor = faux
  dropMenu.rows = {}
  function dropMenu:Close() self:Hide() end
  dropMenu:Hide()
  return dropMenu
end

local function menuRowOnClick(row)
  local e = row._entry
  if not e or e.kind == "title" or e.kind == "divider" then
    return
  end
  if e.onClick then
    e.onClick(e, { buttonName = "LeftButton" })
  end
  if e.kind == "checkbox" then
    -- stay open and refresh the tick marks (idempotent if onClick already rebuilt).
    if dropMenu and dropMenu:IsShown() then
      widgets.RefreshDropdownMenu()
    end
  elseif dropMenu then
    dropMenu:Hide()
  end
end

function ensureRow(index)
  local row = dropMenu.rows[index]
  if row then
    return row
  end
  row = CreateFrame("Button", nil, dropMenu)
  row:SetHeight(MENU_ROW_HEIGHT)
  row:SetPoint("TOPLEFT", dropMenu.listAnchor, "TOPLEFT", 0, -(index - 1) * MENU_ROW_HEIGHT)
  row:SetPoint("TOPRIGHT", dropMenu.listAnchor, "TOPRIGHT", 0, -(index - 1) * MENU_ROW_HEIGHT)

  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(row)
  highlight:SetTexture(1, 1, 1, 0.15)

  row.check = row:CreateTexture(nil, "ARTWORK")
  row.check:SetPoint("LEFT", 4, 0)
  row.check:SetSize(12, 12)

  row.swatch = row:CreateTexture(nil, "OVERLAY")
  row.swatch:SetPoint("RIGHT", -6, 0)
  row.swatch:SetSize(16, 10)
  row.swatch:Hide()

  -- retail per-entry initializers reference button.fontString.
  row.fontString = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.fontString:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
  row.fontString:SetPoint("RIGHT", row.swatch, "LEFT", -4, 0)
  row.fontString:SetJustifyH("LEFT")

  row:SetScript("OnClick", menuRowOnClick)
  row:SetScript("OnEnter", function(self)
    local e = self._entry
    if e and e.tooltipFunc and GameTooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      e.tooltipFunc(GameTooltip)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)

  dropMenu.rows[index] = row
  return row
end

function paintRow(row, e)
  row._entry = e
  row:Show()
  row:Enable()
  row.check:Hide()
  row.swatch:Hide()
  -- Reset children a prior initializer attached to this pooled row (e.g. the
  -- profile-delete button): hide them and drop stale OnClick so a reused row never
  -- shows a ghost affordance. A current-entry initializer re-shows/re-wires its own.
  if row._initChildren then
    for _, child in ipairs(row._initChildren) do
      if child.SetScript then child:SetScript("OnClick", nil) end
      if child.Hide then child:Hide() end
    end
  end
  if row.fontString.SetFontObject then
    row.fontString:SetFontObject("GameFontHighlight") -- reset before an initializer overrides
  end

  if e.kind == "title" then
    row.fontString:SetText(e.text or "")
    if row.fontString.SetFontObject then row.fontString:SetFontObject("GameFontNormalSmall") end
    row:Disable()
  elseif e.kind == "divider" then
    row.fontString:SetText("")
    row:Disable()
  else
    row.fontString:SetText(e.text or "")
    if (e.kind == "checkbox" or e.kind == "radio") and e.isSelected and e.isSelected() then
      row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
      row.check:Show()
    end
    if e.kind == "colorswatch" and e.colorInfo then
      row.swatch:SetTexture(e.colorInfo.r or 1, e.colorInfo.g or 1, e.colorInfo.b or 1, 1)
      row.swatch:Show()
    end
  end

  -- per-entry initializers (font preview, profile-delete affordance) + final one.
  for _, init in ipairs(e.initializers) do
    init(row, e, dropMenu)
  end
  if e.finalInitializer then
    e.finalInitializer(row, e, dropMenu)
  end
end

-- Repaint the visible row window from the current list + scroll offset.
function widgets.RefreshDropdownMenu()
  local menu = dropMenu
  if not (menu and menu._list) then
    return
  end
  local list = menu._list
  local total = #list
  local shown = menu._numVisible or total
  local offset = 0
  if menu._scroll then
    local getOffset = fauxGlobal("FauxScrollFrame_GetOffset")
    if getOffset then
      offset = getOffset(menu.faux) or 0
    end
  end
  for i = 1, shown do
    local row = ensureRow(i)
    local e = list[i + offset]
    if e then
      paintRow(row, e)
    else
      row._entry = nil
      row:Hide()
    end
  end
  for i = shown + 1, #menu.rows do
    menu.rows[i]:Hide()
  end
  local update = fauxGlobal("FauxScrollFrame_Update")
  if update then
    update(menu.faux, total, shown, MENU_ROW_HEIGHT)
  end
end

-- Show the dropdown popup for `rootDescription` anchored under `owner`. Clicking
-- the owner again while its menu is open toggles it shut.
function widgets.ShowDropdownMenu(owner, rootDescription)
  if not CreateFrame then
    return
  end
  local menu = ensureDropMenu()
  if menu:IsShown() and menu._owner == owner then
    menu:Hide()
    return
  end
  menu._owner = owner

  local list = {}
  for _, e in ipairs(rootDescription.entries) do
    list[#list + 1] = e
  end
  menu._list = list
  menu._scroll = rootDescription.scrollMode and true or false

  local total = #list
  -- scroll mode: cap the visible window and page the rest; else show every entry.
  local maxRows = total
  if menu._scroll and rootDescription.maxScrollHeight then
    maxRows = math.max(1, math.floor(rootDescription.maxScrollHeight / MENU_ROW_HEIGHT))
  end
  menu._numVisible = math.max(1, math.min(total == 0 and 1 or total, maxRows))

  menu:SetHeight(menu._numVisible * MENU_ROW_HEIGHT + 8)
  local width = MENU_WIDTH
  if owner and owner.GetWidth then
    local w = owner:GetWidth()
    if w and w > 40 then width = w end
  end
  menu:SetWidth(width)

  menu:ClearAllPoints()
  if owner and owner.GetName and owner:GetName() then
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
  else
    menu:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end

  local setOffset = fauxGlobal("FauxScrollFrame_SetOffset")
  if setOffset then
    setOffset(menu.faux, 0)
  end

  menu:Show()
  widgets.RefreshDropdownMenu()
end

function widgets.CloseDropdownMenu(owner)
  if dropMenu and dropMenu:IsShown() and (owner == nil or dropMenu._owner == owner) then
    dropMenu:Hide()
  end
end

--==============================================================================
-- MenuTemplates + GameTooltip_SetTitle stand-ins (absent on 3.3.5), used by the
-- profile menu's per-entry delete affordance. AttachAutoHideButton returns a
-- Button with a `.Texture` whose SetAtlas is a no-op (3.3.5 has no atlases).
--==============================================================================
if rawget(_G, "MenuTemplates") == nil then
  rawset(_G, "MenuTemplates", {})
end
fillMember(rawget(_G, "MenuTemplates"), "AttachAutoHideButton", function(parent, atlas)
  -- Cache one button per (parent, atlas): paintRow re-runs every initializer on each
  -- repaint of a pooled row, so creating a fresh button here would stack duplicates
  -- and leak a stale-OnClick button onto a row reused by another dropdown. Registering
  -- on parent._initChildren lets paintRow hide/neutralise it before each repaint.
  parent._autoHideButtons = parent._autoHideButtons or {}
  local key = atlas or "default"
  local button = parent._autoHideButtons[key]
  if not button then
    button = CreateFrame("Button", nil, parent)
    local texture = button:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(button)
    if texture.SetAtlas == nil then
      texture.SetAtlas = function() end -- 3.3.5 has no atlases
    end
    button.Texture = texture
    parent._autoHideButtons[key] = button
    parent._initChildren = parent._initChildren or {}
    parent._initChildren[#parent._initChildren + 1] = button
  end
  button:Show()
  return button
end)

if rawget(_G, "GameTooltip_SetTitle") == nil then
  rawset(_G, "GameTooltip_SetTitle", function(tooltip, text)
    if tooltip and tooltip.SetText then
      tooltip:SetText(text)
    end
  end)
end
