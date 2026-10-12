-- Contextual playback: native cinematics and in-world ambient lines.
return function(A)
    local S=A.state
    local subtitles=dofile(A.root..'/subtitles.lua')
    local M={}
    local C,extras,playlists
    local ensureSublevel
    local function context()
        if not C then C=dofile(A.data..'/context.lua');extras=dofile(A.data..'/extras.lua');S.context=C;playlists=dofile(A.root..'/playlist.lua').new(C,{scenes=A.scenes},extras) end
        return C
    end
    local function hud() local c=A.pc();return A.valid(c) and c:GetMainHUD() or nil end
    local function ftext(value) return StaticFindObject('/Script/Engine.Default__KismetTextLibrary'):Conv_StringToText(tostring(value or '')) end
    local function hideCaption()
        if S.subtitleHandle and A.valid(S.subtitleHud) then S.subtitleHud:HideSubtitles(S.subtitleHandle) end
        S.subtitleHandle=nil;S.subtitleHud=nil
    end
    local function caption(text,speaker)
        hideCaption();local h=hud();assert(A.valid(h),'The game subtitle display is not ready')
        local g=A.gi();if A.valid(g.GameConfigManager) then g.GameConfigManager.ShowSubtitles=true end
        h:SetVisibility(0);h:SetRenderOpacity(1.0);h.MainHudPanel:SetVisibility(0);h.ImgFadeToBlackMain:SetRenderOpacity(0.0)
        if not h:IsInViewport() then h:AddToViewport(0) end
        S.subtitleHud=h;S.subtitleHandle=h:ShowSubtitles(ftext(text),ftext(speaker),true)
        assert(S.subtitleHandle>=0,'Subtitles are disabled in the game settings')
    end
    local function sameWorld(actor)
        local c=A.pc();return A.valid(c) and A.actorWorld(actor)==A.full(c:GetWorld())
    end
    local function cleanupCinematic()
        if A.valid(S.sequence) then S.sequence:StopAtCurrentTime() end
        if A.valid(S.sequenceActor) then S.sequenceActor:K2_DestroyActor() end
        if S.sequence then
            local h=hud();if A.valid(h) then h:EndCinematic() end
            local c=A.pc();if A.valid(c) then c:SetActiveSequenceScript(nil);c:ResetIgnoreInputFlags() end
            local p=A.player();if A.valid(p) then p:SetIsInCutScene(false);p:SetActorHiddenInGame(false);p:SetInvincibility(true) end
            StaticFindObject('/Script/Pineapple.Default__PINE_InputUtils'):EnableAllInput(c)
        end
        S.sequence=nil;S.sequenceActor=nil
    end
    function M.cleanup() hideCaption();cleanupCinematic() end
    function M.pause(paused)
        if A.valid(S.sequence) then if paused then S.sequence:Pause() else S.sequence:Play() end end
    end
    local function seconds(q)
        return (q.Time.FrameNumber.Value+q.Time.SubFrame)*q.Rate.Denominator/q.Rate.Numerator
    end
    local function stopOriginalCinematics()
        for _,actor in ipairs(FindAllOf('LevelSequenceActor') or {}) do
            if sameWorld(actor) then local p=actor:GetSequencePlayer();if A.valid(p) then p:StopAtCurrentTime() end end
        end
        for _,owner in ipairs(FindAllOf('BP_CutsceneStart_C') or {}) do
            if sameWorld(owner) then
                local p=owner['Sequence Player'];if A.valid(p) then p:StopAtCurrentTime() end
                owner:K2_DestroyActor()
            end
        end
        local c=A.pc();c:SetActiveSequenceScript(nil);c:ResetIgnoreInputFlags()
        StaticFindObject('/Script/Pineapple.Default__PINE_InputUtils'):EnableAllInput(c)
        local p=A.player();if A.valid(p) then p:SetIsInCutScene(false);p:SetInvincibility(true) end
    end
    function M.prepareNativeView()
        A.stopNativeDialogue()
        stopOriginalCinematics()
        local p=A.player()
        if A.valid(p) then
            p:SetActorHiddenInGame(false)
            if A.valid(p.Mesh) then p.Mesh:SetHiddenInGame(false,false);p.Mesh:SetVisibility(true,false) end
            A.pc():SetViewTargetWithBlend(p,0.0,0,0.0,false)
        end
    end
    local function cinematicTick(item)
        A.stopNativeDialogue()
        assert(item.map and item.sequenceObjectPath,'The cutscene location or sequence is missing')
        S.map=item.map
        if S.phase~='cinematic' then
            if not A.ensureMap(item.map,false) then return end
            stopOriginalCinematics()
            local seq=LoadAsset(item.sequenceObjectPath);assert(A.valid(seq),'Could not load the cutscene: '..item.sequenceObjectPath)
            seq=StaticFindObject('/Script/Pineapple.Default__PINE_LocalizedVoiceOverUtils'):GetLocalizedCutScene(A.pc(),seq)
            local out={}
            S.sequence=StaticFindObject('/Script/LevelSequence.Default__LevelSequencePlayer'):CreateLevelSequencePlayer(A.pc(),seq,{
                bAutoPlay=false,LoopCount={Value=0},PlayRate=1.0,StartTime=0.0,bRandomStartTime=false,bRestoreState=true,
                bDisableMovementInput=true,bDisableLookAtInput=true,bHidePlayer=true,bHideHud=false,bDisableCameraCuts=false,bPauseAtEnd=true
            },out)
            S.sequenceActor=out.OutActor
            assert(A.valid(S.sequence) and A.valid(S.sequenceActor),'Could not start the cutscene')
            local h=hud();if A.valid(h) then h:StartCinematic(false) end
            S.sequence:Play();S.phase='cinematic';S.phaseAt=S.now;S.lineCount=0;S.line=0
            S.title=item.name or item.sequenceObjectPath:match('%.([^%.]+)$');S.message='Playing cutscene.'
            A.log('CINEMATIC_STARTED',item.sequenceObjectPath..' map='..item.map)
        else
            assert(A.valid(S.sequence),'The cutscene was interrupted')
            local elapsed=seconds(S.sequence:GetCurrentTime());local endTime=seconds(S.sequence:GetEndTime())
            local voice=item.voiceIndex and extras.voices[item.voiceIndex]
            local activeLine
            for _,line in ipairs(voice and voice.timedSubtitles or {}) do if (line.start or -1)>=0 and (line.stop or -1)>=0 and elapsed>=line.start and elapsed<=line.stop then activeLine=line;break end end
            local text=subtitles.cinematic(activeLine,voice)
            if text~=S.captionText then
                S.captionText=text;S.text=text
                if text=='' then hideCaption() else
                    local speaker=activeLine.speaker~='' and activeLine.speaker or activeLine.character or ''
                    if speaker=='FrenchNarrator' then speaker='French Narrator' elseif speaker=='FishAnnouncer' then speaker='Fish Announcer' end
                    caption(text,speaker)
                end
            end
            if elapsed>=endTime-0.08 and S.now-S.phaseAt>1 then
                S.completed=S.completed+1;A.log('CINEMATIC_FINISHED',item.sequenceObjectPath);A.nextScene(1,true)
            elseif S.now-S.phaseAt>2 and not S.sequence:IsPlaying() then error('The cutscene stopped before it finished') end
        end
    end
    local function locateVoice(item)
        local map=item.map
        if not map then
            map=S.lastPlayableMap
            if not map then local current=A.mapNow();if A.valid(A.player()) then map=current end end
            map=map or '/Game/Maps/BikiniBottom/BikiniBottom_P'
        end
        S.map=map
        if not A.ensureMap(map) then return false end
        if item.placementContext and not ensureSublevel(item.placementContext.sublevel,map) then return false end
        if A.switchCharacter(item.character) then S.stableAt=S.now;return false end
        local p=A.player();p:SetInvincibility(true);p.CanNotDrown=true
        M.prepareNativeView()
        local anchor
        for _,path in ipairs(item.placementActorPaths or {}) do local a=StaticFindObject(path);if A.valid(a) and sameWorld(a) then anchor=a;break end end
        if #(item.placementActorPaths or {})>0 then
            assert(A.valid(anchor),'The game has not loaded the location for this voice line')
            local component
            for _,data in ipairs(item.placementContext.actors or {}) do
                if data.volumeComponent then local c=StaticFindObject(data.volumeComponent.objectPath);if A.valid(c) then component=c;break end end
            end
            A.placeInArea(anchor,p,component)
        end
        S.lastPlayableMap=map
        return true
    end
    local function silenceNativeBarks()
        local p=A.player()
        if A.valid(p) and A.valid(p.BarkComponent) then p.BarkComponent:Stop();p.BarkComponent.QueuedBarks={} end
    end
    local function voiceTick(item)
        A.stopNativeDialogue()
        silenceNativeBarks()
        local voice=extras.voices[item.voiceIndex];assert(voice,'The voice line is missing from the catalog')
        if S.phase~='context-voice' then
            if not locateVoice(item) then return end
            local p=A.player();A.pc():SetViewTargetWithBlend(p,0.0,0,0.0,false)
            local sound=LoadAsset(voice.objectPath);assert(A.valid(sound),'Voice audio is missing: '..voice.objectPath)
            S.audio=A.gp():SpawnSound2D(A.pc(),sound,1.0,1.0,0.0,nil,false,false);assert(A.valid(S.audio),'Could not start the voice line')
            S.text=subtitles.voice(voice,sound,0);caption(S.text,item.speakerName or voice.character or '')
            S.phase='context-voice';S.phaseAt=S.now;S.title=voice.name or voice.objectPath;S.line=1;S.lineCount=1
            S.message=item.contextDependent and ('Playing reaction: '..(item.trigger or 'available in several locations')) or 'Playing voice line.'
            A.log('CONTEXT_VOICE_STARTED',voice.objectPath..' map='..S.map..' contextDependent='..tostring(item.contextDependent==true))
        elseif S.now-S.phaseAt>0.75 and (not A.valid(S.audio) or not S.audio:IsPlaying()) then
            S.completed=S.completed+1;A.log('CONTEXT_VOICE_FINISHED',voice.objectPath);A.nextScene(1,true)
        elseif S.now-S.phaseAt>600 then error('Voice playback timed out') end
    end
    local dynamicLevels={}
    function M.nativeContext(index) return context().nativeScenes[index] end
    function M.prepareScene(index)
        local entry=context().nativeScenes[index];if not entry then return true end
        local owner
        for _,actor in ipairs(entry.originalActors or {}) do if actor.objectPath==entry.preferredActorPath then owner=actor;break end end
        owner=owner or (entry.originalActors or {})[1]
        return not owner or ensureSublevel(owner.sublevel,entry.map)
    end
    ensureSublevel=function(sublevel,map)
        if not sublevel or sublevel==map then return true end
        local key=A.mapNow()..':'..sublevel
        local stream=A.gp():GetStreamingLevel(A.pc(),FName(sublevel:match('[^/]+$')))
        if not A.valid(stream) then
            stream=dynamicLevels[key]
            if not A.valid(stream) then
                local out={};stream=StaticFindObject('/Script/Engine.Default__LevelStreamingDynamic'):LoadLevelInstance(A.pc(),sublevel,{X=0,Y=0,Z=0},{Pitch=0,Yaw=0,Roll=0},out)
                assert(A.valid(stream),'Could not load the conversation area: '..sublevel)
                dynamicLevels[key]=stream;A.log('AUTHORED_SUBLEVEL',sublevel)
            end
        end
        stream:SetShouldBeLoaded(true);stream:SetShouldBeVisible(true)
        if stream:IsLevelLoaded() and stream:IsLevelVisible() then S.sublevelAt=nil;return true end
        S.sublevelAt=S.sublevelAt or S.now;assert(S.now-S.sublevelAt<30,'The conversation area took too long to load: '..sublevel)
        S.message='Loading conversation area: '..sublevel:match('[^/]+$');return false
    end
    function M.start(index,mode)
        context();S.voiceCheckIndices=nil;S.playlistMode=mode or 'all'
        S.playlist=playlists:get(S.playlistMode);S.storyIndex=index or 1
        A.log('PLAYLIST_SELECTED',S.playlistMode..' entries='..#S.playlist)
    end
    function M.beginLocationChecks()
        S.playlistMode='all';S.playlist=nil;S.voiceCheckIndices={};S.voiceCheckAt=1
        for index,item in ipairs(context().playlist) do if item.kind=='voice' and item.placementContext then S.voiceCheckIndices[#S.voiceCheckIndices+1]=index end end
        S.storyIndex=S.voiceCheckIndices[1]
    end
    function M.sourceIndex() context();return playlists:sourceIndex(S.playlistMode or 'all',S.storyIndex or 1) or S.storyIndex or 1 end
    function M.total(mode) context();return mode and playlists:count(mode) or #(S.playlist or C.playlist) end
    function M.lineIsVoiced(sceneIndex,sentenceIndex,variantIndex) context();return playlists:lineIsVoiced(sceneIndex,sentenceIndex,variantIndex) end
    function M.tick()
        if S.voiceCheckIndices then
            local index=S.voiceCheckIndices[S.voiceCheckAt]
            if not index then S.voiceCheckIndices=nil;return A.finish() end
            S.storyIndex=index;local item=context().playlist[index]
            local ok,ready=pcall(locateVoice,item)
            if ok and not ready then return end
            if ok then S.completed=S.completed+1;A.log('VOICE_LOCATION_VALIDATED',item.voiceIndex..' '..item.name..' playlist='..index)
            else S.failed=S.failed+1;A.log('VOICE_LOCATION_FAILED',item.voiceIndex..' '..item.name..' '..tostring(ready)) end
            S.voiceCheckAt=S.voiceCheckAt+1;A.nextScene(1);return
        end
        local item=(S.playlist or context().playlist)[S.storyIndex]
        if not item then return A.finish() end
        if item.kind=='scene' then S.index=item.sceneIndex;S.lastPlayableMap=A.scenes[S.index].map;A.scenesTick()
        elseif item.kind=='cinematic' then cinematicTick(item)
        elseif item.kind=='voice' then voiceTick(item)
        else error('Unsupported scene type: '..tostring(item.kind)) end
    end
    return M
end
