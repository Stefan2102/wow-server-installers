# AzerothCore PowerShell 7 Installer

Windows installer for AzerothCore with optional playerbots support.
Clones source and modules, builds the server, initializes a bundled MySQL, patches configs, and generates launcher batch files — all from a terminal menu.

## Requirements

| Component           | Source                                                      |
| ------------------- | ----------------------------------------------------------- |
| Windows 10/11 x64   | OS                                                          |
| PowerShell 7+       | https://github.com/PowerShell/PowerShell/releases            |
| winget              | App Installer (default on Windows 11)                       |
| Internet access     | GitHub + AzerothCore repos                                  |

Visual Studio 2022 Community and Git are installed by the installer if missing (via winget).

## Getting Started

1. Install [PowerShell 7](https://github.com/PowerShell/PowerShell/releases).
2. Open the script and edit the configuration block at the top (see Configuration Explained below).
3. Double-click `start_azerothcore-installer.bat` or run:

   ```
   pwsh -NoProfile -ExecutionPolicy Bypass -File "azerothcore-installer.ps1"
   ```

## Configuration Explained

```powershell
$RootFolderName = 'AzerothCore'
$ParentDirectory = 'D:\WoW_Servers'
$SqlUser         = 'acore'
$SqlPassword     = 'acore'
$SqlPort         = 3306
$ClientPath      = 'D:\Games\World of Warcraft 3.3.5a'
$BuildThreads    = 0

$CoreRepositoryUrl = 'https://github.com/azerothcore/azerothcore-wotlk.git'

$ModuleRepositoryUrls = @(
    'https://github.com/azerothcore/mod-aoe-loot.git',
    'https://github.com/azerothcore/mod-learn-spells.git'
)
```

- `$RootFolderName` + `$ParentDirectory` — root folder (e.g. `D:\WoW_Servers\AzerothCore`).
- `$SqlUser` / `$SqlPassword` — MySQL credentials.
- `$SqlPort` — TCP port for bundled MySQL.
- `$ClientPath` — WoW 3.3.5a client folder (map extraction only).
- `$BuildThreads` — CMake parallelism. `0` = auto (all cores). Set `4` or `8` if compile runs out of memory.
- `$CoreRepositoryUrl` — AzerothCore fork.
- `$ModuleRepositoryUrls` — module repos cloned into `source/modules/`.

### Config File Edits

`$ConfigEdits` is also located in the configuration section. It controls the exact literal replacements applied by **Configure Config Files**.

```powershell
$ConfigEdits = @(
    @{
        File = 'worldserver.conf'
        Edits = @(
            @{ find = 'DataDir = "."'; replace = 'DataDir = "./data"' }
            @{ find = 'MapUpdate.Threads = 1'; replace = 'MapUpdate.Threads = 4' }
            @{ find = 'EnablePlayerSettings = 0'; replace = 'EnablePlayerSettings = 1' }
        )
    }
)
```

- `find` must exactly match the text in the generated `.conf` file.
- `replace` is the exact text written to the `.conf` file.
- Add or remove entries to customize configuration values.
- Database and MySQL path values can use the automatic tokens `{{LOGIN_DATABASE}}`, `{{WORLD_DATABASE}}`, `{{CHARACTER_DATABASE}}`, `{{PLAYERBOTS_DATABASE}}`, and `{{MYSQL_EXECUTABLE}}`.
- Missing patterns are reported as warnings. Running Configure again reports values that are already configured.
- **Generate .conf files** copies `.conf.dist` files to `.conf` files. **Configure Config Files** only applies the `$ConfigEdits` replacements and does not copy or delete configuration files.

### Not Configurable

- MySQL host: always `127.0.0.1` — the bundled MySQL, authserver, and worldserver all run on the same machine.
- Database names: `acore_auth`, `acore_world`, `acore_characters`, `acore_playerbots` (only if `mod-playerbots` is cloned).
- Database migrations are auto-imported by the servers on launch — no manual SQL import needed.

## Menu Steps

Run in this order for a first-time install:

1. **Create Folder Structure** — creates the root folder plus `build/`, `downloads/`, `source/`, `tools/`, `install/server/`, `install/database/`.
2. **Install Dependencies** — Git, Visual Studio 2022 (NativeDesktop workload), portable CMake, Boost, OpenSSL, MySQL.
3. **Source & Modules** — sub-menu: Clone (clones missing repos) and Update (fetches, shows commits behind, asks Y/N before pulling).
4. **Build Server** — sub-menu: Build (incremental), Clean Build, Data (Download or Extract maps from your WoW client).
5. **Setup Database** — sub-menu: Write `my.ini`, Initialize MySQL Data, Create Database User & Schemas.
6. **Finalization** — sub-menu: Generate `.conf` files (copies `.conf.dist` → `.conf`), Configure Config Files (applies `$ConfigEdits` literal replacements), Generate launcher `.bat` files.

## Typical Flows

### First-time install

```
1. Create Folder Structure
2. Install Dependencies
3. Source & Modules → 1. Clone
4. Build Server → 2. Clean Build
5. Setup Database → 1. Write my.ini → 2. Initialize MySQL Data → 3. Create Database User & Schemas
6. Finalization → 1. Generate .conf files → 2. Configure Config Files → 3. Generate launcher .bat files
```

### Update core / modules

```
3. Source & Modules → 2. Update   (review what changed)
4. Build Server → 1. Build (incremental)
6. Finalization → 1. Generate .conf files   (optional — only if new .conf.dist templates appeared)
```

### Change MySQL port

Edit `$SqlPort` in configuration, then:

```
5. Setup Database → 1. Write my.ini
5. Setup Database → 3. Create Database User & Schemas
6. Finalization → 2. Configure Config Files
```

### Extract your own maps

Set `$ClientPath` to your WoW 3.3.5a folder, then:

```
4. Build Server → 3. Data → 2. Extract Data
```

Extraction takes 30–60 minutes. Requires all four extractor executables (compiled by Build Server).

## Branch Behavior

- Clone uses each repo's default branch.
- To use a specific branch: `cd source/<repo>` and run `git checkout <branch>` manually.
- Update always respects the **currently checked-out branch** — never switches or pulls from a different branch.
- Repos with no upstream tracking are skipped with a warning.

## Starting the Server

1. Run `install/01_start_mysql.bat` — opens MySQL console. Leave it running.
2. Run `install/02_start_authserver.bat` — auto-imports pending SQL migrations on first launch.
3. Run `install/03_start_worldserver.bat` — auto-imports SQL, loads the world.

## Troubleshooting

| Symptom                                     | Fix                                                                                    |
| ------------------------------------------- | -------------------------------------------------------------------------------------- |
| `pwsh` not found                            | Install PowerShell 7 from https://github.com/PowerShell/PowerShell/releases             |
| `winget` not found                          | Install App Installer from the Microsoft Store (preinstalled on Windows 11)             |
| Visual Studio workload not detected         | Re-run Install Dependencies; invokes `vs_installer.exe modify` for existing VS installs |
| `cmake` / `git` not found in PATH           | Close and relaunch `start_azerothcore-installer.bat`                                     |
| `.7z` extraction fails                      | Windows 10 < 1803 lacks `.7z` support in `tar.exe`. Install 7-Zip.                     |
| Port in use                                 | Setup Database prompts you to stop the external MySQL and re-checks the port           |
| Update skipped: no upstream                 | `git branch --set-upstream-to=origin/<branch> <branch>`                                  |
| Build fails: cannot find Boost              | Confirm `tools/boost/lib64-msvc-14.3/cmake/Boost-*.cmake` exists. Re-run dependencies. |
| PCH memory errors (C3859 / C1076)          | Too many parallel compiles. Set `$BuildThreads = 4` in config and re-run Build.            |

## License

GPL-3.0 — see [LICENSE](LICENSE).
