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
 local flat=TEST_LINE_LOOP({mode='story',playlistMode='dialogue',index=1},TEST_CONTEXT,function() return sentenceArray(scene) end,nil,scene)
 assert(#flat==8)
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
