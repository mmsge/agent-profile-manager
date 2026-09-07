#
# probe-claude-windows.ps1: answer the questions docs/FACTS.md W01 to W06 ask
# and cannot answer from documentation, on a real Windows machine.
#
# Run this on Windows, then paste the whole output back and update the Windows
# section of docs/FACTS.md from it. Nothing in that section is VERIFIED today,
# because nobody has run this yet.
#
# Written for Windows PowerShell 5.1 and PowerShell 7. No modules beyond what
# ships with Windows, and Get-AppxPackage is optional: PowerShell 7 cannot
# always load it, and the probe says so rather than failing.
#
# Safety: this script creates a throwaway config root, app data directory and
# launcher directory under $env:TEMP and removes them at the end. It never
# touches a real config root, it never reads the content of a credential file,
# and it never prints an environment variable other than the one it set itself.
#

Set-StrictMode -Version 1.0

$ProbeVersion = '1'

function Say([string]$Text = '') { Write-Output $Text }
function Head2([string]$Text) { Write-Output ''; Write-Output ("== {0} ==" -f $Text) }
function Kv([string]$Key, $Value) { Write-Output ("  {0,-28} {1}" -f $Key, $Value) }
function Lines($Text) {
    foreach ($l in @($Text)) {
        if ($null -ne $l) { Write-Output ("    {0}" -f $l) }
    }
}

# Write a .cmd file the way both hosts agree on. Set-Content -Encoding differs
# between Windows PowerShell 5.1 and PowerShell 7, and a byte order mark breaks
# a .cmd, so this goes through .NET instead.
function Write-CmdFile([string]$Path, [string[]]$Body) {
    [System.IO.File]::WriteAllLines($Path, $Body, [System.Text.Encoding]::Default)
}

if ($env:OS -ne 'Windows_NT') {
    Write-Output 'This probe only means anything on Windows. Nothing was run.'
    exit 1
}

# ---------------------------------------------------------------------------
# Throwaway everything
# ---------------------------------------------------------------------------

$Stamp = [guid]::NewGuid().ToString('N').Substring(0, 8)
$Tmp = Join-Path $env:TEMP ("agent-profile-probe-" + $Stamp)
$ProbeRoot = Join-Path $Tmp 'root'
$ProbeAppData = Join-Path $Tmp 'appdata'
$ProbeLaunchers = Join-Path $Tmp 'launchers'

New-Item -ItemType Directory -Path $ProbeRoot -Force | Out-Null
New-Item -ItemType Directory -Path $ProbeAppData -Force | Out-Null
New-Item -ItemType Directory -Path $ProbeLaunchers -Force | Out-Null

$SavedConfigDir = $env:CLAUDE_CONFIG_DIR
$AppLaunched = $false

# Count the entries under a directory, recursively. The probe watches this
# number rather than any single file, because what Claude Code writes first is
# not something to hard-code.
function Get-EntryCount([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    $items = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue)
    return $items.Count
}

# Access control list as plain lines. Metadata only: this never opens the file.
function Get-AclLines([string]$Path) {
    $out = New-Object System.Collections.ArrayList
    try {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    } catch {
        [void]$out.Add('could not read the access control list')
        return $out
    }
    [void]$out.Add(("owner: {0}" -f $acl.Owner))
    foreach ($ace in $acl.Access) {
        [void]$out.Add(("{0}  {1}  {2}  inherited={3}" -f `
            $ace.IdentityReference, $ace.FileSystemRights, `
            $ace.AccessControlType, $ace.IsInherited))
    }
    return $out
}

# Run a command with the config root pinned for that run only, and put the
# variable back afterwards. Nothing here is allowed to leave the probe's own
# shell pinned.
function Invoke-Pinned([string]$Exe, [string[]]$CmdArgs) {
    $before = $env:CLAUDE_CONFIG_DIR
    try {
        $env:CLAUDE_CONFIG_DIR = $ProbeRoot
        & $Exe @CmdArgs 2>&1 | Out-Null
    } catch {
        # A non-zero exit or a missing subcommand is not interesting here. What
        # the run wrote to the throwaway root is.
    } finally {
        $env:CLAUDE_CONFIG_DIR = $before
    }
}

