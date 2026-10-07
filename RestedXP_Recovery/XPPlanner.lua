-- Pure XP-deficit and optional-quest selection logic.
local _, addon = ...

local XPPlanner = {}
addon.XPPlanner = XPPlanner

local function idsFromName(name)
    if type(name) ~= "string" then
        return nil, nil
    end
    local first, last = name:match("(%d+)%s*%-%s*(%d+)")
    return tonumber(first), tonumber(last)
end

function XPPlanner.FindGate(guide, currentStep, player)
    if type(guide) ~= "table" or type(guide.steps) ~= "table" then
        return nil
    end
    currentStep = math.max(1, tonumber(currentStep) or 1)
    player = player or {}

    for index = currentStep, #guide.steps do
        for _, element in ipairs(guide.steps[index].elements or {}) do
            if element.tag == "xp" and tonumber(element.level) then
                local level = tonumber(element.level)
                local amount = tonumber(element.xp) or 0
                if (player.level or 0) < level
                    or ((player.level or 0) == level and amount > (player.xp or 0)) then
                    return {
                        kind = "explicit",
                        step = index,
                        level = level,
                        xp = amount,
                    }
                end
            end
        end
    end

    local _, finishLevel = idsFromName(guide.name)
    if finishLevel and #guide.steps > 0 and currentStep / #guide.steps >= 0.85
        and (player.level or 0) < finishLevel then
        return {
            kind = "guide-finish",
            step = #guide.steps,
            level = finishLevel,
            xp = 0,
        }
    end
    return nil
end

function XPPlanner.SelectCandidates(candidateIds, api, limit)
    local result, seen = {}, {}
    local playerLevel = tonumber(api.playerLevel) or 1
    limit = tonumber(limit) or 8

    for _, rawId in pairs(candidateIds or {}) do
        local id = tonumber(rawId)
        if id and id > 0 and not seen[id] then
            seen[id] = true
            local quest = api.getQuest(id)
            local required = quest and tonumber(quest.requiredLevel) or 0
            local level = quest and tonumber(quest.level or quest.questLevel) or playerLevel
            local doable = not api.isDoable or api.isDoable(id)
            if quest and not api.completed(id) and not api.onQuest(id)
                and doable ~= false and required <= playerLevel
                and level >= playerLevel - 5 and level <= playerLevel + 3
                and (not api.hasReference or api.hasReference(id)) then
                result[#result + 1] = {
                    id = id,
                    name = quest.name or (api.getName and api.getName(id))
                        or ("Quest #" .. id),
                    level = level,
                    xp = api.getXP and (tonumber(api.getXP(id)) or 0) or 0,
                    references = api.getReferences and api.getReferences(id) or {},
                }
            end
        end
    end

    table.sort(result, function(a, b)
        if a.xp ~= b.xp then
            return a.xp > b.xp
        end
        local ad, bd = math.abs(a.level - playerLevel), math.abs(b.level - playerLevel)
        if ad ~= bd then
            return ad < bd
        end
        return a.id < b.id
    end)

    local effectiveLimit = limit
    local neededXP = tonumber(api.neededXP)
    if neededXP and neededXP > 0 then
        local accumulated = 0
        for index, quest in ipairs(result) do
            if quest.xp <= 0 then
                break
            end
            accumulated = accumulated + quest.xp
            if accumulated >= neededXP then
                effectiveLimit = math.min(effectiveLimit, index)
                break
            end
        end
    end

    while #result > effectiveLimit do
        table.remove(result)
    end
    return result
end

return XPPlanner
