# Checks every map.json and that index.signed is signed and lists exactly them. CI runs it on every push and PR.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

$problems = New-Object System.Collections.Generic.List[string]
$prohibited = Get-Prohibited
$owners = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)

foreach ($folder in Get-MapFolders) {
    foreach ($file in Get-ChildItem -LiteralPath $folder.FullName -Recurse) {
        # Case-sensitive: GitHub serves preview.jpg by its exact name.
        if ($file.PSIsContainer -or $MapFolderFiles -cnotcontains $file.Name) {
            $problems.Add("maps/$($folder.Name)/$($file.Name): a map folder holds only $($MapFolderFiles -join ' and '); packages go in releases")
        }
    }
    foreach ($problem in @(Test-Preview $folder)) {
        $problems.Add("maps/$($folder.Name): $problem")
    }
    $mapJson = Join-Path $folder.FullName 'map.json'
    if (-not (Test-Path $mapJson)) {
        $problems.Add("maps/$($folder.Name) has no map.json")
        continue
    }
    $map = Read-MapJson $mapJson
    foreach ($problem in @(Test-MapEntry $map $folder.Name $prohibited)) {
        $problems.Add("maps/$($folder.Name): $problem")
    }
    foreach ($file in @($map.files)) {
        $packageFolder = Get-PackageFolder ([string]$file.path)
        if (-not $packageFolder -or -not $packageFolder.Searched) {
            continue
        }
        $name = Get-PackageName ([string]$file.path)
        if ($owners.ContainsKey($name)) {
            $problems.Add("maps/$($folder.Name): package $name is also in maps/$($owners[$name])")
        }
        else {
            $owners[$name] = $folder.Name
        }
    }
}

$mapCodes = @(Get-MapFolders | ForEach-Object { $_.Name })
$official = Get-Official
foreach ($code in $official) {
    if ($mapCodes -notcontains $code) {
        $problems.Add("official.txt lists $code, which has no folder in maps/")
    }
}

$index = Read-SignedIndex
if (-not $index) {
    if ((Get-MapFolders).Count -gt 0) {
        $problems.Add('index.signed is missing: run tools\Publish-Map.ps1 -Reindex')
    }
}
elseif (-not (Test-IndexSignature $index.Signature $index.Payload)) {
    $problems.Add('index.signed is not signed by signing-key.pub: run tools\Publish-Map.ps1 -Reindex')
}
else {
    $parsed = [Text.Encoding]::UTF8.GetString($index.Payload) | ConvertFrom-Json
    if ([int]$parsed.schema -ne $IndexSchema) {
        $problems.Add("index.signed is schema $($parsed.schema), not $IndexSchema")
    }
    $listed = (@($parsed.maps | ForEach-Object { ConvertTo-IndexEntry $_ ([bool]$_.official) $_.preview }) | ConvertTo-Json -Depth 8 -Compress)
    $expected = (Get-IndexEntries | ConvertTo-Json -Depth 8 -Compress)
    if ($listed -cne $expected) {
        $problems.Add('index.signed does not match the map folders: run tools\Publish-Map.ps1 -Reindex')
    }
}

if ($problems.Count -gt 0) {
    $problems | ForEach-Object { Write-Host "::error::$_" }
    exit 1
}
Write-Host "$((Get-MapFolders).Count) maps OK."
