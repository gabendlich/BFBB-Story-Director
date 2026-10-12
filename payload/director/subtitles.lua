-- Resolve captions from the user's installed game; no transcript is distributed.
local M = {}
local cache = {}
local function text(value)
    if type(value)=='string' then return value end
    if value==nil then return '' end
    local ok,result=pcall(function() return value:ToString() end)
    return ok and result or ''
end
local function plain(value)
    return text(value):gsub('<Split>','\n'):gsub('<img.-id="([^"]+)".-/>','[%1]'):gsub('<[^>]+>','')
end
local function localization(key)
    if not key or key=='' then return '' end
    local out={}
    local ok,found=pcall(function()
        return StaticFindObject('/Script/Engine.Default__KismetTextLibrary'):FindTextInLocalizationTable('',key,out)
    end)
    return ok and found and plain(out.OutText) or ''
end
local function sourceText(source)
    if not source.asset or not source.propertyPath then return '' end
    local ok,result=pcall(function()
        local value=LoadAsset(source.asset)
        if not value or not value:IsValid() then return '' end
        if source.category=='announcer' then
            local row=value:FindRow(source.propertyPath:match('^Rows%.(.+)$'))
            return row and plain(row.Text) or ''
        end
        if source.category=='cutscene' then return '' end
        for part in source.propertyPath:gmatch('[^.]+') do
            local index=tonumber(part)
            value=value[index and index+1 or part]
        end
        return plain(value.SpokenText)
    end)
    return ok and result or ''
end
function M.voice(voice,sound,elapsed)
    local selected=''
    if sound and sound:IsValid() then
        pcall(function()
            sound.Subtitles:ForEach(function(_,entry)
                local cue=entry:get()
                if cue.Time<=(elapsed or 0) then selected=plain(cue.Text) end
            end)
        end)
    end
    if selected~='' then return selected end
    if cache[voice.objectPath] then return cache[voice.objectPath] end
    for _,source in ipairs(voice.subtitleSources or {}) do
        local value=sourceText(source)
        if value=='' then value=localization(source.textKey) end
        if value~='' then cache[voice.objectPath]=value;return value end
    end
    return ''
end
function M.cinematic(line,voice)
    if not line then return '' end
    local key=(voice and voice.objectPath or '')..':'..(line.sourcePropertyPath or line.textKey or '')
    if cache[key] then return cache[key] end
    local result=''
    if voice and line.sourcePropertyPath then
        pcall(function()
            local data=LoadAsset('/Game/Sequences/DA_CutScenes.DA_CutScenes')
            if not data or not data:IsValid() then return end
            local index=tonumber(line.sourcePropertyPath:match('%.Lines%.(%d+)$'))
            if not index then return end
            data.Cutscenes:ForEach(function(_,entry)
                local content=entry:get()
                local sound=content.AudioFile
                if sound and sound:IsValid() and sound:GetFullName():match('^[^ ]+ (.+)$')==voice.objectPath then
                    result=plain(content.Lines[index+1].SpokenText)
                    return true
                end
            end)
        end)
    end
    if result=='' then result=localization(line.textKey) end
    if result~='' then cache[key]=result end
    return result
end
-- Native callers replace subtitle IDs. A non-positive ID is the game's explicit clear-all operation.
function M.clear(hud)
    if hud and hud:IsValid() then hud:HideSubtitles(-1) end
end
return M
