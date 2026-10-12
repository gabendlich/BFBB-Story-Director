-- Pure playlist selection; no file I/O, game calls, or input-table mutations.
-- Construct once: local P=dofile(ROOT..'/playlist.lua').new(context,catalog,extras)
-- Scene and source playlist indices are 1-based. Sentence/variant indices are 0-based.
local M = {}
local function canonical(value)
    return type(value) == 'string' and value ~= '' and value:lower() or nil
end
local function required(value, name)
    assert(type(value) == 'table', name .. ' must be a table')
    return value
end
function M.new(context, catalog, extras)
    local source = required(required(context, 'context').playlist, 'context.playlist')
    local scenes = required(catalog, 'catalog')
    scenes = required(scenes.scenes or scenes, 'catalog.scenes')
    local voices = required(required(extras, 'extras').voices, 'extras.voices')
    local knownAudio = {}
    for _, voice in ipairs(voices) do
        local key = canonical(voice.objectPath)
        if key then knownAudio[key] = voice.objectPath end
    end
    local sceneData = {}
    for position, scene in ipairs(scenes) do
        local sceneIndex = scene.index or position
        local info = {sceneIndex=sceneIndex, totalLines=0, voicedLineCount=0,
            unvoicedLineCount=0, voicedLines={}, flags={}}
        for sentencePosition, sentence in ipairs(scene.sentences or {}) do
            local sentenceIndex = sentence.sentenceIndex
            if sentenceIndex == nil then sentenceIndex = sentencePosition - 1 end
            for variantPosition, line in ipairs(sentence.lineVariants or {}) do
                local variantIndex = line.lineVariantIndex
                if variantIndex == nil then variantIndex = variantPosition - 1 end
                info.totalLines = info.totalLines + 1
                local key = canonical(line.audioSource)
                local objectPath = key and knownAudio[key]
                if objectPath then
                    info.voicedLineCount = info.voicedLineCount + 1
                    info.flags[sentenceIndex .. ':' .. variantIndex] = true
                    info.voicedLines[#info.voicedLines + 1] = {
                        sentenceIndex=sentenceIndex, lineVariantIndex=variantIndex,
                        flatIndex=info.totalLines, audioSource=objectPath}
                else
                    info.unvoicedLineCount = info.unvoicedLineCount + 1
                end
            end
        end
        sceneData[sceneIndex] = info
    end
    local lists = {all=source, dialogue={}, cutscenes={}, voiced={}}
    local sourceIndices = {all={}, dialogue={}, cutscenes={}, voiced={}}
    local positions = {all={}, dialogue={}, cutscenes={}, voiced={}}
    for sourceIndex, item in ipairs(source) do
        sourceIndices.all[sourceIndex] = sourceIndex
        positions.all[sourceIndex] = sourceIndex
        local mode
        if item.kind == 'cinematic' then
            mode = 'cutscenes'
        elseif item.kind == 'scene' then
            local info = assert(sceneData[item.sceneIndex],
                'Playlist references missing native scene ' .. tostring(item.sceneIndex))
            if info.voicedLineCount > 0 then mode = 'dialogue' end
        end
        local isVoiced = mode ~= nil or item.kind == 'voice'
        if isVoiced then
            local position = #lists.voiced + 1
            lists.voiced[position] = item
            sourceIndices.voiced[position] = sourceIndex
            positions.voiced[sourceIndex] = position
        end
        if mode then
            local position = #lists[mode] + 1
            lists[mode][position] = item
            sourceIndices[mode][position] = sourceIndex
            positions[mode][sourceIndex] = position
        end
    end
    local P = {}
    local function selectedMode(mode)
        mode = mode or 'all'
        assert(lists[mode], 'Unknown playlist mode: ' .. tostring(mode))
        return mode
    end
    -- Returned entries and metadata are read-only references; item.index stays the
    -- original all-playlist index. Keep the filtered cursor separately.
    function P:get(mode)
        mode = selectedMode(mode)
        return lists[mode], sourceIndices[mode]
    end
    function P:count(mode)
        return #lists[selectedMode(mode)]
    end
    function P:counts()
        return {all=#lists.all, dialogue=#lists.dialogue, cutscenes=#lists.cutscenes, voiced=#lists.voiced}
    end
    function P:sourceIndex(mode, filteredPosition)
        return sourceIndices[selectedMode(mode)][filteredPosition]
    end
    function P:positionForSource(mode, sourceIndex)
        return positions[selectedMode(mode)][sourceIndex]
    end
    function P:lineIsVoiced(sceneIndex, sentenceIndex, lineVariantIndex)
        local info = sceneData[sceneIndex]
        return info ~= nil and info.flags[sentenceIndex .. ':' .. lineVariantIndex] == true
    end
    function P:voicedLines(sceneIndex)
        local info = sceneData[sceneIndex]
        return info and info.voicedLines or {}
    end
    function P:sceneInfo(sceneIndex)
        local info = sceneData[sceneIndex]
        if not info then return nil end
        return {sceneIndex=info.sceneIndex, totalLines=info.totalLines,
            voicedLineCount=info.voicedLineCount, unvoicedLineCount=info.unvoicedLineCount}
    end
    function P:audioIsKnown(objectPath)
        local key = canonical(objectPath)
        return key ~= nil and knownAudio[key] ~= nil
    end
    return P
end
return M
