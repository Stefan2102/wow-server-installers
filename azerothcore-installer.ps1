#requires -Version 7.0

[CmdletBinding()]
param()

# ==============================================================================
# CONFIGURATION
# ==============================================================================

$RootFolderName = 'AzerothCore'                                      # Root folder name
$ParentDirectory = 'D:\WoW_Servers'                                  # Parent path (drive or directory)

$SqlUser     = 'acore'                                               # MySQL user account
$SqlPassword = 'acore'                                               # MySQL password
$SqlPort     = 3306                                                  # MySQL TCP port
$ClientPath  = 'D:\Games\World of Warcraft 3.3.5a'                   # WoW 3.3.5a installation directory
$BuildThreads = 0                                                    # CMake build parallelism (0 = auto)

$CoreRepositoryUrl = 'https://github.com/azerothcore/azerothcore-wotlk.git'   # AzerothCore upstream repository

$ModuleRepositoryUrls = @(                                           # Module repositories (cloned into source/modules/)
    'https://github.com/azerothcore/mod-aoe-loot.git',
    'https://github.com/azerothcore/mod-learn-spells.git'
)

$DependencyUrls = @{                                                 # download URLs for portable toolchain
    CMake      = 'https://github.com/Stefan2102/build-tools/releases/download/cmake_4.4.0/cmake-4.4.0-windows-x86_64.7z'
    Boost      = 'https://github.com/Stefan2102/build-tools/releases/download/boost_1.91.0/boost_1_91_0.7z'
    OpenSSL    = 'https://github.com/Stefan2102/build-tools/releases/download/openssl_v4.0.1/openssl.7z'
    MySQL      = 'https://github.com/Stefan2102/build-tools/releases/download/mysql_8.4.8/mysql-8.4.8-winx64.7z'
    ClientData = 'https://github.com/wowgaming/client-data/releases/download/v20.0/Data.zip'  # pre-extracted maps
}

$ConfigEdits = @(                                                    # .conf edits (exact find/replace text)
    @{
        File = 'authserver.conf'
        Edits = @(
            @{ find = 'LoginDatabaseInfo = "127.0.0.1;3306;acore;acore;acore_auth"'; replace = 'LoginDatabaseInfo = "{{LOGIN_DATABASE}}"' }
            @{ find = 'MySQLExecutable = ""'; replace = 'MySQLExecutable = "{{MYSQL_EXECUTABLE}}"' }
            @{ find = 'LogsDir = ""'; replace = 'LogsDir = "./logs"' }
        )
    },
    @{
        File = 'worldserver.conf'
        Edits = @(
            @{ find = 'DataDir = "."'; replace = 'DataDir = "./data"' }
            @{ find = 'LogsDir = ""'; replace = 'LogsDir = "./logs"' }
            @{ find = 'TempDir = ""'; replace = 'TempDir = "./temp"' }
            @{ find = 'MySQLExecutable = ""'; replace = 'MySQLExecutable = "{{MYSQL_EXECUTABLE}}"' }
            @{ find = 'MapUpdate.Threads = 1'; replace = 'MapUpdate.Threads = 4' }
            @{ find = 'EnablePlayerSettings = 0'; replace = 'EnablePlayerSettings = 1' }
            @{ find = 'DBC.EnforceItemAttributes = 1'; replace = 'DBC.EnforceItemAttributes = 0' }
            @{ find = 'GameType = 0'; replace = 'GameType = 1' }
            @{ find = 'LoginDatabaseInfo     = "127.0.0.1;3306;acore;acore;acore_auth"'; replace = 'LoginDatabaseInfo     = "{{LOGIN_DATABASE}}"' }
            @{ find = 'WorldDatabaseInfo     = "127.0.0.1;3306;acore;acore;acore_world"'; replace = 'WorldDatabaseInfo     = "{{WORLD_DATABASE}}"' }
            @{ find = 'CharacterDatabaseInfo = "127.0.0.1;3306;acore;acore;acore_characters"'; replace = 'CharacterDatabaseInfo = "{{CHARACTER_DATABASE}}"' }
        )
    },
    @{
        File = 'modules\playerbots.conf'
        Optional = $true
        Edits = @(
            @{ find = 'PlayerbotsDatabaseInfo = "127.0.0.1;3306;acore;acore;acore_playerbots"'; replace = 'PlayerbotsDatabaseInfo = "{{PLAYERBOTS_DATABASE}}"' }
        )
    },
    @{
        File = 'dbimport.conf'
        Edits = @(
            @{ find = 'LoginDatabaseInfo     = "127.0.0.1;3306;acore;acore;acore_auth"'; replace = 'LoginDatabaseInfo     = "{{LOGIN_DATABASE}}"' }
            @{ find = 'WorldDatabaseInfo     = "127.0.0.1;3306;acore;acore;acore_world"'; replace = 'WorldDatabaseInfo     = "{{WORLD_DATABASE}}"' }
            @{ find = 'CharacterDatabaseInfo = "127.0.0.1;3306;acore;acore;acore_characters"'; replace = 'CharacterDatabaseInfo = "{{CHARACTER_DATABASE}}"' }
            @{ find = 'MySQLExecutable = ""'; replace = 'MySQLExecutable = "{{MYSQL_EXECUTABLE}}"' }
            @{ find = 'LogsDir = ""'; replace = 'LogsDir = "./logs"' }
        )
    }
)

# ==============================================================================
# VARIABLES
# ==============================================================================

function Get-InstallPaths {
    $Root = Join-Path $ParentDirectory $RootFolderName
    return [pscustomobject]@{
        Root      = $Root
        Source    = Join-Path $Root 'source'
        Build     = Join-Path $Root 'build'
        Downloads = Join-Path $Root 'downloads'
        Tools     = Join-Path $Root 'tools'
        Server    = Join-Path $Root 'install\server'
        Database  = Join-Path $Root 'install\database'
        Modules   = Join-Path $Root 'source\modules'
        Cmake     = Join-Path $Root 'tools\cmake\bin'
        Boost     = Join-Path $Root 'tools\boost'
        Openssl   = Join-Path $Root 'tools\openssl'
        MysqlBin  = Join-Path $Root 'install\database\bin'
    }
}

$Paths = Get-InstallPaths

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

function Write-SectionHeader {
    param([string]$Title)
    $line = '=' * 70
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Message)
    Write-Host "  => $Message" -ForegroundColor Gray
}

function Write-Done {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [!!] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "  [X] $Message" -ForegroundColor Red
}

function New-Folder {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) { return }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Write-Done "created: $Path"
}

