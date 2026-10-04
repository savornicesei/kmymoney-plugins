function Install-KMMApplication {
    <#
    .SYNOPSIS
    Installs a Craft KMyMoney SDK for FirstRun and CI on any supported OS.
    .DESCRIPTION
    Bootstraps Craft when absent, selects its KMyMoney version, installs dependencies,
    and builds the host from source so matching generated headers are available.
    Writes intermediate configuration to ignored build/setup/env.ini. Requires Python,
    Git, a native compiler, network access, and the platform's Craft prerequisites.
    .PARAMETER Context
    Build context created by build.ps1, including the selected INI values.
    .EXAMPLE
    ./build.ps1 -Tasks CI -KMMAppVersion master -EnvFile env.ci.ini
    .NOTES
    CI provisioning installs into CRAFT_ROOT (default build/craft). Use a disposable
    prefix for CI. Normal Build/BuildCI tasks only select the version and build plugins.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Explicit FirstRun/CI provisioning; native build operations require execution.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Context)
    $ErrorActionPreference = 'Stop'
    $Values = $Context.EnvironmentValues.Clone()
    $ReportDirectory = Join-Path $Context.Source 'build/setup'
    New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
    if (-not $Values.CRAFT_ROOT) { $Values.CRAFT_ROOT = Join-Path $Context.Source 'build/craft' }
    if (-not [IO.Path]::IsPathFullyQualified($Values.CRAFT_ROOT)) { throw 'CRAFT_ROOT must be absolute.' }
    $Candidates = if ($Values.CRAFT_PYTHON) { @($Values.CRAFT_PYTHON) } else {
        $Suffix = if ($IsWindows) { '.exe' } else { '' }
        @((Join-Path $Values.CRAFT_ROOT "bin/python3$Suffix"),
            (Join-Path $Values.CRAFT_ROOT "bin/python$Suffix"), 'python3', 'python')
    }
    $Python = $null
    foreach ($Candidate in $Candidates) {
        $Application = Get-Command $Candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($Application) {
            try {
                Invoke-KMMNativeTool $Application.Source @('-c', 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)') | Out-Null
                $Python = $Application.Source
                break
            } catch {
                if ($Values.CRAFT_PYTHON) { throw }
                Write-Verbose "Skipping unusable Python candidate: $Candidate"
            }
        }
    }
    if (-not $Python) { throw 'Craft provisioning requires Python 3.9+. Set CRAFT_PYTHON in the INI.' }
    $Values.CRAFT_PYTHON = $Python
    $CraftScript = Join-Path $Values.CRAFT_ROOT 'craft/bin/craft.py'
    if (-not (Test-Path -LiteralPath $CraftScript -PathType Leaf)) {
        $Bootstrap = Join-Path $ReportDirectory 'CraftBootstrap.py'
        Invoke-WebRequest -Uri 'https://invent.kde.org/packaging/craft/-/raw/master/setup/CraftBootstrap.py' -OutFile $Bootstrap
        Invoke-KMMNativeTool $Python @($Bootstrap, '--prefix', $Values.CRAFT_ROOT, '--use-defaults')
    }
    # Craft initialization validates paths before the host source has been fetched.
    $Values.KMYMONEY_SOURCE_DIR = $Context.Source
    $ExecutableName = if ($IsWindows) { 'kmymoney.exe' } else { 'kmymoney' }
    $Values.KMYMONEY_EXECUTABLE = Join-Path $Values.CRAFT_ROOT "bin/$ExecutableName"
    $Context.EnvFile = Join-Path $ReportDirectory 'env.ini'
    $Values.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" } |
        Set-Content -LiteralPath $Context.EnvFile -Encoding utf8
    Enter-KMMCraftEnvironment -EnvFile $Context.EnvFile -Confirm:$false
    Set-KMMAppVersion -KMMAppVersion $Context.KMMAppVersion -Confirm:$false
    Invoke-KMMNativeTool $Python @($CraftScript, '--ci-mode', '--install-deps', 'extragear/kmymoney')
    # Explicit source actions avoid a binary-only SDK without generated headers.
    Invoke-KMMNativeTool $Python @($CraftScript, '--ci-mode', '--no-cache', '--fetch', '--unpack',
        '--configure', '--make', '--install', '--post-install', '--qmerge', '--post-qmerge', 'extragear/kmymoney')
    # buildTarget is the reusable tag/branch; version can include daily or patch suffixes.
    $TargetOutput = @(Invoke-KMMNativeTool $Python @($CraftScript, '-q', '--get', 'buildTarget', 'extragear/kmymoney'))
    if ($TargetOutput.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$TargetOutput[0]) -or
        [string]$TargetOutput[0] -match '[\r\n\x00]') {
        throw 'Craft did not return a single KMyMoney build target.'
    }
    $Values.KMM_APP_VERSION = ([string]$TargetOutput[0]).Trim()
    $Context.KMMAppVersion = $Values.KMM_APP_VERSION
    $SourceOutput = @(Invoke-KMMNativeTool $Python @($CraftScript, '-q', '--get', 'sourceDir', 'extragear/kmymoney'))
    $BuildOutput = @(Invoke-KMMNativeTool $Python @($CraftScript, '-q', '--get', 'buildDir', 'extragear/kmymoney'))
    $Values.KMYMONEY_SOURCE_DIR = [string]($SourceOutput | Select-Object -Last 1)
    $Values.KMYMONEY_SDK_SOURCE_DIR = $Values.KMYMONEY_SOURCE_DIR
    $Values.KMYMONEY_BUILD_DIR = [string]($BuildOutput | Select-Object -Last 1)
    foreach ($Name in 'KMYMONEY_SOURCE_DIR', 'KMYMONEY_BUILD_DIR') {
        if (-not [IO.Path]::IsPathFullyQualified($Values[$Name]) -or
            -not (Test-Path -LiteralPath $Values[$Name] -PathType Container)) {
            throw "Craft returned an invalid $Name path."
        }
    }
    if ($IsMacOS -and -not (Test-Path -LiteralPath $Values.KMYMONEY_EXECUTABLE)) {
        $BundleRoot = Join-Path $Values.CRAFT_ROOT 'Applications'
        $Executable = Get-ChildItem -LiteralPath $BundleRoot -Recurse -File -Filter kmymoney |
            Where-Object { $_.FullName -like '*/Contents/MacOS/kmymoney' } | Select-Object -First 1
        if (-not $Executable) { throw 'Cannot find the installed KMyMoney bundle executable.' }
        $Values.KMYMONEY_EXECUTABLE = $Executable.FullName
    }
    $Values.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" } |
        Set-Content -LiteralPath $Context.EnvFile -Encoding utf8
    $Context.EnvironmentValues = $Values
    foreach ($Name in 'KMYMONEY_SDK_SOURCE_DIR', 'KMYMONEY_BUILD_DIR') {
        [Environment]::SetEnvironmentVariable($Name, $Values[$Name], 'Process')
    }
    Enter-KMMCraftEnvironment -EnvFile $Context.EnvFile -Confirm:$false
}
