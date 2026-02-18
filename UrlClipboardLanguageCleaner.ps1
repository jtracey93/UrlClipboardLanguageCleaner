<#
.SYNOPSIS
    Monitors the clipboard for URLs and removes language/locale segments.
.DESCRIPTION
    Cross-platform PowerShell clipboard monitor. On Windows, uses the Win32
    AddClipboardFormatListener API for event-driven monitoring (zero CPU when
    idle). On macOS/Linux, uses efficient polling via pbpaste/xclip/wl-paste.
    Strips locale path segments (e.g. /en-gb/, /en-us/, /fr-fr/) so shared
    links redirect recipients to their preferred language.
.EXAMPLE
    ./UrlClipboardLanguageCleaner.ps1
    # Runs in the foreground, monitoring clipboard until Ctrl+C
.EXAMPLE
    ./UrlClipboardLanguageCleaner.ps1 -Install
    # Registers the script to auto-run at logon (hidden) and starts it
.EXAMPLE
    ./UrlClipboardLanguageCleaner.ps1 -Uninstall
    # Removes the auto-run registration
.EXAMPLE
    ./UrlClipboardLanguageCleaner.ps1 -PollingIntervalMs 300
    # (macOS/Linux only) Polls every 300ms instead of the default 500ms
#>
[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$Uninstall,
    [int]$PollingIntervalMs = 500
)

# --- Platform detection ---
$platform = if ($IsWindows -or [System.Environment]::OSVersion.Platform -eq 'Win32NT') {
    'Windows'
} elseif ($IsMacOS) {
    'macOS'
} else {
    'Linux'
}

$scriptPath = $PSCommandPath
$appName = "UrlClipboardLanguageCleaner"

# ============================================================
# Install / Uninstall logic
# ============================================================
function Install-AutoStart {
    if ($platform -eq 'Windows') {
        $startupDir = [System.Environment]::GetFolderPath('Startup')
        $shortcutPath = Join-Path $startupDir "$appName.lnk"

        if (Test-Path $shortcutPath) {
            Write-Host "Already installed: $shortcutPath" -ForegroundColor Yellow
            return $false
        }

        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "powershell.exe"
        $shortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
        $shortcut.WindowStyle = 7
        $shortcut.Description = "Monitors clipboard and removes locale segments from URLs"
        $shortcut.Save()
        Write-Host "Installed to startup: $shortcutPath" -ForegroundColor Green

    } elseif ($platform -eq 'macOS') {
        $plistDir = Join-Path $HOME "Library/LaunchAgents"
        $plistPath = Join-Path $plistDir "com.user.$appName.plist"

        if (Test-Path $plistPath) {
            Write-Host "Already installed: $plistPath" -ForegroundColor Yellow
            return $false
        }

        if (-not (Test-Path $plistDir)) { New-Item -ItemType Directory -Path $plistDir -Force | Out-Null }

        $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        if (-not $pwshPath) { $pwshPath = "/usr/local/bin/pwsh" }

        $plistContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.$appName</string>
    <key>ProgramArguments</key>
    <array>
        <string>$pwshPath</string>
        <string>-NoProfile</string>
        <string>-File</string>
        <string>$scriptPath</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/$appName.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/$appName.err</string>
</dict>
</plist>
"@
        Set-Content -Path $plistPath -Value $plistContent -Encoding UTF8
        & launchctl load $plistPath 2>$null
        Write-Host "Installed LaunchAgent: $plistPath" -ForegroundColor Green

    } else {
        $serviceDir = Join-Path $HOME ".config/systemd/user"
        $servicePath = Join-Path $serviceDir "$appName.service"

        if (Test-Path $servicePath) {
            Write-Host "Already installed: $servicePath" -ForegroundColor Yellow
            return $false
        }

        if (-not (Test-Path $serviceDir)) { New-Item -ItemType Directory -Path $serviceDir -Force | Out-Null }

        $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        if (-not $pwshPath) { $pwshPath = "/usr/bin/pwsh" }

        $serviceContent = @"
[Unit]
Description=URL Clipboard Language Cleaner
After=graphical-session.target

[Service]
ExecStart=$pwshPath -NoProfile -File $scriptPath
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
"@
        Set-Content -Path $servicePath -Value $serviceContent -Encoding UTF8
        & systemctl --user daemon-reload 2>$null
        & systemctl --user enable $appName 2>$null
        & systemctl --user start $appName 2>$null
        Write-Host "Installed systemd user service: $servicePath" -ForegroundColor Green
    }

    Write-Host "The script will now run automatically at logon." -ForegroundColor Cyan
    return $true
}

