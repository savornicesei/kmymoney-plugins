function Read-KMMLocalEnvironment {
    <#
    .SYNOPSIS
    Reads local development paths from an INI file without changing the environment.
    .DESCRIPTION
    Returns a hashtable of literal project values. Supports the documented configuration
    keys, optional [Environment] section, and full-line # or ; comments. Values are
    not executed or expanded. Rejects duplicate/unknown keys and malformed lines.
    .PARAMETER EnvFile
    INI path, resolved relative to the repository root. Omitted means env.ini;
    a missing default returns an empty hashtable, but a missing explicit file fails.
    .EXAMPLE
    $Paths = Read-KMMLocalEnvironment -EnvFile linux.env.ini
    .OUTPUTS
    System.Collections.Hashtable.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([string]$EnvFile)

    & {
        param([string]$SelectedFile)
        Set-StrictMode -Version 3.0
        $ErrorActionPreference = 'Stop'
        $ExplicitFile = -not [string]::IsNullOrWhiteSpace($SelectedFile)
        $RepositoryRoot = $script:RepositoryRoot
        $FilePath = if ($ExplicitFile) { [IO.Path]::GetFullPath($SelectedFile, $RepositoryRoot) }
        else { Join-Path $RepositoryRoot 'env.ini' }
        $Values = @{}
        if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
            if ($ExplicitFile) { throw "Environment file does not exist: $FilePath" }
            return $Values
        }
        $AllowedKeys = @('CRAFT_ROOT', 'KMYMONEY_SOURCE_DIR', 'KMYMONEY_EXECUTABLE', 'CRAFT_PYTHON',
            'KMM_PLUGINS', 'KMM_APP_VERSION', 'KMYMONEY_SDK_SOURCE_DIR', 'KMYMONEY_BUILD_DIR',
            'CMAKE_BUILD_PARALLEL_LEVEL', 'QT_QPA_PLATFORM', 'LANG', 'LC_ALL')
        $LineNumber = 0
        foreach ($Line in Get-Content -LiteralPath $FilePath -Encoding utf8) {
            $LineNumber++
            $Text = $Line.Trim()
            if (-not $Text -or $Text.StartsWith('#') -or $Text.StartsWith(';')) { continue }
            if ($Text -eq '[Environment]') { continue }
            if ($Text -notmatch '^([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$') {
                throw "Invalid INI entry at ${FilePath}:$LineNumber. Expected KEY=value."
            }
            $Name = $Matches[1].ToUpperInvariant()
            $Value = $Matches[2].Trim()
            if ($Name -notin $AllowedKeys) { throw "Unknown environment key '$Name' at ${FilePath}:$LineNumber." }
            if ($Values.ContainsKey($Name)) { throw "Duplicate environment key '$Name' at ${FilePath}:$LineNumber." }
            if ($Value.Length -ge 2 -and (($Value.StartsWith('"') -and $Value.EndsWith('"')) -or
                ($Value.StartsWith("'") -and $Value.EndsWith("'")))) {
                $Value = $Value.Substring(1, $Value.Length - 2)
            }
            if ($Value.Contains([char]0)) { throw "Invalid NUL in '$Name'." }
            $Values[$Name] = $Value
        }
        return $Values
    } $EnvFile
}
