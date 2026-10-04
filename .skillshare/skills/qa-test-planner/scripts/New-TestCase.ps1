[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string] $OutputDirectory = (Get-Location).Path
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

function Read-ListItems {
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

    return $items.ToArray()
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

Write-Host '╔══════════════════════════════════════════════════╗' -ForegroundColor Blue
Write-Host '║       Manual Test Case Generator                 ║' -ForegroundColor Blue
Write-Host '╚══════════════════════════════════════════════════╝' -ForegroundColor Blue
Write-Host

Write-Host '━━━ Step 1: Test Case Basics ━━━' -ForegroundColor Magenta
Write-Host

$testCaseId = Read-PromptValue -Prompt 'Test Case ID (e.g., TC-LOGIN-001):' -Required
$testCaseTitle = Read-PromptValue -Prompt 'Test Case Title:' -Required

Write-Host
Write-Host 'Priority:'
Write-Host '1) P0 - Critical (blocks release)'
Write-Host '2) P1 - High (important features)'
Write-Host '3) P2 - Medium (nice to have)'
Write-Host '4) P3 - Low (minor issues)'
Write-Host

$priorityNumber = Read-PromptValue -Prompt 'Select priority (1-4):' -Required
$priority = switch ($priorityNumber) {
    '1' { 'P0 (Critical)' }
    '2' { 'P1 (High)' }
    '3' { 'P2 (Medium)' }
    '4' { 'P3 (Low)' }
    default { 'P2 (Medium)' }
}

Write-Host
Write-Host 'Test Type:'
Write-Host '1) Functional'
Write-Host '2) UI/Visual'
Write-Host '3) Integration'
Write-Host '4) Regression'
Write-Host '5) Performance'
Write-Host '6) Security'
Write-Host

$typeNumber = Read-PromptValue -Prompt 'Select test type (1-6):' -Required
$testType = switch ($typeNumber) {
    '1' { 'Functional' }
    '2' { 'UI/Visual' }
    '3' { 'Integration' }
    '4' { 'Regression' }
    '5' { 'Performance' }
    '6' { 'Security' }
    default { 'Functional' }
}

$estimatedTime = Read-PromptValue -Prompt 'Estimated test time (minutes):'

Write-Host
Write-Host '━━━ Step 2: Test Objective ━━━' -ForegroundColor Magenta
Write-Host

$objective = Read-PromptValue -Prompt 'What are you testing? (objective):' -Required
$whyImportant = Read-PromptValue -Prompt 'Why is this test important?'

Write-Host
Write-Host '━━━ Step 3: Preconditions ━━━' -ForegroundColor Magenta
Write-Host

$preconditions = @(Read-ListItems -Prompt 'Enter preconditions (one per line, press Enter twice when done):')

Write-Host
Write-Host '━━━ Step 4: Test Steps ━━━' -ForegroundColor Magenta
Write-Host
Write-Host "Enter test steps (type 'done' or leave the action blank when finished)"
Write-Host

$testSteps = [System.Collections.Generic.List[string]]::new()
$stepNumber = 1

while ($true) {
    Write-Host "Step ${stepNumber}:" -ForegroundColor Yellow
    $action = Read-PromptValue -Prompt 'Action:'

    if ([string]::IsNullOrWhiteSpace($action) -or $action -eq 'done') {
        break
    }

    $expected = Read-PromptValue -Prompt 'Expected result:' -Required
    $testSteps.Add("${stepNumber}. $action`n   **Expected:** $expected")
    $stepNumber++
}

Write-Host
Write-Host '━━━ Step 5: Test Data ━━━' -ForegroundColor Magenta
Write-Host

$testData = Read-PromptValue -Prompt 'Test data required (e.g., user credentials, sample data):'

$figmaUrl = ''
$visualChecks = ''
if ($testType -eq 'UI/Visual') {
    Write-Host
    Write-Host '━━━ Step 6: Figma Design Validation ━━━' -ForegroundColor Magenta
    Write-Host

    $figmaUrl = Read-PromptValue -Prompt 'Figma design URL (if applicable):'
    $visualChecks = Read-PromptValue -Prompt 'Visual elements to validate:'
}

Write-Host
Write-Host '━━━ Step 7: Additional Info ━━━' -ForegroundColor Magenta
Write-Host

$edgeCases = Read-PromptValue -Prompt 'Edge cases or variations to consider:'
$relatedTestCases = Read-PromptValue -Prompt 'Related test cases (IDs):'
$notes = Read-PromptValue -Prompt 'Notes or comments:'

$fileName = '{0}.md' -f ($testCaseId -replace '[^a-zA-Z0-9_-]', '')
$resolvedOutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$outputFile = Join-Path -Path $resolvedOutputDirectory -ChildPath $fileName
$newLine = [Environment]::NewLine
$preconditionsText = ($preconditions | ForEach-Object { "- $_" }) -join $newLine
$testStepsText = $testSteps -join ($newLine + $newLine)
$estimatedTime = Get-ValueOrDefault -Value $estimatedTime -Default 'TBD'
$testData = Get-ValueOrDefault -Value $testData -Default 'No specific test data required'
$edgeCases = Get-ValueOrDefault -Value $edgeCases -Default 'Consider boundary values, null inputs, special characters, concurrent users'
$relatedTestCases = Get-ValueOrDefault -Value $relatedTestCases -Default 'None'

$whyImportantSection = if (-not [string]::IsNullOrWhiteSpace($whyImportant)) {
    "**Why this matters:** $whyImportant"
} else {
    ''
}

$figmaSection = if ($testType -eq 'UI/Visual' -and -not [string]::IsNullOrWhiteSpace($figmaUrl)) {
    @"
## Visual Validation (Figma)

**Design Reference:** $figmaUrl

**Elements to validate:**
$visualChecks

**Verification checklist:**
- [ ] Layout matches Figma design
- [ ] Spacing (padding/margins) accurate
- [ ] Typography (font, size, weight, color) correct
- [ ] Colors match design system
- [ ] Component states (hover, active, disabled) implemented
- [ ] Responsive behavior as designed

---

"@
} else {
    ''
}

$content = @"
# ${testCaseId}: $testCaseTitle

**Priority:** $priority
**Type:** $testType
**Status:** Not Run
**Estimated Time:** $estimatedTime minutes
**Created:** $(Get-Date -Format 'yyyy-MM-dd')

---

## Objective

$objective

$whyImportantSection

---

## Preconditions

$preconditionsText

---

## Test Steps

$testStepsText

---

## Test Data

$testData

---

$figmaSection## Post-conditions

- [Describe system state after test execution]
- [Any cleanup required]

---

## Edge Cases & Variations

$edgeCases

---

## Related Test Cases

$relatedTestCases

---

## Execution History

| Date | Tester | Build | Result | Notes |
|------|--------|-------|--------|-------|
| | | | Not Run | |

---

## Notes

$notes

---

## Attachments

- [ ] Screenshots
- [ ] Screen recordings
- [ ] Console logs
- [ ] Network traces
"@

Write-Host
Write-Host 'Generating test case...' -ForegroundColor Blue
Write-Host

[System.IO.File]::WriteAllText($outputFile, $content, [System.Text.UTF8Encoding]::new($false))

Write-Host '✅ Test case generated successfully!' -ForegroundColor Green
Write-Host
Write-Host 'File location: ' -NoNewline
Write-Host $outputFile -ForegroundColor Blue
Write-Host
Write-Host 'Next steps:' -ForegroundColor Yellow
Write-Host '1. Review test case for completeness'
Write-Host '2. Add to test suite'
Write-Host '3. Execute test and update results'
if ($testType -eq 'UI/Visual' -and -not [string]::IsNullOrWhiteSpace($figmaUrl)) {
    Write-Host '4. Validate against Figma design using MCP'
}

Write-Host
Write-Host 'Tip: Create multiple test cases for comprehensive coverage' -ForegroundColor Cyan
Write-Host

Get-Item -LiteralPath $outputFile
