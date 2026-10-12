import sys,json,hashlib,re
from pathlib import Path
dev=Path(__file__).resolve().parent
from lupa.lua54 import LuaRuntime
root=dev.parent/'payload'/'director'
lua=LuaRuntime(unpack_returned_tuples=True)
lua.globals().ROOT=root.as_posix()
setup=r"""
local originalDofile=dofile
TEST_WRITES={}
io.open=function(path,mode)
 if mode=='w' or mode=='a' then
  local data=mode=='a' and (TEST_WRITES[path] or '') or ''
  return {write=function(self,text) data=data..text;TEST_WRITES[path]=data end,close=function() end}
 end
 return nil
end
os.remove=function() error('Mock must never delete files') end
print=function() end
_G.STORY_DIRECTOR_ROOT=ROOT
_G.STORY_DIRECTOR_PROFILE=ROOT..'/Profile'
_G.STORY_DIRECTOR_SESSION='mock-session'
StaticFindObject=function(path)
 if path=='/Script/Engine.Default__KismetSystemLibrary' then
  return {GetProjectSavedDirectory=function() return {ToString=function() return ROOT..'/profile/Saved/' end} end}
 end
 return nil
end
FindFirstOf=function() return nil end
FindAllOf=function() return {} end
LoopAsync=function(interval,callback) TEST_LOOP=callback end
ExecuteInGameThread=function(callback) error('No live scheduling allowed') end
RegisterKeyBind=function() end
RegisterBeginPlayPreHook=function(callback) TEST_BEGIN_PLAY=callback end
Key={F6=6,F7=7,F8=8}
dofile=function(path)
 local result=originalDofile(path)
 if path==ROOT..'/contextual.lua' then
  return function(A)
   TEST_A=A
   A.scenesTick=function() TEST_LAST_NATIVE=A.state.index end
   A.ensureMap=function() return false end
   local module=result(A);TEST_CONTEXT=module;return module
  end
 end
 return result
end
originalDofile(ROOT..'/director.lua')
TEST_CASES={}
function check(name,fn)
 local ok,err=pcall(fn)
 TEST_CASES[#TEST_CASES+1]={name=name,passed=ok,error=not ok and tostring(err) or nil}
end
local S=_G.StoryDirector.state
local command=_G.StoryDirector.command
check('voiced includes every spoken category without text-only scenes',function()
 command('voiced')
 assert(S.mode=='story' and S.playlistMode=='voiced' and TEST_CONTEXT.total()==734)
 local counts={scene=0,cinematic=0,voice=0}
 for _,item in ipairs(S.playlist) do counts[item.kind]=counts[item.kind]+1 end
 assert(counts.scene==411 and counts.cinematic==37 and counts.voice==286)
 command('next');assert(S.storyIndex==2 and S.playlistMode=='voiced')
 command('previous');assert(S.storyIndex==1)
end)
check('cutscenes count and first entry',function()
 command('cutscenes')
 assert(S.mode=='story' and S.playlistMode=='cutscenes' and #S.playlist==37 and TEST_CONTEXT.total()==37)
 assert(S.storyIndex==1 and S.playlist[1].kind=='cinematic')
 TEST_CONTEXT.tick()
end)
check('next and previous retain filtered cursor',function()
 command('next');assert(S.storyIndex==2 and S.playlistMode=='cutscenes')
 command('previous');assert(S.storyIndex==1)
 command('previous');assert(S.storyIndex==1)
end)
check('filtered end stops after final cinematic',function()
 S.storyIndex=37;command('next');assert(S.storyIndex==38)
 TEST_CONTEXT.tick();assert(S.phase=='complete' and S.paused and TEST_CONTEXT.total()==37)
end)
check('dialogue count and native dispatch use filtered entries',function()
 command('dialogue')
 assert(TEST_CONTEXT.total()==411 and S.storyIndex==1)
 TEST_CONTEXT.tick();assert(TEST_LAST_NATIVE==S.playlist[1].sceneIndex)
 command('next');TEST_CONTEXT.tick();assert(TEST_LAST_NATIVE==S.playlist[2].sceneIndex)
 assert(S.storyIndex==2 and S.playlistMode=='dialogue')
end)
check('repeated active mode does not restart',function()
 local before=S.storyIndex;command('dialogue');assert(S.storyIndex==before)
end)
check('pause resume retains filtered cursor',function()
 local before=S.storyIndex;command('pause');assert(S.paused)
 command('resume');assert(not S.paused and S.storyIndex==before and S.playlistMode=='dialogue')
end)
check('long pause preserves loading and ending timeout budgets',function()
 local timerAges={lineAt=5,phaseAt=7,stableAt=2,switchAt=1,sublevelAt=1,lastAdvanceAt=0.5}
 S.now=100;S.phase='ending'
 for key,age in pairs(timerAges) do S[key]=S.now-age end
 local cursor=S.storyIndex
 command('pause');assert(S.pauseAt==100)
 S.now=280;command('pause');assert(S.pauseAt==100)
 S.now=400;command('resume')
 assert(not S.paused and S.pauseAt==nil and S.phase=='ending' and S.storyIndex==cursor)
 for key,age in pairs(timerAges) do assert(math.abs((S.now-S[key])-age)<0.0001,key..' aged during pause') end
 assert(S.now-S.switchAt<30 and S.now-S.sublevelAt<30 and S.now-S.phaseAt<8)
end)

check('source selection803 resets filtered dialogue to all',function()
 command('story 803')
 assert(S.playlistMode=='all' and S.storyIndex==803 and TEST_CONTEXT.total()==803)
end)
check('source selection803 resets filtered cutscenes to all',function()
 command('cutscenes');command('story 803')
 assert(S.playlistMode=='all' and S.storyIndex==803 and TEST_CONTEXT.total()==803)
end)
check('all mode clears filter and starts from beginning',function()
 command('dialogue');command('play')
 assert(S.storyIndex==1 and S.playlistMode=='all' and TEST_CONTEXT.total()==803)
end)
check('native manual selection exits filtered playback',function()
 command('dialogue');command('scene 30')
 assert(S.mode=='scenes' and S.index==30 and S.manual and not S.validation)
end)
check('invalid source selection rejected',function()
 assert(not pcall(function() command('story 804') end))
end)
check('invalid playlist mode rejected',function()
 assert(not pcall(function() TEST_CONTEXT.total('invalid') end))
 assert(not pcall(function() TEST_CONTEXT.start(1,'invalid') end))
 TEST_CONTEXT.start(1,'all')
end)
check('location check mode resets to all',function()
 command('dialogue');command('validate-voice-locations')
 assert(S.playlistMode=='all' and S.playlist==nil and #S.voiceCheckIndices==27 and TEST_CONTEXT.total()==803)
 command('play');assert(S.voiceCheckIndices==nil and S.playlistMode=='all')
end)
check('watch completes one entry without advancing its source cursor',function()
 command('watch 395');assert(S.storyIndex==395 and S.singleScene and not S.paused)
 TEST_A.nextScene(1,true)
 assert(S.storyIndex==395 and S.phase=='complete' and S.paused)
 command('resume');assert(S.paused and S.phase=='complete')
 command('watch 803');assert(S.storyIndex==803 and not S.paused)
 TEST_A.nextScene(1,true);assert(S.storyIndex==803 and S.phase=='complete' and S.paused)
end)
check('watch navigation keeps single-entry behavior and story clears it',function()
 command('watch 10');command('next');assert(S.storyIndex==11 and S.singleScene)
 command('previous');assert(S.storyIndex==10 and S.singleScene)
 command('story 10');assert(not S.singleScene)
 TEST_A.nextScene(1,true);assert(S.storyIndex==11 and not S.paused)
 command('watch 20');command('cutscenes');assert(not S.singleScene)
end)
check('invalid watch source cannot start playback',function()
 for _,value in ipairs({'0','804','1.5','oops'}) do assert(not pcall(function() command('watch '..value) end)) end
end)
check('session and profile are present in status',function()
 command('watch 20')
 local value=TEST_WRITES[ROOT..'/status.json']
 assert(value:find('"sessionId":"mock-session"',1,true))
 assert(value:find('"profile":"'..ROOT..'/Profile"',1,true))
 assert(value:find('"sourceIndex":20',1,true))
 assert(value:find('"singleScene":true',1,true))
end)
TEST_SCENES=originalDofile(ROOT..'/data/scenes.lua').scenes
"""
lua.execute(setup)
source=(root/'director.lua').read_text(encoding='utf-8-sig')
match=re.search(r'local flat,variants=\{\},\{\}\s*(sourceSentences\(a,scene\):ForEach\(.*?\n\s*end\))\s*assert\(#flat>0',source,re.S)
assert match,'Cannot identify exact installed line-selection block'
loop=lua.execute('return function(S,contextual,sourceSentences,a,scene) local flat,variants={},{} '+match.group(1)+' return flat,variants end')
lua.globals().TEST_LINE_LOOP=loop
lua.execute(r"""
local function ueArray(items)
 return {ForEach=function(self,fn)
  for i,item in ipairs(items) do fn(i,{get=function() return item end}) end
 end}
end
local function sentenceArray(scene)
 local sentences={}
 for _,sentence in ipairs(scene.sentences) do
  sentences[#sentences+1]={SentenceData=ueArray(sentence.lineVariants)}
 end
 return ueArray(sentences)
end
check('exact installed loop skips all text-only variants and keeps original order',function()
 local total=0
 for sceneIndex,scene in ipairs(TEST_SCENES) do
  if scene.defaultIncluded then
   local state={mode='story',playlistMode='dialogue',index=sceneIndex}
   local flat,variants=TEST_LINE_LOOP(state,TEST_CONTEXT,function() return sentenceArray(scene) end,nil,scene)
   local expected={}
   for _,sentence in ipairs(scene.sentences) do
    for _,variant in ipairs(sentence.lineVariants) do
     if TEST_CONTEXT.lineIsVoiced(sceneIndex,sentence.sentenceIndex,variant.lineVariantIndex) then expected[#expected+1]=variant end
    end
   end
   assert(#variants==#expected and #flat==#expected)
   for i,variant in ipairs(variants) do assert(variant==expected[i]) end
   total=total+#variants
  end
 end
 assert(total==1185)
end)
check('Gary branch retains8 voiced variants from12',function()
 local scene=TEST_SCENES[1]
 for _,mode in ipairs({'dialogue','voiced'}) do
  local flat=TEST_LINE_LOOP({mode='story',playlistMode=mode,index=1},TEST_CONTEXT,function() return sentenceArray(scene) end,nil,scene)
  assert(#flat==8)
 end
end)
check('all and manual native selection keep unvoiced lines',function()
 local scene=TEST_SCENES[1]
 for _,state in ipairs({{mode='story',playlistMode='all',index=1},{mode='scenes',playlistMode='dialogue',index=1}}) do
  local flat=TEST_LINE_LOOP(state,TEST_CONTEXT,function() return sentenceArray(scene) end,nil,scene)
  assert(#flat==12)
 end
end)
""")

