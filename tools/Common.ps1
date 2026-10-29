# Shared by the scripts in this folder; dot-source it.
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path $PSScriptRoot -Parent
$MapsDir = Join-Path $RepoRoot 'maps'
$IndexPath = Join-Path $RepoRoot 'index.signed'
$ProhibitedPath = Join-Path $RepoRoot 'prohibited.txt'
$PublicKeyPath = Join-Path $RepoRoot 'signing-key.pub'
$DefaultKeyPath = Join-Path $env:USERPROFILE '.scct-reloaded\map-index-signing.key'
$DefaultRepo = 'Joshhhuaaa/EnhancedSCCTVersus_CommunityMaps'

# Must match CommunityMaps.cpp in Reloaded.Core.
$IndexSchema = 1
$IndexSignatureHeader = "SCCT Versus Reloaded map index`n"
$MaxCodeLength = 20
$CodePattern = '^[A-Za-z0-9_-]+$'
$Games = @('enhanced', 'any')
# The folders the engine searches, by package extension.
$PackageFolders = @{
    '.sdc' = 'Packages/Maps'
    '.utx' = 'Packages/Textures'
    '.utc' = 'Packages/Textures'
    '.usx' = 'Packages/StaticMeshes'
    '.uax' = 'Packages/Sounds'
    '.ukx' = 'Packages/Animations'
    '.umx' = 'Packages/Music'
}
# A map folder holds its metadata only; packages go in releases.
$MapFolderFiles = @('map.json', 'preview.jpg')

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-Sha256([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-Prohibited {
    $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in Get-Content -LiteralPath $ProhibitedPath) {
        if ($line -and -not $line.StartsWith('#')) {
            [void]$names.Add($line.Trim())
        }
    }
    return , $names
}

function Read-MapJson([string]$Path) {
    [IO.File]::ReadAllText($Path, $Utf8NoBom) | ConvertFrom-Json
}

function Write-Json($Value, [string]$Path) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 8), $Utf8NoBom)
}

function Get-PackageName([string]$Path) {
    [IO.Path]::GetFileNameWithoutExtension($Path)
}

function Test-Property($Object, [string]$Name) {
    $null -ne $Object.PSObject.Properties[$Name]
}

# The index entry for a map.json, fields in index order.
function ConvertTo-IndexEntry($Map) {
    [ordered]@{
        code        = [string]$Map.code
        title       = [string]$Map.title
        authors     = @($Map.authors | ForEach-Object { [string]$_ })
        description = [string]$Map.description
        game        = [string]$Map.game
        revision    = [int]$Map.revision
        updated     = [string]$Map.updated
        archive     = [ordered]@{
            url    = [string]$Map.archive.url
            size   = [long]$Map.archive.size
            sha256 = [string]$Map.archive.sha256
        }
        files       = @($Map.files | ForEach-Object {
                [ordered]@{ path = [string]$_.path; size = [long]$_.size; sha256 = [string]$_.sha256 }
            })
    }
}

function Get-MapFolders {
    if (-not (Test-Path $MapsDir)) {
        return @()
    }
    @(Get-ChildItem -LiteralPath $MapsDir -Directory | Sort-Object { $_.Name.ToLowerInvariant() })
}

function Get-IndexEntries {
    @(Get-MapFolders | ForEach-Object { ConvertTo-IndexEntry (Read-MapJson (Join-Path $_.FullName 'map.json')) })
}

# The signature line and the JSON after it, or null when there is no index yet.
function Read-SignedIndex {
    if (-not (Test-Path $IndexPath)) {
        return $null
    }
    $bytes = [IO.File]::ReadAllBytes($IndexPath)
    $newline = [Array]::IndexOf($bytes, [byte]10)
    if ($newline -lt 0) {
        throw "$IndexPath has no signature line."
    }
    [pscustomobject]@{
        Signature = [Text.Encoding]::ASCII.GetString($bytes, 0, $newline).Trim()
        Payload   = [byte[]]($bytes[($newline + 1)..($bytes.Length - 1)])
    }
}

