[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$entries=@((Get-Content -LiteralPath (Join-Path $root 'payload\director\data\entries.json') -Raw | ConvertFrom-Json).entries)
$zones=@{IntroCutscene='Opening';BikiniBottom='Bikini Bottom';JellyfishFields='Jellyfish Fields';DownTownBikiniBottom='Downtown Bikini Bottom';GooLagoon='Goo Lagoon';Poseidome='Poseidome';RockBottom='Rock Bottom';Mermalair='Mermalair';SandMountain='Sand Mountain';IndustrialPark='Industrial Park';KelpForest='Kelp Forest';DutchmanGraveyard="Flying Dutchman's Graveyard";SpongeBobDream="SpongeBob's Dream";ChumBucketLab='Chum Bucket Lab'}
$interiors=@{SpongeBobHouse="SpongeBob's House";PatrickHouse="Patrick's House";SquidwardHouse="Squidward's House";SandyHouse="Sandy's Tree Dome";KrustyKrab='Krusty Krab';ChumBucket='Chum Bucket';PoliceStation='Police Station';RestHome='Shady Shoals Rest Home'}
$characters=@{SpongeBob='SpongeBob';Patrick='Patrick';Sandy='Sandy';Any='Any character';FrenchNarrator='French Narrator';FishAnnouncer='Fish Announcer';Fish_Announcer='Fish Announcer';FishCitizen='Fish Citizen';KingNeptune='King Neptune';RoboPatrick='Robo-Patrick';RoboPlankton='Robo-Plankton';BarnacleBoy='Barnacle Boy';JellyfishKing='King Jellyfish';ArfDawg='Arf Dawg';TarTar='Tar-Tar';SleepyTime='Sleepy-Time';Unknown='Not specified'}
$cinematics=@{
    Prolog_M='Opening cinematic';Cin_hammer_M='Ham-mer introduction';Cin_fodder_M='Fodder introduction';Cin_tartar_M='Tar-Tar introduction';Cin_Glove_M='G-Love introduction';Cin_Chuck_M='Chuck introduction';Cin_monsoon_M='Monsoon introduction';Cin_Sleepy_M='Sleepy-Time introduction';Cin_Arf_M='Arf introduction';Cin_Tube_M='Tubelet introduction';Cin_Slick_M='Slick introduction'
    KJ_Open_M='King Jellyfish - battle opening';BC_PrawnOpen_M='Prawn - battle opening';BC_PrawnEnd_M='Prawn - battle ending';GY_DutchOpen_M_Slowed='Flying Dutchman - battle opening';GY_DutchEnd_M='Flying Dutchman - battle ending'
    B1_Open_M='Robo-Sandy - battle opening';B1_tran_12_M='Robo-Sandy - phase 2';B1_tran_23_M='Robo-Sandy - phase 3';B1_End_mono='Robo-Sandy - battle ending'
    B2_Open_M='Robo-Patrick - battle opening';B2_tran_12_M='Robo-Patrick - phase 2';B2_tran_23_M='Robo-Patrick - phase 3';B2_End_M='Robo-Patrick - battle ending'
    B3_Open_M='Robo-SpongeBob - battle opening';B3_Trans_M='Robo-SpongeBob - battle transition';B3_End_M='Robo-SpongeBob - battle ending'
}
function Format-Label([string]$value) {
    $value=$value -replace '_',' '
    # PowerShell -replace is case insensitive; -creplace is essential here.
    $value=$value -creplace '([a-z0-9])([A-Z])','$1 $2' -creplace '([A-Z])([A-Z][a-z])','$1 $2'
    $value=$value -replace '\bSponge Bob\b','SpongeBob' -replace '\bMr Krabs\b','Mr. Krabs' -replace '\bMrs Puff\b','Mrs. Puff' -replace '\bBubble Buddy\b','Bubble Buddy'
    $value=$value -replace '(?i)\bBreafing\b','Briefing' -replace '\s+',' '
    return $value.Trim(' ','-','_','/')
}
function Get-Location($entry) {
    if([string]::IsNullOrWhiteSpace([string]$entry.map)){return 'Multiple locations'}
    $parts=([string]$entry.map).Split('/')
    $zone=if($parts.Length -gt 3){$parts[3]}else{''}
    $leaf=$parts[-1] -replace '_P$',''
    if($interiors.ContainsKey($leaf)){return $interiors[$leaf]}
    $label=if($zones.ContainsKey($zone)){$zones[$zone]}else{Format-Label $zone}
    if($parts.Length -gt 5 -and $parts[4] -match '^Part(\d+)$'){$label+=' - Area '+$Matches[1]}
    if(-not $label){$label='Location not specified'}
    return $label
}
function Get-TriggerLabel([string]$value) {
    $value=$value.Trim()
    if($value -match '^boss encounter cue '){
        $contexts=@($value -split ';\s*')
        $value=$contexts[0] -replace '^boss encounter cue (RS|RP|SSP)_','' -replace '_0(\d)$',' $1'
        $value='Boss announcement - '+(Format-Label $value)
        if($contexts.Count -gt 1){$value+=' (shared cue)'}
        return $value
    }
    $value=$value -replace '^DA_','' -replace '\bSB house\b',"SpongeBob's house" -replace '\bGL([1-3])\b','Goo Lagoon area $1' -replace '\bJFF([1-4])\b','Jellyfish Fields area $1' -replace '\bDTBB([1-4])\b','Downtown Bikini Bottom area $1' -replace '\bDTBB\b','Downtown Bikini Bottom'
    $value=$value -replace "(?i)sandy's treehouse","Sandy's tree dome" -replace 'Krusty Krabs','Krusty Krab' -replace '^add the beginning of bungee$','Beginning a bungee jump' -replace 'Sleepytime','Sleepy-Time'
    $value=Format-Label $value
    if($value){$value=$value.Substring(0,1).ToUpperInvariant()+$value.Substring(1)}
    return $value
}
$seen=@{}
$rows=@(foreach($entry in $entries) {
    $index=[int]$entry.index
    if($index -lt 1 -or $seen.ContainsKey($index)){throw 'Catalog indices must be unique positive integers.'}
    $seen[$index]=$true
    $location=Get-Location $entry
    $name=[string]$entry.name
    $character=[string]$entry.character
    if($entry.kind -ne 'scene' -and -not [string]::IsNullOrWhiteSpace([string]$entry.speakerName)){$character=[string]$entry.speakerName}
    $character=if($characters.ContainsKey($character)){$characters[$character]}else{Format-Label $character}
    if(-not $character){$character='Not specified'}
    switch([string]$entry.kind) {
        'cinematic' {
            $kind='Cutscene'
            if($cinematics.ContainsKey($name)){$title=$cinematics[$name]}
            elseif($name -match '^fn'){$title=($location -replace ' - Area \d+$','')+' flythrough'}
            else{$title=Format-Label ($name -replace '^Cin_','' -replace '_M$','')}
        }
        'voice' {
            $kind=if($entry.sourceCategory -eq 'announcer'){'Announcer'}else{'Reaction'}
            # The reference catalog calls this field trigger, not situation.
            $title=Get-TriggerLabel ([string]$entry.trigger)
            if(-not $title){$title='Character reaction - '+(Format-Label $name)}
        }
        'scene' {
            $information=$name -match ' / Info(?:Sentence)?$'
            $kind=if($information){'Information'}else{'Dialogue'}
            $title=$name -replace ' / (AsSpongeBob|AsPatrick|AsSandy|InfoSentence|Info|Conditional)$','' -replace '^DA_',''
            $title=$title -replace '^(BB|JF|JFF|DTBB|GL|RB|ML|SM|KF|DG|SD|CB)\d*(?:_(?:SBH|SQH|RH|SH|PH|KK|om|\d{2}))?_',''
            $title=$title -replace '(?:^|_)BP_','_' -replace 'DialogueNPC_?','' -replace 'Dialogue_?','' -replace '(?:^|_)Quest_','_'
            $title=Format-Label $title
            if($information){
                if($title -match '^(\d+) Info$'){$title='Information '+$Matches[1]}
                else{$title='Information - '+($title -replace ' Info$','')}
            }
            else {$title=$title -replace '^\d+\s+(?=[A-Za-z])','';if($name -match ' / Conditional$'){$title+=' (alternative)'}}
        }
        default {throw ('Unknown scene kind: '+$entry.kind)}
    }
    if([string]::IsNullOrWhiteSpace($title)){throw ('Entry '+$index+' has no display title.')}
    [pscustomobject][ordered]@{Index=$index;Title=$title;Location=$location;Kind=$kind;Character=$character}
})
# Distinguish multiple recorded variants without redistributing their spoken text.
foreach($group in @($rows | Group-Object -Property Title,Location,Kind,Character | Where-Object Count -gt 1)) {
    $variant=0
    foreach($row in $group.Group){$variant++;$row.Title+=' (variant '+$variant+')'}
}
[IO.File]::WriteAllText((Join-Path $root 'payload\catalog.json'),(ConvertTo-Json -InputObject $rows -Depth 5),[Text.UTF8Encoding]::new($false))