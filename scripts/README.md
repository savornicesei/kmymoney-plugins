# KMM Plugin Build module

Use repository-root `build.ps1` for all automation. The module is an implementation
library for its task graph; do not invoke files in Public or Private directly.

```text
scripts/
  README.md
  KMMPluginBuild/
    KMMPluginBuild.psd1     # Manifest and explicit export list
    KMMPluginBuild.psm1     # Loads function definitions; no setup side effects
    Public/                # Operations called by build.ps1 tasks
    Private/               # Shared Craft installer, INI reader, and native process helper
    Tests/                 # Pester tests and synthetic-repository helper
```

PowerShell 7 Core is required. The Docker job supplies a pinned PowerShell runtime. Public
functions have the `KMM` prefix, and only the manifest's explicit list is exported.
Private functions, variables, and aliases are not exported.

## Task reference

Run from the repository root, or pass an absolute path to `build.ps1`.

| Task | Behavior |
| --- | --- |
| `Setup` | Download missing dependency versions into the ignored cache and import them |
| `FirstRun` | Prompt with defaults, install KMyMoney and its SDK through Craft, then atomically save the INI |
| `Init` / `Configure` | Initialize Craft and configure selected plugins using the native CMake preset |
| `Clean` | Configure, then clean through CMake; does not delete staging or sources |
| `Build` | Configure and build selected plugins; accepts an optional native `-Target` |
| `Test` | Build and run CTest; zero discovered tests is an error |
| `Stage` / `Install` | Build and install selected plugins into local staging |
| `BuildCI` | Build, Test, and Stage, stopping on failure |
| `EnterCraft` | Initialize Craft and retain its environment in this PowerShell process |
| `Run` | Initialize Craft and start the host without rebuilding |
| `OpenWorkspace` | Resolve local paths in a generated workspace and launch VS Code |
| `UpdateTranslations` | Extract/merge catalogs for each selected plugin |
| `Check` | Initialize Craft, analyze PowerShell, and run all module regression tests |
| `PrepareCI` | Bootstrap Craft if needed and build a matching host SDK on the native platform |
| `CI` | PrepareCI, Check, and the same BuildCI graph used locally |
| `?` | List the task graph |

```powershell
./build.ps1 -Tasks FirstRun -EnvFile laptop.env.ini
./build.ps1 -Tasks BuildCI -Plugins draft-transactions -EnvFile laptop.env.ini
./build.ps1 -Tasks Run -KMMAppArguments @('--help')
./build.ps1 -Tasks OpenWorkspace -GenerateOnly
./build.ps1 -Tasks UpdateTranslations -Plugins draft-transactions -Preview
./build.ps1 -Tasks Check -EnvFile laptop.env.ini
Get-Help ./build.ps1 -Full
```

`Tasks` and `Plugins` accept arrays when called from PowerShell. Plugin names are
directories under `plugins` with a CMakeLists.txt; use `all` alone for discovery.
Plugins defaults to `all`. In CI, initialization overrides even an explicit
Plugins argument with comma-separated `KMM_PLUGINS`: a runner value takes
precedence over the selected INI. Outside CI, this variable is ignored. Unknown
plugins fail before Craft setup. `Stage` does not imply Test; use BuildCI when
staging must follow successful tests. Shared dependencies run once per invocation.

`-GenerateOnly` applies to OpenWorkspace. `-KMMAppArguments` applies to Run.
`-Target` applies to Build. `-Preview` applies only to EnterCraft, OpenWorkspace,
and UpdateTranslations. It previews the operation without modifying its files or
starting programs; dependency module setup still occurs before the task graph.

## Dependency setup

Versions for InvokeBuild, Pester, and PSScriptAnalyzer are defined only in
[Initialize-KMMPowerShell.ps1](KMMPluginBuild/Public/Initialize-KMMPowerShell.ps1).
The bootstrap loads them before Invoke-Build itself is needed. FirstRun and Setup
reuse that function, and CI enters through `build.ps1 -Tasks CI`.

```powershell
./build.ps1 -Tasks Setup
./build.ps1 -Tasks Setup -ModulePath .cache/powershell
```

The default cache is ignored `build/powershell/modules`. Relative ModulePath
values resolve against the repository root. Missing versions are downloaded with
Save-Module from PSGallery; existing cached manifests are validated and imported
by exact path. Setup adds the cache to this process's PSModulePath for child
PowerShell processes. It does not change repository trust or install into the
user's global module directory. Downloads remain cached after failure; a failed
import restores the prior PSModulePath, but already imported modules remain.
Use a fresh PowerShell session after changing versions with loaded assemblies.
Populate the cache before working offline.

## Environment and IDEs