function Save-File {
    param(
        [string]$Source,
        [string]$Destination
    )
    if (Test-Path -LiteralPath $Destination) {
        Write-Step "skip download (exists): $(Split-Path $Destination -Leaf)"
        return
    }
    Write-Step "downloading: $Source"
    try {
        Import-Module BitsTransfer -ErrorAction SilentlyContinue
        Start-BitsTransfer -Source $Source -Destination $Destination
    } catch {
        Write-Step "BITS failed, falling back to Invoke-WebRequest..."
        try {
            Invoke-WebRequest -Uri $Source -OutFile $Destination
        } catch {
            Write-Err "Download failed ($Source): $_"
            throw "Download failed: $Source"
        }
    }
    Write-Done "saved: $Destination"
}

function Expand-File {
    param(
        [string]$Archive,
        [string]$Destination
    )
    Write-Step "extracting: $Archive -> $Destination"
    switch -Wildcard ($Archive) {
        '*.7z' {
            $sevenZipCandidates = @(
                "$env:ProgramFiles\7-Zip\7z.exe",
                "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
            )
            $sevenZip = $sevenZipCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            if ($sevenZip) {
                & $sevenZip x $Archive "-o$Destination" -y -bso0 -bse0
                if ($LASTEXITCODE -ne 0) { throw "Extraction failed: $Archive" }
            } else {
                & tar.exe -xf $Archive -C $Destination
                if ($LASTEXITCODE -ne 0) { throw "Extraction failed: $Archive" }
            }
        }
        '*.zip' {
            Expand-Archive -Path $Archive -DestinationPath $Destination -Force
        }
        default { throw "Unknown archive format: $Archive" }
    }
}

function Test-DependencyInstalled {
    param(
        [string]$CheckPath,
        [string[]]$RequiredFiles = @()
    )
    if (-not (Test-Path -LiteralPath $CheckPath)) { return $false }
    foreach ($f in $RequiredFiles) {
        if ($f -match '[\*\?]') {
            $matches = Get-ChildItem -Path $CheckPath -Filter $f -ErrorAction SilentlyContinue
            if (-not $matches) { return $false }
        } elseif ($f -match '[\\/]') {
            if (-not (Test-Path -LiteralPath (Join-Path $CheckPath $f))) { return $false }
        } else {
            $matches = Get-ChildItem -Path $CheckPath -Filter $f -Recurse -Depth 5 -ErrorAction SilentlyContinue
            if (-not $matches) { return $false }
        }
    }
    return $true
}

function Invoke-ExternalProcess {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory
    )
    if ($WorkingDirectory) { Push-Location $WorkingDirectory }
    try {
        & $FilePath @ArgumentList
        if ($LASTEXITCODE -ne 0) {
            throw "'$FilePath' exited with code $LASTEXITCODE"
        }
    } finally {
        if ($WorkingDirectory) { Pop-Location }
    }
}

function Test-GitInstalled {
    try {
        $null = Get-Command git -ErrorAction Stop
        return $true
    } catch { return $false }
}

function Install-Git {
    Write-Step "installing Git via winget..."
    try {
        Invoke-ExternalProcess -FilePath 'winget' -ArgumentList @('install','--id','Git.Git','-e','--source','winget','--accept-package-agreements','--accept-source-agreements')
        Write-Done "Git installed"
    } catch {
        Write-Err "Git install failed: $_"
        throw "Git installation failed: $_"
    }
}

function Test-VisualStudioInstalled {
    $vswhere = Get-VswherePath
    if (-not $vswhere) { return $null }
    $installPath = & $vswhere -latest -products * -version '[17.0,18.0)' -property installationPath 2>$null
    if ([string]::IsNullOrWhiteSpace($installPath)) { return $null }
    return $installPath.Trim()
}

