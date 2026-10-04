function Invoke-KMMCheck {
    <#
    .SYNOPSIS
    Runs static analysis and the module's Pester regression suite.
    .DESCRIPTION
    Writes build/ci/pester.xml for GitLab and fails when any check fails.
    Requires the shared dependency modules and native fixture tools on PATH.
    .EXAMPLE
    Invoke-KMMCheck
    #>
    [CmdletBinding()]
    param()
    $ErrorActionPreference = 'Stop'
    $ModuleRoot = Join-Path $script:RepositoryRoot 'scripts/KMMPluginBuild'
    $Findings = @(Invoke-ScriptAnalyzer -Path $ModuleRoot -Recurse)
    $Findings += @(Invoke-ScriptAnalyzer -Path (Join-Path $script:RepositoryRoot 'build.ps1'))
    if ($Findings.Count) { $Findings | Format-Table; throw 'PowerShell analysis failed.' }
    $ReportDirectory = Join-Path $script:RepositoryRoot 'build/ci'
    New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
    # Pester imports fixture copies of KMMPluginBuild. A separate runspace keeps
    # those copies and mocks out of the module/session executing this task.
    $Runner = [powershell]::Create()
    try {
        $null = $Runner.AddScript({
            param($TestPath, $ReportPath, $PesterManifest, $BuildManifest)
            $ErrorActionPreference = 'Stop'
            Import-Module $PesterManifest
            Import-Module $BuildManifest
            $Configuration = New-PesterConfiguration
            $Configuration.Run.Path = $TestPath
            $Configuration.Run.PassThru = $true
            $Configuration.TestRegistry.Enabled = $false
            $Configuration.TestResult.Enabled = $true
            $Configuration.TestResult.OutputFormat = 'JUnitXml'
            $Configuration.TestResult.OutputPath = $ReportPath
            Invoke-Pester -Configuration $Configuration
        }.ToString()).AddArgument((Join-Path $ModuleRoot 'Tests')).AddArgument((Join-Path $ReportDirectory 'pester.xml')).
            AddArgument((Get-Command Invoke-Pester).Module.Path).AddArgument((Get-Module InvokeBuild | Select-Object -First 1).Path)
        $Results = $Runner.Invoke()
        foreach ($Record in $Runner.Streams.Information) {
            Write-Information -MessageData $Record.MessageData -InformationAction Continue
        }
        if ($Runner.HadErrors) { throw ($Runner.Streams.Error | Out-String) }
        $Result = $Results | Select-Object -Last 1
        if (-not $Result) { throw 'Pester returned no result.' }
    } finally {
        $Runner.Dispose()
    }
    if ($Result.FailedCount -or -not $Result.PassedCount) { throw 'PowerShell regression checks failed.' }
}