# Verify the earliest guard in a fresh VM, before any catalog, I/O or hooks.
for saved in ['C:/NormalGame/Saved/', 'C:/DifferentProfile/Saved/']:
    isolated=LuaRuntime(unpack_returned_tuples=True)
    isolated.globals().ROOT=root.as_posix()
    isolated.globals().ACTUAL_SAVED=saved
    isolated.execute(r"""
        STORY_DIRECTOR_ROOT=ROOT;STORY_DIRECTOR_PROFILE=ROOT..'/Profile';STORY_DIRECTOR_SESSION='test-session'
        StaticFindObject=function() return {GetProjectSavedDirectory=function() return {ToString=function() return ACTUAL_SAVED end} end} end
        print=function() end
        dofile=function() error('Mismatched profile must not load a catalog') end
        LoopAsync=function() error('Mismatched profile must not register a loop') end
        RegisterKeyBind=function() error('Mismatched profile must not register input') end
    """)
    isolated.execute(source)
    assert isolated.globals().StoryDirector is None
lua.execute(r"""
check('runtime subtitle sources resolve without distributed text',function()
 local originalFind,originalLoad=StaticFindObject,LoadAsset
 local function txt(value) return {ToString=function() return value end} end
 local function array(values)
  local a=values
  a.ForEach=function(self,fn) for i,value in ipairs(values) do if fn(i,{get=function() return value end}) then return end end end
  return a
 end
 local assets={
  bark={IsValid=function() return true end,PossibleLines=array({{SpokenText=txt('Bark from the game')}})},
  table={IsValid=function() return true end,FindRow=function(self,name) assert(name=='Row_A');return {Text=txt('Announcer from the game')} end}
 }
 local sound={IsValid=function() return true end,GetFullName=function() return 'SoundWave /Game/Audio.Movie' end}
 assets['/Game/Sequences/DA_CutScenes.DA_CutScenes']={IsValid=function() return true end,Cutscenes=array({{AudioFile=sound,Lines=array({{SpokenText=txt('Cinematic from the game')}})}})}
 LoadAsset=function(path) return assets[path] end
 StaticFindObject=function() return {FindTextInLocalizationTable=function(self,namespace,key,out) out.OutText=txt('Localized '..key);return true end} end
 local subtitles=dofile(ROOT..'/subtitles.lua')
 local cues={IsValid=function() return true end,Subtitles=array({{Time=0,Text=txt('First cue')},{Time=2,Text=txt('Second cue')}})}
 assert(subtitles.voice({objectPath='cues'},cues,0)=='First cue')
 assert(subtitles.voice({objectPath='cues'},cues,3)=='Second cue')
 assert(subtitles.voice({objectPath='bark',subtitleSources={{category='bark',asset='bark',propertyPath='PossibleLines.0'}}},nil,0)=='Bark from the game')
 assert(subtitles.voice({objectPath='announcer',subtitleSources={{category='announcer',asset='table',propertyPath='Rows.Row_A'}}},nil,0)=='Announcer from the game')
 assert(subtitles.voice({objectPath='fallback',subtitleSources={{textKey='ID_ONLY'}}},nil,0)=='Localized ID_ONLY')
 assert(subtitles.cinematic({sourcePropertyPath='CutScenes.guid.Lines.0'},{objectPath='/Game/Audio.Movie'})=='Cinematic from the game')
 assert(subtitles.cinematic(nil)=='' and subtitles.voice({objectPath='missing'},nil,0)=='')
 StaticFindObject,LoadAsset=originalFind,originalLoad
end)
""")
# Exercise the actual ownership, character and audio helpers with small engine doubles.
def helper(start, stop, arguments, returns):
    block=source[source.index(start):source.index(stop,source.index(start))]
    return lua.execute('return function('+arguments+') '+block+' return '+returns+' end')
