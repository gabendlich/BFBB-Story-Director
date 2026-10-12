# Shared, file-system-only release packaging helpers. No game or OBS actions.

function Assert-BuildPath {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Path)
    $base=[IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $full=[IO.Path]::GetFullPath($Path)
    if(-not $full.StartsWith($base+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
        throw ('Build path is outside its root: '+$full)
    }
    $cursor=$full
    while($cursor.Length -ge $base.Length) {
        if(Test-Path -LiteralPath $cursor) {
            $item=Get-Item -LiteralPath $cursor -Force
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('Build paths cannot contain junctions or symbolic links: '+$cursor) }
        }
        if($cursor -ieq $base){break}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    return $full
}

function Get-BuildPath {
    param([string]$Root,[string]$Relative)
    if([IO.Path]::IsPathRooted($Relative)){throw 'Expected a relative build path.'}
    return Assert-BuildPath -Root $Root -Path (Join-Path $Root $Relative)
}

function Copy-ReleaseFiles {
    param([string]$SourceRoot,[string]$DestinationRoot,[string[]]$Paths)
    foreach($relative in $Paths) {
        $source=Get-BuildPath $SourceRoot $relative
        $target=Get-BuildPath $DestinationRoot $relative
        if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw ('Required source file is missing: '+$relative)}
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target
    }
}

function Assert-ReleaseFiles {
    param([string]$Root,[string[]]$Expected)
    $base=[IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $actual=@(Get-ChildItem -LiteralPath $base -Recurse -File -Force | ForEach-Object {
        $checked=Assert-BuildPath -Root $base -Path $_.FullName
        $checked.Substring($base.Length+1).Replace('\','/')
    })
    $expectedPaths=@($Expected | ForEach-Object {$_.Replace('\','/')})
    if(@($expectedPaths | Select-Object -Unique).Count -ne $expectedPaths.Count){throw 'Duplicate expected release file.'}
    $difference=@(Compare-Object -ReferenceObject $expectedPaths -DifferenceObject $actual)
    if($difference.Count){throw ('Unexpected or missing package files: '+(($difference | ForEach-Object {$_.SideIndicator+' '+$_.InputObject}) -join '; '))}
}

function Write-RuntimeManifest {
    param([string]$Root,[string[]]$Files)
    if($Files -contains 'SHA256SUMS.json'){throw 'Runtime manifest cannot hash itself.'}
    $expected=@($Files)
    if(Test-Path -LiteralPath (Join-Path $Root 'SHA256SUMS.json')){$expected+=@('SHA256SUMS.json')}
    Assert-ReleaseFiles -Root $Root -Expected $expected
    $hashes=[ordered]@{}
    foreach($relative in ($Files | Sort-Object)) {
        $file=Get-BuildPath $Root $relative
        $hashes[$relative.Replace('\','/')]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    [IO.File]::WriteAllText((Join-Path $Root 'SHA256SUMS.json'),($hashes | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
}

function Write-ReleaseZip {
    param([string]$PackageRoot,[string]$Destination,[string[]]$Files)
    Assert-ReleaseFiles -Root $PackageRoot -Expected $Files
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $stream=[IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $zip=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
    try {
        foreach($relative in ($Files | Sort-Object)) {
            $entry=$zip.CreateEntry($relative.Replace('\','/'),[IO.Compression.CompressionLevel]::Optimal)
            # Stable ZIP metadata and ordering; the legacy compiler itself does not
            # promise a byte-identical PE executable between separate compilations.
            $entry.LastWriteTime=[DateTimeOffset]::new(2000,1,1,0,0,0,[TimeSpan]::Zero)
            $input=[IO.File]::OpenRead((Get-BuildPath $PackageRoot $relative))
            $output=$entry.Open()
            try{$input.CopyTo($output)}finally{$output.Dispose();$input.Dispose()}
        }
    } finally {$zip.Dispose();$stream.Dispose()}
    $archive=[IO.Compression.ZipFile]::OpenRead($Destination)
    try {
        $actual=@($archive.Entries | ForEach-Object {$_.FullName})
        $expected=@($Files | ForEach-Object {$_.Replace('\','/')})
        if(@(Compare-Object $expected $actual).Count){throw 'ZIP content differs from the explicit release file list.'}
        foreach($entry in $archive.Entries) {
            $input=$entry.Open();$sha=[Security.Cryptography.SHA256]::Create()
            try{$digest=[BitConverter]::ToString($sha.ComputeHash($input)).Replace('-','').ToLowerInvariant()}finally{$input.Dispose();$sha.Dispose()}
            if($digest -cne (Get-FileHash -LiteralPath (Get-BuildPath $PackageRoot $entry.FullName) -Algorithm SHA256).Hash.ToLowerInvariant()) {
                throw ('ZIP file checksum differs: '+$entry.FullName)
            }
        }
    }finally{$archive.Dispose()}
}
