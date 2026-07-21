---@class addonTableChattynator
local addonTable = select(2, ...)

local playerPattern = "(|Hplayer:[^|]+|h%[?)([^|%[%]][^c%[%]][^%[%]]-)(%]?|h)"
-- 3.3.5: grey fallback for a custom-class token missing from both color tables (else nil-index crash).
local GREY_CLASS_COLOR = { r = 0.62, g = 0.62, b = 0.62 }
local function Color(data)
  if data.typeInfo.player and data.typeInfo.player.class then
    local token = data.typeInfo.player.class
    -- classFile token keys CUSTOM_CLASS_COLORS -> RAID_CLASS_COLORS -> grey; this runs
    -- unwrapped on the per-message path, so a nil color would crash.
    local color = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[token])
      or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[token])
      or GREY_CLASS_COLOR
    -- 3.3.5: format the hex directly; ColorMixin/CreateColor is unreliable and the color
    -- tables carry no mixin methods.
    local hex = ("|cff%02x%02x%02x"):format(color.r * 255, color.g * 255, color.b * 255)
    data.text = data.text:gsub(playerPattern, "%1" .. hex .. "%2|r%3")
  end
end

local function StripColor(data)
  if not data.typeInfo.player then
    return
  end
  data.text = data.text:gsub("(|Hplayer:.-|h[^|]-)|c[fF][fF]%x%x%x%x%x%x(.-)|r([^|]-|h)", "%1%2%3")
end

function addonTable.Modifiers.InitializeClassColors()
  if addonTable.Config.Get(addonTable.Config.Options.CLASS_COLORS) then
    addonTable.Messages:AddLiveModifier(Color)
  else
    addonTable.Messages:AddLiveModifier(StripColor)
  end
  addonTable.CallbackRegistry:RegisterCallback("SettingChanged", function(_, settingName)
    if settingName == addonTable.Config.Options.CLASS_COLORS then
      if addonTable.Config.Get(addonTable.Config.Options.CLASS_COLORS) then
        addonTable.Messages:AddLiveModifier(Color)
        addonTable.Messages:RemoveLiveModifier(StripColor)
      else
        addonTable.Messages:RemoveLiveModifier(Color)
        addonTable.Messages:AddLiveModifier(StripColor)
      end
    end
  end)
end
