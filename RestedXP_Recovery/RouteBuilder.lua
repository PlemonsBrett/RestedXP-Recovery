-- Builds an in-memory recovery guide from RestedXP's already-loaded steps.
-- This module has no WoW API dependencies and is testable with ordinary Lua.
local _, addon = ...

local RouteBuilder = {}
addon.RouteBuilder = RouteBuilder

local QUEST_TAGS = {
    accept = true,
    daily = true,
    complete = true,
    turnin = true,
    dailyturnin = true,
    abandon = true,
}

local UNSAFE_NONQUEST_TAGS = {
    next = true,
    nextguide = true,
    include = true,
    xp = true,
}

local function questIds(element)
    local result = {}
    if type(element) ~= "table" then
        return result
    end
    if type(element.ids) == "table" then
        for _, id in pairs(element.ids) do
            id = tonumber(id)
            if id and id > 0 then
                result[#result + 1] = id
            end
        end
    end
    local id = tonumber(element.questId)
    if id and id > 0 then
        result[#result + 1] = id
    end
    return result
end

local function stepContains(step, questId)
    for _, element in ipairs(step.elements or {}) do
        for _, id in ipairs(questIds(element)) do
            if id == questId then
                return true
            end
        end
    end
    return false
end

local function isNavigationOnly(step)
    local elements = step and step.elements
    if type(elements) ~= "table" or #elements == 0 then
        return false
    end
    for _, element in ipairs(elements) do
        if QUEST_TAGS[element.tag] or #questIds(element) > 0 then
            return false
        end
    end
    return true
end

local function clone(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        if key ~= "frame" and key ~= "active" and key ~= "completed"
            and key ~= "lastStep" and key ~= "index" and key ~= "step"
            and key ~= "include" and key ~= "requires"
            and key ~= "completewith" and key ~= "label" then
            copy[clone(key, seen)] = clone(child, seen)
        end
    end
    return copy
end

local function cloneStep(step, allowed)
    local copy = clone(step)
    copy.elements = {}

    for _, element in ipairs(step.elements or {}) do
        local ids = questIds(element)
        local keep = #ids == 0 and not UNSAFE_NONQUEST_TAGS[element.tag]
        for _, id in ipairs(ids) do
            if allowed[id] then
                keep = true
                break
            end
        end
        if keep then
            local elementCopy = clone(element)
            elementCopy.step = copy
            copy.elements[#copy.elements + 1] = elementCopy
        end
    end

    if #copy.elements == 0 then
        return nil
    end
    return copy
end

local function referenceIndex(reference)
    if tonumber(reference.stepIndex) then
        return tonumber(reference.stepIndex)
    end
    local guide = reference.guide
    if type(guide) ~= "table" or type(guide.steps) ~= "table" then
        return nil
    end
    local sourceStep = reference.sourceStep
    for index, step in ipairs(guide.steps) do
        if step == sourceStep
            or (sourceStep and sourceStep.stepId
                and step.stepId == sourceStep.stepId) then
            return index
        end
    end
    return nil
end

local function bestSource(planStep, currentGroup)
    local accepts, turnins = {}, {}
    for _, reference in ipairs(planStep.references or {}) do
        reference.stepIndex = referenceIndex(reference)
        if reference.guide and reference.stepIndex then
            if reference.action == "accept" then
                accepts[#accepts + 1] = reference
            elseif reference.action == "turnin" then
                turnins[#turnins + 1] = reference
            end
        end
    end

    local best
    for _, accept in ipairs(accepts) do
        local finish
        for _, turnin in ipairs(turnins) do
            if turnin.guide == accept.guide and turnin.stepIndex >= accept.stepIndex
                and (not finish or turnin.stepIndex < finish.stepIndex) then
                finish = turnin
            end
        end
        local endIndex = finish and finish.stepIndex or accept.stepIndex
        local score = endIndex - accept.stepIndex
        if accept.group ~= currentGroup then
            score = score + 1000
        end
        if not best or score < best.score then
            best = {
                accept = accept,
                finish = finish,
                score = score,
            }
        end
    end
    return best
end

function RouteBuilder.Build(plan, options)
    options = options or {}
    local route = {
        steps = {},
        warnings = {},
        sources = {},
        questIds = {},
    }
    local allowed, emitted = {}, {}

    for _, planStep in ipairs(plan.steps or {}) do
        allowed[planStep.id] = true
        route.questIds[#route.questIds + 1] = planStep.id
    end

    for _, planStep in ipairs(plan.steps or {}) do
        local source = bestSource(planStep, options.currentGroup)
        if not source then
            route.warnings[#route.warnings + 1] =
                "No usable RestedXP accept step was found for quest #" .. planStep.id
        else
            local guide = source.accept.guide
            local startIndex = source.accept.stepIndex
            -- Root carry-over quests only need to be accepted. Their original
            -- guide remains responsible for completion and turn-in.
            local endIndex = planStep.requiredBy and
                (source.finish and source.finish.stepIndex or startIndex) or startIndex
            if planStep.requiredBy and not source.finish then
                for index = startIndex, #guide.steps do
                    if stepContains(guide.steps[index], planStep.id) then
                        endIndex = index
                    end
                end
                route.warnings[#route.warnings + 1] =
                    "No RestedXP turn-in step was found for quest #" .. planStep.id
            end
            local selected = {}

            for index = startIndex, endIndex do
                local step = guide.steps[index]
                if step and stepContains(step, planStep.id) then
                    selected[index] = true
                    if index > startIndex and isNavigationOnly(guide.steps[index - 1]) then
                        selected[index - 1] = true
                    end
                end
            end
            selected[startIndex] = true

            for index = startIndex, endIndex do
                if selected[index] then
                    local step = guide.steps[index]
                    local sourceKey = tostring(guide.key or source.accept.group or "?")
                        .. ":" .. tostring(step.stepId or index)
                    if not emitted[sourceKey] then
                        local copied = cloneStep(step, allowed)
                        if copied then
                            emitted[sourceKey] = true
                            copied.rxprSource = sourceKey
                            route.steps[#route.steps + 1] = copied
                        end
                    end
                end
            end

            route.sources[#route.sources + 1] = {
                questId = planStep.id,
                group = source.accept.group,
                name = source.accept.name,
                startStep = startIndex,
                endStep = endIndex,
            }
        end
    end

    return route
end

return RouteBuilder