function ConvertFrom-Hex([string]$Hex) {
    $bytes = New-Object byte[] ($Hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16)
    }
    return , $bytes
}

function ConvertTo-Hex([byte[]]$Bytes) {
    -join ($Bytes | ForEach-Object { $_.ToString('x2') })
}

function Get-SignedMessage([byte[]]$Payload) {
    $header = [Text.Encoding]::ASCII.GetBytes($IndexSignatureHeader)
    $message = New-Object byte[] ($header.Length + $Payload.Length)
    [Array]::Copy($header, $message, $header.Length)
    [Array]::Copy($Payload, 0, $message, $header.Length, $Payload.Length)
    return , $message
}

function Test-IndexSignature([string]$SignatureHex, [byte[]]$Payload) {
    if (-not (Test-Path $PublicKeyPath)) {
        throw "$PublicKeyPath is missing. Run tools\Publish-Map.ps1 -NewKey first."
    }
    if ($SignatureHex -notmatch '^[0-9a-f]{128}$') {
        return $false
    }
    $publicKey = ConvertFrom-Hex ((Get-Content -LiteralPath $PublicKeyPath -Raw).Trim())
    $verifier = New-Object System.Security.Cryptography.ECDsaCng ([System.Security.Cryptography.CngKey]::Import($publicKey,
            [System.Security.Cryptography.CngKeyBlobFormat]::EccPublicBlob))
    $verifier.VerifyData((Get-SignedMessage $Payload), (ConvertFrom-Hex $SignatureHex),
        [System.Security.Cryptography.HashAlgorithmName]::SHA256)
}

# Problems with one published map.json; empty when it is fine.
function Test-MapEntry($Map, [string]$FolderName, $Prohibited) {
    $problems = New-Object System.Collections.Generic.List[string]
    $code = [string]$Map.code
    if ($code -cne $FolderName) {
        $problems.Add("code '$code' is not the folder name '$FolderName'")
    }
    if ($code -notmatch $CodePattern -or $code.Length -gt $MaxCodeLength) {
        $problems.Add("code '$code' must be 1-$MaxCodeLength letters, digits, '_' or '-'")
    }
    if (-not [string]$Map.title) {
        $problems.Add('title is empty')
    }
    $authors = @($Map.authors | Where-Object { [string]$_ })
    if ($authors.Count -eq 0) {
        $problems.Add('authors is empty')
    }
    if (-not (Test-Property $Map 'description')) {
        $problems.Add('description is missing')
    }
    if ($Games -notcontains [string]$Map.game) {
        $problems.Add("game must be one of: $($Games -join ', ')")
    }
    if (-not (Test-Property $Map 'revision') -or [int]$Map.revision -lt 1) {
        $problems.Add('not published yet: run tools\Publish-Map.ps1')
        return $problems
    }
    if (-not [string]$Map.archive.url -or [long]$Map.archive.size -le 0 -or
        [string]$Map.archive.sha256 -notmatch '^[0-9a-f]{64}$') {
        $problems.Add('archive needs url, size and sha256')
    }

    $mapFile = "Packages/Maps/$code.sdc"
    $hasMapFile = $false
    foreach ($file in @($Map.files)) {
        $path = [string]$file.path
        $extension = [IO.Path]::GetExtension($path)
        $name = Get-PackageName $path
        if ($extension -cne $extension.ToLowerInvariant() -or -not $PackageFolders.ContainsKey($extension) -or
            $path -cne "$($PackageFolders[$extension])/$name$extension" -or $name -notmatch $CodePattern) {
            $problems.Add("$path is not a package path the engine searches")
            continue
        }
        if ($Prohibited.Contains($name)) {
            $problems.Add("$path uses the name of a package Enhanced ships")
        }
        if ([long]$file.size -le 0 -or [string]$file.sha256 -notmatch '^[0-9a-f]{64}$') {
            $problems.Add("$path needs size and sha256")
        }
        if ($path -ceq $mapFile) {
            $hasMapFile = $true
        }
    }
    if (-not $hasMapFile) {
        $problems.Add("files has no $mapFile")
    }
    return $problems
}
