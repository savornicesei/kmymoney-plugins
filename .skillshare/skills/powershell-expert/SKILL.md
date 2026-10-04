---
name: powershell-expert
description: Expert in developing PowerShell scripts, tools, modules, automation and GUIs following Microsoft best practices. Specialized in Windows administration, cross-platform PowerShell development, enterprise automation solutions, and comprehensive testing with Pester following PoshCode community standards and modern PowerShell best practices. Use when writing PowerShell code, creating Windows Forms/WPF interfaces, working with PowerShell Gallery modules, or needing cmdlet/module recommendations. Covers script development, parameter design, pipeline handling, error management, GUI creation patterns, optimization, complex automation tasks, test-driven development. Verifies module availability and cmdlet syntax against live documentation when accuracy is critical.
---

# PowerShell Expert

Develop production-quality PowerShell scripts, tools, and GUIs using Microsoft best practices and the PowerShell ecosystem.

## Key Skills
### Core Capabilities
- PowerShell Core and Windows PowerShell development with advanced functions
- Pipeline-aware cmdlet development using CmdletBinding attributes
- Custom function and module development with proper parameter validation
- Windows system administration and Active Directory automation
- Cross-platform PowerShell compatibility and remote management
- Secure credential handling and authentication systems
- Performance optimization using PowerShell idioms and best practices
- Error handling following "pit of success" principles
- Enterprise automation with proper logging and audit trails
- Object-oriented PowerShell with classes and type acceleration
- **Comprehensive testing framework using Pester for unit and integration tests**
- **Test-driven development (TDD) and behavior-driven development (BDD) practices**
- **Mock testing and test isolation for external dependencies**

### Development Standards
- Follow PoshCode PowerShell Practice and Style guidelines for consistency
- Use approved verbs (Get-Verb) and Verb-Noun naming conventions with singular nouns
- Implement comprehensive comment-based help with .SYNOPSIS, .DESCRIPTION, .PARAMETER, .EXAMPLE, and .NOTES
- Use [CmdletBinding()] with SupportsShouldProcess for -WhatIf and -Confirm support
- Apply proper parameter attributes: [Parameter()], [ValidateSet()], [ValidateRange()], [ValidateScript()]
- Design for pipeline input with ValueFromPipeline and ValueFromPipelineByPropertyName
- Use Begin/Process/End blocks appropriately for pipeline processing
- Implement comprehensive error handling with try/catch and proper error types
- Follow PascalCase naming for functions, parameters, and variables
- Use 4-space indentation with opening braces on same line
- Ensure all functions include complete comment-based help documentation
- Implement proper parameter validation using appropriate validate attributes
- Support -Verbose, -Debug, -WhatIf, and -Confirm parameters where applicable
- Use Write-Verbose for detailed logging and Write-Debug for troubleshooting
- Apply strongly typed parameters with proper [Parameter()] attributes
- Ensure pipeline support with appropriate parameter binding
- Implement proper error handling with terminating vs non-terminating errors
- Use SecureString for sensitive data and proper credential management
- Follow PowerShell Script Analyzer (PSScriptAnalyzer) rules and style guidelines
- Test across different PowerShell versions and validate cross-platform compatibility
- Use switch parameters instead of boolean parameters for true/false values
- Support PassThru parameter when modifying objects

### Pester Testing Standards
- **Follow *.Tests.ps1 naming convention for all test files**
- **Create comprehensive unit tests using Describe, Context, It, Should, and Mock keywords**
- **Implement BeforeAll/AfterAll and BeforeEach/AfterEach setup and teardown blocks**
- **Use dot-sourcing with $PSScriptRoot for importing functions under test**
- **Write descriptive test names that clearly explain the expected behavior**
- **Test both positive and negative scenarios including edge cases**
- **Implement proper mocking for external dependencies using Mock keyword**
- **Structure tests logically with Describe for function grouping and Context for scenarios**
- **Use appropriate Should assertions: -Be, -BeExactly, -Match, -Contain, -Throw, etc.**
- **Test parameter validation, pipeline input, and error conditions**
- **Ensure tests are isolated and can run independently in any order**
- **Generate code coverage reports and test result artifacts for CI/CD pipelines**
- **Test across different PowerShell versions and operating systems**
- **Validate help documentation and examples through tests**
- **Use TestCases for parameterized testing when appropriate**

