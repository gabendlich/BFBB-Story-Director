[CmdletBinding()]
param([string]$RuntimeArchive, [switch]$NoZip)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($PSScriptRoot)
. (Join-Path $root 'tools\Package-Release.ps1')
$expectedArchiveHash='3c72142a383e25e9f9553ac9e4d5677aa572e98cb369cac57200efb2e381e603'
$archiveName='UE4SS_v3.0.1-1164-g5e627997.zip'
$releaseName='StoryDirector-0.1.1-win-x64.zip'
$sourceReleaseName='StoryDirector-0.1.1-source.zip'
$sourceFiles=@('src/Program.cs','src/PlayerBackend.cs','src/PlayerForm.cs')
$documentFiles=@('README.md','README.de.md','LICENSE','THIRD-PARTY-NOTICES.md')
$buildSupportFiles=@('build.ps1','.gitignore','tools/Package-Release.ps1','tests/Test-Packaging.ps1','tests/test_portable_core.py','tests/portable-core-results.json','tests/live-validation.json','.github/workflows/build.yml')
$directorFiles=@(
    'payload/director/director.lua','payload/director/contextual.lua',
    'payload/director/playlist.lua','payload/director/subtitles.lua',
    'payload/director/data/context.json','payload/director/data/context.lua',
    'payload/director/data/entries.json','payload/director/data/entries.lua',
    'payload/director/data/extras.json','payload/director/data/extras.lua',
    'payload/director/data/scenes.json','payload/director/data/scenes.lua'
)
# These five files are the complete runtime. The manifest is generated separately.
$runtimeFiles=@('dwmapi.dll','ue4ss/UE4SS.dll','ue4ss/LICENSE','ue4ss/UE4SS_SDK_Backends/UE4SS.json','ue4ss/UE4SS-settings.ini')
$archiveFiles=@('dwmapi.dll','ue4ss/UE4SS.dll','ue4ss/LICENSE','ue4ss/UE4SS_SDK_Backends/UE4SS.json')
$cache=Get-BuildPath $root '.cache'
New-Item -ItemType Directory -Path $cache -Force | Out-Null
$lockPath=Get-BuildPath $root '.cache/build.lock'
try{$buildLock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw 'Another build is active. Wait for it to finish before building again.'}
$buildId=[Guid]::NewGuid().ToString('N')
$stage=Get-BuildPath $root ('.cache/build-'+$buildId)
$published=$false
try {
    New-Item -ItemType Directory -Path $stage | Out-Null
    $snapshot=Join-Path $stage 'source'
    New-Item -ItemType Directory -Path $snapshot | Out-Null
    # Snapshot an allowlist only. Root payload/catalog.json, payload/runtime,
    # old dist trees, commands, logs, status files and personal profiles are ignored.
    Copy-ReleaseFiles -SourceRoot $root -DestinationRoot $snapshot -Paths ($sourceFiles+$documentFiles+$directorFiles+$buildSupportFiles+@('tools/Build-Catalog.ps1','runtime/UE4SS-settings.ini'))
    & (Join-Path $snapshot 'tools\Build-Catalog.ps1')
    if(-not $RuntimeArchive) {
        $vendored=Get-BuildPath $root ('third_party/'+$archiveName)
        if(Test-Path -LiteralPath $vendored -PathType Leaf){$RuntimeArchive=$vendored}
    }
    if(-not $RuntimeArchive) {
        $RuntimeArchive=Get-BuildPath $root ('.cache/'+$archiveName)
        if(-not(Test-Path -LiteralPath $RuntimeArchive -PathType Leaf)) {
            $download=Get-BuildPath $stage 'runtime-download.zip'
            Invoke-WebRequest -UseBasicParsing -Uri ('https://github.com/UE4SS-RE/RE-UE4SS/releases/download/experimental-latest/'+$archiveName) -OutFile $download
            if((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ine $expectedArchiveHash){throw 'UE4SS download checksum mismatch.'}
            Copy-Item -LiteralPath $download -Destination $RuntimeArchive
        }
    }
    $RuntimeArchive=(Resolve-Path -LiteralPath $RuntimeArchive).Path
    if((Get-FileHash -LiteralPath $RuntimeArchive -Algorithm SHA256).Hash -ine $expectedArchiveHash){throw 'UE4SS archive checksum mismatch. The build will not use an unverified runtime.'}
    $release=Get-BuildPath $stage 'release'
    $package=Join-Path $release 'StoryDirector'
    New-Item -ItemType Directory -Path $package -Force | Out-Null
    Copy-ReleaseFiles -SourceRoot $snapshot -DestinationRoot $package -Paths ($documentFiles+$directorFiles+@('payload/catalog.json'))
    $runtime=Join-Path $package 'payload\runtime'
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead($RuntimeArchive)
    try {
        foreach($relative in $archiveFiles) {
            $entry=$archive.GetEntry($relative)
            if($null -eq $entry){throw ('Pinned runtime archive is missing '+$relative)}
            $target=Get-BuildPath $runtime $relative
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
            $input=$entry.Open();$output=[IO.File]::Open($target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{$input.CopyTo($output)}finally{$output.Dispose();$input.Dispose()}
        }
    }finally{$archive.Dispose()}
    Copy-Item -LiteralPath (Join-Path $snapshot 'runtime\UE4SS-settings.ini') -Destination (Get-BuildPath $runtime 'ue4ss/UE4SS-settings.ini')
    Write-RuntimeManifest -Root $runtime -Files $runtimeFiles
    $sourceThirdParty=Get-BuildPath $snapshot 'third_party'
    New-Item -ItemType Directory -Path $sourceThirdParty | Out-Null
    Copy-Item -LiteralPath $RuntimeArchive -Destination (Get-BuildPath $sourceThirdParty $archiveName)
    Copy-Item -LiteralPath (Get-BuildPath $runtime 'ue4ss/LICENSE') -Destination (Get-BuildPath $sourceThirdParty 'LICENSE.UE4SS')
    $compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if(-not(Test-Path -LiteralPath $compiler)){throw '.NET Framework 4.8 compiler is required (included with supported Windows 10/11 installations).'}
    $sources=@($sourceFiles | ForEach-Object {Get-BuildPath $snapshot $_})
    & $compiler /nologo /target:winexe /platform:x64 /optimize+ /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll /r:System.Management.dll /r:System.Core.dll ('/out:'+(Join-Path $package 'StoryDirector.exe')) $sources
    if($LASTEXITCODE -ne 0){throw 'Compilation failed.'}
    $packageFiles=@('StoryDirector.exe','payload/catalog.json')+$documentFiles+$directorFiles+@($runtimeFiles | ForEach-Object {'payload/runtime/'+$_})+@('payload/runtime/SHA256SUMS.json')
    Assert-ReleaseFiles -Root $package -Expected $packageFiles
    $test=Start-Process -FilePath (Join-Path $package 'StoryDirector.exe') -ArgumentList '--self-test' -WindowStyle Hidden -PassThru -Wait
    if($test.ExitCode -ne 0){throw 'Backend self-tests failed.'}
    # The self-test must not leave generated files inside the distributable.
    Assert-ReleaseFiles -Root $package -Expected $packageFiles
    if(-not $NoZip) {
        $zip=Get-BuildPath $release $releaseName
        Write-ReleaseZip -PackageRoot $package -Destination $zip -Files $packageFiles
        $hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        [IO.File]::WriteAllText($zip+'.sha256.txt',$hash+' *'+$releaseName+"`n",[Text.UTF8Encoding]::new($false))
        $sourceBundleFiles=$sourceFiles+$documentFiles+$directorFiles+$buildSupportFiles+@('tools/Build-Catalog.ps1','runtime/UE4SS-settings.ini','payload/catalog.json',('third_party/'+$archiveName),'third_party/LICENSE.UE4SS')
        $sourceZip=Get-BuildPath $release $sourceReleaseName
        Write-ReleaseZip -PackageRoot $snapshot -Destination $sourceZip -Files $sourceBundleFiles
        $sourceHash=(Get-FileHash -LiteralPath $sourceZip -Algorithm SHA256).Hash.ToLowerInvariant()
        [IO.File]::WriteAllText($sourceZip+'.sha256.txt',$sourceHash+' *'+$sourceReleaseName+"`n",[Text.UTF8Encoding]::new($false))
    }
    # Publish only a fully checked build. Preserve the previous dist tree intact,
    # and restore it if the second move fails. Every move stays inside this project.
    $dist=Get-BuildPath $root 'dist'
    $previous=Get-BuildPath $root ('.cache/previous-dist-'+$buildId)
    if(Test-Path -LiteralPath $dist) {
        Assert-BuildPath -Root $root -Path $dist | Out-Null
        Assert-BuildPath -Root $root -Path $previous | Out-Null
        Move-Item -LiteralPath $dist -Destination $previous
    }
    try {
        Assert-BuildPath -Root $root -Path $release | Out-Null
        Assert-BuildPath -Root $root -Path $dist | Out-Null
        Move-Item -LiteralPath $release -Destination $dist
    } catch {
        if((Test-Path -LiteralPath $previous) -and -not(Test-Path -LiteralPath $dist)) {
            Assert-BuildPath -Root $root -Path $previous | Out-Null
            Assert-BuildPath -Root $root -Path $dist | Out-Null
            Move-Item -LiteralPath $previous -Destination $dist
        }
        throw
    }
    $published=$true
    Write-Host ('Built '+(Join-Path $dist 'StoryDirector\StoryDirector.exe'))
    if(-not $NoZip){Write-Host ('ZIP SHA-256: '+$hash);Write-Host ('Source ZIP SHA-256: '+$sourceHash)}
    if(Test-Path -LiteralPath $previous){Write-Host ('Previous build preserved in '+$previous)}
} finally {
    if($published -and (Test-Path -LiteralPath $stage)) {
        $checked=Assert-BuildPath -Root $cache -Path $stage
        Remove-Item -LiteralPath $checked -Recurse -Force
    }
    $buildLock.Dispose()
}
