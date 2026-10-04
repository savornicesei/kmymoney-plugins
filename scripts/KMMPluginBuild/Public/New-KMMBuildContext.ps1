function New-KMMBuildContext {
    <#
    .SYNOPSIS
    Resolves the selected plugins and native build paths for a task invocation.
    .EXAMPLE
    New-KMMBuildContext -Plugins all
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory context without changing external state.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string[]]$Plugins = @('all'),
        [string]$EnvFile
    )

    $ErrorActionPreference = 'Stop'
    $Available = @(Get-ChildItem -LiteralPath (Join-Path $script:RepositoryRoot 'plugins') -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'CMakeLists.txt') -PathType Leaf } |
        Sort-Object Name | ForEach-Object Name)

    if ($Plugins -contains 'all') {
        if ($Plugins.Count -ne 1) { throw "Use 'all' alone, or provide plugin directory names." }
        $Selected = $Available
    } else {
        $Selected = @($Plugins | Sort-Object -Unique | ForEach-Object {
            $Requested = $_
            $Match = @($Available | Where-Object { $_ -ceq $Requested })
            if ($Match.Count -ne 1) { throw "Unknown plugin '$Requested'. Available plugins: $($Available -join ', ')." }
            $Match[0]
        })
    }

    $Preset = if ($IsWindows) {
        'craft-windows'
    } elseif ($IsLinux) {
        'craft-linux'
    } elseif ($IsMacOS) {
        'craft-macos'
    } else {
        throw 'Supported platforms are Windows, Linux, and macOS.'
    }

    return @{
        Source = $script:RepositoryRoot
        Preset = $Preset
        Plugins = @($Selected)
        EnvFile = $EnvFile
        Build = Join-Path $script:RepositoryRoot "build/$Preset"
        Stage = Join-Path $script:RepositoryRoot "stage/$Preset"
        Environment = $null
        CraftFunction = $null
        Location = $null
        CMake = $null
        CTest = $null
    }
}
