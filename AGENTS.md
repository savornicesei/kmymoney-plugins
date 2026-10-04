# Repository scope

This repository prepares KMyMoney plugin development on Windows, Linux, and macOS.
The root CMake project aggregates independently selectable plugins.
The first plugin is `plugins/draft-transactions`, displayed as **Draft transactions**.
Do not create additional plugins or a Craft blueprint unless requested.

- Drafts use versioned document metadata in both XML and SQL storage.
- Preserve complete transactions and splits; only the posting date may change on restore.
- Use host APIs and undo history; never modify the host or write directly to its database.
- Metadata requires explicit undo commands: the current host's parameter setters bypass undo.
- Keep recovery copies until the host is clean and the restored transaction matches completely.
- Keep plugin code resident while undo history can reference its commands.
- Run the synthetic CTest suite after changing transaction or serialization behavior.
- Keep each plugin's user-facing strings in its own translation domain
  (`drafttransactions` for Draft transactions); update
  PO catalogs and localized plugin JSON together. See `plugins/draft-transactions/po/README.md`.
- Preserve UTF-8 in plugin-generated exceptions through `draftError`; the host's
  exception macro uses the Windows code page and can damage translated text.

# Environment

- Local paths come from `CRAFT_ROOT`, `KMYMONEY_SOURCE_DIR`, and
  `KMYMONEY_EXECUTABLE`; `CRAFT_PYTHON` optionally selects Python. Do not hardcode
  a developer's paths in scripts, presets, or the shared workspace.
- `build.ps1 -Tasks FirstRun` writes every project configuration key to ignored `env.ini`.
  It defaults Craft to the user's kdecraft-root directory, provisions KMyMoney
  through the shared Craft installer, and discovers unspecified source/executable
  paths. Preserve explicit paths and replace the INI only after successful setup.
  Define shared defaults in env.example.ini and Linux CI overrides in env.ci.ini.
  Plugins defaults to all; CI initialization overrides it with KMM_PLUGINS.
  KMM_APP_VERSION selects Craft's KMyMoney version/branch through --set; the
  shared CI task provisions the SDK with Craft on the native platform.
  Automation accepts `-EnvFile`; use the private `Read-KMMLocalEnvironment` helper to parse literal
  values, never execute configuration text. File entries override matching env values.
- Match the compiler, architecture, Qt version, and runtime to the host's Craft
  ABI. Use native platform presets, Ninja, and `RelWithDebInfo`.
- Use PowerShell 7 Core (`pwsh`) for scripts and IDE terminals. Scripts must
  require version 7.0 or later and the Core edition; keep `.ps1` files UTF-8/LF.
- Define dependency versions only in `scripts/KMMPluginBuild/Public/Initialize-KMMPowerShell.ps1`.
  Build bootstrap, FirstRun, and CI delegate module setup to that function. Use its
  ignored local cache; do not add per-script module installs or change PSGallery trust.
- Use `build.ps1 -Tasks EnterCraft` in `pwsh` before starting an IDE. A terminal
  environment does not change the environment of an already-running IDE.
- Use `build.ps1` tasks as the single automation entry point. Implementation lives
  in the KMMPluginBuild module's Public/Private folders, with Pester tests in Tests.
  Do not add standalone script entry points. Importing the module must have no setup side effects.
- Use root `build.ps1 -Tasks BuildCI -Plugins <names>` for selected-plugin build,
  test, and staging. Root CMake discovers `plugins/*/CMakeLists.txt`; keep plugin
  names compatible with their `BUILD_<NAME>` options and `KMM_PLUGIN_SELECTION`.
- Keep builds in `build/<preset>/` and installs in `stage/<preset>/` using shared presets.
  Do not mix MSVC and MinGW or Qt major versions.

# Working practices

- Keep changes within this repository unless the task authorizes external changes.
- Treat the sibling KMyMoney checkout as reference material; do not modify it
  or install into Craft as part of routine plugin configuration work.
- Follow the actual KMyMoney plugin interfaces and CMake macros. Source headers
  alone are not a standalone plugin SDK; verify generated headers, libraries,
  exported symbols, and host ABI before choosing the future build integration.
- Keep editor configuration shared through the workspace and CMake presets.
  Ignore personal CLion, Qt Creator, VS Code, and Visual Studio state.
- `build.ps1 -Tasks OpenWorkspace` resolves environment-based folder paths into an
  ignored local workspace. Edit only the shared workspace template.
- Use PowerShell path APIs and the platform path separator. Never substitute
  shell commands into generated command strings. Preserve native command errors.
- Never commit financial files, credentials, build output, or debug dumps.
- Use synthetic financial data when exercising the host application.
- Update README.md when changing paths, setup, build, install, or debug commands.
- Validate JSON, PowerShell 7 syntax, preset discovery, and `git diff --check` for
  configuration changes. Do not claim compilation or plugin loading was tested
  before a plugin exists. Report any checks that could not be run.
- follow [KMyMoney coding conventions](https://invent.kde.org/office/kmymoney/-/wikis/Coding-conventions) and [KDE coding guideliness](https://develop.kde.org/docs/getting-started/building/)
- Check:
    - primary [KMyMoney wiki](https://invent.kde.org/office/kmymoney/-/wikis/home), [issues](https://invent.kde.org/office/kmymoney/-/work_items) and [source code](https://invent.kde.org/office/kmymoney/-/tree/master), [official KMyMoney plugins](https://invent.kde.org/office/kmymoney/-/tree/master/kmymoney/plugins),
    - secondary [official KDE development documentation](https://develop.kde.org/), tutorials, guidelines like [Plasma Developer Guide](https://community.kde.org/Plasma/DeveloperGuide) or [KDE Windows developemnt](https://community.kde.org/Get_Involved/development/Windows#)
    - third QT official documentation, tutorials and guideliness
