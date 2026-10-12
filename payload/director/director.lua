-- Story Director: dialogue replay and scene touring for BFBB Rehydrated.
-- Run only with the dedicated save profile; ordinary Steam launches are inert.
local ROOT = assert(_G.STORY_DIRECTOR_ROOT, 'Story Director installation root is missing')
local DATA = _G.STORY_DIRECTOR_DATA or (ROOT .. '/data')
local PROFILE = assert(_G.STORY_DIRECTOR_PROFILE, 'Dedicated save profile is missing')
local SESSION = assert(_G.STORY_DIRECTOR_SESSION, 'Launch session is missing')
assert(type(SESSION)=='string' and SESSION~='', 'Launch session is empty')
-- Defense in depth: the generated bootstrap checks this before loading this file.
local function normalizePath(value) return value:gsub('\\','/'):gsub('/+$',''):lower() end
local saved=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary'):GetProjectSavedDirectory():ToString()
if normalizePath(saved)~=normalizePath(PROFILE..'/Saved') then
    print('[StoryDirector] INACTIVE: save profile verification failed.\n');return
end
local subtitles=dofile(ROOT..'/subtitles.lua')
local catalog = dofile(DATA .. '/scenes.lua')
local scenes = catalog.scenes
local tourMaps={}
local excludedMaps={["BattleArena_P"]=true,["MainMenu_P"]=true,["MP_CharacerSelection_P"]=true,["MP_IntroMap_P"]=true,["MP_MainLevel_02_P"]=true,["SpongeBobDream_05_P"]=true,["ChumBucketLab_01_P"]=true}
for _,entry in ipairs(catalog.maps) do if not excludedMaps[entry.name] then tourMaps[#tourMaps+1]=entry end end
catalog.maps=tourMaps
local contextual
local S = {mode='story', audioMode='normal', playlistMode='all', storyIndex=1, phase='idle', paused=true, index=1, completed=0, failed=0,
    title='Ready', message='Choose a scene to play.', now=0,
    phaseAt=0, lineAt=0, lastIndex=-1, statusAt=0, validation=false, voiceIndex=1, tourIndex=1}
local function valid(o) return o and o:IsValid() end
local function full(o) return valid(o) and o:GetFullName() or '' end
local function simple(s) return (s or ''):lower():gsub('[^a-z0-9]','') end
local function quote(s)
    return '"'..tostring(s or ''):gsub('[%z\1-\31\\"]',function(c)
        return ({['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'})[c] or string.format('\\u%04x',c:byte())
    end)..'"'
end
local function json(t)
    local p={};for k,v in pairs(t) do
        p[#p+1]=quote(k)..':'..(type(v)=='number' and tostring(v) or type(v)=='boolean' and tostring(v) or quote(v))
    end;return '{'..table.concat(p,',')..'}'
end
local function write(name,text)
    local f=io.open(ROOT..'/'..name,'w');if f then f:write(text);f:close() end
end
local function log(event,detail)
    print('[StoryDirector] '..event..' '..tostring(detail or '')..'\n')
    local f=io.open(ROOT..'/session.jsonl','a');if f then
        f:write(json({time=os.date('!%Y-%m-%dT%H:%M:%SZ'),event=event,sceneIndex=S.index,mode=S.mode,sessionId=SESSION,detail=detail or ''})..'\n');f:close()
    end
end
local function status()
    local total=S.mode=='story' and contextual.total() or S.mode=='voices' and #(S.extras and S.extras.voices or {}) or S.mode=='tour' and #catalog.maps or #scenes
    write('status.json',json({sessionId=SESSION,profile=PROFILE,audioMode=S.audioMode,phase=S.phase,singleScene=S.singleScene==true,sourceIndex=S.mode=='story' and contextual.sourceIndex() or S.index,mode=S.mode,status=S.paused and 'paused' or S.phase,sceneIndex=S.mode=='story' and S.storyIndex or S.mode=='voices' and S.voiceIndex or S.mode=='tour' and S.tourIndex or S.index,totalScenes=total,
        playlistMode=S.mode=='story' and (S.playlistMode or 'all') or S.mode,title=S.title,map=S.map or '',lineIndex=S.line or 0,lineCount=S.lineCount or 0,message=S.message or '',error=S.error or '',currentText=S.text or '',completedCount=S.completed,failedCount=S.failed}))
end
local function gp() return StaticFindObject('/Script/Engine.Default__GameplayStatics') end
local function gi() return FindFirstOf('PINE_GameInstance') end
local function pc()
    local g=gi();if not valid(g) then return nil end
    local c=gp():GetPlayerController(g,0);return valid(c) and c or nil
end
local function player()
    local c=pc();if not valid(c) then return nil end
    local p=c:K2_GetPawn();return valid(p) and p or nil
end
local function actorWorld(a) return valid(a) and full(a:GetOuter().OwningWorld) or '' end
local function manager()
    -- Each playable pawn creates a manager. An earlier pawn's manager can survive a switch.
    local p=player();local c=pc();if not valid(p) or not valid(c) then return nil end
    local m=p.NewDialogueManager
    return valid(m) and actorWorld(m)==full(c:GetWorld()) and m or nil
end
local function mapNow()
    local p=pc();if valid(p) then return full(p:GetWorld()):match('World (.-)%.') or '' end
    local instance=gi();if valid(instance) then return full(instance:GetWorld()):match('World (.-)%.') or '' end
    return ''
end
local npcCache,npcCacheWorld={},''
local function objectPath(o) return full(o):match('^[^ ]+ (.+)$') end
local function resolveAsset(path)
    if not path then return nil end
    local asset=LoadAsset(path)
    assert(valid(asset),'Could not reload dialogue data: '..path)
    return asset
end
local function restoreNpc()
    local original=S.originalNpc
    if original then
        -- Lua wrappers do not keep detached Unreal assets alive across garbage collection.
        local actor=StaticFindObject(original.actorPath)
        local controller=pc()
        if valid(actor) and valid(controller) and actorWorld(actor)==full(controller:GetWorld()) then
            actor:SetDialogueData(resolveAsset(original.questPath),resolveAsset(original.singlePath))
        end
    end
    S.originalNpc=nil
end
local function clearDialogueManager(m,orphan)
    local wasActive=m['CurrentDialogue?']
    if wasActive then m:OnDialogueSpoken(true) end
    local n=m.DialogueNpc
    m['CurrentDialogue?']=false
    if wasActive and valid(n) and n['IsDialogueActive?'] then n:EndConversation(0) end
    if valid(m.AudioManager) then m.AudioManager:ClearTimerHandler();m.AudioManager:UnbindSpeakerEvents() end
    if valid(m.DialogueWidget) then m.DialogueWidget:StopAllAnimations();m.DialogueWidget:SetVisibility(2) end
    if valid(m.MainWidget) then
        m.MainWidget:StopAllAnimations();m.MainWidget:OnDialogueEnded()
        if orphan then m.MainWidget:SetVisibility(2);m.MainWidget:RemoveFromParent() end
    end
    if valid(m.DialogueSpeaker) then m.DialogueSpeaker:Stop() end
end
local function clearOrphanDialogueManagers()
    local current=manager()
    for _,m in ipairs(FindAllOf('BP_NewDialogueManager_C') or {}) do
        if valid(m) and full(m)~=full(current) then clearDialogueManager(m,true) end
    end
end
local function stopNativeDialogue()
    clearOrphanDialogueManagers()
    local m=manager();if valid(m) then clearDialogueManager(m,false) end
end
local function stopConversation()
    stopNativeDialogue()
    if valid(S.audio) then S.audio:Stop();S.audio=nil end
    restoreNpc()
    if contextual then contextual.cleanup() end
end
local function resetPhase()
    stopConversation();S.phase='prepare';S.phaseAt=S.now;S.stableAt=nil;S.error=nil;S.line=0;S.text='';S.lastIndex=-1;S.sublevelAt=nil;S.captionText=nil;S.pauseAt=S.paused and S.now or nil
end
local function nextScene(delta,completed)
    if completed and S.singleScene then
        resetPhase();S.phase='complete';S.paused=true;S.message='Scene complete.'
        if valid(pc()) then gp():SetGamePaused(pc(),true) end
        log('SINGLE_COMPLETE',S.title);return
    end
    S.replayRetryKey=nil;S.replayRetryCount=0
    resetPhase()
    if S.mode=='story' then S.storyIndex=S.storyIndex+delta
    elseif S.mode=='voices' then S.voiceIndex=S.voiceIndex+delta
    elseif S.mode=='tour' then S.tourIndex=S.tourIndex+delta
    else S.index=S.index+delta end
end
local function finish()
    S.phase='complete';S.paused=true;S.message='Playlist complete. Completed: '..S.completed..'; failed: '..S.failed..'. See session.jsonl.';log('COMPLETE',S.message)
end
local function fail(err)
    S.failed=S.failed+1;S.error=tostring(err);log('FAILED',S.error)
    S.message='Stopped at an error. Choose Next to continue, or replay this scene.'
    if S.validation and not S.singleCheck then nextScene(1) else S.singleCheck=false;S.paused=true;S.phase='error' end
end
local function findNpc(scene)
    local c=pc();local world=valid(c) and full(c:GetWorld()) or ''
    if npcCacheWorld~=world then npcCache={};npcCacheWorld=world end
    local exact,hinted={},{}
    for _,n in ipairs(FindAllOf('BP_NewDialogueNPC_C') or {}) do
        if actorWorld(n)==world then
            local key=full(n);local original=npcCache[key]
            if not original or not valid(original.actor) then
                original={actor=n,actorPath=objectPath(n),questPath=objectPath(n.TargetQuest),singlePath=objectPath(n.SingleSentence),paths={}}
                local quest,single=n.TargetQuest,n.SingleSentence
                original.paths[#original.paths+1]=full(single)
                if valid(quest) then quest.DialogueDataAssets:ForEach(function(_,asset) original.paths[#original.paths+1]=full(asset:get()) end) end
                npcCache[key]=original
            end
            local owns=false
            for _,path in ipairs(original.paths) do if path:lower():find(scene.objectPath:lower(),1,true) then owns=true end end
            if owns then exact[#exact+1]=original else
                for _,hint in ipairs(scene.npcHints or {}) do
                    if #hint>2 and simple(key):find(simple(hint),1,true) then hinted[#hinted+1]=original;break end
                end
            end
        end
    end
    local candidates=#exact>0 and exact or hinted
    assert(#candidates>0,'Could not find the speaker for '..scene.id..'. No other speaker was used.')
    local chosen=candidates[1]
    if #exact==0 then log('NPC_NAME_MATCH',scene.id..' -> '..full(chosen.actor)) end
    S.originalNpc=chosen
    return chosen.actor,#exact>0 and 1000 or 20
end
local function floorPoint(anchor,p,x,y,ignore)
    -- Start above the floor; collision-aware teleport and character gravity settle the capsule.
    return {X=x,Y=y,Z=anchor.Z+p.CapsuleComponent:GetScaledCapsuleHalfHeight()+96}
end
local function placeInArea(actor,p,component)
    local anchor=valid(component) and component:K2_GetComponentLocation() or actor:K2_GetActorLocation()
    local point=floorPoint(anchor,p,anchor.X,anchor.Y,actor)
    local radius=valid(component) and component:IsA('/Script/Engine.SphereComponent') and component:GetScaledSphereRadius() or nil
    local candidates={point}
    if radius then
        -- A trigger is a region, and its centre can be inside an NPC or scenery.
        -- Keep all retries within the live sphere and let TeleportTo test capsule collision.
        candidates[#candidates+1]={X=anchor.X,Y=anchor.Y,Z=anchor.Z}
        for _,height in ipairs({0,p.CapsuleComponent:GetScaledCapsuleHalfHeight(),-p.CapsuleComponent:GetScaledCapsuleHalfHeight()}) do
            for _,fraction in ipairs({0.25,0.5,0.75}) do
                for step=0,7 do
                    local angle=step*math.pi/4
                    candidates[#candidates+1]={X=anchor.X+math.cos(angle)*radius*fraction,Y=anchor.Y+math.sin(angle)*radius*fraction,Z=anchor.Z+height}
                end
            end
        end
    end
    local function inside(q)
        if not radius then return true end
        local x,y,z=q.X-anchor.X,q.Y-anchor.Y,q.Z-anchor.Z
        return x*x+y*y+z*z<=radius*radius
    end
    local placed,attempts=false,0
    for _,candidate in ipairs(candidates) do
        if inside(candidate) then
            attempts=attempts+1
            if p:K2_TeleportTo(candidate,p:K2_GetActorRotation()) then
                local actual=p:K2_GetActorLocation()
                if inside(actual) then point=actual;placed=true;break end
            end
        end
    end
    assert(placed,'Could not find a clear position in this scene: '..full(actor))
    p.CharacterMovement:StopMovementImmediately()
    log('VOICE_LOCATION',full(actor)..' x='..point.X..' y='..point.Y..' z='..point.Z..' attempts='..attempts..' radius='..tostring(radius or 'not-spherical'))
end
local function placeAtSpeaker(n,p)
    local marker=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary'):Conv_SoftObjectReferenceToObject(n.DialoguePlayerLocation)
    local point,source
    if valid(marker) then
        point=StaticFindObject('/Script/Pineapple.Default__PINE_ActorUtils'):GetCharacterSpawnLocationFromPlayerStart(marker,p)
        source='authored-player-start'
    else
        local f=n:GetActorForwardVector();local anchor=n:K2_GetActorLocation();point=floorPoint(anchor,p,anchor.X+f.X*180,anchor.Y+f.Y*180,n)
        source='beside-original-speaker'
    end
    local target=n:K2_GetActorLocation();local r=p:K2_GetActorRotation();r.Yaw=math.deg(math.atan(target.Y-point.Y,target.X-point.X));r.Pitch=0;r.Roll=0
    local placed
    if source=='authored-player-start' then placed=p:K2_SetActorLocation(point,false,{},true) else
        placed=p:K2_TeleportTo(point,r)
        if not placed then
            local anchor=n:K2_GetActorLocation();local base=math.atan(point.Y-anchor.Y,point.X-anchor.X)
            for _,radius in ipairs({280,400,180,550}) do
                for _,offset in ipairs({0,math.pi/4,-math.pi/4,math.pi/2,-math.pi/2,math.pi}) do
                    local candidate=floorPoint(anchor,p,anchor.X+math.cos(base+offset)*radius,anchor.Y+math.sin(base+offset)*radius,n)
                    if p:K2_TeleportTo(candidate,r) then point=candidate;placed=true;break end
                end
                if placed then break end
            end
        end
    end
    assert(placed,'Could not position the player near the speaker: '..full(n)..' placement='..source)
    p.CharacterMovement:StopMovementImmediately();pc():SetControlRotation(r)
    S.locationSource=source;S.actor=full(n)
    log('REPLAY_LOCATION',source..' actor='..full(n)..' x='..point.X..' y='..point.Y..' z='..point.Z)
end
local function cheat()
    local controller=pc();if not valid(controller) then return nil end
    if valid(controller.CheatManager) then return controller.CheatManager end
    local c=StaticFindObject('/Game/Blueprints/Utils/BP_CheatManager.BP_CheatManager_C')
    if not valid(c) then return nil end
    controller.CheatManager=StaticConstructObject(c,controller);return controller.CheatManager
end
local function switchCharacter(name)
    if not name or name=='Any' then return false end
    local p=player();if not valid(p) then return false end
    local c=cheat();assert(valid(c),'Character switching is unavailable')
    local index,target
    c.PlayableCharacter:ForEach(function(i,v)
        local class=v:get()
        if simple(full(class):match('([^./]+)$'))==simple('BP_'..name..'_C') or simple(full(class):match('([^./]+)$'))==simple(name..'_C') then index=i-1;target=class end
    end)
    -- Match only the class name: a SpongeBob pawn in SandyHouse is still SpongeBob.
    if not target then
        c.PlayableCharacter:ForEach(function(i,v)
            local class=v:get();local className=full(class):match('([^./]+)$') or ''
            if simple(className):find(simple(name),1,true) then index=i-1;target=class end
        end)
    end
    assert(index~=nil and valid(target),'Character is unavailable: '..name)
    if full(p:GetClass())==full(target) then
        if S.switchAt then log('CHARACTER_READY',name..' pawn='..full(p));clearOrphanDialogueManagers() end
        S.switchAt=nil;return false
    end
    if S.switchAt then assert(S.now-S.switchAt<30,'Character change timed out: '..name..' current='..full(p));return true end
    stopNativeDialogue()
    S.switchAt=S.now;log('CHARACTER_CHANGE',name..' from '..full(p));c:PINE_ChangeCharacter(index);return true
end
local function sourceSentences(a,scene)
    if scene.variant=='Info' or scene.variant=='InfoSentence' then return a.InfoSentence.Sentences end
    if scene.conditionalIndex~=nil then return a.ConditionalDialogues[scene.conditionalIndex+1].Dialogue.Sentences end
    return a[scene.variant].Sentences
end
local function showLine(n,index)
    local m=manager()
    if m['CurrentDialogue?'] then m:OnDialogueSpoken(true) end
    n.SentenceIndex=index
    m['CurrentDialogue?']=false
    m['DialogueFinished?']=false
    n:HandleCamera({})
    n:ShowNextDialogue(index)
end
local function startScene(scene)
    log('PREPARE_ACTOR',scene.id)
    local p=player();assert(valid(p),'Player is not ready');p:SetInvincibility(true);p.CanNotDrown=true
    local n,score=findNpc(scene);log('PREPARE_ASSET',scene.id);assert(valid(n),'The speaker is missing from this area')
    local a=LoadAsset(scene.objectPath);assert(valid(a),'Could not load dialogue data: '..scene.objectPath)
    log('PREPARE_VARIANTS',scene.id)
    local flat,variants={},{}
    sourceSentences(a,scene):ForEach(function(sentenceIndex,s)
        s:get().SentenceData:ForEach(function(variantIndex,v)
            if (S.playlistMode~='dialogue' and S.playlistMode~='voiced') or S.mode~='story' or contextual.lineIsVoiced(S.index,sentenceIndex-1,variantIndex-1) then
                flat[#flat+1]=s:get();variants[#variants+1]=v:get()
            end
        end)
    end)
    assert(#flat>0,'The scene has no playable lines')
    local clone=StaticConstructObject(StaticFindObject('/Script/Pineapple.PINE_DialogueEntryDataAsset'),n)
    clone.AsSpongeBob.Sentences=flat
    clone.AsSpongeBob.NegativeResponseStartIndex=-1
    clone.AsSpongeBob.ShouldMovePlayerCharacterToDialoguePlayerLocation=true
    clone.AsSpongeBob.Sentences:ForEach(function(i,s)
        local line=s:get();line.SentenceData={variants[i]};line.ActionsAtEndOfSentence={};line.DialogueButtons=0
        line.SentenceData[1].SkipToNextDialogueAfter=0
    end)
    clone.AsPatrick=clone.AsSpongeBob;clone.AsSandy=clone.AsSpongeBob
    log('PREPARE_LOCATION',scene.id)
    n:SetDialogueData(nil,clone)
    n.SentenceIndex=0
    -- Preserve the original dialogue cameras, voices and animations; only quest actions are omitted.
    if S.checkLocations then placeAtSpeaker(n,p) end
    if not S.validation then
        StaticFindObject('/Script/Pineapple.Default__PINE_ActorUtils'):SetActorActive(n,true)
        n:SetActorHiddenInGame(false)
        if valid(n.Mesh) then n.Mesh:SetHiddenInGame(false,false);n.Mesh:SetVisibility(true,false) end
        if valid(n.PINE_Culling) then n.PINE_Culling.IsMeshCullingEnabled=false;n.PINE_Culling.ShouldCullAnimationsWithMesh=false end
        placeAtSpeaker(n,p)
        log('PREPARE_NATIVE_DIALOGUE',scene.id)
        local m=manager();assert(valid(m),'The player dialogue system is not ready')
        if valid(m.MainWidget) then m.MainWidget:SetVisibility(0);if not m.MainWidget:IsInViewport() then m.MainWidget:AddToViewport(0) end end
        m['CurrentDialogue?']=false
        p:StartDialogueWithNPC(n)
        if not n['IsDialogueActive?'] then n:StartDialogueWithPlayer(p) end
        p.NearbyNPC=n;m.PlayerCharacter=p;m.DialogueNpc=n;m.EndOfDialogueResult=0
        if not m['CurrentDialogue?'] or m.CurrentDialogueIndex~=0 then showLine(n,0) end
    end
    S.heardLines={};S.lastAdvanceAt=-1
    S.npc=n;S.lineCount=#flat;S.phase='playing';S.phaseAt=S.now;S.lineAt=S.now;S.lastIndex=-1
    S.title=scene.name..' / '..scene.variant;S.message='Playing dialogue.'
    log('SCENE_STARTED',scene.id..' lines='..#flat..' npc='..full(n))
    write('checkpoint.txt',tostring(S.index))
end
local audioManagerKey
local normalAudioSettings
local function ensureAudioSettings()
    local g=gi();if not valid(g) then return false end
    if not valid(g.SaveOptions) then
        local options=gp():LoadGameFromSlot('UserSettings',0)
        if valid(options) and full(options):find('SaveOptions_C',1,true) then
            g.SaveOptions=options;log('AUDIO_SETTINGS_LOADED','UserSettings from isolated replay profile')
        else
            g:InitUserSettings();log('AUDIO_SETTINGS_LOADED','Native defaults for new replay profile')
        end
        assert(valid(g.SaveOptions),'Could not load audio settings')
        g.HasLoadedUserSettings=true
    end
    local cfg=g.GameConfigManager;if not valid(cfg) then return false end
    local options=g.SaveOptions
    if not normalAudioSettings then normalAudioSettings={MusicVolume=options.MusicVolume,SFXVolume=options.SFXVolume,SpeechVolume=options.SpeechVolume} end
    local volumes=S.audioMode=='speech' and {MusicVolume=0,SFXVolume=0,SpeechVolume=1} or normalAudioSettings
    for name,value in pairs(volumes) do options[name]=value end
    local key=full(cfg)..':'..full(options)..':'..S.audioMode
    if audioManagerKey~=key then
        cfg.SaveOptionsRef=g.SaveOptions
        cfg:ApplyAudioSettings()
        audioManagerKey=key
        local options=g.SaveOptions
        log('AUDIO_SETTINGS_APPLIED','effects='..tostring(options.SFXVolume)..' music='..tostring(options.MusicVolume)..' speech='..tostring(options.SpeechVolume))
    end
    return true
end
local function ensureMap(map,requirePlayer)
    contextual.suppressAutomaticCinematics()
    if mapNow():lower()==map:lower() and (requirePlayer==false or valid(player())) then
        if not ensureAudioSettings() then return false end
        local g=gi();local engine=FindFirstOf('GameEngine')
        if valid(engine) and engine.DisplayGamma<=0.5 and valid(g.GameConfigManager) then
            g.GameConfigManager:ChangeGamma(g.Default_Gamma);log('DISPLAY_DEFAULT_RESTORED','gamma='..engine.DisplayGamma)
        end
        if not S.stableAt then S.stableAt=S.now end
        local ready=S.now-S.stableAt>=(S.validation and 0.25 or 2.0)
        if ready then
            StaticFindObject('/Script/Pineapple.Default__PINE_UiUtils'):HideLoadingScreen(g)
            clearOrphanDialogueManagers()
        end
        return ready
    end
    S.stableAt=nil
    if S.phase~='travel' then
        local g=gi();assert(valid(g),'Game instance is not ready')
        g.CurrentSaveSlot='StoryDirector'
        if valid(g.SaveManager) then g.SaveManager:SetAutoSaveDeferred(true) end
        g:RequestLevelChange(FName(map:match('[^/]+$')),FName('None'),true,false)
        S.phase='travel';S.phaseAt=S.now;S.map=map;S.message='Loading '..map:match('[^/]+$');log('TRAVEL',map)
    elseif S.now-S.phaseAt>90 then error('Map load timed out: '..map) end
    return false
end
local function loadExtras()
    if not S.extras then S.extras=dofile(DATA..'/extras.lua') end
end
local function voicesTick()
    loadExtras();local item=S.extras.voices[S.voiceIndex]
    if not item then return finish() end
    local map='/Game/Maps/BikiniBottom/SpongeBobHouse/SpongeBobHouse_P';S.map=map
    if S.phase~='voice' then
        if not ensureMap(map) then return end
        stopConversation()
        local sound=LoadAsset(item.objectPath);assert(valid(sound),'Voice audio is missing: '..tostring(item.objectPath))
        S.audio=gp():SpawnSound2D(pc(),sound,1.0,1.0,0.0,nil,false,false)
        assert(valid(S.audio),'Could not start audio playback')
        S.phase='voice';S.phaseAt=S.now;S.title=item.objectPath:match('%.([^%.]+)$') or item.objectPath
        S.text=subtitles.voice(item,sound,0);S.message='Playing voice line.'
        log('VOICE_STARTED',item.objectPath)
    else
        local item=S.extras.voices[S.voiceIndex];local elapsed=S.now-S.phaseAt
        for _,sub in ipairs(item.timedSubtitles or {}) do
            local start=sub.start or sub.startTime or sub.startTimeInSec or 0
            local stop=sub.stop or sub.stopTime or sub.stopTimeInSec or start+5
            if elapsed>=start and elapsed<=stop then S.text=subtitles.cinematic(sub,item) end
        end
        if elapsed>0.75 and (not valid(S.audio) or not S.audio:IsPlaying()) then
            S.completed=S.completed+1;log('VOICE_FINISHED',item.objectPath);nextScene(1,true)
        elseif elapsed>600 then error('Voice playback timed out') end
    end
end
-- Interrupted native conversations must replay in full before they can count as complete.
local function retryInterruptedScene(scene,missingLine,m)
    local key=S.mode..':'..tostring(S.mode=='story' and S.storyIndex or S.index)..':'..scene.id
    if S.replayRetryKey~=key then S.replayRetryKey=key;S.replayRetryCount=0 end
    local attempt=(S.replayRetryCount or 0)+1
    local audio=valid(m.DialogueSpeaker) and m.DialogueSpeaker:IsPlaying() or false
    local source=m.CurrentSentence.SentenceData
    local duration=source:GetArrayNum()>0 and valid(source[1].AudioSource) and source[1].AudioSource.Duration or 0
    local detail=scene.id..' line='..missingLine..' retry='..attempt..'/2 currentDialogue='..tostring(m['CurrentDialogue?'])..' npcActive='..tostring(valid(S.npc) and S.npc['IsDialogueActive?'] or false)..' audioPlaying='..tostring(audio)..' duration='..duration..' elapsed='..(S.now-S.lineAt)
    if attempt>2 then error('Conversation repeatedly ended before line '..missingLine..' was completed: '..detail) end
    S.replayRetryCount=attempt
    log('SCENE_RETRY',detail)
    resetPhase()
    S.message='Conversation interrupted. Retrying ('..attempt..'/2).'
end
local function scenesTick()
    local scene=scenes[S.index]
    local original=contextual.nativeContext(S.index);if scene and original and original.map then scene.map=original.map end
    if not scene then return finish() end
    if scene.bonus and not S.manual then nextScene(1);return end
    S.map=scene.map
    if S.phase=='ending' then
        if not valid(S.npc) or not S.npc['IsDialogueActive?'] then
            S.completed=S.completed+1;log('SCENE_FINISHED',scene.id);nextScene(1,true)
        elseif S.now-S.phaseAt>8 then error('The conversation did not finish closing: '..scene.id) end
        return
    end
    if S.phase~='playing' then
        if not ensureMap(scene.map) then return end
        if not contextual.prepareScene(S.index) then return end
        if switchCharacter(scene.character) then S.stableAt=S.now;return end
        if not S.validation then
            if S.phase~='dialogue-settle' then
                contextual.prepareNativeView();S.phase='dialogue-settle';S.phaseAt=S.now
                S.message='Preparing conversation...';return
            end
            -- Native EndConversation uses a latent fade callback. Let it finish before restarting.
            if S.now-S.phaseAt<1.5 then return end
        end
        startScene(scene);return
    end
    local m=manager();assert(valid(m),'The game dialogue system is not ready')
    if S.validation then
        S.completed=S.completed+1;log('VALIDATED',scene.id);if S.singleCheck then S.singleCheck=false;finish() else nextScene(1) end;return
    end
    if not m['CurrentDialogue?'] or not valid(S.npc) or not S.npc['IsDialogueActive?'] then
        if S.now-S.phaseAt>1 then
            for i=1,S.lineCount do
                if not S.heardLines[i] then retryInterruptedScene(scene,i,m);return end
            end
            S.completed=S.completed+1;log('SCENE_FINISHED',scene.id);nextScene(1,true)
        end
        return
    end
    local current=S.npc.SentenceIndex
    S.line=current+1
    if current~=S.lastIndex then
        S.lastIndex=current;S.lineAt=S.now
        local data=m.CurrentSentence.SentenceData
        if data:GetArrayNum()>0 then S.text=data[1].SpokenText:ToString():gsub('<Split>','\n'):gsub('<img.-id="([^"]+)".-/>','[%1]'):gsub('<[^>]+>','') end
        log('LINE',scene.id..' '..S.line..'/'..S.lineCount)
    end
    local playing=valid(m.DialogueSpeaker) and m.DialogueSpeaker:IsPlaying()
    local duration = 0
    if m.CurrentSentence.SentenceData:GetArrayNum()>0 and valid(m.CurrentSentence.SentenceData[1].AudioSource) then duration=m.CurrentSentence.SentenceData[1].AudioSource.Duration end
    local noAudio=m.CurrentSentence.SentenceData:GetArrayNum()==0 or not valid(m.CurrentSentence.SentenceData[1].AudioSource)
    local strings=m.CurrentStrings:GetArrayNum()
    if strings>1 and m.CurrentStringsIdx<strings and S.now-S.lineAt>duration*(m.CurrentStringsIdx/strings) then m:ProgressSentenceText() end
    local minimum=noAudio and math.max(2,math.min(15,#(S.text or '')/22)) or math.max(1.0, math.min(duration+0.25,120))
    if not playing and S.now-S.lineAt>minimum and S.now-S.lastAdvanceAt>0.75 then
        S.heardLines[current+1]=true
        if current+1>=S.lineCount then
            m['CurrentDialogue?']=false;S.npc:EndConversation(0);S.phase='ending';S.phaseAt=S.now
        else showLine(S.npc,current+1) end
        S.lastAdvanceAt=S.now
    end
    if S.now-S.lineAt>120 then error('Dialogue stopped responding: '..scene.id..' line '..S.line) end
end
local function tourTick()
    local item=catalog.maps[S.tourIndex];if not item then return finish() end
    local map=type(item)=='string' and item or item.map or item.gamePath
    assert(map,'Tour map is missing')
    if S.phase~='tour' then
        if not ensureMap(map,false) then return end
        local p=player();if valid(p) then p:SetInvincibility(true);p.CanNotDrown=true end
        S.phase='tour';S.phaseAt=S.now;S.title=map:match('[^/]+$');S.message='Scene tour: 20 seconds per map.';log('TOUR_LOADED',map)
    elseif S.now-S.phaseAt>20 then S.completed=S.completed+1;nextScene(1) end
end
local function command(cmd)
    local op,arg=cmd:match('^(%S+)%s*(.-)%s*$')
    if op=='play' or op=='voices' or op=='dialogue' or op=='voiced' or op=='cutscenes' or op=='story' or op=='scenes' or op=='scene' or op=='tour' then S.singleScene=false end
    if op=='play' or op=='voices' or op=='dialogue' or op=='voiced' or op=='cutscenes' then
        local playlistMode=(op=='dialogue' or op=='voiced' or op=='cutscenes') and op or 'all'
        if S.mode=='story' and S.playlistMode==playlistMode and not S.paused and not S.validation and S.phase~='complete' then log('COMMAND_IGNORED','Playlist already playing: '..playlistMode);return end
        S.mode='story';contextual.start(1,playlistMode);S.manual=false;S.validation=false;S.checkLocations=false;S.paused=false;resetPhase()
    elseif op=='watch' then
        local index=tonumber(arg);assert(index and index%1==0 and index>=1 and index<=contextual.total('all'),'Scene index is out of range')
        S.mode='story';contextual.start(index,'all');S.singleScene=true;S.manual=false;S.validation=false;S.checkLocations=false;S.paused=false;resetPhase()
    elseif op=='story' then local index=tonumber(arg);assert(index and index>=1 and index<=contextual.total('all'),'Story index is out of range');S.mode='story';contextual.start(index,'all');S.manual=false;S.validation=false;S.checkLocations=false;S.paused=false;resetPhase()
    elseif op=='scenes' then S.mode='scenes';S.index=1;S.manual=false;S.validation=false;S.checkLocations=false;S.paused=false;resetPhase()
    elseif op=='collect-garbage' then log('GC_REQUESTED','Replay stress test');StaticFindObject('/Script/Engine.Default__KismetSystemLibrary'):CollectGarbage()
    elseif op=='audio' then
        assert(arg=='speech' or arg=='normal','Choose audio speech or audio normal')
        S.audioMode=arg;audioManagerKey=nil;ensureAudioSettings()
        log('AUDIO_MODE',arg)
    elseif op=='audio-diagnose' then
        local g=gi();local cfg=g.GameConfigManager;local opts=g.SaveOptions
        log('AUDIO_SETTINGS','loaded='..tostring(g.HasLoadedUserSettings)..' options='..full(opts)..' manager='..full(cfg)..' managerOptions='..(valid(cfg) and full(cfg.SaveOptionsRef) or ''))
        if valid(opts) then log('AUDIO_VOLUMES','effects='..tostring(opts.SFXVolume)..' music='..tostring(opts.MusicVolume)..' speech='..tostring(opts.SpeechVolume)) end
        if valid(cfg) then for _,key in ipairs({'SoundFXVolume','MusicVolume','DialoguesVolume'}) do local value={};cfg:GetConfigValue(key,value,{});log('AUDIO_CONFIG',key..'='..value.Value:ToString()) end end
        local count=0
        for _,component in ipairs(FindAllOf('AudioComponent') or {}) do if component:IsPlaying() and count<15 then count=count+1;log('AUDIO_ACTIVE',full(component)..' sound='..full(component.Sound)..' volume='..tostring(component.VolumeMultiplier)) end end
    elseif op=='diagnose' then local g=gi();log('DISPLAY_DIAGNOSTIC','gamma='..FindFirstOf('GameEngine').DisplayGamma..' default='..tostring(g.Default_Gamma))
    elseif op=='inspect' then
        log('INSPECT_WORLD',full(pc():GetWorld()))
        for _,n in ipairs(FindAllOf('BP_NewDialogueNPC_C') or {}) do log('INSPECT_NPC',full(n)..' world='..full(n:GetWorld())..' quest='..full(n.TargetQuest)..' single='..full(n.SingleSentence)) end
    elseif op=='pause' then if not S.paused then S.pauseAt=S.now end;S.paused=true
    elseif op=='resume' then if S.phase=='complete' then status();return end;if S.paused and S.pauseAt then local d=S.now-S.pauseAt;for _,key in ipairs({'lineAt','phaseAt','stableAt','switchAt','sublevelAt','lastAdvanceAt'}) do if S[key] then S[key]=S[key]+d end end;S.pauseAt=nil end;S.paused=false;if S.phase=='idle' then S.phase='prepare' end
    elseif op=='next' then if S.phase=='error' then S.paused=false end;nextScene(1)
    elseif op=='previous' then
        if S.mode=='story' then S.storyIndex=math.max(2,S.storyIndex) elseif S.mode=='scenes' then S.index=math.max(2,S.index) elseif S.mode=='voices' then S.voiceIndex=math.max(2,S.voiceIndex) else S.tourIndex=math.max(2,S.tourIndex) end
        nextScene(-1)
    elseif op=='scene' then
        local index=tonumber(arg);assert(index and index>=1 and index<=#scenes,'Scene index is out of range')
        S.mode='scenes';S.index=index;S.manual=true;S.validation=false;S.checkLocations=false;S.paused=false;resetPhase()
    elseif op=='tour' then S.mode='tour';S.validation=false;S.tourIndex=1;S.paused=false;resetPhase()
    elseif op=='check-location' then S.mode='scenes';S.index=assert(tonumber(arg),'Scene index required');S.validation=true;S.checkLocations=true;S.singleCheck=true;S.manual=true;S.paused=false;resetPhase()
    elseif op=='validate-voice-locations' then S.mode='story';S.validation=true;S.singleCheck=false;S.checkLocations=false;S.paused=false;contextual.beginLocationChecks();resetPhase()
    elseif op=='validate-locations' then S.singleCheck=false; S.mode='scenes';S.index=tonumber(arg) or 1;S.validation=true;S.checkLocations=true;S.manual=false;S.paused=false;resetPhase()
    elseif op=='validate' then S.mode='scenes';S.index=tonumber(arg) or 1;S.validation=true;S.manual=false;S.paused=false;resetPhase()
    elseif op=='screenshot' then StaticFindObject('/Script/Engine.Default__KismetSystemLibrary'):ExecuteConsoleCommand(pc(),'Shot showui',pc())
    elseif op=='reload' then local chunk,err=loadfile(ROOT..'/director.lua');assert(chunk,err);stopConversation();S.paused=true;chunk();return
    elseif op=='quit' then
        stopConversation();S.paused=true;StaticFindObject('/Script/Engine.Default__KismetSystemLibrary'):QuitGame(pc(),pc(),0,false)
    end
    if valid(pc()) then gp():SetGamePaused(pc(),S.paused) end
    if valid(S.audio) then S.audio:SetPaused(S.paused) end
    if contextual then contextual.pause(S.paused) end
    log('COMMAND',cmd);status()
end
contextual=dofile(ROOT..'/contextual.lua')({state=S,root=ROOT,data=DATA,valid=valid,full=full,actorWorld=actorWorld,pc=pc,player=player,gp=gp,gi=gi,log=log,
    mapNow=mapNow,stopNativeDialogue=stopNativeDialogue,placeInArea=placeInArea,ensureMap=ensureMap,switchCharacter=switchCharacter,scenes=scenes,scenesTick=scenesTick,nextScene=nextScene,finish=finish})
local last=os.clock()
local function tick()
    local clock=os.clock();local delta=clock-last;last=clock;S.now=S.now+math.max(0.05,math.min(delta,1))
    local f=io.open(ROOT..'/command.txt','r');if f then local cmd=f:read('*l');f:close();os.remove(ROOT..'/command.txt');if cmd then command(cmd) end end
    clearOrphanDialogueManagers()
    contextual.suppressNativeBarks()
    if not S.paused then
        if S.phase=='idle' then S.phase='prepare' end
        if S.mode=='story' then contextual.tick() elseif S.mode=='scenes' then scenesTick() elseif S.mode=='voices' then voicesTick() else tourTick() end
    end
    if S.now-S.statusAt>=0.75 then status();S.statusAt=S.now end
end
local queued=false
local generation={}
_G.StoryDirectorGeneration=generation
RegisterBeginPlayPreHook(function(context)
    if _G.StoryDirectorGeneration~=generation then return end
    local actor=context:get()
    contextual.suppressAutomaticActor(actor)
end)
LoopAsync(250,function()
    if _G.StoryDirectorGeneration~=generation then return true end
    if queued then return false end;queued=true
    ExecuteInGameThread(function()
        local ok,err=pcall(tick);if not ok then fail(err);status() end;queued=false
    end)
    return false
end)
RegisterKeyBind(Key.F6,function() if _G.StoryDirectorGeneration==generation then ExecuteInGameThread(function() command(S.paused and 'resume' or 'pause') end) end end)
RegisterKeyBind(Key.F7,function() if _G.StoryDirectorGeneration==generation then ExecuteInGameThread(function() command('next') end) end end)
RegisterKeyBind(Key.F8,function() if _G.StoryDirectorGeneration==generation then ExecuteInGameThread(function() command('previous') end) end end)
_G.StoryDirector={state=S,command=command}
log('READY','Save profile verified: '..saved);status()
