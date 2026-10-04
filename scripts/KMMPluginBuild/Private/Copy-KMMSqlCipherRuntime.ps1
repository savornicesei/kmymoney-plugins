#Requires -Version 7.0
#Requires -PSEdition Core

function Copy-KMMSqlCipherRuntime {
    <#
    .SYNOPSIS
    Stages the Windows SQLCipher DLL under its import library's expected name.
    .DESCRIPTION
    Works around Craft packages that install sqlite3.dll as libsqlcipher.dll
    without updating the import library. Leaves Craft and existing different
    staged DLLs untouched. A conflicting staged file requires manual resolution.
    .PARAMETER Context
    Build context with the native preset and staging prefix.
    .EXAMPLE
    Copy-KMMSqlCipherRuntime -Context $Context
    .NOTES
    Private helper called after installation. Uses the initialized CRAFT_ROOT.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Context)

    $ErrorActionPreference = 'Stop'
    if ($Context.Preset -ne 'craft-windows' -or [string]::IsNullOrWhiteSpace($env:CRAFT_ROOT)) {
        return
    }
    $CraftBin = Join-Path $env:CRAFT_ROOT 'bin'
    if (Test-Path -LiteralPath (Join-Path $CraftBin 'sqlite3.dll') -PathType Leaf) {
        return
    }
    $Source = Join-Path $CraftBin 'libsqlcipher.dll'
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        return
    }
    $StageBin = Join-Path $Context.Stage 'bin'
    $Destination = Join-Path $StageBin 'sqlite3.dll'
    if (Test-Path -LiteralPath $Destination) {
        if ((Test-Path -LiteralPath $Destination -PathType Leaf) -and
            (Get-FileHash -LiteralPath $Destination).Hash -eq (Get-FileHash -LiteralPath $Source).Hash) {
            return
        }
        throw [IO.IOException]::new("Staged SQLCipher conflicts with Craft: $Destination. Move the existing file aside and rerun Stage.")
    }
    $null = New-Item -ItemType Directory -Path $StageBin -Force
    Copy-Item -LiteralPath $Source -Destination $Destination
    Write-Verbose "Staged SQLCipher compatibility copy: $Destination"
}