function Test-VisualStudioWorkload {
    param([string]$InstallPath)
    $vswhere = Get-VswherePath
    if (-not $vswhere -or [string]::IsNullOrWhiteSpace($InstallPath)) { return $false }
    try {
        $out = & $vswhere -latest -products * -version '[17.0,18.0)' `
            -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath 2>$null
        $paths = @($out | ForEach-Object { $_.Trim() })
        return $paths -contains $InstallPath
    } catch { return $false }
}

function Install-VisualStudio {
    Write-Step "checking Visual Studio 2022..."
    $installPath = Test-VisualStudioInstalled

    if ($installPath) {
        Write-Step "VS 2022 detected at $installPath"
        if (Test-VisualStudioWorkload -InstallPath $installPath) {
            Write-Step "skip Visual Studio 2022 (installed with NativeDesktop workload)"
            return
        }
        Write-Step "NativeDesktop workload missing - running modify via vs_installer.exe"
        $vsInstaller = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"
        if (-not (Test-Path -LiteralPath $vsInstaller)) {
            Write-Err "vs_installer.exe not found at $vsInstaller"
            return
        }
        $argString = "modify --installPath `"$installPath`" --add Microsoft.VisualStudio.Workload.NativeDesktop --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621 --includeRecommended --passive --norestart"
        try {
            $proc = Start-Process -FilePath $vsInstaller -ArgumentList $argString -Wait -PassThru -Verb RunAs
            if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010 -or $proc.ExitCode -eq 1641) {
                Write-Done "Visual Studio 2022 modified (workload installed)"
            } else {
                Write-Warn "vs_installer exited with code $($proc.ExitCode)"
            }
        } catch {
            Write-Err "Failed to launch vs_installer for modify: $_"
        }
        return
    }

    Write-Step "VS 2022 not detected - fresh install via winget"
    $overrideArgs = '--passive --wait --add Microsoft.VisualStudio.Workload.NativeDesktop --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621 --includeRecommended'
    $argString = "install --id Microsoft.VisualStudio.2022.Community -e --override `"$overrideArgs`" --accept-package-agreements --accept-source-agreements"
    try {
        $proc = Start-Process -FilePath 'winget' -ArgumentList $argString -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010 -or $proc.ExitCode -eq 1641) {
            Write-Done "Visual Studio 2022 installed"
        } else {
            Write-Warn "winget exited with code $($proc.ExitCode)"
        }
    } catch {
        Write-Err "Failed to launch winget for Visual Studio: $_"
    }
}

function Find-PlayerbotsModule {
    param($Paths)
    return (Test-Path -LiteralPath "$($Paths.Modules)\mod-playerbots")
}

function Test-PortInUse {
    param([int]$Port = 3306)
    try {
        $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop
        return $null -ne $conn
    } catch { return $false }
}

function Confirm-Overwrite {
    param([string]$Path, [string]$Message = "already exists", [string]$Prompt = "Overwrite? (Y/N)")
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -and -not (Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)) {
        return $true
    }
    Write-Warn "$(Split-Path $Path -Leaf) $Message."
    do {
        $answer = Read-Host $Prompt
        if ($answer -match '^[YyNn]$') { break }
        Write-Warn "Invalid input: $answer"
    } while ($true)
    return $answer -match '^[Yy]'
}

function Wait-Enter {
    Write-Host ""
    Write-Host "Press any key to return to menu..." -ForegroundColor Gray
    [void][Console]::ReadKey($true)
}

function Resolve-ConfigReplacement {
    param(
        [string]$Text,
        [hashtable]$Tokens
    )

    foreach ($token in $Tokens.Keys) {
        $marker = '{{' + $token + '}}'
        $Text = $Text.Replace($marker, $Tokens[$token])
    }
    return $Text
}

function Update-ConfigFile {
    param(
        [string]$Path,
        [object[]]$Edits,
        [hashtable]$Tokens
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warn "$(Split-Path $Path -Leaf) not found at $Path"
        return
    }

    $content = Get-Content -LiteralPath $Path -Raw
    $changed = $false
    $missed = 0
    foreach ($edit in $Edits) {
        $find = $edit.find
        $replace = Resolve-ConfigReplacement -Text $edit.replace -Tokens $Tokens
        if ($content.Contains($find)) {
            if ($find -eq $replace) {
                Write-Step "already configured:"
                Write-Host "     value: $replace" -ForegroundColor DarkGray
            } else {
                $content = $content.Replace($find, $replace)
                Write-Step "replaced:"
                Write-Host "     before: $find" -ForegroundColor DarkGray
                Write-Host "     after:  $replace" -ForegroundColor DarkGray
                $changed = $true
            }
        } elseif ($content.Contains($replace)) {
            Write-Step "already configured:"
            Write-Host "     value: $replace" -ForegroundColor DarkGray
        } else {
            Write-Warn "pattern not found:"
            Write-Host "     expected: $find" -ForegroundColor DarkGray
            Write-Host "     wanted:   $replace" -ForegroundColor DarkGray
            $missed++
        }
    }

    if ($missed -gt 0) {
        [System.IO.File]::WriteAllText($Path, $content)
        Write-Done "$(Split-Path $Path -Leaf) partially patched ($missed key(s) not found)"
    } elseif ($changed) {
        [System.IO.File]::WriteAllText($Path, $content)
        Write-Done "$(Split-Path $Path -Leaf) patched"
    } else {
        Write-Step "$(Split-Path $Path -Leaf) unchanged"
    }
}

function Get-GitRepositories {
    param($Paths)
    $repos = @()
    $coreGitDir = Join-Path $Paths.Source '.git'
    if (Test-Path -LiteralPath $coreGitDir) {
        $repos += [pscustomobject]@{ Name = 'core'; Path = $Paths.Source }
    }
    if (Test-Path -LiteralPath $Paths.Modules) {
        Get-ChildItem -LiteralPath $Paths.Modules -Directory | ForEach-Object {
            if (Test-Path "$($_.FullName)\.git") {
                $repos += [pscustomobject]@{ Name = $_.Name; Path = $_.FullName }
            }
        }
    }
    return $repos
}

function Get-VswherePath {
    @(
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe",
        "$env:ProgramFiles\Microsoft Visual Studio\Installer\vswhere.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

# ==============================================================================
# FOLDER STRUCTURE
# ==============================================================================

function Invoke-CreateFolderStructure {
    param($Paths)

    if ([string]::IsNullOrWhiteSpace($RootFolderName)) { throw '$RootFolderName is empty' }
    if ([string]::IsNullOrWhiteSpace($ParentDirectory)) { throw '$ParentDirectory is empty' }

    Write-SectionHeader "Create Folder Structure"
    Write-Step "root folder: $($Paths.Root)"

    $folders = @(
        $Paths.Root,
        $Paths.Build,
        $Paths.Downloads,
        $Paths.Source,
        $Paths.Tools,
        $Paths.Server,
        $Paths.Database
    )
    $created = 0; $existed = 0
    foreach ($f in $folders) {
        if (Test-Path -LiteralPath $f) { $existed++ } else { $created++; New-Folder -Path $f }
    }

    Write-Done "folder structure ready ($created folder(s) created, $existed already existed)"
}

# ==============================================================================
# INSTALL DEPENDENCIES
# ==============================================================================

function Invoke-InstallDependencies {
    param($Paths)

    Write-SectionHeader "Install Dependencies"

    if (-not (Test-Path -LiteralPath $Paths.Root)) {
        Write-Err "Root folder missing. Run 'Create Folder Structure' first."
        return
    }

    if (Test-GitInstalled) { Write-Step "skip Git (installed)" }
    else { Install-Git }

    Write-Host ""
    Install-VisualStudio

    Write-Host ""
    Install-PortableTool -Paths $Paths -ToolName 'CMake' -CheckSubdir $Paths.Cmake -RequiredFiles @('cmake.exe')

    Write-Host ""
    Install-PortableTool -Paths $Paths -ToolName 'Boost' -CheckSubdir $Paths.Boost -RequiredFiles @('BoostConfig.cmake')

    Write-Host ""
    Install-PortableTool -Paths $Paths -ToolName 'OpenSSL' -CheckSubdir "$($Paths.Openssl)\bin" -RequiredFiles @('libcrypto*.dll')

    Write-Host ""
    Install-MySQLPortable -Paths $Paths

    Write-Host ""
    Write-Done "dependencies ready"
}

function Install-PortableTool {
    param(
        $Paths,
        [string]$ToolName,
        [string]$CheckSubdir,
        [string[]]$RequiredFiles
    )
    Write-Step "checking $ToolName at $CheckSubdir"
    if (Test-DependencyInstalled -CheckPath $CheckSubdir -RequiredFiles $RequiredFiles) {
        Write-Step "skip $ToolName (already installed)"
        return
    }

    $url = $DependencyUrls[$ToolName]
    if (-not $url) { Write-Err "no URL configured for $ToolName"; return }
    $archiveName = Split-Path $url -Leaf
    $archivePath = Join-Path $Paths.Downloads $archiveName

    Save-File -Source $url -Destination $archivePath

    $tempExtract = Join-Path $Paths.Tools "$ToolName-extract"
    if (Test-Path -LiteralPath $tempExtract) { Remove-Item -LiteralPath $tempExtract -Recurse -Force }
    New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null
    Expand-File -Archive $archivePath -Destination $tempExtract

    $normalParent = switch ($ToolName) {
        'CMake'   { Join-Path $Paths.Tools 'cmake' }
        'Boost'   { $Paths.Boost }
        'OpenSSL' { $Paths.Openssl }
        default   { Join-Path $Paths.Tools $ToolName.ToLower() }
    }
    if (Test-Path -LiteralPath $normalParent) { Remove-Item -LiteralPath $normalParent -Recurse -Force }

    $items = Get-ChildItem -LiteralPath $tempExtract -Force
    if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
        Move-Item -LiteralPath $items[0].FullName -Destination $normalParent -Force
    } else {
        New-Folder -Path $normalParent
        Copy-Item -Path "$tempExtract\*" -Destination $normalParent -Recurse -Force
    }
    Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

    if (Test-DependencyInstalled -CheckPath $CheckSubdir -RequiredFiles $RequiredFiles) {
        Write-Done "$ToolName installed at $normalParent"
    } else {
        Write-Err "$ToolName install verification failed"
    }
}

function Install-MySQLPortable {
    param($Paths)
    $mysqlCheck = Join-Path $Paths.Database 'bin\mysqld.exe'
    Write-Step "checking MySQL at $mysqlCheck"
    if (Test-Path -LiteralPath $mysqlCheck) {
        Write-Step "skip MySQL (already installed)"
        return
    }

    $url = $DependencyUrls['MySQL']
    $archiveName = Split-Path $url -Leaf
    $archivePath = Join-Path $Paths.Downloads $archiveName

    Save-File -Source $url -Destination $archivePath

    $tempExtract = Join-Path $Paths.Downloads 'mysql-extract'
    if (Test-Path -LiteralPath $tempExtract) { Remove-Item -LiteralPath $tempExtract -Recurse -Force }
    New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null
    Expand-File -Archive $archivePath -Destination $tempExtract

    $src = Get-ChildItem -LiteralPath $tempExtract -Directory | Select-Object -First 1
    if ($src) {
        Copy-Item -Path "$($src.FullName)\*" -Destination $Paths.Database -Recurse -Force
    } else {
        Copy-Item -Path "$tempExtract\*" -Destination $Paths.Database -Recurse -Force
    }
    Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $mysqlCheck) {
        Write-Done "MySQL installed at $($Paths.Database)"
    } else {
        Write-Err "MySQL install verification failed (mysqld.exe not found)"
    }
}

# ==============================================================================
# SOURCE & MODULES
# ==============================================================================

function Invoke-CloneAll {
    param($Paths)

    Write-SectionHeader "Clone"

    if (-not (Test-GitInstalled)) {
        Write-Err "Git is not installed. Run 'Install Dependencies' first."
        return
    }
    if (-not (Test-Path -LiteralPath $Paths.Root)) {
        Write-Err "Root folder missing. Run 'Create Folder Structure' first."
        return
    }

    $coreGitDir = Join-Path $Paths.Source '.git'
    if (Test-Path -LiteralPath $coreGitDir) {
        Write-Step "core already cloned, skipping"
    } else {
        Write-Step "cloning core: $CoreRepositoryUrl"
        try {
            Invoke-ExternalProcess -FilePath 'git' -ArgumentList @('clone', '-q', $CoreRepositoryUrl, $Paths.Source)
            Write-Done "core cloned to $($Paths.Source)"
        } catch {
            Write-Err "core clone failed: $_"
        }
    }

    New-Folder -Path $Paths.Source
    New-Folder -Path $Paths.Modules

    foreach ($url in $ModuleRepositoryUrls) {
        $name = (Split-Path $url -Leaf) -replace '\.git$',''
        $target = Join-Path $Paths.Modules $name
        $gitDir = Join-Path $target '.git'
        if (Test-Path -LiteralPath $gitDir) {
            Write-Step "module already cloned, skipping: $name"
        } else {
            Write-Step "cloning module: $name"
            try {
                Invoke-ExternalProcess -FilePath 'git' -ArgumentList @('clone', '-q', $url, $target)
                Write-Done "module cloned: $name"
            } catch {
                Write-Err "module clone failed for ${name}: $_"
            }
        }
    }
}

function Invoke-CloneRepositories {
    param($Paths)
    while ($true) {
        Clear-Host
        Write-SectionHeader "Source & Modules"
        Write-Host "  1. Clone"
        Write-Host "  2. Update"
        Write-Host "  B. Back to main menu"
        Write-Host ""
        $choice = Read-Host "Select option"
        switch -Regex ($choice) {
            '^1$' { try { Invoke-CloneAll -Paths $Paths } catch { Write-Err "Step failed: $_" }; Wait-Enter }
            '^2$' { try { Invoke-CheckUpdates -Paths $Paths } catch { Write-Err "Step failed: $_" }; Wait-Enter }
            '^[Bb]$' { return }
            default { Write-Warn "Invalid choice: $choice" }
        }
        if ($choice -match '^[Bb]$') { break }
    }
}

function Invoke-CheckUpdates {
    param($Paths)

    Write-SectionHeader "Update"

    $repos = Get-GitRepositories -Paths $Paths
    if (-not $repos) {
        Write-Warn "No repositories found"
        return
    }

    Write-Step "checking $($repos.Count) repo(s)..."
    $results = @()
    foreach ($r in $repos) {
        $branch = & git -C $r.Path branch --show-current 2>$null
        if ([string]::IsNullOrWhiteSpace($branch)) { continue }
        $branch = $branch.Trim()

        $upstream = & git -C $r.Path rev-parse --abbrev-ref '@{u}' 2>$null
        if ([string]::IsNullOrWhiteSpace($upstream)) {
            Write-Warn "$($r.Name) ($branch) - skipped: no upstream configured"
            continue
        }
        $remote = ($upstream -split '/')[0]

        & git -C $r.Path fetch $remote $branch 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "fetch failed for $($r.Name), skipping"
            continue
        }

        $countOut = & git -C $r.Path rev-list --count "HEAD..$remote/$branch" 2>$null
        $behind = 0
        if ($countOut -and ($countOut -match '^\d+$')) { [int]$behind = $countOut }
        $results += [pscustomobject]@{
            Name   = $r.Name
            Path   = $r.Path
            Branch = $branch
            Remote = $remote
            Behind = $behind
        }
    }

    Write-Host ""
    $outdated = @()
    foreach ($r in $results) {
        if ($r.Behind -gt 0) {
            Write-Host "  $($r.Name) ($($r.Branch)) - $($r.Behind) commit(s) behind" -ForegroundColor Yellow
            $outdated += $r
        } else {
            Write-Done "$($r.Name) ($($r.Branch)) - up to date"
        }
    }

    if (-not $outdated) {
        Write-Host ""
        Write-Done "All repositories are up to date."
        return
    }

    Write-Host ""
    do {
        $answer = Read-Host "Apply updates? (Y/N)"
        if ($answer -match '^[YyNn]$') { break }
        Write-Warn "Invalid input: $answer"
    } while ($true)
    if ($answer -match '^[Nn]') {
        Write-Step "cancelled"
        return
    }

    foreach ($r in $outdated) {
        Write-Step "pulling $($r.Name)..."
        try {
            Invoke-ExternalProcess -FilePath 'git' -ArgumentList @('-C', $r.Path, 'pull', $r.Remote, $r.Branch)
            Write-Done "$($r.Name) updated"
        } catch {
            Write-Err "pull failed for $($r.Name): $_"
        }
    }
}

# ==============================================================================
# BUILD SERVER
# ==============================================================================

function Invoke-BuildServer {
    param($Paths)
    while ($true) {
        Clear-Host
        Write-SectionHeader "Build Server"
        Write-Host "  1. Build (incremental)"
        Write-Host "  2. Clean Build"
        Write-Host "  3. Data"
        Write-Host "  B. Back to main menu"
        Write-Host ""
        $choice = Read-Host "Select option"
        switch -Regex ($choice) {
            '^1$' { try { Invoke-BuildIncremental -Paths $Paths } catch { Write-Err "Step failed: $_" }; Wait-Enter }
            '^2$' { try { Invoke-BuildClean -Paths $Paths } catch { Write-Err "Step failed: $_" }; Wait-Enter }
            '^3$' { try { Invoke-DataSubMenu -Paths $Paths } catch { Write-Err "Step failed: $_" } }
            '^[Bb]$' { return }
            default { Write-Warn "Invalid choice: $choice" }
        }
        if ($choice -match '^[Bb]$') { break }
    }
}

function Invoke-BuildIncremental {
    param($Paths)

    Write-SectionHeader "Build (Incremental)"

    $buildHasContent = (Test-Path -LiteralPath $Paths.Build) -and (Get-ChildItem -LiteralPath $Paths.Build -Force -ErrorAction SilentlyContinue)
    if ($buildHasContent) {
        Write-Step "keeping existing build folder"
    } else {
        if (Test-Path -LiteralPath $Paths.Build) {
            Remove-Item -LiteralPath $Paths.Build -Recurse -Force
        }
        New-Folder -Path $Paths.Build
    }

    Invoke-RunBuild -Paths $Paths
}

function Invoke-BuildClean {
    param($Paths)

    Write-SectionHeader "Clean Build"

    if (Test-Path -LiteralPath $Paths.Build) {
        Remove-Item -LiteralPath $Paths.Build -Recurse -Force
    }
    New-Folder -Path $Paths.Build

    Invoke-RunBuild -Paths $Paths
}

function Invoke-RunBuild {
    param($Paths)

    if (-not (Test-Path -LiteralPath $Paths.Source)) {
        Write-Err "Source folder missing. Run 'Clone Source & Modules' first."
        return
    }
    if (-not (Test-Path -LiteralPath "$($Paths.Database)\bin\mysqld.exe")) {
        Write-Err "MySQL not installed. Run 'Install Dependencies' first."
        return
    }
    if (-not (Test-Path -LiteralPath "$($Paths.Openssl)\bin")) {
        Write-Err "OpenSSL not installed. Run 'Install Dependencies' first."
        return
    }
    if (-not (Test-Path -LiteralPath $Paths.Boost)) {
        Write-Err "Boost not installed. Run 'Install Dependencies' first."
        return
    }

    Write-Step "configuring session environment (no system changes)"
    $env:PATH = "$($Paths.Cmake);$env:PATH"
    $env:PATH = "$($Paths.Openssl)\bin;$env:PATH"
    $env:BOOST_ROOT = Join-Path $Paths.Boost 'lib64-msvc-14.3\cmake'
    $env:OPENSSL_ROOT_DIR = $Paths.Openssl
    Write-Done "CMake = $($Paths.Cmake)"
    Write-Done "OpenSSL = $($Paths.Openssl)\bin"
    Write-Done "BOOST_ROOT = $env:BOOST_ROOT"

    Write-Step "running CMake configure"
    try {
        Invoke-ExternalProcess -FilePath 'cmake' -ArgumentList @(
            '-S', $Paths.Source,
            '-B', $Paths.Build,
            '-G', 'Visual Studio 17 2022',
            '-A', 'x64',
            "-DMYSQL_INCLUDE_DIR=$(Join-Path $Paths.Database 'include')",
            "-DMYSQL_LIBRARY=$(Join-Path $Paths.Database 'lib\libmysql.lib')",
            "-DCMAKE_INSTALL_PREFIX=$($Paths.Server)",
            '-DTOOLS_BUILD=all'
        )
        Write-Done "CMake configure complete"
    } catch {
        Write-Err "CMake configure failed: $_"
        return
    }

    Write-Step "building (RelWithDebInfo)..."
    try {
        $buildArgs = @('--build', $Paths.Build, '--config', 'RelWithDebInfo', '--parallel')
        if ($BuildThreads -gt 0) { $buildArgs += [string]$BuildThreads }
        Invoke-ExternalProcess -FilePath 'cmake' -ArgumentList $buildArgs
        Write-Done "build complete"
    } catch {
        Write-Err "CMake build failed: $_"
        return
    }

    Write-Step "installing..."
    try {
        Invoke-ExternalProcess -FilePath 'cmake' -ArgumentList @('--install', $Paths.Build, '--config', 'RelWithDebInfo')
        Write-Done "installed to $($Paths.Server)"
    } catch {
        Write-Err "CMake install failed: $_"
        return
    }

    Write-Step "copying runtime DLLs to server bin"
    $binDir = if (Test-Path -LiteralPath "$($Paths.Server)\bin") { "$($Paths.Server)\bin" } else { $Paths.Server }
    $libmysql = Join-Path $Paths.Database 'lib\libmysql.dll'
    if (Test-Path -LiteralPath $libmysql) {
        Copy-Item -LiteralPath $libmysql -Destination $binDir -Force
        Write-Done "copied libmysql.dll"
    } else {
        Write-Warn "libmysql.dll not found at $libmysql"
    }
    $opensslBin = Join-Path $Paths.Openssl 'bin'
    if (Test-Path -LiteralPath $opensslBin) {
        Copy-Item -Path "$opensslBin\libcrypto*.dll" -Destination $binDir -Force
        Copy-Item -Path "$opensslBin\libssl*.dll" -Destination $binDir -Force
        Copy-Item -Path "$opensslBin\legacy.dll" -Destination $binDir -Force
        Write-Done "copied OpenSSL DLLs"
    } else {
        Write-Warn "OpenSSL bin not found at $opensslBin"
    }

    Write-Done "server built"
}

function Invoke-DownloadClientData {
    param($Paths)

    Write-SectionHeader "Download Client Data"

    Write-Step "downloading client data (Data.zip)"
    $dataZip = Join-Path $Paths.Downloads 'Data.zip'
    if (Confirm-Overwrite -Path $dataZip -Message "already exists" -Prompt "Re-download? (Y/N)") {
        Remove-Item -LiteralPath $dataZip -Force -ErrorAction SilentlyContinue
    }
    Save-File -Source $DependencyUrls.ClientData -Destination $dataZip

    Write-Host ""
    $dataDest = Join-Path $Paths.Server 'data'
    if (-not (Confirm-Overwrite -Path $dataDest -Message "already exists")) {
        Write-Step "keeping existing client data"
        return
    }
    Remove-Item -LiteralPath $dataDest -Recurse -Force -ErrorAction SilentlyContinue
    New-Folder -Path $dataDest
    try {
        Expand-File -Archive $dataZip -Destination $dataDest
        $items = Get-ChildItem -LiteralPath $dataDest -Force
        if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
            $wrapper = $items[0].FullName
            Get-ChildItem -LiteralPath $wrapper | Move-Item -Destination $dataDest -Force
            Remove-Item -LiteralPath $wrapper -Recurse -Force
        }
        Write-Done "client data extracted to $dataDest"
    } catch {
        Write-Err "Client data extraction failed: $_"
    }
}

function Invoke-DataSubMenu {
    param($Paths)
    while ($true) {
        Clear-Host
        Write-SectionHeader "Data"
        Write-Host "  1. Download Data"
        Write-Host "  2. Extract Data"
        Write-Host "  B. Back"
        Write-Host ""
        $choice = Read-Host "Select option"
        switch -Regex ($choice) {
            '^1$' { try { Invoke-DownloadClientData -Paths $Paths } catch { Write-Err "Step failed: $_" }; Wait-Enter }
            '^2$' { try { Invoke-ExtractData -Paths $Paths } catch { Write-Err "Step failed: $_" }; Wait-Enter }
            '^[Bb]$' { return }
            default { Write-Warn "Invalid choice: $choice" }
        }
        if ($choice -match '^[Bb]$') { break }
    }
}

function Invoke-ExtractData {
    param($Paths)

    Write-SectionHeader "Extract Data"

    $extractorsDir = $Paths.Server
    $mapExe       = Join-Path $extractorsDir 'map_extractor.exe'
    $vmap4ExtExe  = Join-Path $extractorsDir 'vmap4_extractor.exe'
    $vmap4AsmExe  = Join-Path $extractorsDir 'vmap4_assembler.exe'
    $mmapsExe     = Join-Path $extractorsDir 'mmaps_generator.exe'

    $allPresent = (Test-Path -LiteralPath $mapExe) -and
                  (Test-Path -LiteralPath $vmap4ExtExe) -and
                  (Test-Path -LiteralPath $vmap4AsmExe) -and
                  (Test-Path -LiteralPath $mmapsExe)
    if (-not $allPresent) {
        Write-Err "Extractors missing. Run 'Build Server' first."
        return
    }

    if ([string]::IsNullOrWhiteSpace($ClientPath) -or -not (Test-Path "$ClientPath\Data")) {
        Write-Err "Client Data folder not found. Check `$ClientPath in configuration."
        return
    }

    $outputDir = Join-Path $Paths.Server 'data'
    if (-not (Confirm-Overwrite -Path $outputDir -Message "already contains data")) {
        Write-Step "keeping existing data"
        return
    }
    Remove-Item -LiteralPath $outputDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Folder -Path $outputDir

    $configPath = Join-Path $extractorsDir 'mmaps-config.yaml'
    $hasConfig = Test-Path -LiteralPath $configPath
    $originalContent = ''
    if ($hasConfig) {
        $originalContent = Get-Content $configPath -Raw
        $patchedContent = $originalContent -replace 'dataDir:\s*"[^"]*"', "dataDir: `"$outputDir/`""
        $patchedContent = $patchedContent -replace '\\', '/'
        [System.IO.File]::WriteAllText($configPath, $patchedContent)
    }

    try {
        Write-Step "map_extractor.exe"
        Invoke-ExternalProcess -FilePath $mapExe -ArgumentList @('-i', $ClientPath, '-o', $outputDir) `
            -WorkingDirectory $outputDir

        Write-Step "vmap4_extractor.exe"
        Invoke-ExternalProcess -FilePath $vmap4ExtExe -ArgumentList @('-d', "$ClientPath\Data") `
            -WorkingDirectory $outputDir

        Write-Step "vmap4_assembler.exe"
        Invoke-ExternalProcess -FilePath $vmap4AsmExe -ArgumentList @('Buildings', 'vmaps') `
            -WorkingDirectory $outputDir

        Write-Step "mmaps_generator.exe"
        Invoke-ExternalProcess -FilePath $mmapsExe -WorkingDirectory $outputDir

        Write-Done "data extracted to $outputDir"
    } catch {
        Write-Err "Extraction failed: $_"
    } finally {
        if ($hasConfig -and $originalContent) {
            [System.IO.File]::WriteAllText($configPath, $originalContent)
        }
    }
}