lua.globals().TEST_MANAGER_HELPER=helper('local function manager()', 'local function mapNow()', 'player,pc,valid,actorWorld,full', 'manager')
lua.globals().TEST_CLEAR_HELPER=helper('local function clearDialogueManager', 'local function stopConversation()', 'manager,valid,full', 'clearOrphanDialogueManagers,stopNativeDialogue')
lua.globals().TEST_SWITCH_HELPER=helper('local function switchCharacter', 'local function sourceSentences', 'S,player,cheat,valid,full,simple,log,clearOrphanDialogueManagers,stopNativeDialogue', 'switchCharacter')
lua.globals().TEST_AUDIO_HELPER=helper('local audioManagerKey', 'local function ensureMap', 'S,gi,gp,valid,full,log', 'ensureAudioSettings')
lua.execute(r"""
local function valid(value) return value and value:IsValid() end
local function full(value) return valid(value) and value:GetFullName() or '' end
local function object(name)
 return {IsValid=function() return true end,GetFullName=function() return name end}
end
local function array(values)
 values.ForEach=function(self,fn) for i,value in ipairs(values) do fn(i,{get=function() return value end}) end end
 return values
end
check('controlled pawn owns selected manager even when older manager is first',function()
 local old,new=object('old-manager'),object('new-manager')
 local world=object('World /Game/SandyHouse_P.SandyHouse_P')
 local p={NewDialogueManager=new};local controller={GetWorld=function() return world end}
 local get=TEST_MANAGER_HELPER(function() return p end,function() return controller end,function(v) return v~=nil end,function() return full(world) end,full)
 assert(get()==new)
 p.NewDialogueManager=nil;assert(get()==nil)
end)
check('orphan manager widgets are removed and controlled widgets stay attached',function()
 local function widget()
  local w=object('widget');w.removed=0;w.hidden=0;w.stops=0
  w.StopAllAnimations=function(self) self.stops=self.stops+1 end
  w.SetVisibility=function(self,value) self.hidden=value end
  w.RemoveFromParent=function(self) self.removed=self.removed+1 end
  w.OnDialogueEnded=function() end
  return w
 end
 local old,new=object('old-manager'),object('new-manager')
 for _,m in ipairs({old,new}) do m.MainWidget=widget();m.DialogueWidget=widget();m.DialogueSpeaker=object('speaker');m.DialogueSpeaker.Stop=function(self) self.stopped=true end end
 local ending=object('old-npc');ending['IsDialogueActive?']=true;ending.ends=0
 ending.EndConversation=function(self) self.ends=self.ends+1 end
 old.DialogueNpc=ending;old['CurrentDialogue?']=true;old.OnDialogueSpoken=function() end
 local saved=FindAllOf;FindAllOf=function() return {old,new} end
 local prune,stop=TEST_CLEAR_HELPER(function() return new end,valid,full)
 prune();assert(old.MainWidget.removed==1 and old.MainWidget.hidden==2 and old.DialogueWidget.hidden==2 and old.DialogueSpeaker.stopped)
 assert(new.MainWidget.removed==0 and not new.DialogueSpeaker.stopped)
 stop();assert(new.MainWidget.removed==0 and new.DialogueWidget.hidden==2 and new.DialogueSpeaker.stopped)
 assert(ending.ends==1,'Repeated cleanup restarted a closing fade')
 FindAllOf=saved
end)
check('SandyHouse path does not turn a SpongeBob pawn into Sandy',function()
 local sponge=object('BlueprintGeneratedClass /Game/BP_SpongeBob.BP_SpongeBob_C')
 local sandy=object('BlueprintGeneratedClass /Game/BP_Sandy.BP_Sandy_C')
 local p=object('BP_SpongeBob_C /Game/Maps/SandyHouse_P.PersistentLevel.BP_SpongeBob_C_0')
 p.GetClass=function() return sponge end
 local c=object('cheat');c.PlayableCharacter=array({sponge,sandy});local changes=0
 c.PINE_ChangeCharacter=function(self,index) assert(index==1);changes=changes+1 end
 local state={now=5};local pruned=0
 local change=TEST_SWITCH_HELPER(state,function() return p end,function() return c end,valid,full,function(v) return (v or ''):lower():gsub('[^a-z0-9]','') end,function() end,function() pruned=pruned+1 end,function() end)
 assert(not change('SpongeBob') and changes==0)
 assert(change('Sandy') and changes==1)
 assert(change('Sandy') and changes==1)
 p.GetClass=function() return sandy end
 assert(not change('Sandy') and state.switchAt==nil and pruned==1)
end)
check('speech audio restores copied preferences and reapplies after manager replacement',function()
 local settings=object('SaveOptions_C copied');settings.MusicVolume=0.17;settings.SFXVolume=0.43;settings.SpeechVolume=0.79
 local cfg=object('config1');local applied=0;cfg.ApplyAudioSettings=function() applied=applied+1 end
 local g=object('game');g.SaveOptions=settings;g.GameConfigManager=cfg
 local state={audioMode='normal'}
 local apply=TEST_AUDIO_HELPER(state,function() return g end,function() error('Must use existing copied settings') end,valid,full,function() end)
 assert(apply() and applied==1)
 state.audioMode='speech';assert(apply() and applied==2)
 assert(settings.MusicVolume==0 and settings.SFXVolume==0 and settings.SpeechVolume==1)
 assert(apply() and applied==2)
 local cfg2=object('config2');cfg2.ApplyAudioSettings=cfg.ApplyAudioSettings;g.GameConfigManager=cfg2
 assert(apply() and applied==3 and cfg2.SaveOptionsRef==settings)
 state.audioMode='normal';assert(apply() and applied==4)
 assert(settings.MusicVolume==0.17 and settings.SFXVolume==0.43 and settings.SpeechVolume==0.79)
end)
check('audio commands publish their mode and reject unknown mixes',function()
 local command=StoryDirector.command
 command('audio speech');assert(StoryDirector.state.audioMode=='speech')
 assert(TEST_WRITES[ROOT..'/status.json']:find('"audioMode":"speech"',1,true))
 assert(not pcall(function() command('audio loud') end))
 command('audio normal');assert(StoryDirector.state.audioMode=='normal')
end)
check('subtitle cleanup clears a caption whose native handle replaced ours',function()
 local h=object('hud');h.CurrentSubtitleId=77;h.visible=true
 h.HideSubtitles=function(self,id) if id<=0 or id==self.CurrentSubtitleId then self.visible=false end end
 h:HideSubtitles(76);assert(h.visible)
 dofile(ROOT..'/subtitles.lua').clear(h);assert(not h.visible)
end)
check('automatic dialogue filtering preserves unrelated setup actions',function()
 local oldConstruct,oldFind=StaticConstructObject,StaticFindObject
 StaticFindObject=function() return object('class') end
 StaticConstructObject=function()
  return {AsSpongeBob=setmetatable({}, {__newindex=function(t,k,v)
   local copied={};for i,entry in ipairs(v) do local item={};for key,value in pairs(entry) do item[key]=value end;copied[i]=item end
   rawset(t,k,array(copied))
  end})}
 end
 local actor=object('Squidward-load-trigger');actor.Conditions='unchanged';actor.IsFinished=false
 actor.IsA=function(self,path) return path=='/Script/Pineapple.PINE_GameplayTrigger' end
 local keep1={ActionType=0,ActorParam='spatula',IsAffectingChildren=true}
 local keep2={ActionType=7,StringParam='scene-state',IntegerParam=3}
 actor.Actions=array({keep1,{ActionType=4,DialogueParam='briefing'},{ActionType=24,Bark='entry-reaction'},keep2})
 TEST_CONTEXT.suppressAutomaticActor(actor)
 assert(#actor.Actions==2 and actor.Actions[1].ActionType==0 and actor.Actions[1].ActorParam=='spatula' and actor.Actions[1].IsAffectingChildren)
 assert(actor.Actions[2].ActionType==7 and actor.Actions[2].IntegerParam==3 and actor.Conditions=='unchanged' and actor.IsFinished==false)
 StaticConstructObject,StaticFindObject=oldConstruct,oldFind
end)
check('native bark component is blocked before BeginPlay without changing explicit voice audio',function()
 local component=object('native-barks');component.VolumeMultiplier=1;component.ShouldShowSubtitles=true;component.tick=true;component.stops=0
 component.IsComponentTickEnabled=function(self) return self.tick end
 component.SetComponentTickEnabled=function(self,value) self.tick=value end
 component.SetVolumeMultiplier=function(self,value) self.VolumeMultiplier=value end
 component.Stop=function(self) self.stops=self.stops+1 end
 local actor=object('player');actor.BarkComponent=component
 actor.IsA=function(self,path) return path=='/Script/Pineapple.PineappleCharacter' end
 local explicit=object('direct-playlist-audio');explicit.VolumeMultiplier=1
 TEST_A.state.audio=explicit
 TEST_BEGIN_PLAY({get=function() return actor end})
 assert(component.VolumeMultiplier==0 and not component.tick and not component.ShouldShowSubtitles and component.stops==1)
 assert(#component.QueuedBarks==0 and explicit.VolumeMultiplier==1)
 component.QueuedBarks={GetArrayNum=function() return 0 end}
 TEST_CONTEXT.suppressNativeBarks(actor);assert(component.stops==1)
 TEST_A.state.audio=nil
end)
check('BeginPlay suppresses map cutscenes and stale generations do nothing',function()
 local actor=object('intro-trigger');actor.IsFinished=false;actor.CanRunMultipleTimes=true
 actor.IsA=function(self,path) return path=='/Game/Blueprints/LevelScripts/BP_CutsceneStart.BP_CutsceneStart_C' end
 TEST_BEGIN_PLAY({get=function() return actor end})
 assert(actor.IsFinished and not actor.CanRunMultipleTimes)
 local generation=StoryDirectorGeneration;StoryDirectorGeneration={};actor.IsFinished=false
 TEST_BEGIN_PLAY({get=function() return actor end});assert(not actor.IsFinished)
 StoryDirectorGeneration=generation
end)
""")