FirstRun writes ignored `env.ini`; `-EnvFile` selects another literal INI.
All configurable project variables are listed in [env.example.ini](../env.example.ini).
The selected INI overrides these defaults; inherited project settings are replaced
for the task invocation. FirstRun prompts for four paths and writes every key,
preserving other existing settings. Empty CRAFT_PYTHON enables automatic detection. Unknown keys,
duplicates, malformed lines, and missing explicitly selected files fail.
Configuration values are never evaluated as PowerShell expressions.
FirstRun suggests the absolute `~/kdecraft-root` path when Craft has no configured
location. Blank source/executable entries are discovered after Craft installs the
host SDK; explicit entries are preserved. It uses the same private installer as
CI, bootstrapping Craft if necessary. Python, Git, and the native compiler are
prerequisites. The selected INI is replaced only after successful installation;
completed Craft downloads and installations remain if a later step fails.
The shared installer writes intermediate configuration to `build/setup/env.ini`.
FirstRun saves the final values to the selected INI; CI uses the intermediate
file for subsequent tasks and records the resolved target in `build/ci/kmymoney-version.txt`.
GitLab selects [env.ci.ini](../env.ci.ini) for headless Qt and locale settings.
CI/TF_BUILD/GITHUB_ACTIONS are runner flags, not project configuration. Craft's
environment, search paths, and computed KMYMONEY_PRESET/KMYMONEY_STAGE_DIR are
runtime outputs. CI derives SDK paths from the host it builds.

Normal tasks restore environment variables, the prior craft function, and working
directory in Exit-Build even after failure. Successful EnterCraft intentionally
retains the environment for subsequent commands in the same shell:

```powershell
pwsh -NoProfile -NoExit -File ./build.ps1 -Tasks EnterCraft
```

The root script returns on success instead of terminating the interactive shell.
Each top-level call reloads the module to pick up script changes in persistent
terminals. The internal Invoke-Build invocation reuses that loaded instance.
Launch CLion or Qt Creator from that shell. OpenWorkspace starts VS Code with the
same Craft environment; a task cannot change an already-running IDE's environment.
The root README describes each IDE's CMake and debugger configuration.

Craft setup obtains environment JSON from CraftSetupHelper.py, verifies KDEROOT,
and adds staged plugin/data/library search paths using the platform path separator.
Native arguments are passed separately and failures terminate the task graph.
The reported error contains the native exit code; `pwsh -File` returns a nonzero
script status. CI uses Craft on all platforms. JUnit reports go to build/ci and
build/<preset>; plugins stage under stage/<preset>.

## Translation maintenance

UpdateTranslations accepts the same `-Plugins` selection as build tasks. Each
plugin needs src/, po/, and exactly one root-level `<domain>.json.in`. The metadata
filename selects its translation domain. The optional XMLGUI resource contributes
menu strings. Existing translations are preserved; new entries remain empty.
Failures stop processing but do not undo earlier catalog merges. Review changed
catalogs and localized JSON metadata; metadata translations are not automatically
regenerated. See the [catalog guide](../plugins/draft-transactions/po/README.md).

## Regression checks

`./build.ps1 -Tasks Check` invokes PSScriptAnalyzer and Pester through the module.
Tests mock module dependencies, exercise real Invoke-Build task ordering and
native failure propagation, and use synthetic repositories and financial fixtures.
The suite checks setup/cache behavior, literal configuration, environment rollback,
workspace generation, plugin selection, translation coverage, task routing, and
module exports. Native fixture checks require CMake, CTest, Ninja, and gettext.

Tests are in `KMMPluginBuild/Tests`; keep new tests there. They may invoke module
functions directly to test behavior, but user-facing commands and CI must go
through build.ps1. The checks write `build/ci/pester.xml`; GitLab publishes that
report alongside CTest results. Registry fixtures are disabled. Pester runs in a
separate PowerShell runspace so fixture modules cannot replace the module running
the build. Fixture environment changes are restored by the tests.

## KMyMoney version

KMMAppVersion appears immediately before KMMAppArguments in build.ps1. It overrides
KMM_APP_VERSION from the INI and supplies the literal version value to Craft's
`--set` action for extragear/kmymoney. Empty leaves Craft's selection unchanged.
Versions and branches must be supported by the installed blueprint. The setting
persists in Craft even after the task environment is restored. Local builds require
an already matching installed SDK; FirstRun and CI provision it from source.
After provisioning, the installer queries Craft's `buildTarget` and saves that
exact tag/branch to KMM_APP_VERSION, including when no version was requested.
It does not use the package display version, which can include daily/patch suffixes.

For interactive testing, use `./build.ps1 -Tasks Stage,Run -Plugins draft-transactions`.
For debugging, stage first, launch OpenWorkspace, and select the native debugger
configuration. See the [VS Code walkthrough](../README.md#visual-studio-code).
