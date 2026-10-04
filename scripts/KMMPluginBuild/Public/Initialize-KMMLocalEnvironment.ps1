function Initialize-KMMLocalEnvironment {
    <#
    .SYNOPSIS
    Installs KMyMoney through Craft and saves local development paths.
    .DESCRIPTION
    Defaults Craft to the user's kdecraft-root directory. Blank application paths
    are discovered after provisioning; explicit paths and other settings survive.
    The selected INI is replaced atomically only after provisioning succeeds.
    .PARAMETER EnvFile
    INI path relative to the repository, or an absolute path.
    .PARAMETER ModulePath
    Optional dependency module cache directory.
    .PARAMETER KMMAppVersion
    Optional Craft version or branch; otherwise use the selected INI setting.
    .EXAMPLE
    Initialize-KMMLocalEnvironment -EnvFile laptop.env.ini
    #>
    [CmdletBinding()]
    param([string]$EnvFile, [string]$ModulePath, [string]$KMMAppVersion)
    $ErrorActionPreference = 'Stop'
    $ENV_FILE = if ($EnvFile) { [IO.Path]::GetFullPath($EnvFile, $script:RepositoryRoot) }
        else { Join-Path $script:RepositoryRoot 'env.ini' }
    Initialize-KMMPowerShell -Path $ModulePath -Confirm:$false
    $ExistingValues = if (Test-Path -LiteralPath $ENV_FILE -PathType Leaf) {
        Read-KMMLocalEnvironment -EnvFile $ENV_FILE
    } else { @{} }
    $Values = Get-KMMBuildEnvironment -EnvFile $EnvFile -AllowMissing
    if ($PSBoundParameters.ContainsKey('KMMAppVersion')) { $Values.KMM_APP_VERSION = $KMMAppVersion }
    $Parent = Split-Path -Parent $ENV_FILE
    if (-not (Test-Path -LiteralPath $Parent -PathType Container)) {
        throw "Environment file directory does not exist: $Parent"
    }
    $ProvidedPaths = @{}
    foreach ($Name in 'CRAFT_ROOT', 'KMYMONEY_SOURCE_DIR', 'KMYMONEY_EXECUTABLE', 'CRAFT_PYTHON') {
        $Default = if ($ExistingValues.ContainsKey($Name)) { $ExistingValues[$Name] }
        else { [Environment]::GetEnvironmentVariable($Name) }
        if ($Name -eq 'CRAFT_ROOT' -and -not $Default) {
            $Default = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'kdecraft-root'
        }
        $Hint = if ($Name -eq 'CRAFT_PYTHON') { ' (optional; - selects automatic detection)' }
            elseif ($Name -in 'KMYMONEY_SOURCE_DIR', 'KMYMONEY_EXECUTABLE') { ' (absolute path; blank discovers from Craft)' }
            else { ' (absolute path)' }
        do {
            $Value = (Read-Host -Prompt "$Name$Hint [$Default]").Trim()
            if (-not $Value) { $Value = [string]$Default }
            if ($Name -eq 'CRAFT_PYTHON' -and $Value -eq '-') { $Value = '' }
            $Valid = $Value -notmatch '[\r\n\x00]' -and
                ($Name -eq 'CRAFT_PYTHON' -or [IO.Path]::IsPathFullyQualified($Value) -or
                    (-not $Value -and $Name -in 'KMYMONEY_SOURCE_DIR', 'KMYMONEY_EXECUTABLE'))
            if (-not $Valid) { Write-Warning "Enter an absolute path for $Name without line breaks." }
        } until ($Valid)
        $Values[$Name] = $Value
        if ($Value -and $Name -in 'KMYMONEY_SOURCE_DIR', 'KMYMONEY_EXECUTABLE') { $ProvidedPaths[$Name] = $Value }
    }
    $Context = @{
        Source = $script:RepositoryRoot
        EnvironmentValues = $Values
        KMMAppVersion = $Values.KMM_APP_VERSION
    }
    Install-KMMApplication -Context $Context
    $ResolvedValues = $Context.EnvironmentValues
    foreach ($Name in $ProvidedPaths.Keys) { $ResolvedValues[$Name] = $ProvidedPaths[$Name] }
    foreach ($Name in 'KMYMONEY_SDK_SOURCE_DIR', 'KMYMONEY_BUILD_DIR') {
        if ($Values[$Name]) { $ResolvedValues[$Name] = $Values[$Name] }
    }
    $Lines = [Collections.Generic.List[string]]::new()
    $Lines.Add('# Local development configuration. Do not commit this file.')
    $Lines.Add('[Environment]')
    foreach ($Name in @($ResolvedValues.Keys | Sort-Object)) { $Lines.Add("$Name=$($ResolvedValues[$Name])") }
    $TemporaryFile = Join-Path $Parent ('.env-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($TemporaryFile, ($Lines -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $TemporaryFile -Destination $ENV_FILE -Force
        foreach ($Name in 'KMYMONEY_SDK_SOURCE_DIR', 'KMYMONEY_BUILD_DIR') {
            [Environment]::SetEnvironmentVariable($Name, $ResolvedValues[$Name], 'Process')
        }
    } finally {
        if (Test-Path -LiteralPath $TemporaryFile -PathType Leaf) { Remove-Item -LiteralPath $TemporaryFile }
    }
    Write-Information -InformationAction Continue -MessageData "Saved environment file: $ENV_FILE"
}
