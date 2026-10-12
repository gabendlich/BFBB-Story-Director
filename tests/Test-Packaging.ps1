[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'tools\Package-Release.ps1')
$caseRoot=Get-BuildPath $root ('.cache/packaging-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
$passed=0
function Check([string]$Name,[scriptblock]$Action) {
    & $Action
    $script:passed++
    Write-Host ('PASS '+$Name)
}
function Assert-Throws([scriptblock]$Action) {
    $threw=$false
    try{& $Action}catch{$threw=$true}
    if(-not $threw){throw 'Expected operation to be rejected.'}
}
try {
    $source=Join-Path $caseRoot 'source'
    New-Item -ItemType Directory -Path (Join-Path $source 'payload\payload') -Force | Out-Null
    foreach($item in @{'StoryDirector.exe'='fixture-exe';'payload/catalog.json'='[]';'payload/status.json'='stale status';'payload/command.txt'='quit';'payload/payload/stale.txt'='nested stale payload'}.GetEnumerator()) {
        [IO.File]::WriteAllText((Join-Path $source $item.Key),$item.Value)
    }
    $files=@('StoryDirector.exe','payload/catalog.json')
    $first=Join-Path $caseRoot 'first'
    New-Item -ItemType Directory -Path $first | Out-Null
    Check 'explicit allowlist ignores status, commands and nested payloads' {
        Copy-ReleaseFiles $source $first $files
        Assert-ReleaseFiles $first $files
    }
    Check 'package validation rejects an unexpected generated file' {
        [IO.File]::WriteAllText((Join-Path $first 'unexpected.log'),'stale')
        Assert-Throws {Assert-ReleaseFiles $first $files}
        $checked=Get-BuildPath $first 'unexpected.log';Remove-Item -LiteralPath $checked
    }
    Check 'path traversal and absolute targets are rejected' {
        Assert-Throws {Get-BuildPath $source '../outside.txt'}
        Assert-Throws {Get-BuildPath $source ([IO.Path]::GetFullPath((Join-Path $caseRoot 'outside.txt')))}
        Assert-Throws {Assert-BuildPath $source $source}
    }
    $runtime=Join-Path $caseRoot 'runtime'
    $runtimeFiles=@('dwmapi.dll','ue4ss/UE4SS.dll','ue4ss/LICENSE','ue4ss/UE4SS_SDK_Backends/UE4SS.json','ue4ss/UE4SS-settings.ini')
    foreach($file in $runtimeFiles) {
        $target=Get-BuildPath $runtime $file
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
        [IO.File]::WriteAllText($target,'fixture '+$file)
    }
    Check 'runtime manifest contains only five explicit files' {
        Write-RuntimeManifest $runtime $runtimeFiles
        $manifest=Get-Content -LiteralPath (Join-Path $runtime 'SHA256SUMS.json') -Raw | ConvertFrom-Json
        $keys=@($manifest.PSObject.Properties.Name)
        if($keys.Count -ne 5 -or @((Compare-Object $runtimeFiles $keys)).Count){throw 'Wrong runtime manifest keys.'}
    }
    Check 'runtime manifest regeneration is stable and cannot include itself' {
        $before=(Get-FileHash -LiteralPath (Join-Path $runtime 'SHA256SUMS.json')).Hash
        Write-RuntimeManifest $runtime $runtimeFiles
        if((Get-FileHash -LiteralPath (Join-Path $runtime 'SHA256SUMS.json')).Hash -cne $before){throw 'Manifest changed when inputs did not.'}
        Assert-Throws {Write-RuntimeManifest $runtime ($runtimeFiles+@('SHA256SUMS.json'))}
    }
    Check 'runtime validation rejects stale files' {
        [IO.File]::WriteAllText((Join-Path $runtime 'old.log'),'stale')
        Assert-Throws {Write-RuntimeManifest $runtime $runtimeFiles}
    }
    Check 'repeated clean staging and ZIP files have the same exact inventory' {
        $second=Join-Path $caseRoot 'second'
        New-Item -ItemType Directory -Path $second | Out-Null
        Copy-ReleaseFiles $source $second $files
        Write-ReleaseZip $first (Join-Path $caseRoot 'one.zip') $files
        Write-ReleaseZip $second (Join-Path $caseRoot 'two.zip') $files
        if((Get-FileHash -LiteralPath (Join-Path $caseRoot 'one.zip')).Hash -cne (Get-FileHash -LiteralPath (Join-Path $caseRoot 'two.zip')).Hash){throw 'Identical package inputs produced different ZIP bytes.'}
    }
    Write-Host ('Passed '+$passed+' packaging fixtures; no game or OBS changes.')
} finally {
    $checked=Assert-BuildPath -Root (Join-Path $root '.cache') -Path $caseRoot
    Remove-Item -LiteralPath $checked -Recurse -Force
}
