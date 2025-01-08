-- areas_pvp/init.lua
-- Allow or disallow PvP in areas
-- Copyright (C) 2025 1F616EMO
-- SPDX-License-Identifier: LGPL-3.0-or-later

if not core.settings:get_bool("enable_pvp", true) then
    core.log("warning", "[areas_pvp] enable_pvp = false, not loading.")
    return
end

local S = core.get_translator("areas_pvp")
local NS = function(s) return s end

local pvp_default = core.settings:get_bool("areas_pvp.pvp_default", false)
if pvp_default == false then pvp_default = nil end

local hud_type_name = core.features.hud_def_type_field and "type" or "hud_elem_type"
local hud_text = S("You're in peaceful area")
local hud_color = 0x00FF00
local target_protected_msg_key = NS("@1 is in a peaceful area!")
local hitter_protected_msg = S("You're in a peaceful area!")
if not pvp_default then -- Disabled outside
    hud_text = S("You're in PvP area")
    hud_color = 0xF00000
    target_protected_msg_key = NS("@1 isn't in a PvP-enabled area!")
    hitter_protected_msg = S("You're not in a PvP-enabled area!")
end

local players_in_pvp_area = {}
local player_huds = {}
modlib.minetest.register_globalstep(0.5, function()
    for k in pairs(players_in_pvp_area) do
        players_in_pvp_area[k] = nil
    end

    for _, player in ipairs(core.get_connected_players()) do
        local name = player:get_player_name()
        local pos = vector.round(player:get_pos())

        for _, area in pairs(areas:getAreasAtPos(pos)) do
            if area.areas_pvp then
                players_in_pvp_area[name] = true
                break
            end
        end

        -- We're not using areas:registerHudHandler
        -- as it takes a position instead of a player (yuck!)
        if players_in_pvp_area[name] then
            if not player_huds[name] then
                player_huds[name] = player:hud_add({
                    [hud_type_name] = "text",
                    position = { x = 1, y = 0.2 },
                    alignment = { x = -1, y = 1 },
                    offset = { x = -6, y = 0 },
                    text = hud_text,
                    number = hud_color,
                })
            end
        elseif player_huds[name] then
            player:hud_remove(player_huds[name])
            player_huds[name] = nil
        end
    end
end)

-- Player in PvP Area + Defaults => Outcome
--[[
(false => nil)
In Area | Default | Allow?
  true  |  true   | false
  false |  false  | false
  true  |  false  | true
  false |  true   | true
]]

core.register_on_punchplayer(function(player, hitter)
    if not (hitter and hitter:is_player()) then return end

    local player_name = player:get_player_name()
    local hitter_name = hitter:get_player_name()

    -- Don't prevent "self-harming"
    if player_name == hitter_name then return end

    if players_in_pvp_area[player_name] == pvp_default then
        core.chat_send_player(hitter_name,
            S(target_protected_msg_key, player_name))
        return true
    elseif players_in_pvp_area[hitter_name] == pvp_default then
        core.chat_send_player(hitter_name,
            hitter_protected_msg)
        return true
    end
end)

core.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    players_in_pvp_area[name] = nil
    player_huds[name] = nil
end)

local toggle_privs = core.settings:get("areas_pvp.toggle_priv")
if not toggle_privs then toggle_privs = "areas" end
toggle_privs = core.string_to_privs(toggle_privs)

local allow_self_toggle = core.settings:get_bool("areas_pvp.self_toggle", false)

core.register_chatcommand("areas_pvp", {
    description = S("Toggle PvP for an area"),
    params = S("<area id>"),
    func = function(name, param)
        local area_id = tonumber(param)
        local area = areas.areas[area_id]
        if not area then
            return false
        end

        if not allow_self_toggle or name ~= area.owner then
            local success, missing_privs = core.check_player_privs(name, toggle_privs)
            if not success then
                return false, S(name == area.owner
                    and NS("You're not allowed to toggle PvP on your areas (missing privileges: @1)")
                    or NS("You're not allowed to toggle PvP on other's areas (missing privileges: @1)"),
                        table.concat(missing_privs, ", "))
            end
        end

        area.areas_pvp = not area.areas_pvp or nil -- luacheck: ignore
        areas:save()

        return true, S("Successfully @1 PvP on area @2.",
            area.areas_pvp and S("enabled") or S("disabled"), area_id)
    end,
})
