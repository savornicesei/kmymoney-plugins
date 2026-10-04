function Open-KMMWorkspace {
    <#
    .SYNOPSIS
    Resolves local workspace folders and optionally opens VS Code.
    .DESCRIPTION
    Initializes Craft, reads the shared workspace template, resolves local source and
    Craft folders, and replaces the ignored local workspace. Existing local edits are
    overwritten; edit the shared template instead. VS Code inherits this environment.
    .PARAMETER GenerateOnly
    Writes the local workspace and returns its absolute path without starting VS Code.
    .PARAMETER EnvFile
    INI file passed to Craft initialization; defaults to repository env.ini.
    .EXAMPLE
    ./build.ps1 -Tasks OpenWorkspace
    Generates the local workspace and starts a new VS Code window.
    .EXAMPLE
    ./build.ps1 -Tasks OpenWorkspace -GenerateOnly -Verbose
    Generates the local workspace, reports diagnostics, and returns its path.
    .EXAMPLE
    ./build.ps1 -Tasks OpenWorkspace -Preview
    Previews generation and launch without invoking Craft or writing files.
    .INPUTS
    None.
    .OUTPUTS
    System.String. The local workspace path when GenerateOnly is specified.
    .NOTES
    Requires the environment variables documented by EnterCraft. The code
    launcher must be on PATH unless GenerateOnly is specified. Close existing IDE
    instances first: a reused process may retain its previous environment.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([string])]
    param([switch]$GenerateOnly, [string]$EnvFile)

    $Operation = if ($GenerateOnly) { 'Generate local workspace' } else { 'Generate local workspace and launch VS Code' }
    if (-not $PSCmdlet.ShouldProcess('KMyMoney VS Code workspace', $Operation)) {
        return
    }

    & {
        param([string]$SelectedFile)
        Set-StrictMode -Version 3.0
        $ErrorActionPreference = 'Stop'
        $PSNativeCommandUseErrorActionPreference = $false
        $RepositoryRoot = $script:RepositoryRoot
        $TemplatePath = Join-Path $RepositoryRoot 'kmymoney-plugin.code-workspace'
        $Workspace = Get-Content -LiteralPath $TemplatePath -Raw | ConvertFrom-Json -AsHashtable
        if ($Workspace -isnot [Collections.IDictionary] -or
            $Workspace['settings'] -isnot [Collections.IDictionary]) {
            throw [IO.InvalidDataException]::new('The shared workspace must contain a JSON object with a settings object.')
        }
        $CodeExecutable = if (-not $GenerateOnly) {
            (Get-Command -Name code -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        }

        Enter-KMMCraftEnvironment -EnvFile $SelectedFile -Confirm:$false
        # VS Code does not substitute environment variables in folders[].path.
        $Workspace['folders'] = @(
            @{ name = 'Plugins'; path = '.' },
            @{ name = 'KMyMoney'; path = $env:KMYMONEY_SOURCE_DIR },
            @{ name = 'Craft'; path = $env:CRAFT_ROOT }
        )
        $CraftGlob = $env:CRAFT_ROOT.Replace('\', '/').TrimEnd('/') + '/**'
        foreach ($SettingName in @('files.watcherExclude', 'search.exclude')) {
            if (-not $Workspace['settings'].Contains($SettingName)) {
                $Workspace['settings'][$SettingName] = @{}
            }
            if ($Workspace['settings'][$SettingName] -isnot [Collections.IDictionary]) {
                throw [IO.InvalidDataException]::new("Workspace setting $SettingName must be a JSON object.")
            }
            $Workspace['settings'][$SettingName][$CraftGlob] = $true
        }

        $WorkspacePath = Join-Path $RepositoryRoot 'kmymoney-plugin.local.code-workspace'
        $TemporaryPath = Join-Path $RepositoryRoot ('.workspace-' + [guid]::NewGuid().ToString('N') + '.tmp')
        try {
            $Json = ($Workspace | ConvertTo-Json -Depth 30).Replace("`r`n", "`n") + "`n"
            [IO.File]::WriteAllText($TemporaryPath, $Json, [Text.UTF8Encoding]::new($false))
            Move-Item -LiteralPath $TemporaryPath -Destination $WorkspacePath -Force
        } finally {
            if (Test-Path -LiteralPath $TemporaryPath) {
                Remove-Item -LiteralPath $TemporaryPath
            }
        }
        Write-Verbose "Generated $WorkspacePath."
        if ($GenerateOnly) {
            $WorkspacePath
            return
        }
        & $CodeExecutable --new-window $WorkspacePath
        if ($LASTEXITCODE -ne 0) {
            throw [InvalidOperationException]::new("VS Code launch failed with exit code $LASTEXITCODE.")
        }
    } $EnvFile
}
