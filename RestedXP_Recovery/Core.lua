local addonName, addon = ...

addon.name = addonName
addon.version = "0.4.0"
addon.prefix = "|cff4fd1c5RXP Recovery:|r "

RXPRecoveryDB = RXPRecoveryDB or {}
addon.db = RXPRecoveryDB

if addon.db.autoPrompt == nil then
    addon.db.autoPrompt = true
end
if addon.db.xpRecovery == nil then
    addon.db.xpRecovery = true
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
        return nil
    end
    return a, b, c
end

function addon:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(self.prefix .. tostring(message))
end

function addon:GetRXP()
    local rxp = _G.RXP
    if type(rxp) ~= "table" then
        return nil
    end
    return rxp
end

function addon:IsForever()
    local rxp = self:GetRXP()
    return rxp and rxp.game == "FOREVER"
end

function addon:IsQuestTurnedIn(id)
    local rxp = self:GetRXP()
    if rxp and type(rxp.IsQuestTurnedIn) == "function" then
        return safeCall(rxp.IsQuestTurnedIn, id) and true or false
    end

    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(id) and true or false
    end

    return false
end

function addon:IsOnQuest(id)
    local rxp = self:GetRXP()
    if rxp and type(rxp.IsOnQuest) == "function" then
        return safeCall(rxp.IsOnQuest, id) and true or false
    end

    if C_QuestLog and C_QuestLog.IsOnQuest then
        return C_QuestLog.IsOnQuest(id) and true or false
    end

    return false
end

function addon:IsQuestComplete(id)
    local rxp = self:GetRXP()
    if rxp and type(rxp.IsQuestComplete) == "function" then
        return safeCall(rxp.IsQuestComplete, id) and true or false
    end

    if C_QuestLog and C_QuestLog.IsComplete then
        return C_QuestLog.IsComplete(id) and true or false
    end

    return false
end

function addon:GetQuestName(id)
    local rxp = self:GetRXP()
    if rxp and type(rxp.GetQuestName) == "function" then
        local name = safeCall(rxp.GetQuestName, id)
        if name and name ~= "" then
            return name
        end
    end

    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        local name = C_QuestLog.GetTitleForQuestID(id)
        if name and name ~= "" then
            return name
        end
    end

    return "Quest #" .. tostring(id)
end

function addon:GetQuestDB()
    local rxp = self:GetRXP()
    local db = rxp and rxp.questieDB
    if db and type(db.GetQuest) == "function" then
        return db
    end

    if _G.QuestieLoader and type(_G.QuestieLoader.ImportModule) == "function" then
        local ok, questieDB = pcall(_G.QuestieLoader.ImportModule,
            _G.QuestieLoader, "QuestieDB")
        if ok and type(questieDB) == "table"
            and type(questieDB.GetQuest) == "function" then
            return questieDB
        end
    end
    return nil
end

function addon:GetQuestRecord(id)
    local db = self:GetQuestDB()
    if not db then
        return nil
    end

    -- Questie has shipped both dot-call and method-style module APIs. Prefer
    -- the current dot-call form, then tolerate older wrappers.
    local ok, quest = pcall(db.GetQuest, id)
    if ok and type(quest) == "table"
        and (not quest.Id or tonumber(quest.Id) == tonumber(id)) then
        return quest
    end
    ok, quest = pcall(db.GetQuest, db, id)
    if ok and type(quest) == "table" then
        return quest
    end
    return nil
end

function addon:IsQuestDoable(id)
    local db = self:GetQuestDB()
    if not db or type(db.IsDoable) ~= "function" then
        return nil
    end
    local ok, doable = pcall(db.IsDoable, db, id)
    if not ok then
        ok, doable = pcall(db.IsDoable, id)
    end
    if ok then
        return doable and true or false
    end
    return nil
end

function addon:GetQuestXP(id)
    if not (_G.QuestieLoader and type(_G.QuestieLoader.ImportModule) == "function") then
        return 0
    end
    local ok, questXP = pcall(_G.QuestieLoader.ImportModule,
        _G.QuestieLoader, "QuestXP")
    if not ok or type(questXP) ~= "table"
        or type(questXP.GetQuestLogRewardXP) ~= "function" then
        return 0
    end
    local rewardOK, reward = pcall(questXP.GetQuestLogRewardXP,
        questXP, id, false)
    return rewardOK and tonumber(reward) or 0
end

function addon:GetGuideProgress(guide)
    local rxp = self:GetRXP()
    if not rxp or not guide then
        return 1
    end

    if type(rxp.GetGuideProgress) == "function" then
        local step = safeCall(rxp.GetGuideProgress, guide)
        if tonumber(step) then
            return tonumber(step)
        end
    end

    return 1
end

function addon:GetGuideReferences(id)
    local rxp = self:GetRXP()
    if not rxp then
        return {}
    end

    local references = {}
    local seen = {}
    local lists = {
        { entries = rxp.pickUpList, action = "accept" },
        { entries = rxp.turnInList, action = "turnin" },
    }

    for _, source in ipairs(lists) do
        local entries = type(source.entries) == "table" and source.entries[id]
        if type(entries) == "table" then
            for _, entry in pairs(entries) do
                local group = entry.group or (entry.guide and entry.guide.group) or "?"
                local name = entry.name or (entry.guide and entry.guide.name) or "?"
                local stepId = entry.step and entry.step.stepId
                local key = source.action .. ":" .. tostring(group) .. "\\"
                    .. tostring(name) .. ":" .. tostring(stepId or entry.step)
                if not seen[key] then
                    seen[key] = true
                    references[#references + 1] = {
                        group = group,
                        name = name,
                        step = entry.step and entry.step.index,
                        stepIndex = entry.step and entry.step.index,
                        stepId = stepId,
                        action = source.action,
                        guide = entry.guide,
                        sourceStep = entry.step,
                    }
                end
            end
        end
    end

    table.sort(references, function(a, b)
        if a.group == b.group then
            return tostring(a.name) < tostring(b.name)
        end
        return tostring(a.group) < tostring(b.group)
    end)

    return references
end

function addon:GetPlayerXPState()
    return {
        level = UnitLevel and UnitLevel("player") or 1,
        xp = UnitXP and UnitXP("player") or 0,
        xpMax = UnitXPMax and UnitXPMax("player") or 0,
    }
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    if not addon:GetRXP() then
        addon:Print("RestedXP was not detected. Make sure RestedXP Guides is enabled.")
        return
    end

    if not addon:IsForever() then
        addon:Print("Loaded, but this build is currently targeted at WoW Forever.")
    end
end)
