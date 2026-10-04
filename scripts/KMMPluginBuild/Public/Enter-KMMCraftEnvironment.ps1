function Enter-KMMCraftEnvironment {
    <#
    .SYNOPSIS
    Initializes the current process for native KMyMoney plugin development.
    .DESCRIPTION
    Imports Craft's JSON environment, selects the native CMake preset, and adds local
    staging paths. Requires absolute CRAFT_ROOT, KMYMONEY_SOURCE_DIR, and
    KMYMONEY_EXECUTABLE environment variables. CRAFT_PYTHON optionally selects Python.
    Setup failure restores the process environment. Craft's own cache/log writes
    cannot be rolled back. No build directories or plugin projects are created.
    .PARAMETER EnvFile
    Optional INI path relative to the repository root. File values override the
    matching environment variables. Defaults to env.ini if present.
    .EXAMPLE
    ./build.ps1 -Tasks EnterCraft -Verbose
    Initializes this PowerShell session before starting an IDE.
    .EXAMPLE
    ./build.ps1 -Tasks EnterCraft -Preview
    Previews setup without invoking Python or changing the environment.
    .INPUTS
    None.
    .OUTPUTS
    None. Diagnostics use the verbose stream; Craft may write diagnostics to stderr.
    .NOTES
    Requires PowerShell 7 Core and Python 3.9 or later. Exports KMYMONEY_PRESET and
    KMYMONEY_STAGE_DIR and defines the global craft CLI forwarding function.
    A child pwsh process cannot initialize its parent shell.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseApprovedVerbs', '', Scope = 'Function', Target = 'global:craft',
        Justification = 'Preserves the standard Craft CLI command name.'
    )]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param([string]$EnvFile)

    # Child scope keeps preferences, strict mode, and helper functions out of the caller.
    & {
        param([string]$SelectedFile)
        Set-StrictMode -Version 3.0
        $ErrorActionPreference = 'Stop'
        $PSNativeCommandUseErrorActionPreference = $false

        if (-not $PSCmdlet.ShouldProcess('Current process', 'Initialize Craft and plugin search paths')) {
            return
        }

        $RepositoryRoot = $script:RepositoryRoot
        $FileValues = Read-KMMLocalEnvironment -EnvFile $SelectedFile
        $PathComparer = if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
        $Preset = if ($IsWindows) {
            'craft-windows'
        } elseif ($IsLinux) {
            'craft-linux'
        } elseif ($IsMacOS) {
            'craft-macos'
        } else {
            throw [PlatformNotSupportedException]::new('Supported platforms are Windows, Linux, and macOS.')
        }

        $LocalPaths = @{}
        foreach ($Name in @('CRAFT_ROOT', 'KMYMONEY_SOURCE_DIR', 'KMYMONEY_EXECUTABLE')) {
            $Value = if ($FileValues.ContainsKey($Name)) { $FileValues[$Name] } else { [Environment]::GetEnvironmentVariable($Name) }
            if ([string]::IsNullOrWhiteSpace($Value) -or -not [IO.Path]::IsPathFullyQualified($Value)) {
                throw [ArgumentException]::new("Set $Name to an absolute local path. See README.md.")
            }
            $LocalPaths[$Name] = [IO.Path]::GetFullPath($Value)
        }
        foreach ($Name in @('CRAFT_ROOT', 'KMYMONEY_SOURCE_DIR')) {
            if (-not (Test-Path -LiteralPath $LocalPaths[$Name] -PathType Container)) {
                throw [IO.DirectoryNotFoundException]::new("$Name must point to an existing directory: $($LocalPaths[$Name])")
            }
            $LocalPaths[$Name] = (Resolve-Path -LiteralPath $LocalPaths[$Name]).ProviderPath
        }

        $CraftRoot = $LocalPaths['CRAFT_ROOT']
        $SetupHelper = Join-Path $CraftRoot 'craft/bin/CraftSetupHelper.py'
        if (-not (Test-Path -LiteralPath $SetupHelper -PathType Leaf)) {
            throw [IO.FileNotFoundException]::new('Craft setup helper was not found.', $SetupHelper)
        }
        if ($env:KDEROOT) {
            $ActiveRoot = (Resolve-Path -LiteralPath $env:KDEROOT).ProviderPath
            if (-not $PathComparer.Equals(
                [IO.Path]::GetFullPath($ActiveRoot).TrimEnd('/','\'),
                [IO.Path]::GetFullPath($CraftRoot).TrimEnd('/','\'))) {
                throw [InvalidOperationException]::new("A different Craft installation is active: '$ActiveRoot'; requested: '$CraftRoot'. Start a fresh pwsh session.")
            }
        }

        $ConfiguredPython = if ($FileValues.ContainsKey('CRAFT_PYTHON')) { $FileValues['CRAFT_PYTHON'] } else { $env:CRAFT_PYTHON }
        $PythonCandidates = if ($ConfiguredPython) {
            @($ConfiguredPython)
        } else {
            $ExecutableSuffix = if ($IsWindows) { '.exe' } else { '' }
            @(
                (Join-Path $CraftRoot "bin/python3$ExecutableSuffix"),
                (Join-Path $CraftRoot "bin/python$ExecutableSuffix"),
                'python3',
                'python'
            )
        }
        $PythonExecutable = $null
        foreach ($Candidate in $PythonCandidates) {
            try {
                $Application = Get-Command -Name $Candidate -CommandType Application -ErrorAction Stop |
                    Select-Object -First 1
                & $Application.Source -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)'
                if ($LASTEXITCODE -eq 0) {
                    $PythonExecutable = $Application.Source
                    break
                }
            } catch {
                Write-Verbose "Python candidate is unavailable: $Candidate"
            }
        }
        if (-not $PythonExecutable) {
            throw [InvalidOperationException]::new('No usable Python 3.9+ interpreter was found. Set CRAFT_PYTHON to a working executable.')
        }

        function Add-PluginEnvironmentPath {
            <#
            .SYNOPSIS
            Prepends process search paths while preserving platform-specific case rules.
            .PARAMETER Name
            Environment variable containing a native path-separated list.
            .PARAMETER Path
            Directories to prepend in priority order.
            .EXAMPLE
            Add-PluginEnvironmentPath -Name PATH -Path '/tmp/plugins/bin'
            .NOTES
            Private helper; initialization's ShouldProcess decision covers this change.
            #>
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]$Name,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string[]]$Path
            )

            $Existing = [Environment]::GetEnvironmentVariable($Name)
            $Separator = [string][IO.Path]::PathSeparator
            $Seen = [Collections.Generic.HashSet[string]]::new($PathComparer)
            $Entries = @($Path) + @($Existing -split [regex]::Escape($Separator))
            $UniquePaths = foreach ($Entry in $Entries) {
                if ($Entry -and $Seen.Add($Entry)) {
                    $Entry
                }
            }
            [Environment]::SetEnvironmentVariable($Name, ($UniquePaths -join $Separator), 'Process')
        }

        $OriginalEnvironment = [Environment]::GetEnvironmentVariables()
        try {
            foreach ($Name in $LocalPaths.Keys) {
                [Environment]::SetEnvironmentVariable($Name, $LocalPaths[$Name], 'Process')
            }
            $env:CRAFT_PYTHON = $PythonExecutable
            # craftRoot is Craft's variable; CRAFT_ROOT is this repository's input.
            $env:craftRoot = Join-Path $CraftRoot 'craft'
            Write-Verbose "Importing the Craft environment for $Preset from $CraftRoot."
            $EnvironmentJson = & $PythonExecutable $SetupHelper --setup --format=json
            if ($LASTEXITCODE -ne 0) {
                throw [InvalidOperationException]::new("Craft environment initialization failed with exit code $LASTEXITCODE.")
            }
            $CraftEnvironment = ($EnvironmentJson -join "`n") | ConvertFrom-Json -AsHashtable
            if ($CraftEnvironment -isnot [Collections.IDictionary]) {
                throw [IO.InvalidDataException]::new('Craft must return a JSON object containing environment variables.')
            }
            foreach ($Name in $CraftEnvironment.Keys) {
                if ([string]::IsNullOrEmpty($Name) -or $Name.Contains('=') -or
                    $CraftEnvironment[$Name] -isnot [string]) {
                    throw [IO.InvalidDataException]::new('Craft returned an invalid environment variable.')
                }
            }
            $ReturnedRoot = $CraftEnvironment['KDEROOT']
            if ([string]::IsNullOrWhiteSpace($ReturnedRoot) -or
                -not [IO.Path]::IsPathFullyQualified($ReturnedRoot) -or
                -not $PathComparer.Equals([IO.Path]::GetFullPath($ReturnedRoot).TrimEnd('/','\'), $CraftRoot.TrimEnd('/','\'))) {
                throw [IO.InvalidDataException]::new('Craft returned an unexpected KDEROOT.')
            }
            foreach ($Name in $CraftEnvironment.Keys) {
                [Environment]::SetEnvironmentVariable($Name, $CraftEnvironment[$Name], 'Process')
            }
            # Craft settings must not replace this repository's explicit local inputs.
            foreach ($Name in $LocalPaths.Keys) {
                [Environment]::SetEnvironmentVariable($Name, $LocalPaths[$Name], 'Process')
            }
            $env:CRAFT_PYTHON = $PythonExecutable
            $env:KMYMONEY_PRESET = $Preset
            $env:KMYMONEY_STAGE_DIR = Join-Path $RepositoryRoot "stage/$Preset"

            Add-PluginEnvironmentPath -Name PATH -Path (Join-Path $env:KMYMONEY_STAGE_DIR 'bin')
            Add-PluginEnvironmentPath -Name QT_PLUGIN_PATH -Path @(
                (Join-Path $env:KMYMONEY_STAGE_DIR 'lib/plugins'),
                (Join-Path $env:KMYMONEY_STAGE_DIR 'plugins')
            )
            Add-PluginEnvironmentPath -Name XDG_DATA_DIRS -Path (Join-Path $env:KMYMONEY_STAGE_DIR 'share')
            if ($IsWindows) {
                # KDEInstallDirs uses bin/data for Windows application data and catalogs.
                Add-PluginEnvironmentPath -Name XDG_DATA_DIRS -Path (Join-Path $env:KMYMONEY_STAGE_DIR 'bin/data')
            }
            $LibraryPaths = @((Join-Path $env:KMYMONEY_STAGE_DIR 'lib'), (Join-Path $CraftRoot 'lib'))
            if ($IsLinux) {
                Add-PluginEnvironmentPath -Name LD_LIBRARY_PATH -Path $LibraryPaths
            } elseif ($IsMacOS) {
                Add-PluginEnvironmentPath -Name DYLD_LIBRARY_PATH -Path $LibraryPaths
            }
        } catch {
            # Roll back process changes, including variables absent before initialization.
            foreach ($Name in @([Environment]::GetEnvironmentVariables().Keys)) {
                if (-not $OriginalEnvironment.Contains($Name)) {
                    Remove-Item -LiteralPath "Env:$Name"
                }
            }
            foreach ($Name in $OriginalEnvironment.Keys) {
                [Environment]::SetEnvironmentVariable($Name, $OriginalEnvironment[$Name], 'Process')
            }
            throw
        }

        function global:craft {
            <#
            .SYNOPSIS
            Forwards arguments unchanged to Craft's Python CLI.
            .DESCRIPTION
            Uses CRAFT_PYTHON and CRAFT_ROOT from the initialized environment.
            This intentionally remains a native-style function: PowerShell common
            parameters must not consume Craft's own flags. Inspect LASTEXITCODE.
            .EXAMPLE
            craft --version
            .NOTES
            Replaces the session's existing craft function after successful setup.
            #>
            & $env:CRAFT_PYTHON (Join-Path $env:CRAFT_ROOT 'craft/bin/craft.py') @args
        }
        Write-Verbose "Craft is ready. Staging prefix: $env:KMYMONEY_STAGE_DIR"
    } $EnvFile
}