### Production Deliverables
- Production-ready advanced functions with [CmdletBinding()] and comprehensive help
- Well-structured modules with proper manifests, parameter sets, and pipeline support
- Secure automation solutions using SecureString and proper credential handling
- Performance-optimized code leveraging PowerShell idioms and pipeline efficiency
- Cross-platform compatible scripts following modern PowerShell standards
- Enterprise-grade tools with comprehensive logging using Write-Verbose and Write-Debug
- Robust error handling with try/catch blocks and appropriate error actions
- Professional cmdlets supporting standard parameters (-WhatIf, -Confirm, -Verbose)
- Reusable functions following approved verb naming and parameter conventions
- Documentation that enables successful Get-Help usage and practical examples
- **Complete Pester test suites with unit and integration tests for all functions**
- **Test automation scripts that integrate with CI/CD pipelines**
- **Code coverage reports and test result artifacts for quality assurance**
- **Mock implementations for testing complex scenarios and external dependencies**
- **Test-driven development workflows that ensure code quality and reliability**

### Testing Workflow
- **Always create corresponding *.Tests.ps1 files for every PowerShell function or module**
- **Structure tests with clear Describe blocks for each function and Context blocks for different scenarios**
- **Include comprehensive test coverage for all parameters, pipeline scenarios, and error conditions**
- **Use Invoke-Pester with appropriate parameters for running tests and generating reports**
- **Implement continuous testing practices with automated test execution**
- **Provide clear test documentation and examples for maintenance and extension**

## Quick Reference

### Script Structure
```powershell
#Requires -Version 7.0
#Requires -PSEdition Core

<#
.SYNOPSIS
    Brief description.
.DESCRIPTION
    Detailed description.
.PARAMETER Name
    Parameter description.
.EXAMPLE
    Example-Usage -Name 'Value'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Name,

    [switch]$Force
)

begin {
    # One-time setup
}

process {
    foreach ($item in $Name) {
        # Per-item processing
    }
}

end {
    # Cleanup
}
```

### Function Template
```powershell
function Verb-Noun {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('CN')]
        [string]$ComputerName = $env:COMPUTERNAME,

        [switch]$PassThru
    )

    process {
        if ($PSCmdlet.ShouldProcess($Name, 'Action')) {
            # Implementation
            if ($PassThru) { Write-Output $result }
        }
    }
}
```

## Workflow

### 1. Script Development
Follow naming and parameter conventions:
- **Verb-Noun** format with approved verbs (`Get-Verb`)
- **Strong typing** with validation attributes
- **Pipeline support** via `ValueFromPipeline`
- **-WhatIf/-Confirm** for destructive operations

See [best-practices.md](references/best-practices.md) for complete guidelines.

### 2. GUI Development
Windows Forms for simple dialogs, WPF/XAML for complex interfaces:

```powershell
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form -Property @{
    Text          = 'Title'
    Size          = New-Object System.Drawing.Size(400, 300)
    StartPosition = 'CenterScreen'
}
```

See [gui-development.md](references/gui-development.md) for controls, events, and templates.

### 3. PowerShell Gallery Integration
Search and install modules using PSResourceGet:

```powershell
# Search gallery
Find-PSResource -Name 'ModuleName' -Repository PSGallery

# Install module
Install-PSResource -Name 'ModuleName' -Scope CurrentUser -TrustRepository
```

Use [scripts/Search-Gallery.ps1](scripts/Search-Gallery.ps1) for enhanced search.

See [powershellget.md](references/powershellget.md) for full cmdlet reference.

## Key Patterns

### Error Handling
```powershell
try {
    $result = Get-Content -Path $Path -ErrorAction Stop
}
catch [System.IO.FileNotFoundException] {
    Write-Error "File not found: $Path"
    return
}
catch {
    throw
}
```

### Splatting for Readability
```powershell
$params = @{
    Path        = $sourcePath
    Destination = $destPath
    Recurse     = $true
    Force       = $true
}
Copy-Item @params
```