# ==============================================================================
# SETUP DATABASE
# ==============================================================================


function Invoke-SetupDatabase {
    param($Paths)
    while ($true) {
        Clear-Host
        Write-SectionHeader "Setup Database"
        Write-Host "  1. Write my.ini"
        Write-Host "  2. Initialize MySQL Data"
        Write-Host "  3. Create Database User & Schemas"
        Write-Host "  B. Back to main menu"
        Write-Host ""
        $choice = Read-Host "Select option"
        switch -Regex ($choice) {
            '^1$' { try { Invoke-WriteMyIni -Paths $Paths } catch { Write-Err "Step failed: $_" }; Wait-Enter }
            '^2$' { try { Invoke-InitializeMysqlData -Paths $Paths } catch { Write-Err "Step failed: $_" }; Wait-Enter }
            '^3$' { try { Invoke-CreateDatabaseUser -Paths $Paths } catch { Write-Err "Step failed: $_" }; Wait-Enter }
            '^[Bb]$' { return }
            default { Write-Warn "Invalid choice: $choice" }
        }
        if ($choice -match '^[Bb]$') { break }
    }
}

function Invoke-WriteMyIni {
    param($Paths)

    Write-SectionHeader "Write my.ini"

    if (-not (Test-Path -LiteralPath "$($Paths.Database)\bin\mysqld.exe")) {
        Write-Err "MySQL not installed. Run 'Install Dependencies' first."
        return
    }

    $config = @"
[mysqld]
basedir=./
datadir=./data
port=$SqlPort
sql-mode=""
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci
max_allowed_packet=128M
"@

    $myIniPath = Join-Path $Paths.Database 'my.ini'
    if (Confirm-Overwrite -Path $myIniPath -Message "already exists") {
        try {
            [System.IO.File]::WriteAllText($myIniPath, $config, (New-Object System.Text.UTF8Encoding($false)))
            Write-Done "my.ini written"
        } catch {
            Write-Err "Failed to write my.ini: $_"
        }
    } else {
        Write-Step "keeping existing my.ini"
    }
}

