function Invoke-KMMDevelopment {
    <#
    .SYNOPSIS
    Configures, builds, stages, or runs KMyMoney development artifacts.
    .DESCRIPTION
    Initializes Craft and selects the native preset. Build configures first; Install
    configures, builds all default targets, and stages their install rules. Run
    launches the host without building. Native failures stop subsequent steps.
    .PARAMETER Action
    Configure, Build, Install, or Run. Required.
    .PARAMETER Target
    One actual CMake target to build. Valid only with Action Build; omitted means all
    default targets. Installation always builds all default targets.
    .PARAMETER KMMAppFile
    Existing .kmy, .sqlite, or .xml file to open with Run. Relative paths use the
    repository root. SQLite files are passed using the host SQL storage URL.
    .PARAMETER KMMAppArguments
    Arguments forwarded as separate values to the host. Valid only with Action Run.
    .PARAMETER EnvFile
    INI file passed to Craft initialization; defaults to repository env.ini.
    .EXAMPLE
    ./build.ps1 -Tasks Stage -Verbose
    Configures, builds, and stages the native project.
    .EXAMPLE
    ./build.ps1 -Tasks Run -KMMAppArguments @('--help')
    Runs the configured host with one argument.
    .EXAMPLE
    ./build.ps1 -Tasks Build -Target myplugin
    Builds a specific native CMake target.
    .INPUTS
    None.
    .OUTPUTS
    Native command output.
    .NOTES
    Requires the environment variables documented by EnterCraft.
    Configure/Build/Install require the root CMakeLists.txt.
    Errors terminate the script; pwsh -File returns a nonzero status, not necessarily
    the original native exit code. The error message includes that native code.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Configure', 'Build', 'Install', 'Run')]
        [string]$Action,

        [ValidateNotNullOrEmpty()]
        [ValidatePattern('\S')]
        [string]$Target,

        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$KMMAppArguments = @(),

        [string]$KMMAppFile,

        [string]$EnvFile
    )

    if ($PSBoundParameters.ContainsKey('Target') -and $Action -ne 'Build') {
        throw [ArgumentException]::new('-Target is supported only for Build.')
    }
    if ($PSBoundParameters.ContainsKey('KMMAppArguments') -and $Action -ne 'Run') {
        throw [ArgumentException]::new('-KMMAppArguments is supported only for Run.')
    }
    if ($KMMAppFile -and $Action -ne 'Run') {
        throw [ArgumentException]::new('-KMMAppFile is supported only for Run.')
    }
    $HostArguments = @($KMMAppArguments)
    if ($KMMAppFile) {
        $FilePath = [IO.Path]::GetFullPath($KMMAppFile, $script:RepositoryRoot)
        $Extension = [IO.Path]::GetExtension($FilePath)
        if ($Extension -notin '.kmy', '.sqlite', '.xml') {
            throw [ArgumentException]::new('KMMAppFile must be a .kmy, .sqlite, or .xml file.')
        }
        if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
            throw [IO.FileNotFoundException]::new('KMMAppFile does not exist or is not a file.', $FilePath)
        }
        $FileArgument = $FilePath
        if ($Extension -eq '.sqlite') {
            # The host removes the leading separator on Windows. Encode each
            # segment so spaces, Unicode, #, and % remain literal filename data.
            $UrlPath = ($FilePath.Replace('\', '/').Split('/') | ForEach-Object {
                [Uri]::EscapeDataString($_)
            }) -join '/'
            $FileArgument = 'sql://localhost/' + $UrlPath + '?driver=QSQLITE&mode=single'
        }
        $HostArguments += @('--', $FileArgument)
    }
    if (-not $PSCmdlet.ShouldProcess('KMyMoney development environment', $Action)) {
        return
    }

    & {
        param([string]$SelectedFile)
        Set-StrictMode -Version 3.0
        $ErrorActionPreference = 'Stop'
        $PSNativeCommandUseErrorActionPreference = $false
        $RepositoryRoot = $script:RepositoryRoot

        if ($Action -ne 'Run' -and -not (Test-Path -LiteralPath (Join-Path $RepositoryRoot 'CMakeLists.txt') -PathType Leaf)) {
            throw [IO.FileNotFoundException]::new('No CMakeLists.txt exists at the repository root. Restore the project file before building.')
        }

        function Invoke-CheckedNative {
            <#
            .SYNOPSIS
            Invokes a native tool and stops the action if it fails.
            .PARAMETER Executable
            Executable path or command to run.
            .PARAMETER ArgumentList
            Arguments passed separately, without constructing a shell command.
            .EXAMPLE
            Invoke-CheckedNative -Executable cmake -ArgumentList @('--version')
            .NOTES
            Private helper; the script's ShouldProcess decision covers execution.
            #>
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]$Executable,

                [AllowEmptyCollection()]
                [AllowEmptyString()]
                [string[]]$ArgumentList = @()
            )

            Write-Verbose "Running $Executable."
            & $Executable @ArgumentList
            $ExitCode = $LASTEXITCODE
            if ($ExitCode -ne 0) {
                throw [InvalidOperationException]::new("$Executable failed with exit code $ExitCode.")
            }
        }

        Enter-KMMCraftEnvironment -EnvFile $SelectedFile -Confirm:$false
        Push-Location -LiteralPath $RepositoryRoot
        try {
            if ($Action -eq 'Run') {
                if (-not (Test-Path -LiteralPath $env:KMYMONEY_EXECUTABLE -PathType Leaf)) {
                    throw [IO.FileNotFoundException]::new(
                        'KMYMONEY_EXECUTABLE must point to the host binary (inside the .app bundle on macOS).',
                        $env:KMYMONEY_EXECUTABLE
                    )
                }
                Invoke-CheckedNative -Executable $env:KMYMONEY_EXECUTABLE -ArgumentList $HostArguments
                return
            }

            $CMakeExecutable = (Get-Command -Name cmake -CommandType Application | Select-Object -First 1).Source
            Invoke-CheckedNative -Executable $CMakeExecutable -ArgumentList @('--preset', $env:KMYMONEY_PRESET, '-DKMM_PLUGIN_SELECTION=all')
            if ($Action -in @('Build', 'Install')) {
                $BuildArguments = @('--build', '--preset', $env:KMYMONEY_PRESET)
                if ($Target) {
                    $BuildArguments += @('--target', $Target)
                }
                Invoke-CheckedNative -Executable $CMakeExecutable -ArgumentList $BuildArguments
            }
            if ($Action -eq 'Install') {
                Invoke-CheckedNative -Executable $CMakeExecutable -ArgumentList @('--install', "build/$env:KMYMONEY_PRESET")
            }
        } finally {
            Pop-Location
        }
    } $EnvFile
}
