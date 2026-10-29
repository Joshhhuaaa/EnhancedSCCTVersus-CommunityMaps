# Shared by the scripts in this folder; dot-source it.
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path $PSScriptRoot -Parent
$MapsDir = Join-Path $RepoRoot 'maps'
$IndexPath = Join-Path $RepoRoot 'index.signed'
$ProhibitedPath = Join-Path $RepoRoot 'prohibited.txt'
$OfficialPath = Join-Path $RepoRoot 'official.txt'
$PublicKeyPath = Join-Path $RepoRoot 'signing-key.pub'
$DefaultKeyPath = Join-Path $env:USERPROFILE '.scct-reloaded\map-index-signing.key'
$DefaultRepo = 'Joshhhuaaa/EnhancedSCCTVersus-CommunityMaps'

# Must match CommunityMaps.cpp in Reloaded.Core.
$IndexSchema = 1
$IndexSignatureHeader = "SCCT Versus Reloaded map index`n"
$MaxCodeLength = 20
$CodePattern = '^[A-Za-z0-9_-]+$'
# A playlist name or variant word.
$MaxNameLength = 64
$MaxPreviewSize = 256KB
$MaxPreviewDimension = 512
# Both teams together: solo training, then 1v1 to 4v4.
$RecommendedPlayerCounts = @(1, 2, 4, 6, 8)
# The folders under Packages a map's files go in. The engine finds a searched package by name alone. The editor's copy
# of the map (MapsEd) and its sound bank (.uas) are found by the map's name, so they are named after it.
$PackageFolders = @(
    [pscustomobject]@{ Folder = 'Maps'; Extension = '.sdc'; Searched = $true }
    [pscustomobject]@{ Folder = 'MapsEd'; Extension = '.sdc'; Searched = $false }
    [pscustomobject]@{ Folder = 'Textures'; Extension = '.utx'; Searched = $true }
    [pscustomobject]@{ Folder = 'Textures'; Extension = '.utc'; Searched = $true }
    [pscustomobject]@{ Folder = 'StaticMeshes'; Extension = '.usx'; Searched = $true }
    [pscustomobject]@{ Folder = 'Sounds'; Extension = '.uax'; Searched = $true }
    [pscustomobject]@{ Folder = 'Sounds'; Extension = '.uas'; Searched = $false }
    [pscustomobject]@{ Folder = 'Animations'; Extension = '.ukx'; Searched = $true }
)
# A map folder holds its metadata only; packages go in releases.
$MapFolderFiles = @('map.json', 'preview.jpg')

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-Sha256([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Read-NameList([string]$Path) {
    $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in Get-Content -LiteralPath $Path) {
            if ($line.Trim() -and -not $line.StartsWith('#')) {
                [void]$names.Add($line.Trim())
            }
        }
    }
    return , $names
}

function Get-Prohibited {
    Read-NameList $ProhibitedPath
}

# Codes every player installs. Only the repo owners edit official.txt.
function Get-Official {
    Read-NameList $OfficialPath
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

# The $PackageFolders entry of a path such as Packages/Maps/FortX.sdc, or $null when the game does not read it.
function Get-PackageFolder([string]$Path) {
    $parts = $Path -split '/'
    if ($parts.Count -ne 3 -or $parts[0] -cne 'Packages' -or (Get-PackageName $Path) -notmatch $CodePattern) {
        return $null
    }
    $extension = [IO.Path]::GetExtension($Path)
    $PackageFolders | Where-Object { $_.Folder -ceq $parts[1] -and $_.Extension -ceq $extension } | Select-Object -First 1
}

# Every map has these. The sound bank holds at least the win, lose and objective sounds.
function Get-RequiredFiles([string]$Code) {
    @("Packages/Maps/$Code.sdc", "Packages/MapsEd/$Code.sdc", "Packages/Sounds/$Code.uas")
}

function Test-Property($Object, [string]$Name) {
    $null -ne $Object.PSObject.Properties[$Name]
}

# Width and height from a JPEG's frame header, or $null when it is not a JPEG.
function Get-JpegSize([byte[]]$Bytes) {
    if ($Bytes.Length -lt 4 -or $Bytes[0] -ne 0xFF -or $Bytes[1] -ne 0xD8) {
        return $null
    }
    $i = 2
    while ($i + 3 -lt $Bytes.Length) {
        if ($Bytes[$i] -ne 0xFF) {
            return $null
        }
        $marker = $Bytes[$i + 1]
        if ($marker -eq 0xFF) {
            $i++
            continue
        }
        $i += 2
        if ($marker -eq 0x01 -or ($marker -ge 0xD0 -and $marker -le 0xD8)) {
            continue
        }
        # The image data or its end, with no frame header before it.
        if ($marker -eq 0xD9 -or $marker -eq 0xDA) {
            return $null
        }
        # Every SOFn but the DHT, JPG and DAC markers that share the range.
        if ($marker -ge 0xC0 -and $marker -le 0xCF -and $marker -notin 0xC4, 0xC8, 0xCC) {
            if ($i + 6 -ge $Bytes.Length) {
                return $null
            }
            return [pscustomobject]@{ Width = $Bytes[$i + 5] * 256 + $Bytes[$i + 6]; Height = $Bytes[$i + 3] * 256 + $Bytes[$i + 4] }
        }
        $i += $Bytes[$i] * 256 + $Bytes[$i + 1]
    }
    return $null
}

# Problems with a map folder's preview.jpg; empty when it is fine or there is none.
function Test-Preview($Folder) {
    $problems = New-Object System.Collections.Generic.List[string]
    $path = Join-Path $Folder.FullName 'preview.jpg'
    if (-not (Test-Path -LiteralPath $path)) {
        return $problems
    }
    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -gt $MaxPreviewSize) {
        $problems.Add("preview.jpg is larger than $($MaxPreviewSize / 1KB) KB")
    }
    $size = Get-JpegSize $bytes
    if (-not $size) {
        $problems.Add('preview.jpg is not a JPEG')
    }
    elseif ($size.Width -gt $MaxPreviewDimension -or $size.Height -gt $MaxPreviewDimension) {
        $problems.Add("preview.jpg is $($size.Width)x$($size.Height); the most is $($MaxPreviewDimension)x$MaxPreviewDimension")
    }
    return $problems
}