function Invoke-InitializeMysqlData {
    param($Paths)

    Write-SectionHeader "Initialize MySQL Data"

    if (-not (Test-Path -LiteralPath "$($Paths.Database)\bin\mysqld.exe")) {
        Write-Err "MySQL not installed. Run 'Install Dependencies' first."
        return
    }

    $mysqlBin = $Paths.MysqlBin
    $dataPath = Join-Path $Paths.Database 'data'

    if (-not (Test-Path -LiteralPath $dataPath)) {
        Write-Step "initializing MySQL data directory (--initialize-insecure)"
        try {
            Invoke-ExternalProcess -FilePath "$mysqlBin\mysqld.exe" `
                -ArgumentList @('--initialize-insecure',"--basedir=$($Paths.Database)","--datadir=$dataPath") `
                -WorkingDirectory $mysqlBin
            Write-Done "MySQL data initialized"
        } catch {
            Write-Err "MySQL init failed: $_"
        }
        return
    }

    $hasFiles = (Test-Path -LiteralPath $dataPath) -and (Get-ChildItem -LiteralPath $dataPath -Force -ErrorAction SilentlyContinue)
    if ($hasFiles) {
        Write-Warn "Reinitialize will DELETE all existing database data at $dataPath"
    }
    if (-not (Confirm-Overwrite -Path $dataPath -Message "Data directory already contains files" -Prompt "Reinitialize? (Y/N)")) {
        Write-Step "keeping existing data directory"
        return
    }
    Remove-Item -LiteralPath $dataPath -Recurse -Force -ErrorAction SilentlyContinue

    Write-Step "initializing MySQL data directory (--initialize-insecure)"
    try {
        Invoke-ExternalProcess -FilePath "$mysqlBin\mysqld.exe" `
            -ArgumentList @('--initialize-insecure',"--basedir=$($Paths.Database)","--datadir=$dataPath") `
            -WorkingDirectory $mysqlBin
        Write-Done "MySQL data initialized"
    } catch {
        Write-Err "MySQL init failed: $_"
    }
}

