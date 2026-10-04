#Requires -Version 7.0
#Requires -PSEdition Core

$script:RepositoryRoot = [IO.Path]::GetFullPath('../..', $PSScriptRoot)
foreach ($Folder in 'Private', 'Public') {
    foreach ($File in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot $Folder) -Filter '*.ps1' | Sort-Object Name) {
        . $File.FullName
    }
}
