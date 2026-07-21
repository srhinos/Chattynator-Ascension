---@class addonTableChattynator
local addonTable = select(2, ...)

addonTable.CustomiseDialog.Components = {}

-- 3.3.5: the retail Settings/Menu widget templates (SettingsCheckboxTemplate,
-- WowStyle1DropdownTemplate, MinimalSliderWithSteppersTemplate, PanelTopTabButtonTemplate)
-- don't exist here. These factories rebuild them on stock FrameXML templates while
-- keeping the public contract callers use (SetValue/GetValue, frame.DropDown, holder.Slider).
-- Menu descriptors run through the Widgets compat builder + scroll renderer.

-- OptionsSliderTemplate/UIDropDownMenuTemplate auto-create named child regions
-- (_G[name.."Text"] etc.), so each instance needs a stable unique name.
local widgetCount = 0
local function uniqueName(prefix)
  widgetCount = widgetCount + 1
  return "Chattynator335CD" .. prefix .. widgetCount
end

function addonTable.CustomiseDialog.Components.GetCheckbox(parent, label, spacing, callback)
  spacing = spacing or 0
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetHeight(40)
  holder:SetPoint("LEFT", parent, "LEFT", 30, 0)
  holder:SetPoint("RIGHT", parent, "RIGHT", -15, 0)
  -- 3.3.5: SettingsCheckboxTemplate -> stock UICheckButtonTemplate.
  local checkBox = CreateFrame("CheckButton", nil, holder, "UICheckButtonTemplate")

  checkBox:SetPoint("LEFT", holder, "CENTER", -15 - spacing, 0)

  -- Own the label FontString; the template's built-in $parentText is unreliable here.
  local text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("RIGHT", holder, "CENTER", -30 - spacing, 0)
  text:SetText(label)
  checkBox.labelText = text
  if checkBox.SetFontString then
    checkBox:SetFontString(text) -- so GetFontString() (skin code) still resolves
  end

  addonTable.Skins.AddFrame("CheckBox", checkBox)

  function holder:SetValue(value)
    checkBox:SetChecked(value)
  end

  function holder:GetValue()
    return checkBox:GetChecked()
  end

  -- SettingsCheckbox OnEnter/OnLeave tooltip -> GameTooltip.
  holder:SetScript("OnEnter", function()
    if GameTooltip and label then
      GameTooltip:SetOwner(checkBox, "ANCHOR_RIGHT")
      GameTooltip:SetText(label)
      GameTooltip:Show()
    end
  end)

  holder:SetScript("OnLeave", function()
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)

  holder:SetScript("OnMouseUp", function()
    checkBox:Click()
  end)

  checkBox:SetScript("OnClick", function()
    callback(checkBox:GetChecked())
  end)

  return holder
end

function addonTable.CustomiseDialog.Components.GetHeader(parent, text)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetPoint("LEFT", 30, 0)
  holder:SetPoint("RIGHT", -30, 0)
  holder.text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  holder.text:SetText(text)
  holder.text:SetPoint("LEFT", 20, -1)
  holder.text:SetPoint("RIGHT", 20, -1)
  holder:SetHeight(40)
  return holder
end

function addonTable.CustomiseDialog.Components.GetTab(parent, text)
  -- 3.3.5: retail PanelTopTabButtonTemplate is gone; use stock CharacterFrameTabButtonTemplate.
  -- The tab needs a name -- PanelTemplates_TabResize indexes _G[name.."Left"] and would
  -- crash concatenating nil on a nameless tab.
  local tab = CreateFrame("Button", uniqueName("Tab"), parent, "CharacterFrameTabButtonTemplate")
  tab:SetScript("OnShow", function(self)
    PanelTemplates_TabResize(self, 0, nil, nil, nil, self:GetFontString():GetStringWidth())
    PanelTemplates_DeselectTab(self)
  end)
  tab:SetText(text)
  tab:GetScript("OnShow")(tab)
  addonTable.Skins.AddFrame("TopTabButton", tab)
  return tab
end