try {

Say ("agent-profile Windows probe, format {0}" -f $ProbeVersion)
Say ("date         {0}" -f (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
Say ("windows      {0}" -f [System.Environment]::OSVersion.Version)
Say ("powershell   {0} ({1})" -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)
Say ("throwaway    {0}" -f $Tmp)
Say ''
Say 'Everything below answers docs/FACTS.md W01 to W06. Paste it all back.'

# ---------------------------------------------------------------------------
# W01: does the CLI honour CLAUDE_CONFIG_DIR on Windows, and what does a
# Windows value have to look like?
# ---------------------------------------------------------------------------

Head2 'W01  Does the CLI honour CLAUDE_CONFIG_DIR?'

$ClaudeCmd = Get-Command 'claude.exe' -ErrorAction SilentlyContinue
if (-not $ClaudeCmd) { $ClaudeCmd = Get-Command 'claude' -ErrorAction SilentlyContinue }

if ($ClaudeCmd) {
    Kv 'claude' $ClaudeCmd.Source
    $ver = ''
    try { $ver = (& $ClaudeCmd.Source --version 2>&1 | Select-Object -First 1) } catch { $ver = 'could not read' }
    Kv 'claude --version' $ver
    Kv 'default root' (Join-Path $env:USERPROFILE '.claude')
    Kv 'default state file' (Join-Path $env:USERPROFILE '.claude.json')

    $rootBefore = Get-EntryCount $ProbeRoot
    Invoke-Pinned $ClaudeCmd.Source @('--version')
    Invoke-Pinned $ClaudeCmd.Source @('mcp', 'list')
    $rootAfter = Get-EntryCount $ProbeRoot

    Say ''
    Say '  After running the CLI pinned to the throwaway root:'
    if ($rootAfter -gt 0) {
        Lines (Get-ChildItem -LiteralPath $ProbeRoot -Force -ErrorAction SilentlyContinue |
            ForEach-Object { "{0}  {1}" -f $_.Mode, $_.Name })
    } else {
        Say '    (the root is still empty; these commands may not write)'
    }

    Say ''
    if (Test-Path -LiteralPath (Join-Path $ProbeRoot '.claude.json')) {
        Say '  W01 ANSWER: YES. .claude.json was written inside the pinned root, so'
        Say '  the state file moves under the variable on Windows exactly as F10'
        Say '  records for macOS.'
    } elseif ($rootAfter -gt $rootBefore) {
        Say '  W01 ANSWER: YES, partly. Something was written inside the pinned root,'
        Say '  but not .claude.json. List what appeared above and say which files'
        Say '  they were.'
    } else {
        Say '  W01 ANSWER: INCONCLUSIVE. Nothing was written. Run an interactive'
        Say '  session pinned to the root and check again before concluding'
        Say '  anything, because these two commands may simply not write.'
    }

    Say ''
    Say '  The half the documentation does not answer is what a Windows value may'
    Say '  look like. Try each of these by hand and say which ones work and'
    Say '  whether they produce the same root or different ones:'
    Say ''
    Say '    $env:CLAUDE_CONFIG_DIR = "C:\Users\you\.claude-work"'
    Say '    $env:CLAUDE_CONFIG_DIR = "C:\Users\you\.claude-work\"   # trailing separator'
    Say '    $env:CLAUDE_CONFIG_DIR = "C:/Users/you/.claude-work"    # forward slashes'
    Say '    $env:CLAUDE_CONFIG_DIR = "\\server\share\claude-work"   # UNC path'
    Say ''
    Say '  On macOS a trailing slash is a different login, because the credential'
    Say '  is keyed to the literal string (F03). Windows has no such key (W02),'
    Say '  but the answer still decides what a port must normalise.'
} else {
    Kv 'claude' 'not on PATH; W01 could not be exercised'
    Say '  Install Claude Code first, or open a terminal where claude is on PATH.'
    Say '  The native install puts it at %USERPROFILE%\.local\bin\claude.exe.'
}

# ---------------------------------------------------------------------------
# W02: where the credential lives, and what protects it.
#
# Metadata only. This section never opens a credential file, and never prints
# anything from inside one.
# ---------------------------------------------------------------------------

Head2 'W02  Where the credential lives, and its access control list'

Say '  Existence, size and access control list only. This probe never opens a'
Say '  credential file and never prints anything from inside one.'
Say ''

$CredNames = @('.credentials.json')
$RealRoot = Join-Path $env:USERPROFILE '.claude'

foreach ($pair in @(
        @{ Label = 'throwaway root'; Path = $ProbeRoot },
        @{ Label = 'default root'; Path = $RealRoot })) {
    $dir = $pair.Path
    Kv $pair.Label $dir
    if (-not (Test-Path -LiteralPath $dir)) {
        Say '    (directory does not exist)'
        continue
    }
    foreach ($name in $CredNames) {
        $cred = Join-Path $dir $name
        if (Test-Path -LiteralPath $cred) {
            $item = Get-Item -LiteralPath $cred -Force
            Say ("    {0}  present, {1} bytes, last written {2}" -f `
                $name, $item.Length, $item.LastWriteTimeUtc.ToString('u'))
            Lines (Get-AclLines $cred)
        } else {
            Say ("    {0}  absent" -f $name)
        }
    }
}

Say ''
Say '  W02 ANSWER: report whether a .credentials.json appeared, and paste the'
Say '  access control list above into docs/FACTS.md W02. The documentation says'
Say '  the file inherits the access controls of the user profile directory. The'
Say '  list above is the only way to know whether that held for this root.'
Say ''
Say '  Also check the Credential Manager, which the documentation never'
Say '  mentions. Nothing should be there:'
Say ''
Say '    cmdkey /list | Select-String -Pattern "claude" -SimpleMatch'
Say ''
Say '  cmdkey lists target names only and reads no secret. If an entry does'
Say '  appear, W02 is wrong and the port needs a Credential Manager path.'

# ---------------------------------------------------------------------------
# W03: where the desktop app is installed, and where its data lives.
# ---------------------------------------------------------------------------

Head2 'W03  Claude Desktop: install location and data directory'

$AppExe = ''
$PackageFamilyName = ''

try {
    $pkgs = @(Get-AppxPackage -Name '*Claude*' -ErrorAction Stop)
    if ($pkgs.Count -eq 0) {
        Kv 'Get-AppxPackage' 'no package whose name contains Claude'
    }
    foreach ($p in $pkgs) {
        Kv 'package' $p.Name
        Kv 'PackageFullName' $p.PackageFullName
        Kv 'PackageFamilyName' $p.PackageFamilyName
        Kv 'version' $p.Version
        Kv 'InstallLocation' $p.InstallLocation
        $PackageFamilyName = $p.PackageFamilyName
        $exe = @(Get-ChildItem -LiteralPath $p.InstallLocation -Recurse -Depth 3 `
            -Filter 'Claude.exe' -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($exe.Count -gt 0) {
            $AppExe = $exe[0].FullName
            Kv 'executable' $AppExe
        }
    }
} catch {
    Kv 'Get-AppxPackage' 'unavailable in this shell'
    Say '    PowerShell 7 cannot always load the Appx module. Re-run this'
    Say '    section in Windows PowerShell 5.1 to get the package identity,'
    Say '    which W03 and W05 both need.'
}

if (-not $AppExe) {
    Say ''
    Say '  Searching the conventional install locations:'
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'AnthropicClaude'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Claude'),
        (Join-Path $env:LOCALAPPDATA 'Claude'),
        'C:\Program Files\Claude'
    )
    # WindowsApps holds every packaged app on the machine and is locked down, so
    # it is searched by package name rather than walked whole.
    $packaged = 'C:\Program Files\WindowsApps'
    if (Test-Path -LiteralPath $packaged) {
        foreach ($dir in @(Get-ChildItem -LiteralPath $packaged -Directory -Filter 'Claude*' `
                -ErrorAction SilentlyContinue)) {
            $candidates = $candidates + $dir.FullName
        }
    }
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) {
            $hit = @(Get-ChildItem -LiteralPath $c -Recurse -Depth 3 -Filter 'Claude.exe' `
                -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($hit.Count -gt 0) {
                $AppExe = $hit[0].FullName
                Kv 'found' $AppExe
                break
            } else {
                Kv 'searched' $c
            }
        }
    }
}

if (-not $AppExe) {
    Kv 'executable' 'NOT FOUND'
    Say '    W03 stays unanswered and W04 cannot run. If the app is installed,'
    Say '    find its executable and say where it was, because that is half of'
    Say '    what W03 asks.'
}

Say ''
Say '  Candidate data directories, and what is in each:'
$DataDirs = New-Object System.Collections.ArrayList
[void]$DataDirs.Add((Join-Path $env:APPDATA 'Claude'))
if ($PackageFamilyName) {
    [void]$DataDirs.Add((Join-Path (Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Packages') $PackageFamilyName) 'LocalCache\Roaming') 'Claude'))
}
[void]$DataDirs.Add((Join-Path $env:LOCALAPPDATA 'Claude'))

foreach ($d in $DataDirs) {
    if (Test-Path -LiteralPath $d) {
        Kv 'present' $d
        Lines (Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue |
            Select-Object -First 20 | ForEach-Object { $_.Name })
        # F17 says each desktop profile carries its own Claude Code. If that
        # holds on Windows, the versions live under the app data directory.
        $cc = Join-Path $d 'claude-code'
        if (Test-Path -LiteralPath $cc) {
            Kv 'claude-code versions' ((Get-ChildItem -LiteralPath $cc -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { $_.Name }) -join ' ')
        }
    } else {
        Kv 'absent' $d
    }
}

Say ''
Say '  W03 ANSWER: paste the package identity, the executable path and which of'
Say '  the directories above actually holds the app data. Two of them holding'
Say '  the same file names is the AppData virtualisation W03 warns about, and'
Say '  it decides whether an audit can read the app data directory from outside'
Say '  the package at all.'

# ---------------------------------------------------------------------------
# W04: does the app's embedded Claude Code read CLAUDE_CONFIG_DIR from the
# app's process environment? This is F01 for Windows and it is the fact the
# whole desktop half would rest on.
# ---------------------------------------------------------------------------

Head2 'W04  Does the desktop app honour CLAUDE_CONFIG_DIR?'

if (-not $AppExe) {
    Say '  SKIPPED: no executable was found, so nothing could be launched.'
} else {
    $before = Get-EntryCount $ProbeRoot
    Say '  Launching with the variable in this process environment, which a'
    Say '  child process inherits, and with the app data directory pointed at a'
    Say '  throwaway directory.'
    Say ''
    Say '  DO THIS, or the result means nothing:'
    Say '    1. When the app opens, click the Code tab.'
    Say '    2. Start one local session and let it load.'
    Say '    3. Come back here.'
    Say ''
    Say '  The embedded Claude Code writes nothing until a session actually'
    Say '  runs, so quitting early looks identical to the app ignoring the'
    Say '  variable.'
    Say ''

    $savedForLaunch = $env:CLAUDE_CONFIG_DIR
    try {
        $env:CLAUDE_CONFIG_DIR = $ProbeRoot
        Start-Process -FilePath $AppExe -ArgumentList @("--user-data-dir=$ProbeAppData") | Out-Null
        $AppLaunched = $true
        Kv 'launched' $AppExe
        Kv 'CLAUDE_CONFIG_DIR' $ProbeRoot
        Kv '--user-data-dir' $ProbeAppData
    } catch {
        Kv 'launch' ("FAILED: {0}" -f $_.Exception.Message)
        Say '    A packaged app may refuse to start from its executable path.'
        Say '    That refusal is itself an answer to W05: say so, and try the'
        Say '    execution alias or the Start Menu entry instead.'
    } finally {
        $env:CLAUDE_CONFIG_DIR = $savedForLaunch
    }

    if ($AppLaunched) {
        Say ''
        Say '  Launched. Waiting up to 300s, or until the root changes.'
        $waited = 0
        while ($waited -lt 300) {
            Start-Sleep -Seconds 5
            $waited = $waited + 5
            if ((Get-EntryCount $ProbeRoot) -gt $before) { break }
        }

        $after = Get-EntryCount $ProbeRoot
        $appDataEntries = Get-EntryCount $ProbeAppData

        Say ''
        Kv 'entries in root before' $before
        Kv 'entries in root after' $after
        Kv 'entries in app data dir' $appDataEntries
        Say ''

        if ($after -gt $before) {
            Say '  W04 ANSWER: YES. The embedded Claude Code wrote to the pinned root,'
            Say '  so F01 holds on Windows and a launcher can pin the desktop app.'
            Say '  What appeared:'
            Lines (Get-ChildItem -LiteralPath $ProbeRoot -Recurse -Force -ErrorAction SilentlyContinue |
                Select-Object -First 30 | ForEach-Object { $_.FullName.Substring($ProbeRoot.Length) })
        } else {
            # Nothing written is only a NO if a session really ran. Ask rather
            # than guess: a false NO would send a port down a road that does
            # not exist, and a false YES would ship a launcher that pins
            # nothing while looking correct.
            $ran = ''
            try {
                $ran = Read-Host '  Did you start a Code session in the app before coming back? [y/N]'
            } catch {
                $ran = ''
            }

            if ($ran -match '^[yY]') {
                if ($appDataEntries -gt 0) {
                    Say ''
                    Say '  W04 ANSWER: NO. A Code session ran and --user-data-dir populated'
                    Say '  its directory, so the app started fine and did not take'
                    Say '  CLAUDE_CONFIG_DIR from its process environment.'
                    Say ''
                    Say '  Say so in W04 before anyone builds a Windows launcher. The'
                    Say '  route left is the local environment editor inside the app,'
                    Say '  which is per app data directory: environment dropdown, hover'
                    Say '  Local, gear icon. That is F02, which macOS never needed.'
                } else {
                    Say ''
                    Say '  W04 ANSWER: INCONCLUSIVE. The app data directory is empty too, so'
                    Say '  --user-data-dir was ignored or the app never really started.'
                    Say '  Which of those it was, is the first thing to find out.'
                }
            } else {
                Say ''
                Say '  W04 ANSWER: INCONCLUSIVE. No Code session ran, and the embedded'
                Say '  Claude Code writes nothing until one does. This is not evidence'
                Say '  either way. Re-run and start a session before returning.'
            }
        }

        Say ''
        Say '  The same check against a real profile rather than this throwaway root,'
        Say '  which needs no probe at all:'
        Say ''
        Say '    Get-ChildItem "$env:USERPROFILE\.claude*" -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue |'
        Say '        Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-3) }'
        Say ''
        Say '  The path it prints is the root actually in use.'
    }
}

# ---------------------------------------------------------------------------
# W05: which launcher form carries the variable, and does it survive a pin?
# ---------------------------------------------------------------------------

Head2 'W05  Launcher form, the pin, and the ordering trap'

$CarryOut = Join-Path $ProbeLaunchers 'carried.txt'
$CarryCmd = Join-Path $ProbeLaunchers 'carry-test.cmd'

# This proves only one thing, and proves it mechanically: whether a .cmd file
# of this shape puts the variable into the environment of a process it starts.
# It prints one variable, never the whole environment, so nothing else of the
# reader's leaks into a report they are about to paste in public.
$carryBody = @(
    '@echo off',
    ('set "CLAUDE_CONFIG_DIR={0}"' -f $ProbeRoot),
    ('cmd /c set CLAUDE_CONFIG_DIR > "{0}"' -f $CarryOut)
)
Write-CmdFile $CarryCmd $carryBody

try {
    Start-Process -FilePath $env:ComSpec `
        -ArgumentList @('/c', ('"' + $CarryCmd + '"')) `
        -Wait -WindowStyle Hidden | Out-Null
} catch {
    Say ("  running the carry test failed: {0}" -f $_.Exception.Message)
}

if (Test-Path -LiteralPath $CarryOut) {
    $carried = (Get-Content -LiteralPath $CarryOut | Select-Object -First 1)
    if ($carried -and $carried.Trim() -eq ("CLAUDE_CONFIG_DIR=" + $ProbeRoot)) {
        Kv 'set in a .cmd' 'carries into a child process'
    } else {
        Kv 'set in a .cmd' ("unexpected: {0}" -f $carried)
    }
    Remove-Item -LiteralPath $CarryOut -Force -ErrorAction SilentlyContinue
} else {
    Kv 'set in a .cmd' 'produced no output, so the form could not be confirmed'
}

# The launcher the reader is asked to pin. The empty first argument to start is
# deliberate and load-bearing: start reads its first quoted argument as a
# window title, so without it the program path is eaten as a title and nothing
# launches. This is the Windows shape of the --env before --args trap.
$PinCmd = Join-Path $ProbeLaunchers 'Claude-probe.cmd'
if ($AppExe) {
    $pinBody = @(
        '@echo off',
        'rem Launcher form under test, docs/FACTS.md W05.',
        'rem The empty "" before the program path is the window title start(1)',
        'rem expects. Remove it and the path is read as a title and nothing runs.',
        ('set "CLAUDE_CONFIG_DIR={0}"' -f $ProbeRoot),
        ('start "" "{0}" --user-data-dir="{1}"' -f $AppExe, $ProbeAppData)
    )
    Write-CmdFile $PinCmd $pinBody
    Kv 'launcher written' $PinCmd

    $PinLnk = Join-Path $ProbeLaunchers 'Claude probe.lnk'
    try {
        $shell = New-Object -ComObject WScript.Shell
        $sc = $shell.CreateShortcut($PinLnk)
        $sc.TargetPath = $env:ComSpec
        $sc.Arguments = ('/c "' + $PinCmd + '"')
        $sc.WorkingDirectory = $ProbeLaunchers
        $sc.WindowStyle = 7
        $sc.Description = 'agent-profile probe launcher for docs/FACTS.md W05'
        $sc.IconLocation = $AppExe
        $sc.Save()
        Kv 'shortcut written' $PinLnk
    } catch {
        Kv 'shortcut' ("could not be created: {0}" -f $_.Exception.Message)
    }
} else {
    Say '  No executable was found, so no launcher could be written.'
}

Say ''
Say '  What a person has to do here, because no script can answer it:'
Say ''
Say '    1. Right-click the shortcut above and pin it to Start, and to the'
Say '       taskbar if Windows offers it. Say which of the two it allowed.'
Say '    2. Launch the app from the pin, not from the shortcut file.'
Say '    3. Start a Code session, then run the leak test:'
Say ''
Say '         Get-ChildItem "$env:TEMP\agent-profile-probe-*" -Recurse -Filter *.jsonl'
Say ''
Say '    4. Say whether the session landed in the throwaway root or in'
Say '       %USERPROFILE%\.claude.'
Say ''
Say '  Then do it again from the Start Menu entry the app installed for itself.'
Say '  If the app is a packaged app, that entry activates it by its application'
Say '  identifier rather than running an executable, and an activated app is not'
Say '  a child of whatever asked for it. If that launch lands in the default'
Say '  root while the pinned launcher lands in the throwaway one, Windows has'
Say '  the same hole macOS has with its URL handler, and the audit can only'
Say '  report it.'
Say ''
Say '  Three things to write down for W05, in the order they will bite:'
Say '    setx  writes to the registry and pins every later process of this'
Say '          account, so it is never the right way to build a launcher.'
Say '    start reads its first quoted argument as a window title, so the empty'
Say '          "" in the launcher above is load-bearing.'
Say '    pins  may launch the app rather than the launcher, which is exactly'
Say '          the failure the launcher exists to prevent.'

# ---------------------------------------------------------------------------
# W06: transcript layout, the cwd field, and how a Windows path is encoded.
# ---------------------------------------------------------------------------

Head2 'W06  Transcript layout, cwd, and project directory encoding'

$Projects = Join-Path $ProbeRoot 'projects'
if (Test-Path -LiteralPath $Projects) {
    Say '  Project directories under the throwaway root:'
    Lines (Get-ChildItem -LiteralPath $Projects -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Name })

    $transcript = @(Get-ChildItem -LiteralPath $Projects -Recurse -Filter '*.jsonl' `
        -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($transcript.Count -gt 0) {
        Kv 'transcript' $transcript[0].FullName
        $found = $false
        $lineNo = 0
        foreach ($line in (Get-Content -LiteralPath $transcript[0].FullName -TotalCount 40)) {
            $lineNo = $lineNo + 1
            $rec = $null
            try { $rec = $line | ConvertFrom-Json } catch { $rec = $null }
            if ($null -ne $rec -and $rec.PSObject.Properties.Name -contains 'cwd') {
                Kv 'record' ("line {0}, type {1}" -f $lineNo, $rec.type)
                Kv 'cwd' $rec.cwd
                foreach ($f in @('sessionId', 'version', 'gitBranch')) {
                    if ($rec.PSObject.Properties.Name -contains $f) {
                        Kv $f $rec.$f
                    }
                }
                $found = $true
                break
            }
        }
        if ($found) {
            Say ''
            Say '  W06 ANSWER: cwd is present, so doctor D03 has something to read on'
            Say '  Windows. Say whether it carries a drive letter and backslashes, and'
            Say '  in which case, because Windows path comparison is case-insensitive'
            Say '  and a textual comparison would miss a leak.'
        } else {
            Say ''
            Say '  W06 ANSWER: no record in the first 40 lines carries cwd. That is the'
            Say '  worst answer available: D03 detects cross-root leakage by reading'
            Say '  cwd, and without it a port would report a clean machine. Check more'
            Say '  lines before concluding, then say so plainly.'
        }
    } else {
        Say '  No transcript was written, so cwd could not be read. Start a real'
        Say '  session pinned to a throwaway root and look again.'
    }
} else {
    Say '  No projects directory was created, so there is nothing to read yet.'
    Say '  This section needs a session that actually ran.'
}

Say ''
Say '  What the documented encoding rule predicts for this directory, so the'
Say '  prediction can be compared with what appears above:'
$here = (Get-Location).Path
Kv 'working directory' $here
Kv 'predicted <project>' ($here -replace '[^a-zA-Z0-9]', '-')
Say ''
Say '  The rule is that non-alphanumeric characters become a dash. On Windows'
Say '  the drive colon and both separators all become the same dash, so the'
Say '  name is even less decodable than it is on macOS. Never decode it. Read'
Say '  cwd.'

Head2 'Done'
Say 'Paste this whole output back, and update the Windows section of'
Say 'docs/FACTS.md from it. Every W entry it settles stops being UNVERIFIED.'
Say ''
Say 'Nothing here was VERIFIED before this run. Say which version of Claude'
Say 'Code and which version of Claude Desktop this machine had, because each'
Say 'desktop profile carries its own copy of Claude Code and they update on'
Say 'their own schedules.'

} finally {
    # ---------------------------------------------------------------------------
    # Cleanup. The throwaway directories always go, and the probe's own shell is
    # never left pinned to one of them.
    # ---------------------------------------------------------------------------
    $env:CLAUDE_CONFIG_DIR = $SavedConfigDir

    if ($AppLaunched) {
        Write-Output ''
        Write-Output 'Quit the Claude app now so its files can be removed.'
        try { Read-Host 'Press Return when it has quit' | Out-Null } catch { }
    }

    $removed = $false
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $Tmp)) { $removed = $true; break }
        Start-Sleep -Seconds 3
    }

    Write-Output ''
    if ($removed) {
        Write-Output ("Removed the throwaway directories under {0}" -f $Tmp)
    } else {
        Write-Output ("COULD NOT REMOVE {0}" -f $Tmp)
        Write-Output 'The app is probably still holding a file in it. Delete it by hand:'
        Write-Output ("    Remove-Item -LiteralPath '{0}' -Recurse -Force" -f $Tmp)
    }
}