function Uninstall-AutoStart {
    if ($platform -eq 'Windows') {
        $shortcutPath = Join-Path ([System.Environment]::GetFolderPath('Startup')) "$appName.lnk"
        if (Test-Path $shortcutPath) {
            Remove-Item $shortcutPath -Force
            Write-Host "Removed startup shortcut: $shortcutPath" -ForegroundColor Green
        } else {
            Write-Host "Not installed (no shortcut found)." -ForegroundColor Yellow
        }

    } elseif ($platform -eq 'macOS') {
        $plistPath = Join-Path $HOME "Library/LaunchAgents/com.user.$appName.plist"
        if (Test-Path $plistPath) {
            & launchctl unload $plistPath 2>$null
            Remove-Item $plistPath -Force
            Write-Host "Removed LaunchAgent: $plistPath" -ForegroundColor Green
        } else {
            Write-Host "Not installed (no LaunchAgent found)." -ForegroundColor Yellow
        }

    } else {
        $servicePath = Join-Path $HOME ".config/systemd/user/$appName.service"
        if (Test-Path $servicePath) {
            & systemctl --user stop $appName 2>$null
            & systemctl --user disable $appName 2>$null
            Remove-Item $servicePath -Force
            & systemctl --user daemon-reload 2>$null
            Write-Host "Removed systemd user service: $servicePath" -ForegroundColor Green
        } else {
            Write-Host "Not installed (no service found)." -ForegroundColor Yellow
        }
    }
}

# Handle -Install / -Uninstall switches
if ($Uninstall) {
    Uninstall-AutoStart
    exit 0
}

if ($Install) {
    Install-AutoStart | Out-Null
    Write-Host ""
    Write-Host "Starting clipboard monitor now..." -ForegroundColor Cyan
    Write-Host ""
}

$localePattern = '(?i)/[a-z]{2}(?:-[a-z]{2,4})?(?=/)'

function Remove-UrlLocale {
    param([string]$Text)

    $Text = $Text.Trim()
    try {
        $uri = [System.Uri]::new($Text)
    }
    catch {
        return $null
    }

    if ($uri.Scheme -notin @('http', 'https')) { return $null }

    $originalPath = $uri.AbsolutePath
    $cleanedPath = $originalPath -replace $localePattern, '', 1

    if ($cleanedPath -eq $originalPath) { return $null }

    $builder = [System.UriBuilder]::new($uri)
    $builder.Path = $cleanedPath
    return $builder.Uri.AbsoluteUri
}

function Write-CleanedLog {
    param([string]$Original, [string]$Cleaned)
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
    Write-Host "Cleaned: " -NoNewline -ForegroundColor Green
    Write-Host "$Original"
    Write-Host "      -> " -NoNewline -ForegroundColor Green
    Write-Host "$Cleaned"
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " URL Clipboard Language Cleaner" -ForegroundColor Cyan

# --- Windows: event-driven via AddClipboardFormatListener ---
if ($platform -eq 'Windows') {
    Add-Type -AssemblyName System.Windows.Forms

    Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Text.RegularExpressions;

public class ClipboardMonitor : Form
{
    private const int WM_CLIPBOARDUPDATE = 0x031D;
    private static readonly Regex LocalePattern = new Regex(
        @"(?i)/[a-z]{2}(?:-[a-z]{2,4})?(?=/)",
        RegexOptions.Compiled);

    private bool _processing = false;

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AddClipboardFormatListener(IntPtr hwnd);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RemoveClipboardFormatListener(IntPtr hwnd);

    public event Action<string, string> UrlCleaned;

    public ClipboardMonitor()
    {
        this.ShowInTaskbar = false;
        this.WindowState = FormWindowState.Minimized;
        this.FormBorderStyle = FormBorderStyle.None;
        this.Opacity = 0;
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        AddClipboardFormatListener(this.Handle);
    }

    protected override void OnHandleDestroyed(EventArgs e)
    {
        RemoveClipboardFormatListener(this.Handle);
        base.OnHandleDestroyed(e);
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_CLIPBOARDUPDATE && !_processing)
        {
            _processing = true;
            try { ProcessClipboard(); }
            finally { _processing = false; }
        }
        base.WndProc(ref m);
    }

    private void ProcessClipboard()
    {
        string text;
        try
        {
            if (!Clipboard.ContainsText()) return;
            text = Clipboard.GetText();
        }
        catch { return; }

        if (string.IsNullOrWhiteSpace(text)) return;
        text = text.Trim();

        Uri uri;
        if (!Uri.TryCreate(text, UriKind.Absolute, out uri)) return;
        if (uri.Scheme != "http" && uri.Scheme != "https") return;

        string originalPath = uri.AbsolutePath;
        string cleanedPath = LocalePattern.Replace(originalPath, "", 1);
        if (cleanedPath == originalPath) return;

        var builder = new UriBuilder(uri) { Path = cleanedPath };
        string cleanedUrl = builder.Uri.AbsoluteUri;

        try { Clipboard.SetText(cleanedUrl); }
        catch { return; }

        if (UrlCleaned != null) UrlCleaned(text, cleanedUrl);
    }

    public void Stop()
    {
        if (this.InvokeRequired)
            this.Invoke(new Action(() => this.Close()));
        else
            this.Close();
    }
}
'@

    Write-Host "   (event-driven - zero CPU when idle)" -ForegroundColor DarkCyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Platform: Windows (WM_CLIPBOARDUPDATE)" -ForegroundColor DarkGray
    Write-Host "Locale patterns: /en-gb/, /en-us/, /fr-fr/, /de/ etc."
    Write-Host "Press Ctrl+C to stop." -ForegroundColor Yellow
    Write-Host ""

    $monitor = New-Object ClipboardMonitor
    Register-ObjectEvent -InputObject $monitor -EventName UrlCleaned -Action {
        $original = $Event.SourceArgs[0]
        $cleaned  = $Event.SourceArgs[1]
        $timestamp = Get-Date -Format "HH:mm:ss"
        Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
        Write-Host "Cleaned: " -NoNewline -ForegroundColor Green
        Write-Host "$original"
        Write-Host "      -> " -NoNewline -ForegroundColor Green
        Write-Host "$cleaned"
    } | Out-Null

    try {
        [System.Windows.Forms.Application]::Run($monitor)
    }
    finally {
        Write-Host "`nStopped." -ForegroundColor Yellow
    }
    return
}

