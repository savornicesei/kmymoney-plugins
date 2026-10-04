#Requires -Version 7.0
#Requires -PSEdition Core

function Invoke-KMMRelease {
    <#
    .SYNOPSIS
    Builds, tests and packages each selected plugin for the current native platform.
    .DESCRIPTION
    Uses fresh directories below build/<preset>/release and stage/<preset>/release
    for each invocation. Publishes packages, manifests and SHA256 files only after
    every selected plugin has passed its tests and packaged successfully.
    Windows uses ZIP; macOS and Linux use tar.gz. Every platform uses the matching
    installed Craft Qt 6 KMyMoney SDK and the release compatibility matrix.
    CI fans out native jobs through .gitlab-ci.yml; each worker runs this same task.
    .PARAMETER Context
    Build session context with resolved plugin selection and environment file.
    .PARAMETER Version
    Required major.minor.patch version for both plugin metadata and packages.
    .EXAMPLE
    ./build.ps1 -Tasks Release -Version 1.2.3 -Plugins draft-transactions
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][ValidatePattern('^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')]
        [string]$Version
    )
    $ErrorActionPreference = 'Stop'
    if (-not $Context.Plugins.Count) { throw 'No plugins selected for Release.' }
    $Policies = Get-KMMReleaseCompatibility -Context $Context -Version $Version
    $Preset = $Context.Preset
    $Platform = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' }
    if ($env:KMM_RELEASE_TARGET -and $env:KMM_RELEASE_TARGET -ne $Platform) {
        throw "Release runner platform does not match KMM_RELEASE_TARGET=$env:KMM_RELEASE_TARGET."
    }
    Enter-KMMCraftEnvironment -EnvFile $Context.EnvFile -Confirm:$false
    $RunId = [guid]::NewGuid().ToString('N')
    $InspectionDirectory = Join-Path $Context.Source "build/$Preset/release/inspection/$RunId"
    $HostInfo = Get-KMMCraftReleaseHost -Context $Context -Directory $InspectionDirectory
    foreach ($Plugin in $Context.Plugins) {
        $MatchesHost = @($Policies[$Plugin].kmymoney | Where-Object {
            Test-KMMVersionSelector -Selector $_ -Target $HostInfo.Target -HostVersion $HostInfo.Version
        })
        if (-not $MatchesHost.Count) {
            throw "$Plugin $Version does not support KMyMoney $($HostInfo.Target) ($($HostInfo.Version)) according to release-compatibility.json. $($Policies[$Plugin].notes)"
        }
    }
    $CMake = (Get-Command cmake -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $CTest = (Get-Command ctest -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $CPack = (Get-Command cpack -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $BuildRoot = Join-Path $Context.Source "build/$Preset/release/$($HostInfo.Target)/$Version/$RunId"
    $StageRoot = Join-Path $Context.Source "stage/$Preset/release/$($HostInfo.Target)/$Version/$RunId"
    $Pending = @()
    foreach ($Plugin in $Context.Plugins) {
        $Binary = Join-Path $BuildRoot $Plugin
        $Stage = Join-Path $StageRoot $Plugin
        $Arguments = @('--preset', $Preset, '-S', $Context.Source, '-B', $Binary,
            "-DCMAKE_INSTALL_PREFIX=$Stage", "-DKMM_PLUGIN_VERSION=$Version",
            "-DKMM_PLUGIN_SELECTION=$Plugin", '-DKMM_RELEASE_PACKAGING=ON', '-DBUILD_TESTING=ON')
        $Arguments += @("-DKMM_RELEASE_HOST_TARGET=$($HostInfo.Target)",
            "-DKMM_RELEASE_HOST_VERSION=$($HostInfo.Version)",
            "-DKMYMONEY_BUILD_DIR=$($HostInfo.BuildDirectory)")
        Invoke-KMMNativeTool $CMake $Arguments
        Invoke-KMMNativeTool $CMake @('--build', $Binary)
        Invoke-KMMNativeTool $CTest @('--test-dir', $Binary, '--output-on-failure', '--no-tests=error',
            '--output-junit', (Join-Path $Binary 'ctest-junit.xml'))
        Invoke-KMMNativeTool $CMake @('--install', $Binary, '--prefix', $Stage)

        $Info = [ordered]@{}
        foreach ($Line in Get-Content -LiteralPath (Join-Path $Binary 'release-build-info.txt')) {
            $Key, $Value = $Line.Split('=', 2)
            $Info[$Key] = $Value
        }
        if ($Info.Version -ne $Version) { throw 'Configured plugin version differs from the requested release.' }
        if ($Info.HostTarget -cne $HostInfo.Target -or $Info.HostVersion -cne $HostInfo.Version) {
            throw 'Configured host identity differs from the verified installed Craft SDK.'
        }
        $Files = @(Get-ChildItem -LiteralPath $Stage -File -Recurse | Sort-Object FullName | ForEach-Object {
            [ordered]@{
                Path = [IO.Path]::GetRelativePath($Stage, $_.FullName).Replace('\', '/')
                SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        })
        if (-not $Files.Count) { throw "Release staging is empty for $Plugin." }
        $Manifest = Join-Path $Binary 'release-manifest.json'
        [ordered]@{ SchemaVersion = 1; Plugin = $Plugin; Compatibility = $Policies[$Plugin]; Build = $Info; Files = $Files } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Manifest -Encoding utf8
        Invoke-KMMNativeTool $CPack @('--config', (Join-Path $Binary 'CPackConfig.cmake'), '-B', (Join-Path $Binary 'packages'))
        $Extension = switch ($Info.Generator) { ZIP { '.zip' }; TGZ { '.tar.gz' }; default { throw "Unsupported package generator: $($Info.Generator)" } }
        $Package = Join-Path $Binary "packages/$($Info.PackageName)$Extension"
        if (-not (Test-Path -LiteralPath $Package -PathType Leaf) -or (Get-Item -LiteralPath $Package).Length -eq 0) {
            throw "CPack did not produce the expected package: $Package"
        }
        $Pending += @{ Package = $Package; Manifest = $Manifest; Name = $Info.PackageName; Platform = $Info.Platform }
    }
    $PublishRoot = Join-Path $Context.Source "publish/kmymoney/$($HostInfo.Target)"
    foreach ($Item in $Pending) {
        $Destination = Join-Path $PublishRoot $Item.Platform
        foreach ($Name in @([IO.Path]::GetFileName($Item.Package), "$($Item.Name).manifest.json", "$($Item.Name).sha256")) {
            if (Test-Path -LiteralPath (Join-Path $Destination $Name)) {
                throw "Release artifact already exists: $(Join-Path $Destination $Name). Use a new version or move the old artifact aside."
            }
        }
    }
    foreach ($Item in $Pending) {
        $Destination = Join-Path $PublishRoot $Item.Platform
        $null = New-Item -ItemType Directory -Path $Destination -Force
        Copy-Item -LiteralPath $Item.Package -Destination $Destination
        Copy-Item -LiteralPath $Item.Manifest -Destination (Join-Path $Destination "$($Item.Name).manifest.json")
        $Hash = (Get-FileHash -LiteralPath $Item.Package -Algorithm SHA256).Hash.ToLowerInvariant()
        "$Hash  $([IO.Path]::GetFileName($Item.Package))" |
            Set-Content -LiteralPath (Join-Path $Destination "$($Item.Name).sha256") -Encoding utf8
        Write-Information "Published $(Join-Path $Destination ([IO.Path]::GetFileName($Item.Package)))" -InformationAction Continue
    }
}
