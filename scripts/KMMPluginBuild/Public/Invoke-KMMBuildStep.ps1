function Invoke-KMMBuildStep {
    <#
    .SYNOPSIS
    Executes one native step; build.ps1 owns dependency ordering.
    .EXAMPLE
    Invoke-KMMBuildStep -Context $Context -Step Init
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][ValidateSet('Init', 'Clean', 'Build', 'Test', 'Stage')][string]$Step,
        [string]$Target
    )
    $ErrorActionPreference = 'Stop'
    switch ($Step) {
        Init {
            if (-not $Context.Plugins.Count) { throw 'No buildable plugins were found.' }
            Enter-KMMCraftEnvironment -EnvFile $Context.EnvFile -Confirm:$false
            Set-KMMAppVersion -KMMAppVersion $Context.KMMAppVersion -Confirm:$false
            $Context.CMake = (Get-Command cmake -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
            $Context.CTest = (Get-Command ctest -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
            $Arguments = @('--preset', $Context.Preset, '-S', $Context.Source, '-B', $Context.Build,
                "-DCMAKE_INSTALL_PREFIX=$($Context.Stage)", '-DBUILD_TESTING=ON',
                "-DKMM_PLUGIN_SELECTION=$($Context.Plugins -join ';')")
            foreach ($Plugin in $Context.Plugins) {
                $Option = 'BUILD_' + $Plugin.Replace('-', '_').ToUpperInvariant()
                $Arguments += "-D$Option=ON"
            }
            Invoke-KMMNativeTool -Executable $Context.CMake -ArgumentList $Arguments
        }
        Clean { Invoke-KMMNativeTool $Context.CMake @('--build', $Context.Build, '--target', 'clean') }
        Build {
            $Arguments = @('--build', $Context.Build)
            if ($Target) { $Arguments += @('--target', $Target) }
            Invoke-KMMNativeTool $Context.CMake $Arguments
        }
        Test { Invoke-KMMNativeTool $Context.CTest @('--test-dir', $Context.Build, '--output-on-failure', '--no-tests=error', '--output-junit', (Join-Path $Context.Build 'ctest-junit.xml')) }
        Stage {
            Invoke-KMMNativeTool $Context.CMake @('--install', $Context.Build, '--prefix', $Context.Stage)
            Copy-KMMSqlCipherRuntime -Context $Context
        }
    }
}