### Pipeline Best Practices
```powershell
# Stream output immediately
foreach ($item in $collection) {
    Process-Item $item | Write-Output
}

# Accept pipeline input
param(
    [Parameter(ValueFromPipeline)]
    [string[]]$InputObject
)
process {
    foreach ($obj in $InputObject) {
        # Process each
    }
}
```

## Module Recommendations

When recommending modules, search the PowerShell Gallery:

| Category | Popular Modules |
|----------|----------------|
| **Azure** | `Az`, `Az.Compute`, `Az.Storage` |
| **Testing** | `Pester`, `PSScriptAnalyzer` |
| **Console** | `PSReadLine`, `Terminal-Icons` |
| **Secrets** | `Microsoft.PowerShell.SecretManagement` |
| **Web** | `Pode` (web server), `PoshRSJob` (async) |
| **GUI** | `WPFBot3000`, `PSGUI` |

## Live Verification

You MUST verify information against live sources when accuracy is critical. Do not rely solely on training data for module availability or cmdlet syntax.

**Tools to use:**
- **WebFetch**: Retrieve and parse specific documentation URLs (PowerShell Gallery pages, Microsoft Docs)
- **WebSearch**: Find correct URLs when the exact path is unknown or to verify module existence

### When Verification is Required

| Scenario | Action |
|----------|--------|
| User asks "does module X exist?" | **MUST** verify via PowerShell Gallery |
| Recommending a specific module | **MUST** verify it exists and isn't deprecated |
| Providing exact cmdlet syntax | **SHOULD** verify against Microsoft Docs |
| Module version requirements | **MUST** check gallery for current version |
| General best practices | Static references are sufficient |

### Step 1: Verify Module on PowerShell Gallery

When recommending or checking a module, **use the WebFetch tool** to verify it exists:

**WebFetch call:**
- **URL**: `https://www.powershellgallery.com/packages/{ModuleName}`
- **Prompt**: `Extract: module name, latest version, last updated date, total downloads, and whether it shows any deprecation warning or 'unlisted' status`

**If WebFetch returns 404 or error**: The module likely doesn't exist. **Use the WebSearch tool** to confirm:
- **Query**: `{ModuleName} PowerShell module site:powershellgallery.com`

### Step 2: Verify Cmdlet Syntax (When Needed)

Microsoft Docs URLs vary by module. **Use the WebSearch tool** to find the correct documentation page:

**WebSearch call:**
- **Query**: `{Cmdlet-Name} cmdlet site:learn.microsoft.com/en-us/powershell`

**Then use WebFetch** on the returned URL with prompt:
- **Prompt**: `Extract the complete cmdlet syntax, required vs optional parameters, and PowerShell version requirements`

### Step 3: Fallback Strategies

If the WebFetch or WebSearch tools are unavailable or return errors:

1. **For module verification**: Execute `Search-Gallery.ps1` from this skill:
   ```powershell
   ~/.claude/skills/powershell-expert/scripts/Search-Gallery.ps1 -Name 'ModuleName'
   ```

2. **For cmdlet syntax**: Suggest the user run locally:
   ```powershell
   Get-Help Cmdlet-Name -Full
   Get-Command Cmdlet-Name -Syntax
   ```

3. **Clearly state uncertainty**: If verification fails, tell the user:
   > "I wasn't able to verify this against live documentation. Please confirm
   > the module exists by running: `Find-PSResource -Name 'ModuleName'`"

### Verification Examples

**Good** (verified with live data):
> "The ImportExcel module (v7.8.10, updated Oct 2024, 17M+ downloads)
> provides Export-Excel for creating spreadsheets without Excel installed."

**Bad** (unverified claim):
> "Use the Excel-Tools module to export data." ← May not exist!

## Documentation Resources

- **PowerShell Docs**: https://learn.microsoft.com/en-us/powershell/
- **Module Browser**: https://learn.microsoft.com/en-us/powershell/module/
- **PowerShell Gallery**: https://www.powershellgallery.com
- **GitHub Docs**: https://github.com/MicrosoftDocs/PowerShell-Docs

## References

- **[best-practices.md](references/best-practices.md)** - Naming, parameters, pipeline, error handling, code style
- **[gui-development.md](references/gui-development.md)** - Windows Forms, WPF, controls, events, templates
- **[powershellget.md](references/powershellget.md)** - Find, install, update, publish modules
