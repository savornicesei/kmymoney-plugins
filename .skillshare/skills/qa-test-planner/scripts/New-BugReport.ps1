[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string] $OutputDirectory = (Get-Location).Path,

    [ValidateSet('Functional', 'UI/Visual', 'Performance', 'Security')]
    [string] $Type = 'Functional'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-PromptValue {
    param(
        [Parameter(Mandatory)]
        [string] $Prompt,

        [switch] $Required
    )

    do {
        Write-Host $Prompt -ForegroundColor Cyan
        $value = Read-Host

        if (-not $Required -or -not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }

        Write-Host 'This field is required.' -ForegroundColor Red
    } while ($true)
}

function Read-NumberedItems {
    param(
        [Parameter(Mandatory)]
        [string] $Prompt
    )

    Write-Host $Prompt
    $items = [System.Collections.Generic.List[string]]::new()

    while ($true) {
        $item = Read-Host
        if ([string]::IsNullOrEmpty($item)) {
            break
        }

        $items.Add($item)
    }

    for ($index = 0; $index -lt $items.Count; $index++) {
        '{0}. {1}' -f ($index + 1), $items[$index]
    }
}

function Get-ValueOrDefault {
    param(
        [AllowEmptyString()]
        [string] $Value,

        [Parameter(Mandatory)]
        [string] $Default
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Default
    }

    return $Value
}

Write-Host '╔══════════════════════════════════════════════════╗' -ForegroundColor Red
Write-Host '║           Bug Report Generator                   ║' -ForegroundColor Red
Write-Host '╚══════════════════════════════════════════════════╝' -ForegroundColor Red
Write-Host

$bugId = 'BUG-{0}' -f (Get-Date -Format 'yyyyMMddHHmmss')
Write-Host "Auto-generated Bug ID: $bugId" -ForegroundColor Yellow
Write-Host

$bugTitle = Read-PromptValue -Prompt 'Bug title (clear, specific):' -Required

Write-Host
Write-Host 'Severity:'
Write-Host '1) Critical - System crash, data loss, security issue'
Write-Host '2) High - Major feature broken, no workaround'
Write-Host '3) Medium - Feature partially broken, workaround exists'
Write-Host '4) Low - Cosmetic, minor inconvenience'
Write-Host

$severityNumber = Read-PromptValue -Prompt 'Select severity (1-4):' -Required
$severity = switch ($severityNumber) {
    '1' { 'Critical' }
    '2' { 'High' }
    '3' { 'Medium' }
    '4' { 'Low' }
    default { 'Medium' }
}

Write-Host
Write-Host 'Priority:'
Write-Host '1) P0 - Blocks release'
Write-Host '2) P1 - Fix before release'
Write-Host '3) P2 - Fix in next release'
Write-Host '4) P3 - Fix when possible'
Write-Host

$priorityNumber = Read-PromptValue -Prompt 'Select priority (1-4):' -Required
$priority = switch ($priorityNumber) {
    '1' { 'P0' }
    '2' { 'P1' }
    '3' { 'P2' }
    '4' { 'P3' }
    default { 'P2' }
}

Write-Host
Write-Host '━━━ Environment Details ━━━' -ForegroundColor Magenta
Write-Host

$operatingSystem = Read-PromptValue -Prompt 'Operating System (e.g., Windows 11, macOS 14):' -Required
$browser = Read-PromptValue -Prompt 'Browser & Version (e.g., Chrome 120, Firefox 121):' -Required
$device = Read-PromptValue -Prompt 'Device (e.g., Desktop, iPhone 15):'
$build = Read-PromptValue -Prompt 'Build/Version number:' -Required
$url = Read-PromptValue -Prompt 'URL or page where bug occurs:'

Write-Host
Write-Host '━━━ Bug Description ━━━' -ForegroundColor Magenta
Write-Host

$description = Read-PromptValue -Prompt 'Brief description of the issue:' -Required

Write-Host
Write-Host '━━━ Steps to Reproduce ━━━' -ForegroundColor Magenta
Write-Host

$reproductionSteps = @(Read-NumberedItems -Prompt 'Enter reproduction steps (one per line, press Enter twice when done):')

Write-Host
$expected = Read-PromptValue -Prompt 'Expected behavior:' -Required
$actual = Read-PromptValue -Prompt 'Actual behavior:' -Required

