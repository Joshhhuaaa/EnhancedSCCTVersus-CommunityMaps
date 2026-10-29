# Publishes a map revision and re-signs index.signed, the file Reloaded's map browser reads.
#
#   tools\Publish-Map.ps1 -NewKey [-HeaderPath <Reloaded.Core\MapIndexSigningKey.h>]   once: creates the key pair
#   tools\Publish-Map.ps1 -Code FortX -Files <folder laid out like Packages>            every new map or revision
#   tools\Publish-Map.ps1 -Reindex                                                     after editing a map.json or preview.jpg
#
# Write maps\<Code>\map.json (code, title, authors, description, game, recommendedPlayers) before the first publish.
# -Local puts the zip under releases\ instead of a GitHub release, for testing with a local index.
# The private key can put a map on every player's machine, so keep it out of the repo and back it up offline.
[CmdletBinding(DefaultParameterSetName = 'Publish')]
param(
    [Parameter(ParameterSetName = 'Publish', Mandatory = $true)][string]$Code,
    [Parameter(ParameterSetName = 'Publish', Mandatory = $true)][string]$Files,
    [Parameter(ParameterSetName = 'Publish')][switch]$Local,
    [Parameter(ParameterSetName = 'Publish')][string]$Repo,
    [Parameter(ParameterSetName = 'Reindex', Mandatory = $true)][switch]$Reindex,
    [Parameter(ParameterSetName = 'NewKey', Mandatory = $true)][switch]$NewKey,
    [Parameter(ParameterSetName = 'NewKey')][string]$HeaderPath,
    [string]$KeyPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

if (-not $KeyPath) {
    $KeyPath = $DefaultKeyPath
}
if (-not $Repo) {
    $Repo = $DefaultRepo
}
$privateBlob = [System.Security.Cryptography.CngKeyBlobFormat]::EccPrivateBlob
$publicBlob = [System.Security.Cryptography.CngKeyBlobFormat]::EccPublicBlob

function Publish-Index {
    if (-not (Test-Path $KeyPath)) {
        throw "No private key at $KeyPath."
    }
    foreach ($folder in Get-MapFolders) {
        $problems = @(Test-Preview $folder)
        if ($problems.Count -gt 0) {
            throw "maps/$($folder.Name): $($problems -join '; ')"
        }
    }
    $previous = Read-SignedIndex
    $serial = 1
    if ($previous) {
        $serial = [long]([Text.Encoding]::UTF8.GetString($previous.Payload) | ConvertFrom-Json).serial + 1
    }

    $index = [ordered]@{ schema = $IndexSchema; serial = $serial; maps = Get-IndexEntries }
    $payload = $Utf8NoBom.GetBytes(($index | ConvertTo-Json -Depth 8))
    $signer = New-Object System.Security.Cryptography.ECDsaCng ([System.Security.Cryptography.CngKey]::Import([IO.File]::ReadAllBytes($KeyPath), $privateBlob))
    $signature = ConvertTo-Hex $signer.SignData((Get-SignedMessage $payload), [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    if (-not (Test-IndexSignature $signature $payload)) {
        throw "The key at $KeyPath is not the one in signing-key.pub, so Reloaded would reject the index."
    }

    $signatureLine = [Text.Encoding]::ASCII.GetBytes("$signature`n")
    $file = New-Object byte[] ($signatureLine.Length + $payload.Length)
    [Array]::Copy($signatureLine, $file, $signatureLine.Length)
    [Array]::Copy($payload, 0, $file, $signatureLine.Length, $payload.Length)
    [IO.File]::WriteAllBytes($IndexPath, $file)
    Write-Host "Signed index.signed, serial $serial, $($index.maps.Count) maps."
}

if ($NewKey) {
    $KeyPath = [IO.Path]::GetFullPath($KeyPath)
    if ($KeyPath.StartsWith([IO.Path]::GetFullPath($RepoRoot) + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Keep the private key outside the repo.'
    }
    if (Test-Path $KeyPath) {
        throw "$KeyPath already exists."
    }
    if (Test-Path $PublicKeyPath) {
        throw "$PublicKeyPath already exists. Every Reloaded build only accepts indexes signed with it, so delete it by hand only if you mean to replace it."
    }

    $parameters = New-Object System.Security.Cryptography.CngKeyCreationParameters
    $parameters.ExportPolicy = [System.Security.Cryptography.CngExportPolicies]::AllowPlaintextExport
    # PowerShell passes $null to a string parameter as "", which would persist a key named "" in the user's key store.
    $key = [System.Security.Cryptography.CngKey]::Create([System.Security.Cryptography.CngAlgorithm]::ECDsaP256, [NullString]::Value, $parameters)
    New-Item -ItemType Directory -Force -Path (Split-Path $KeyPath) | Out-Null
    [IO.File]::WriteAllBytes($KeyPath, $key.Export($privateBlob))

    $public = $key.Export($publicBlob)
    [IO.File]::WriteAllText($PublicKeyPath, (ConvertTo-Hex $public) + "`n")
    $rows = for ($i = 0; $i -lt $public.Length; $i += 12) {
        '    ' + (($public[$i..($i + 11)] | ForEach-Object { '0x{0:X2}' -f $_ }) -join ', ') + ','
    }
    $header = @(
        '#pragma once'
        ''
        '// Written by the community maps repo''s tools/Publish-Map.ps1 -NewKey: the public half of the key that signs'
        '// index.signed, as a BCRYPT_ECCPUBLIC_BLOB.'
        'inline constexpr unsigned char MapIndexSigningKey[] = {'
        $rows
        '};'
        ''
    ) -join "`r`n"
    if ($HeaderPath) {
        [IO.File]::WriteAllText($HeaderPath, $header)
        Write-Host "Wrote $HeaderPath."
    }
    else {
        Write-Host $header
    }
    Write-Host "Private key: $KeyPath"
    Write-Host 'Back it up offline, commit signing-key.pub, and put the header in Reloaded.Core as MapIndexSigningKey.h.'
    return
}

if ($Reindex) {
    Publish-Index
    return
}

$mapDir = Join-Path $MapsDir $Code
$mapJsonPath = Join-Path $mapDir 'map.json'
if (-not (Test-Path $mapJsonPath)) {
    throw "Write $mapJsonPath first, with code, title, authors, description, game and recommendedPlayers."
}
if (-not (Test-Path $KeyPath)) {
    throw "No private key at $KeyPath."
}
$map = Read-MapJson $mapJsonPath
if ([string]$map.code -cne $Code) {
    throw "$mapJsonPath has code '$($map.code)', not '$Code'."
}

$prohibited = Get-Prohibited
$takenNames = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($folder in Get-MapFolders) {
    if ($folder.Name -eq $Code) {
        continue
    }
    $other = Read-MapJson (Join-Path $folder.FullName 'map.json')
    foreach ($file in @($other.files)) {
        $otherFolder = Get-PackageFolder ([string]$file.path)
        if ($otherFolder -and $otherFolder.Searched) {
            $takenNames[(Get-PackageName ([string]$file.path))] = $folder.Name
        }
    }
}

# The files are laid out as in the game's Packages folder: Maps\<Code>.sdc, MapsEd\<Code>.sdc, Sounds\<Code>.uas, ...
$root = (Resolve-Path -LiteralPath $Files).Path.TrimEnd('\')
$sources = @(Get-ChildItem -LiteralPath $root -File -Recurse)
$packages = foreach ($source in $sources) {
    $relative = $source.FullName.Substring($root.Length + 1)
    $parts = $relative -split '\\'
    $extension = $source.Extension.ToLowerInvariant()
    $folder = $null
    if ($parts.Count -eq 2) {
        $folder = $PackageFolders | Where-Object { $_.Folder -ieq $parts[0] -and $_.Extension -ceq $extension } | Select-Object -First 1
    }
    if (-not $folder) {
        throw "$relative is not a file the game reads from Packages. Lay the folder out as Packages is: Maps\$Code.sdc, MapsEd\$Code.sdc, Sounds\$Code.uas, Textures\..."
    }
    $name = Get-PackageName $source.Name
    if ($name -notmatch $CodePattern) {
        throw "${relative}: package names may only use letters, digits, '_' and '-'."
    }
    # The map package, its editor copy and its sound bank.
    if ($folder.Folder -ceq 'Maps' -or -not $folder.Searched) {
        if ($name -ne $Code) {
            throw "$relative must be named $Code$extension."
        }
        $name = $Code
    }
    if ($prohibited.Contains($name)) {
        throw "$relative has the name of a package Enhanced ships."
    }
    if ($folder.Searched -and $takenNames.ContainsKey($name)) {
        throw "$relative has the name of a package in $($takenNames[$name])."
    }
    [pscustomobject]@{ Source = $source.FullName; Path = "Packages/$($folder.Folder)/$name$extension"; Name = $name; Searched = $folder.Searched }
}
$packages = @($packages | Sort-Object Path)
foreach ($required in Get-RequiredFiles $Code) {
    if (@($packages | Where-Object { $_.Path -ceq $required }).Count -eq 0) {
        throw "$Files has no $($required.Substring('Packages/'.Length).Replace('/', '\')). Every map needs its package, its editor copy (MapsEd) and its sound bank, with at least the win, lose and objective sounds."
    }
}
$duplicate = $packages | Where-Object Searched | Group-Object Name | Where-Object Count -gt 1 | Select-Object -First 1
if ($duplicate) {
    throw "Two packages are named $($duplicate.Name); the engine finds packages by name alone."
}

$revision = 1
if ((Test-Property $map 'revision') -and [int]$map.revision -ge 1) {
    $revision = [int]$map.revision + 1
}
$tag = "$Code-r$revision"
$zipName = "$tag.zip"
$stage = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
try {
    # Fixed timestamps, so the same packages always zip to the same bytes.
    $zipPath = Join-Path $stage $zipName
    $zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($package in $packages) {
            $entry = $zip.CreateEntry($package.Path, [IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = New-Object DateTimeOffset 1980, 1, 1, 0, 0, 0, ([TimeSpan]::Zero)
            $entryStream = $entry.Open()
            $packageStream = [IO.File]::OpenRead($package.Source)
            try {
                $packageStream.CopyTo($entryStream)
            }
            finally {
                $packageStream.Dispose()
                $entryStream.Dispose()
            }
        }
    }
    finally {
        $zip.Dispose()
    }

    $url = if ($Local) { "releases/$tag/$zipName" } else { "https://github.com/$Repo/releases/download/$tag/$zipName" }
    $published = [ordered]@{
        code        = $Code
        title       = [string]$map.title
        authors     = @($map.authors | ForEach-Object { [string]$_ })
        description = [string]$map.description
        game        = [string]$map.game
        recommendedPlayers = $map.recommendedPlayers
        revision    = $revision
        updated     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
        archive     = [ordered]@{ url = $url; size = (Get-Item -LiteralPath $zipPath).Length; sha256 = Get-Sha256 $zipPath }
        files       = @($packages | ForEach-Object {
                [ordered]@{ path = $_.Path; size = (Get-Item -LiteralPath $_.Source).Length; sha256 = Get-Sha256 $_.Source }
            })
    }
    if (Test-Property $map 'playlists') {
        $published.playlists = @($map.playlists | ForEach-Object { [string]$_ })
    }
    if (Test-Property $map 'variant') {
        $published.variant = [string]$map.variant
    }
    $problems = @(Test-MapEntry ([pscustomobject]$published | ConvertTo-Json -Depth 8 | ConvertFrom-Json) $Code $prohibited)
    if ($problems.Count -gt 0) {
        throw "map.json: $($problems -join '; ')"
    }

    if ($Local) {
        $releaseDir = Join-Path $RepoRoot "releases\$tag"
        New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
        Copy-Item -LiteralPath $zipPath -Destination $releaseDir -Force
    }
    else {
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            throw 'Install the GitHub CLI (gh), or pass -Local to test with a local index.'
        }
        & gh release create $tag $zipPath --repo $Repo --title "$($map.title) r$revision" --notes "$($map.title), revision $revision."
        if ($LASTEXITCODE -ne 0) {
            throw 'gh release create failed.'
        }
    }
    Write-Json $published $mapJsonPath
    Write-Host "Published $tag ($url)."
    Publish-Index
}
finally {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
