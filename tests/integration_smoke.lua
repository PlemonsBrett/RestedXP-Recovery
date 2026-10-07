local eventScripts = {}
local messages = {}
local completed, active = {}, {}

RXPRecoveryDB = {}
DEFAULT_CHAT_FRAME = {AddMessage = function() end}
StaticPopupDialogs = {}
StaticPopup_Show = function() end
SlashCmdList = {}
C_Timer = {After = function(_, callback) callback() end}
C_QuestLog = {}
UnitLevel = function() return 18 end
UnitXP = function() return 100 end
UnitXPMax = function() return 1000 end
CreateFrame = function()
    local frame = {}
    function frame:RegisterEvent() end
    function frame:SetScript(_, callback)
        eventScripts[#eventScripts + 1] = callback
    end
    return frame
end

local rawGuide = {
    key = "source-key",
    group = "Leveling",
    name = "1-20",
    classic = true,
    steps = {
        {stepId = 10, elements = {{tag = "accept", questId = 100, text = "Accept"}}},
        {stepId = 11, elements = {{tag = "complete", questId = 100, text = "Complete"}}},
        {stepId = 12, elements = {{tag = "turnin", questId = 100, text = "Turn in"}}},
    },
}
local original = {
    key = "original-key",
    group = "Leveling",
    name = "18-22",
    classic = true,
    steps = {{elements = {}}},
}

RXP = {
    game = "FOREVER",
    currentGuide = original,
    questieDB = {
        GetQuest = function(id)
            if type(id) ~= "number" then
                error("GetQuest must use dot-call semantics")
            end
            return {Id = id, name = "Quest " .. id, level = 18, requiredLevel = 1}
        end,
        IsDoable = function(_, id) return id == 100 end,
    },
    pickUpList = {
        [100] = {{group = rawGuide.group, name = rawGuide.name,
            guide = rawGuide, step = rawGuide.steps[1]}},
    },
    turnInList = {
        [100] = {{group = rawGuide.group, name = rawGuide.name,
            guide = rawGuide, step = rawGuide.steps[3]}},
    },
    IsQuestTurnedIn = function(id) return completed[id] or false end,
    IsOnQuest = function(id) return active[id] or false end,
    IsQuestComplete = function(id) return completed[id] or false end,
    GetGuideProgress = function() return 1, 123 end,
    SaveGuideProgress = function() end,
    LoadGuide = function(self, guide) self.currentGuide = guide end,
    GetGuideTable = function(group, name)
        if group == original.group and name == original.name then
            return original
        end
    end,
    RegisterMessage = function(_, name, callback) messages[name] = callback end,
}

local addon = {}
for _, path in ipairs({
    "../RestedXP_Recovery/Planner.lua",
    "../RestedXP_Recovery/RouteBuilder.lua",
    "../RestedXP_Recovery/XPPlanner.lua",
    "../RestedXP_Recovery/Core.lua",
    "../RestedXP_Recovery/Scanner.lua",
    "../RestedXP_Recovery/Integration.lua",
    "../RestedXP_Recovery/UI.lua",
}) do
    assert(loadfile(path))("RestedXP_Recovery", addon)
end

assert(addon:GetQuestRecord(100).Id == 100, "Questie dot-call adapter failed")

local plan = {
    guide = original,
    targets = {{id = 100, mode = "accept"}},
    steps = {{id = 100, name = "Quest 100", requiredBy = "xp"}},
    warnings = {},
}
local route, err = addon:StartRecovery(plan)
assert(route, err)
assert(RXP.currentGuide.rxprRecovery, "generated recovery guide was not loaded")
assert(#RXP.currentGuide.steps == 3, "full quest segment was not generated")
assert(RXPRecoveryDB.activeRecovery, "recovery state was not persisted")

completed[100] = true
addon:CheckRecoveryStatus()
assert(RXP.currentGuide == original, "original guide was not resumed")
assert(not RXPRecoveryDB.activeRecovery, "completed recovery state was not cleared")

for _, callback in ipairs(eventScripts) do
    callback(nil, "PLAYER_LOGIN")
end
assert(messages.RXP_GUIDE_LOADED, "RestedXP guide-load callback was not registered")

print("Integration smoke test passed")