# --- macOS / Linux: polling with native clipboard tools ---

# Detect the clipboard read/write commands
if ($platform -eq 'macOS') {
    $clipRead  = 'pbpaste'
    $clipWrite = { param($t) $t | pbcopy }
    $platformLabel = "macOS (pbpaste/pbcopy)"
} else {
    # Linux: prefer wl-paste (Wayland), fall back to xclip (X11)
    if (Get-Command 'wl-paste' -ErrorAction SilentlyContinue) {
        $clipRead  = 'wl-paste'
        $clipWrite = { param($t) $t | wl-copy }
        $platformLabel = "Linux/Wayland (wl-paste/wl-copy)"
    } elseif (Get-Command 'xclip' -ErrorAction SilentlyContinue) {
        $clipRead  = 'xclip'
        $clipWrite = { param($t) $t | xclip -selection clipboard }
        $platformLabel = "Linux/X11 (xclip)"
    } elseif (Get-Command 'xsel' -ErrorAction SilentlyContinue) {
        $clipRead  = 'xsel'
        $clipWrite = { param($t) $t | xsel --clipboard --input }
        $platformLabel = "Linux/X11 (xsel)"
    } else {
        Write-Host "ERROR: No clipboard tool found." -ForegroundColor Red
        Write-Host "Install one of: xclip, xsel (X11) or wl-clipboard (Wayland)" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "   (polling every ${PollingIntervalMs}ms)" -ForegroundColor DarkCyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Platform: $platformLabel" -ForegroundColor DarkGray
Write-Host "Locale patterns: /en-gb/, /en-us/, /fr-fr/, /de/ etc."
Write-Host "Press Ctrl+C to stop." -ForegroundColor Yellow
Write-Host ""

function Get-ClipboardText {
    try {
        if ($clipRead -eq 'xclip') {
            return (& xclip -selection clipboard -o 2>$null)
        }
        return (& $clipRead 2>$null)
    }
    catch { return $null }
}

$lastClipboard = ""

try {
    while ($true) {
        Start-Sleep -Milliseconds $PollingIntervalMs

        $current = Get-ClipboardText
        if ([string]::IsNullOrWhiteSpace($current) -or $current -eq $lastClipboard) {
            continue
        }

        $lastClipboard = $current

        if ($current.Trim() -match '^https?://') {
            $cleaned = Remove-UrlLocale -Text $current
            if ($cleaned) {
                & $clipWrite $cleaned
                $lastClipboard = $cleaned
                Write-CleanedLog -Original $current.Trim() -Cleaned $cleaned
            }
        }
    }
}
finally {
    Write-Host "`nStopped." -ForegroundColor Yellow
}
