-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 OmniNull — https://github.com/OmniNull/OmniWM

local keyboardMode = {}

function keyboardMode.chip(style: BarStyle, size: number)
    local mode = style.keyboardMode
    if mode == "normal" then
        return nil
    end
    local tint = if mode == "paused" then "warning" else "success"
    local label, help
    if mode == "paused" then
        label, help = omniwm.l10n("Paused"), omniwm.l10n("OmniWM shortcuts are paused.")
    elseif mode == "prefix" then
        label, help = omniwm.l10n("Prefix"), omniwm.l10n("Prefix: the next key runs an OmniWM command. Escape cancels.")
    else
        label = omniwm.l10n("Window Mode")
        help = omniwm.l10n("Window mode: keys run OmniWM commands until you press Escape.")
    end
    local glyph = math.floor(size * 0.55)
    return ui.row{ h = size, pad = math.floor(size * 0.25), gap = 4, center = true, radius = size / 2,
        fill = tint .. "/0.18", help = help,
        ui.symbol{ name = if mode == "paused" then "pause.fill" else "keyboard", size = glyph, color = tint },
        if style.vertical then nil
            else ui.text{ text = label, size = math.floor(size * 0.5), weight = "semibold", color = tint } }
end

function keyboardMode.wrap(style: BarStyle, button: Element, size: number): Element
    local chip = keyboardMode.chip(style, size)
    if chip == nil then
        return button
    end
    return if style.vertical then ui.column{ gap = 4, center = true, button, chip }
        else ui.row{ gap = 4, center = true, button, chip }
end

return keyboardMode