# A release must contain references only, with no bundled dialogue/prose or personal paths.
for filename in ['scenes.json','context.json','extras.json','entries.json']:
    def audit(value):
        if isinstance(value,dict):
            assert not set(value).intersection({'text','plainText','sourceText','SpokenText','textVariants'}),filename
            for child in value.values():audit(child)
        elif isinstance(value,list):
            for child in value:audit(child)
        elif isinstance(value,str):
            assert not re.search(r'[A-Za-z]:[/\\\\]',value),filename
    audit(json.loads((root/'data'/filename).read_text(encoding='utf-8')))
for path in root.rglob('*.lua'):
    result=lua.execute('return loadfile(...)',str(path))
    assert result is not None,path

cases=lua.globals().TEST_CASES
result=[{'name':cases[i]['name'],'passed':cases[i]['passed'],'error':cases[i]['error']} for i in range(1,len(cases)+1)]
report={'schemaVersion':1,'scope':'Pure Lua5.4 mocked integration using portable core and metadata; no game or live profile writes. Does not verify Unreal callbacks, save API isolation, or audio/camera behavior.','codeSHA256':{name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in ('director.lua','contextual.lua','playlist.lua','subtitles.lua')},'passed':all(x['passed'] for x in result),'tests':result,'testCount':len(result),'profileMismatchGuardCases':2,'allLuaParsed':True,'metadataContainsNoTranscriptOrPersonalPaths':True,'knownUISemantics':'watch N plays one entry; story N continues the all playlist from N.'}
(dev/'portable-core-results.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,indent=2))
sys.exit(0 if report['passed'] else 1)