function addonTable.CustomiseDialog.Components.GetBasicDropdown(parent, labelText, isSelectedCallback, onSelectionCallback)
  local frame = CreateFrame("Frame", nil, parent)
  -- 3.3.5: WowStyle1DropdownTemplate/DropdownButton -> stock UIDropDownMenuTemplate frame.
  -- The popup is rendered by the Widgets compat menu; the native dropdown list is unused.
  local ddName = uniqueName("Dropdown")
  local dropdown = CreateFrame("Frame", ddName, frame, "UIDropDownMenuTemplate")
  dropdown:SetWidth(200)
  dropdown:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
  if UIDropDownMenu_SetWidth then
    UIDropDownMenu_SetWidth(dropdown, 200)
  end
  if UIDropDownMenu_JustifyText then
    UIDropDownMenu_JustifyText(dropdown, "LEFT")
  end

  local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("LEFT", frame, "LEFT", 10, 0)
  label:SetPoint("RIGHT", dropdown, "LEFT", -10, 0)
  label:SetJustifyH("LEFT")
  label:SetText(labelText)
  frame:SetPoint("LEFT", 30, 0)
  frame:SetPoint("RIGHT", -30, 0)

  -- Menu state: the generator closure (SetupMenu) + the default text.
  local generator
  local defaultText = ""

  -- Set the selected-value text shown in the dropdown box. Prefers the currently
  -- selected radio's label; else the default text.
  local function refreshText(rootDescription)
    -- Radios show the selected label; multi-select checkboxes summarise the checked
    -- labels (each already carries its own colour code); else the default text.
    local selected
    local checked = {}
    if rootDescription then
      for _, e in ipairs(rootDescription.entries) do
        if e.kind == "radio" and e.isSelected and e.isSelected() then
          selected = e.text
          break
        elseif e.kind == "checkbox" and e.isSelected and e.isSelected() then
          checked[#checked + 1] = e.text
        end
      end
    end
    local shown
    if selected then
      shown = selected
    elseif #checked > 0 then
      -- Cap absurd lengths: show the first few, then "+K" for the remainder.
      local maxShown = 3
      if #checked <= maxShown then
        shown = table.concat(checked, ", ")
      else
        local head = {}
        for i = 1, maxShown do
          head[i] = checked[i]
        end
        shown = table.concat(head, ", ") .. " +" .. (#checked - maxShown)
      end
    else
      shown = defaultText
    end
    if UIDropDownMenu_SetText then
      UIDropDownMenu_SetText(dropdown, shown)
    end
    local ddText = _G[ddName .. "Text"]
    local ddBtn = _G[ddName .. "Button"]
    if ddText then
      ddText:ClearAllPoints()
      if ddBtn then
        ddText:SetPoint("LEFT", dropdown, "LEFT", 25, 0)
        ddText:SetPoint("RIGHT", ddBtn, "LEFT", -4, 0)
      else
        ddText:SetPoint("LEFT", dropdown, "LEFT", 25, 0)
        ddText:SetPoint("RIGHT", dropdown, "RIGHT", -25, 0)
      end
      ddText:SetJustifyH("LEFT")
    end
  end

  -- Run the generator to build a fresh rootDescription, then refresh the box text.
  local function build()
    local rootDescription = addonTable.Widgets.CreateRootDescription("root")
    if generator then
      generator(dropdown, rootDescription)
    end
    dropdown._rootDescription = rootDescription
    refreshText(rootDescription)
    return rootDescription
  end

  -- Install the generator; retail passes cb(menu, rootDescription). It runs lazily on
  -- GenerateMenu/OpenMenu, not here -- some generators have side effects.
  function dropdown:SetupMenu(cb)
    generator = cb
  end

  function dropdown:GenerateMenu()
    build()
  end

  function dropdown:SetDefaultText(text)
    defaultText = text or ""
    refreshText(dropdown._rootDescription)
  end

  -- Show/hide the popup. Filtering re-opens the addon menu via Close+Open to refresh it.
  function dropdown:OpenMenu()
    local rootDescription = build()
    addonTable.Widgets.ShowDropdownMenu(dropdown, rootDescription)
  end

  function dropdown:CloseMenu()
    addonTable.Widgets.CloseDropdownMenu(dropdown)
  end

  -- Click anywhere on the box (or its template button) toggles the popup.
  dropdown:EnableMouse(true)
  dropdown:SetScript("OnMouseDown", function()
    dropdown:OpenMenu()
  end)
  local ddButton = _G[ddName .. "Button"]
  if ddButton and ddButton.SetScript then
    ddButton:SetScript("OnClick", function()
      dropdown:OpenMenu()
    end)
  end

  -- Static radio list (was MenuUtil.CreateRadioMenu): wires label/value pairs to the
  -- isSelected/onSelection callbacks passed to GetBasicDropdown.
  frame.Init = function(_, entryLabels, values)
    dropdown:SetupMenu(function(_, rootDescription)
      for index = 1, #entryLabels do
        local value = values[index]
        rootDescription:CreateRadio(entryLabels[index],
          function() return isSelectedCallback and isSelectedCallback(value) end,
          function()
            if onSelectionCallback then
              onSelectionCallback(value)
            end
            dropdown:GenerateMenu()
          end)
      end
    end)
  end

  -- Re-run the generator so the box text reflects the current selection (called from
  -- container OnShow handlers). Callers may nil this out.
  frame.SetValue = function()
    dropdown:GenerateMenu()
  end
  frame.Label = label
  frame.DropDown = dropdown
  frame:SetHeight(40)
  addonTable.Skins.AddFrame("Dropdown", frame.DropDown)

  return frame
end

function addonTable.CustomiseDialog.Components.GetSlider(parent, label, min, max, valuePattern, callback)
  valuePattern = valuePattern or "%s"
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetHeight(40)
  holder:SetPoint("LEFT", parent, "LEFT", 30, 0)
  holder:SetPoint("RIGHT", parent, "RIGHT", -30, 0)

  holder.Label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  holder.Label:SetJustifyH("RIGHT")
  holder.Label:SetPoint("LEFT", 20, 0)
  holder.Label:SetPoint("RIGHT", holder, "CENTER", -50, 0)
  holder.Label:SetText(label)

  -- 3.3.5: MinimalSliderWithSteppersTemplate -> stock OptionsSliderTemplate. It auto-creates
  -- _G[name.."Low/High/Text"] FontStrings and drives via SetMinMaxValues/SetValueStep/OnValueChanged.
  local sliderName = uniqueName("Slider")
  holder.Slider = CreateFrame("Slider", sliderName, holder, "OptionsSliderTemplate")
  holder.Slider:SetPoint("LEFT", holder, "CENTER", -32, 0)
  holder.Slider:SetPoint("RIGHT", -45, 0)
  holder.Slider:SetHeight(20)
  holder.Slider:SetMinMaxValues(min, max)
  holder.Slider:SetValueStep(1)
  local isInitializing = true
  holder.Slider:SetValue(min)

  -- The auto-created label FontStrings: Low/High blank, Text = the value readout.
  local lowFS, highFS = _G[sliderName .. "Low"], _G[sliderName .. "High"]
  local textFS = _G[sliderName .. "Text"]
  if lowFS then lowFS:SetText("") end
  if highFS then highFS:SetText("") end

  local function updateText(value)
    if type(value) ~= "number" or not textFS then
      return
    end
    textFS:SetText(WHITE_FONT_COLOR:WrapTextInColorCode(valuePattern:format(math.floor(value + 0.5))))
  end
  updateText(min)

  holder.Slider:SetScript("OnValueChanged", function(_, value)
    updateText(value)
    if not isInitializing then
      callback(value)
    end
  end)

  isInitializing = false

  function holder:GetValue()
    return holder.Slider:GetValue()
  end

  function holder:SetValue(value)
    isInitializing = true
    holder.Slider:SetValue(value)
    updateText(value)
    isInitializing = false
  end

  addonTable.Skins.AddFrame("Slider", holder.Slider)

  holder:SetScript("OnMouseWheel", function(_, delta)
    if not holder.Slider.IsEnabled or holder.Slider:IsEnabled() then
      holder.Slider:SetValue(holder.Slider:GetValue() + delta)
    end
  end)

  return holder
end