Write-Host
Write-Host '━━━ Additional Information ━━━' -ForegroundColor Magenta
Write-Host

$consoleErrors = Read-PromptValue -Prompt 'Console errors (paste if any):'
$frequency = Read-PromptValue -Prompt 'Frequency (Always/Sometimes/Rare):'
$userImpact = Read-PromptValue -Prompt 'How many users affected (estimate):'
$workaround = Read-PromptValue -Prompt 'Workaround available? (describe if yes):'
$testCase = Read-PromptValue -Prompt 'Related test case ID:'
$figmaLink = Read-PromptValue -Prompt 'Figma design link (if UI bug):'
$firstNoticed = Read-PromptValue -Prompt 'First noticed (date/build):'

$resolvedOutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$outputFile = Join-Path -Path $resolvedOutputDirectory -ChildPath "$bugId.md"
$newLine = [Environment]::NewLine
$reproductionStepsText = $reproductionSteps -join $newLine
$device = Get-ValueOrDefault -Value $device -Default 'Desktop'
$url = Get-ValueOrDefault -Value $url -Default 'N/A'
$consoleErrors = Get-ValueOrDefault -Value $consoleErrors -Default 'None'
$frequency = Get-ValueOrDefault -Value $frequency -Default 'Unknown'
$userImpact = Get-ValueOrDefault -Value $userImpact -Default 'Unknown'
$workaround = Get-ValueOrDefault -Value $workaround -Default 'None available'
$codeFence = '```'

$figmaContext = if (-not [string]::IsNullOrWhiteSpace($figmaLink)) {
    "**Figma Design:** $figmaLink"
} else {
    ''
}

$testCaseContext = if (-not [string]::IsNullOrWhiteSpace($testCase)) {
    "**Related Test Case:** $testCase"
} else {
    ''
}

$firstNoticedContext = if (-not [string]::IsNullOrWhiteSpace($firstNoticed)) {
    "**First Noticed:** $firstNoticed"
} else {
    ''
}

$content = @"
# ${bugId}: $bugTitle

**Severity:** $severity
**Priority:** $priority
**Type:** $Type
**Status:** Open
**Reported:** $(Get-Date -Format 'yyyy-MM-dd')
**Reporter:** [Your Name]

---

## Environment

- **OS:** $operatingSystem
- **Browser:** $browser
- **Device:** $device
- **Build:** $build
- **URL:** $url

---

## Description

$description

---

## Steps to Reproduce

$reproductionStepsText

---

## Expected Behavior

$expected

---

## Actual Behavior

$actual

---

## Visual Evidence

- [ ] Screenshot attached
- [ ] Screen recording attached
- [ ] Console logs attached

**Console Errors:**
$codeFence
$consoleErrors
$codeFence

---

## Impact

- **Frequency:** $frequency
- **User Impact:** $userImpact
- **Workaround:** $workaround

---

## Additional Context

$figmaContext

$testCaseContext

$firstNoticedContext

**Is this a regression?** [Yes/No - if yes, since when]

---

## Root Cause

[To be filled by developer]

---

## Fix

[To be filled by developer]

---

## Verification

- [ ] Bug fix verified in dev environment
- [ ] Regression testing completed
- [ ] Related test cases passing
- [ ] Ready for release

**Verified By:** ___________
**Date:** ___________

---

## Comments

[Discussion and updates]
"@

Write-Host
Write-Host 'Generating bug report...' -ForegroundColor Blue
Write-Host

[System.IO.File]::WriteAllText($outputFile, $content, [System.Text.UTF8Encoding]::new($false))

Write-Host '✅ Bug report generated successfully!' -ForegroundColor Green
Write-Host
Write-Host 'File location: ' -NoNewline
Write-Host $outputFile -ForegroundColor Blue
Write-Host
Write-Host '⚠️  IMPORTANT NEXT STEPS:' -ForegroundColor Red
Write-Host '1. Attach screenshots/screen recordings'
Write-Host '2. Add console errors if available'
Write-Host '3. Verify reproduction steps work'
Write-Host '4. Submit to bug tracking system'
if (-not [string]::IsNullOrWhiteSpace($figmaLink)) {
    Write-Host '5. Verify against Figma design'
}

Write-Host
Write-Host 'Tip: Clear, reproducible steps = faster fixes' -ForegroundColor Cyan
Write-Host

Get-Item -LiteralPath $outputFile