function Invoke-CreateDatabaseUser {
    param($Paths)

    Write-SectionHeader "Create Database User & Schemas"

    if (-not (Test-Path -LiteralPath "$($Paths.Database)\bin\mysqld.exe")) {
        Write-Err "MySQL not installed. Run 'Install Dependencies' first."
        return
    }

    $myIniPath = Join-Path $Paths.Database 'my.ini'
    if (-not (Test-Path -LiteralPath $myIniPath)) {
        Write-Err "my.ini not found. Run 'Write my.ini' first."
        return
    }

    $dataPath = Join-Path $Paths.Database 'data'
    if (-not (Test-Path -LiteralPath $dataPath)) {
        Write-Err "MySQL data not initialized. Run 'Initialize MySQL Data' first."
        return
    }

    while (Test-PortInUse -Port $SqlPort) {
        Write-Warn "Port $SqlPort is already in use (external MySQL?)."
        Write-Warn "Stop the service using port $SqlPort, then press Enter to re-check,"
        Write-Warn "or type 'S' to abort."
        $answer = Read-Host
        if ($answer -match '^[Ss]') {
            Write-Err "Aborted (port $SqlPort still in use)."
            return
        }
    }
    Write-Done "Port $SqlPort is free"

    $mysqlBin = $Paths.MysqlBin

    Write-Step "starting mysqld in a new console window"
    $mysqldProc = Start-Process -FilePath "$mysqlBin\mysqld.exe" `
        -ArgumentList '--console' `
        -WorkingDirectory $Paths.Database `
        -PassThru -WindowStyle Normal
    Write-Done "mysqld started (PID $($mysqldProc.Id))"

    Write-Step "waiting for MySQL (up to 60s)..."
    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 1
        if (Test-PortInUse -Port $SqlPort) { $ready = $true; break }
    }
    if (-not $ready) {
        Write-Err "MySQL did not start within 60s."
        Write-Step "attempting shutdown..."
        try { Invoke-ExternalProcess -FilePath "$mysqlBin\mysqladmin.exe" -ArgumentList '-u','root','-P',$SqlPort,'shutdown' } catch {
            Write-Warn "MySQL may still be running. Close the console window manually."
        }
        return
    } else {
        Write-Done "MySQL ready ($(($i + 1))s)"
    }

    try {
        Write-Step "applying SQL setup"
        $playerbotsLine = ''
        if (Find-PlayerbotsModule -Paths $Paths) {
            $playerbotsLine = 'CREATE DATABASE IF NOT EXISTS acore_playerbots;'
            Write-Step "mod-playerbots detected - acore_playerbots database will be created"
        } else {
            Write-Step "mod-playerbots not detected - skipping acore_playerbots"
        }

        $sql = @"
CREATE USER IF NOT EXISTS '$SqlUser'@'localhost' IDENTIFIED BY '$SqlPassword';
GRANT ALL PRIVILEGES ON *.* TO '$SqlUser'@'localhost' WITH GRANT OPTION;
CREATE DATABASE IF NOT EXISTS acore_auth;
CREATE DATABASE IF NOT EXISTS acore_world;
CREATE DATABASE IF NOT EXISTS acore_characters;
$playerbotsLine
DROP USER IF EXISTS 'root'@'localhost';
FLUSH PRIVILEGES;
"@
        $sqlLine = $sql -replace "\r?\n", " "
        & "$mysqlBin\mysql.exe" -u root -P $SqlPort -e $sqlLine
        if ($LASTEXITCODE -ne 0) {
            throw "SQL setup failed with exit code $LASTEXITCODE"
        }
        Write-Done "SQL setup applied"
    } finally {
        Write-Step "stopping mysqld..."
        try {
            Invoke-ExternalProcess -FilePath "$mysqlBin\mysqladmin.exe" `
                -ArgumentList '-u',$SqlUser,"-p$SqlPassword",'-P',$SqlPort,'shutdown'
            Write-Done "mysqld stopped"
        } catch {
            try {
                Invoke-ExternalProcess -FilePath "$mysqlBin\mysqladmin.exe" `
                    -ArgumentList '-u','root','-P',$SqlPort,'shutdown'
                Write-Done "mysqld stopped"
            } catch {
                Write-Warn "mysqladmin shutdown failed. Close the MySQL console window manually."
            }
        }
    }
    Write-Done "database user setup complete"
}

# ==============================================================================
# FINALIZATION
# ==============================================================================

function Invoke-Finalization {
    param($Paths)
    while ($true) {
        Clear-Host
        Write-SectionHeader "Finalization"
        Write-Host "  1. Generate .conf files"
        Write-Host "  2. Configure Config Files"
        Write-Host "  3. Generate launcher .bat files"
        Write-Host "  B. Back to main menu"
        Write-Host ""
        $choice = Read-Host "Select option"
        switch -Regex ($choice) {
            '^1$' { try { Invoke-GenerateConfFiles -Paths $Paths } catch { Write-Err "Step failed: $_" }; Wait-Enter }
            '^2$' { try { Invoke-ConfigureConfFiles -Paths $Paths } catch { Write-Err "Step failed: $_" }; Wait-Enter }
            '^3$' { try { Invoke-GenerateBatFiles -Paths $Paths } catch { Write-Err "Step failed: $_" }; Wait-Enter }
            '^[Bb]$' { return }
            default { Write-Warn "Invalid choice: $choice" }
        }
        if ($choice -match '^[Bb]$') { break }
    }
}

function Invoke-GenerateConfFiles {
    param($Paths)

    Write-SectionHeader "Generate .conf files"

    if (-not (Test-Path -LiteralPath $Paths.Server)) {
        Write-Err "Server folder missing. Run 'Build Server' first."
        return
    }

    Write-Step "copying .conf.dist to .conf"
    $distFiles = Get-ChildItem -LiteralPath $Paths.Server -Filter '*.conf.dist' -Recurse -File -ErrorAction SilentlyContinue
    if (-not $distFiles) {
        Write-Warn "no .conf.dist files found under $($Paths.Server)"
        return
    }

    $newFiles = @()
    $existingFiles = @()
    foreach ($f in $distFiles) {
        $confPath = $f.FullName -replace '\.dist$',''
        $confName = Split-Path $confPath -Leaf
        if (Test-Path -LiteralPath $confPath) {
            $existingFiles += $confName
        } else {
            $newFiles += $confName
            Copy-Item -LiteralPath $f.FullName -Destination $confPath -Force
        }
    }

    if ($newFiles.Count -gt 0) {
        Write-Done "$($newFiles.Count) new config(s) generated:"
        Write-Host "    $($newFiles -join ', ')" -ForegroundColor DarkGray
    }

    if ($existingFiles.Count -gt 0) {
        Write-Warn "$($existingFiles.Count) config(s) already exist:"
        Write-Host "    $($existingFiles -join ', ')" -ForegroundColor DarkGray
        $answer = $null
        do {
            $answer = Read-Host "Overwrite existing configs? (Y/N)"
            if ($answer -notmatch '^[YyNn]$') { Write-Warn "Invalid input: $answer" }
        } while ($answer -notmatch '^[YyNn]$')
        if ($answer -match '^[Nn]') {
            return
        }
        foreach ($f in $distFiles) {
            $confPath = $f.FullName -replace '\.dist$',''
            Copy-Item -LiteralPath $f.FullName -Destination $confPath -Force
        }
        Write-Done "$($existingFiles.Count) existing config(s) overwritten"
    }
}

function Invoke-ConfigureConfFiles {
    param($Paths)

    Write-SectionHeader "Configure Config Files"

    if (-not (Test-Path -LiteralPath $Paths.Server)) {
        Write-Err "Server folder missing. Run 'Build Server' first."
        return
    }

    $confDir = Join-Path $Paths.Server 'configs'
    if (-not (Test-Path -LiteralPath $confDir)) {
        Write-Warn "configs folder not found at $confDir"
        return
    }

    $connStr = "127.0.0.1;$SqlPort;$SqlUser;$SqlPassword"
    $tokens = @{
        LOGIN_DATABASE      = "$connStr;acore_auth"
        WORLD_DATABASE      = "$connStr;acore_world"
        CHARACTER_DATABASE  = "$connStr;acore_characters"
        PLAYERBOTS_DATABASE = "$connStr;acore_playerbots"
        MYSQL_EXECUTABLE    = "$($Paths.MysqlBin)\mysql.exe"
    }

    foreach ($fileConfig in $ConfigEdits) {
        $confPath = Join-Path $confDir $fileConfig.File
        if ($fileConfig.Optional -and -not (Test-Path -LiteralPath $confPath)) {
            if (Find-PlayerbotsModule -Paths $Paths) {
                Write-Host ""
                Write-Step "patching $(Split-Path $fileConfig.File -Leaf)"
                Write-Warn "$(Split-Path $fileConfig.File -Leaf) not found at $confPath"
            }
            continue
        }

        Write-Host ""
        Write-Step "patching $($fileConfig.File)"
        Update-ConfigFile -Path $confPath -Edits $fileConfig.Edits -Tokens $tokens
    }

    New-Folder -Path (Join-Path $Paths.Server 'logs')
}

function Invoke-GenerateBatFiles {
    param($Paths)

    Write-SectionHeader "Generate launcher .bat files"

    $installDir = Join-Path $Paths.Root 'install'

    $batContent = [ordered]@{
        '01_start_mysql.bat' = @'
@echo off
TITLE AzerothCore - MySQL
cd /d "%~dp0database"
.\bin\mysqld.exe --console
'@
        '02_start_authserver.bat' = @'
@echo off
TITLE AzerothCore - Authserver
cd /d "%~dp0server"
start authserver.exe
'@
        '03_start_worldserver.bat' = @'
@echo off
TITLE AzerothCore - Worldserver
cd /d "%~dp0server"
start worldserver.exe
'@
    }

    $newBats = @()
    $existingBats = @()
    foreach ($name in $batContent.Keys) {
        $path = Join-Path $installDir $name
        if (Test-Path -LiteralPath $path) {
            $existingBats += $name
        } else {
            $newBats += $name
            Set-Content -Path $path -Value $batContent[$name] -Force
        }
    }

    if ($newBats.Count -gt 0) {
        Write-Done "$($newBats.Count) new .bat file(s) created:"
        Write-Host "    $($newBats -join ', ')" -ForegroundColor DarkGray
    }

    if ($existingBats.Count -gt 0) {
        Write-Warn "$($existingBats.Count) .bat file(s) already exist:"
        Write-Host "    $($existingBats -join ', ')" -ForegroundColor DarkGray
        $answer = $null
        do {
            $answer = Read-Host "Overwrite existing? (Y/N)"
            if ($answer -notmatch '^[YyNn]$') { Write-Warn "Invalid input: $answer" }
        } while ($answer -notmatch '^[YyNn]$')
        if ($answer -match '^[Nn]') {
            return
        }
        foreach ($name in $existingBats) {
            $path = Join-Path $installDir $name
            Set-Content -Path $path -Value $batContent[$name] -Force
        }
        Write-Done "$($existingBats.Count) existing .bat file(s) overwritten"
    }
}

# ==============================================================================
# MENU
# ==============================================================================

function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  AzerothCore Installer" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. Create Folder Structure"
    Write-Host "  2. Install Dependencies"
    Write-Host "  3. Source & Modules"
    Write-Host "  4. Build Server"
    Write-Host "  5. Setup Database"
    Write-Host "  6. Finalization"
    Write-Host "  Q. Quit"
    Write-Host ""
}

function Invoke-MenuLoop {
    while ($true) {
        Show-Menu
        $choice = Read-Host "Select option"
        switch -Regex ($choice) {
            '^1$' { try { Invoke-CreateFolderStructure -Paths $Paths } catch { Write-Err "Step failed: $_" }; Wait-Enter }
            '^2$' { try { Invoke-InstallDependencies -Paths $Paths } catch { Write-Err "Step failed: $_" }; Wait-Enter }
            '^3$' { try { Invoke-CloneRepositories -Paths $Paths } catch { Write-Err "Step failed: $_" } }
            '^4$' { try { Invoke-BuildServer -Paths $Paths } catch { Write-Err "Step failed: $_" } }
            '^5$' { try { Invoke-SetupDatabase -Paths $Paths } catch { Write-Err "Step failed: $_" } }
            '^6$' { try { Invoke-Finalization -Paths $Paths } catch { Write-Err "Step failed: $_" } }
            '^[Qq]$' { Write-Host "Bye."; return }
            default { Write-Warn "Invalid choice: $choice" }
        }
        if ($choice -match '^[Qq]$') { break }
    }
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

Invoke-MenuLoop
