# Rewrites prohibited.txt from an Enhanced install: every package name it ships, which no community map may
# reuse. Run it on every Enhanced release, with -HeaderPath to refresh Reloaded.Core's copy too.
#
#   tools\Update-Prohibited.ps1 -Install <Enhanced install> [-HeaderPath <Reloaded.Core\ProhibitedPackages.g.h>]
param(
    [Parameter(Mandatory = $true)][string]$Install,
    [string]$HeaderPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

$packagesDir = Join-Path $Install 'Packages'
$systemDir = Join-Path $Install 'System'
if (-not (Test-Path $packagesDir) -or -not (Test-Path $systemDir)) {
    throw "$Install has no Packages and System folders."
}

$files = @(Get-ChildItem -LiteralPath $packagesDir -File -Recurse) + @(Get-ChildItem -LiteralPath $systemDir -File -Recurse -Filter '*.u')
$names = [string[]]@($files | ForEach-Object { (Get-PackageName $_.Name).ToLowerInvariant() } | Select-Object -Unique)
[Array]::Sort($names, [StringComparer]::Ordinal)

$text = @('# Package names Enhanced ships, written by tools\Update-Prohibited.ps1. No community map may use one.') + $names
[IO.File]::WriteAllText($ProhibitedPath, ($text -join "`n") + "`n", $Utf8NoBom)
Write-Host "Wrote $($names.Count) names to prohibited.txt."

if ($HeaderPath) {
    $rows = for ($i = 0; $i -lt $names.Length; $i += 8) {
        '    ' + (($names[$i..([Math]::Min($i + 7, $names.Length - 1))] | ForEach-Object { '"' + $_ + '"' }) -join ', ') + ','
    }
    $header = @(
        '#pragma once'
        ''
        '// Written by the community maps repo''s tools/Update-Prohibited.ps1: every package name Enhanced ships, lowercase.'
        'inline constexpr const char* ProhibitedPackages[] = {'
        $rows
        '};'
        ''
    ) -join "`r`n"
    [IO.File]::WriteAllText($HeaderPath, $header)
    Write-Host "Wrote $HeaderPath."
}
