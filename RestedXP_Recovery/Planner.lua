-- RestedXP Recovery - pure quest dependency planner.
-- No WoW API calls live here so the planner can be unit tested outside the game.
local _, addon = ...

local Planner = {}
addon.Planner = Planner

local function ids(value)
    if type(value) == "number" then
        return { value }
    end
    if type(value) ~= "table" then
        return {}
    end

    local result, seen = {}, {}
    for _, id in pairs(value) do
        id = tonumber(id)
        id = id and math.abs(id)
        if id and id > 0 and not seen[id] then
            seen[id] = true
            result[#result + 1] = id
        end
    end
    table.sort(result)
    return result
end

-- targets: { { id = questId, mode = "carryover"|"accept", ... } }
-- api.completed(id): true when the quest has already been turned in.
-- api.onQuest(id): true when the quest is currently in the player's quest log.
-- api.getQuest(id): Questie-style quest record with preQuestSingle/preQuestGroup.
function Planner.Resolve(targets, api)
    local plan = {
        steps = {},
        warnings = {},
        examined = 0,
        unknown = 0,
    }

    local queued, visiting, warned = {}, {}, {}
    local completed = api.completed
    local onQuest = api.onQuest
    local getQuest = api.getQuest

    local function warn(message)
        if not warned[message] then
            warned[message] = true
            plan.warnings[#plan.warnings + 1] = message
        end
    end

    local function lookup(id)
        local ok, quest = pcall(getQuest, id)
        if ok and type(quest) == "table" then
            return quest
        end
        return nil
    end

    local function finished(id)
        return completed(id) and true or false
    end

    local function active(id)
        return onQuest(id) and true or false
    end

    -- Pick an OR prerequisite branch using a simple outstanding-quest-count
    -- heuristic. Travel-time optimization comes later.
    local function estimate(id, ancestry)
        if finished(id) then
            return 0
        end
        if active(id) then
            return 0.25
        end
        if ancestry[id] then
            return 10000
        end

        ancestry[id] = true
        local quest = lookup(id)
        local score = 1

        if quest then
            for _, required in ipairs(ids(quest.preQuestGroup)) do
                score = score + estimate(required, ancestry)
            end

            local alternatives = ids(quest.preQuestSingle)
            if #alternatives > 0 then
                local best = math.huge
                for _, alternative in ipairs(alternatives) do
                    best = math.min(best, estimate(alternative, ancestry))
                end
                score = score + best
            end
        end

        ancestry[id] = nil
        return score
    end

    local function pickAlternative(quest)
        local options = ids(quest.preQuestSingle)
        if #options == 0 then
            return nil
        end

        -- A completed OR prerequisite means no recovery is needed for this group.
        for _, id in ipairs(options) do
            if finished(id) then
                return nil
            end
        end

        -- Prefer a branch the character has already started.
        for _, id in ipairs(options) do
            if active(id) then
                return id
            end
        end

        local bestId, bestCost
        for _, id in ipairs(options) do
            local cost = estimate(id, {})
            if not bestCost or cost < bestCost or (cost == bestCost and id < bestId) then
                bestId = id
                bestCost = cost
            end
        end
        return bestId
    end

    local function visit(id, reason)
        id = tonumber(id)
        if not id or id < 1 or finished(id) or queued[id] then
            return
        end

        if visiting[id] then
            warn("Circular quest dependency involving quest #" .. id)
            return
        end

        visiting[id] = true
        local quest = lookup(id)

        -- If the player already has the quest, its prerequisites have necessarily
        -- been satisfied. Keep it in the plan as context but do not walk backward.
        if quest and not active(id) then
            for _, prerequisite in ipairs(ids(quest.preQuestGroup)) do
                visit(prerequisite, id)
            end

            local alternative = pickAlternative(quest)
            if alternative then
                visit(alternative, id)
            end
        elseif not quest then
            plan.unknown = plan.unknown + 1
            warn("No quest database entry for #" .. id .. " (chain may be incomplete)")
        end

        visiting[id] = nil

        if not queued[id] then
            queued[id] = true
            plan.steps[#plan.steps + 1] = {
                id = id,
                name = quest and (quest.name or quest.Name)
                    or (api.getName and api.getName(id))
                    or ("Quest #" .. id),
                status = active(id) and "in-log" or "missing",
                requiredBy = reason,
            }
        end
    end

    for _, target in ipairs(targets) do
        local id = tonumber(target.id)
        if id and id > 0 and not finished(id) and not active(id) then
            plan.examined = plan.examined + 1

            if target.mode == "carryover" then
                -- The current guide expects this quest to already exist. Recover
                -- the quest itself plus its transitive prerequisite chain.
                visit(id)
            elseif target.mode == "accept" then
                -- The current guide already contains the accept step, so only
                -- recover prerequisites that prevent that accept from working.
                local quest = lookup(id)
                if quest then
                    for _, prerequisite in ipairs(ids(quest.preQuestGroup)) do
                        visit(prerequisite, id)
                    end
                    local alternative = pickAlternative(quest)
                    if alternative then
                        visit(alternative, id)
                    end
                else
                    plan.unknown = plan.unknown + 1
                    warn("Cannot inspect prerequisites for upcoming quest #" .. id)
                end
            end
        end
    end

    return plan
end

return Planner