# A map folder's preview as the index lists it, relative to index.signed; $null without a preview.jpg.
function Get-PreviewEntry($Folder) {
    $path = Join-Path $Folder.FullName 'preview.jpg'
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }
    [ordered]@{ url = "maps/$($Folder.Name)/preview.jpg"; size = (Get-Item -LiteralPath $path).Length; sha256 = Get-Sha256 $path }
}

# The index entry for a map.json, fields in index order.
function ConvertTo-IndexEntry($Map, [bool]$Official, $Preview) {
    [ordered]@{
        code        = [string]$Map.code
        title       = [string]$Map.title
        authors     = @($Map.authors | ForEach-Object { [string]$_ })
        description = [string]$Map.description
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
        official    = $Official
        playlists   = @($Map.playlists | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
        variant     = [string]$Map.variant
        preview     = [ordered]@{ url = [string]$Preview.url; size = [long]$Preview.size; sha256 = [string]$Preview.sha256 }
        recommendedPlayers = [int]$Map.recommendedPlayers
    }
}

function Get-MapFolders {
    if (-not (Test-Path $MapsDir)) {
        return @()
    }
    @(Get-ChildItem -LiteralPath $MapsDir -Directory | Sort-Object { $_.Name.ToLowerInvariant() })
}

function Get-IndexEntries {
    $official = Get-Official
    @(Get-MapFolders | ForEach-Object {
            ConvertTo-IndexEntry (Read-MapJson (Join-Path $_.FullName 'map.json')) $official.Contains($_.Name) (Get-PreviewEntry $_)
        })
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
    $players = $Map.recommendedPlayers
    if (-not ($players -is [int] -or $players -is [long]) -or $RecommendedPlayerCounts -notcontains $players) {
        $problems.Add('recommendedPlayers must be 1 (solo), 2 (1v1), 4 (2v2), 6 (3v3) or 8 (4v4)')
    }
    if (Test-Property $Map 'official') {
        $problems.Add('official is not a map.json field: the repo owners list official maps in official.txt')
    }
    $variant = [string]$Map.variant
    if ($variant.Length -gt $MaxNameLength -or $variant.Contains(' ')) {
        $problems.Add("variant must be one word of at most $MaxNameLength characters")
    }
    foreach ($playlist in @($Map.playlists | Where-Object { $null -ne $_ })) {
        if (-not [string]$playlist -or ([string]$playlist).Length -gt $MaxNameLength) {
            $problems.Add("playlist names must be 1-$MaxNameLength characters")
        }
    }
    if (-not (Test-Property $Map 'revision') -or [int]$Map.revision -lt 1) {
        $problems.Add('not published yet: run tools\Publish-Map.ps1')
        return $problems
    }
    if (-not [string]$Map.archive.url -or [long]$Map.archive.size -le 0 -or
        [string]$Map.archive.sha256 -notmatch '^[0-9a-f]{64}$') {
        $problems.Add('archive needs url, size and sha256')
    }

    $paths = @($Map.files | ForEach-Object { [string]$_.path })
    foreach ($file in @($Map.files)) {
        $path = [string]$file.path
        $name = Get-PackageName $path
        $folder = Get-PackageFolder $path
        if (-not $folder) {
            $problems.Add("$path is not a file the game reads from Packages")
            continue
        }
        if (-not $folder.Searched -and $name -cne $code) {
            $problems.Add("$path must be named $code$($folder.Extension): the game finds it by the map's name")
        }
        if ($Prohibited.Contains($name)) {
            $problems.Add("$path uses the name of a package Enhanced ships")
        }
        if ([long]$file.size -le 0 -or [string]$file.sha256 -notmatch '^[0-9a-f]{64}$') {
            $problems.Add("$path needs size and sha256")
        }
    }
    foreach ($required in Get-RequiredFiles $code) {
        if ($paths -cnotcontains $required) {
            $problems.Add("files has no $required")
        }
    }
    return $problems
}
