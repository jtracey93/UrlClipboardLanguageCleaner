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
        # Use whichever PowerShell is running this script (pwsh.exe or powershell.exe)
        $psExe = (Get-Process -Id $PID).Path
        $shortcut.TargetPath = $psExe
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
    # Launch the monitor as a hidden background process and return
    $psExe = (Get-Process -Id $PID).Path
    Start-Process $psExe -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`"" -WindowStyle Hidden
    Write-Host "Clipboard monitor started in the background." -ForegroundColor Green
    exit 0
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
    # Use .NET Regex to replace only the first match
    $cleanedPath = [System.Text.RegularExpressions.Regex]::Replace($originalPath, $localePattern, '', 1)

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

    # Pure P/Invoke approach - works on both PowerShell 5.1 and 7+ without WinForms assembly issues
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;

public static class ClipboardNative
{
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool AddClipboardFormatListener(IntPtr hwnd);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool RemoveClipboardFormatListener(IntPtr hwnd);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool OpenClipboard(IntPtr hWndNewOwner);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CloseClipboard();

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool EmptyClipboard();

    [DllImport("user32.dll")]
    public static extern IntPtr GetClipboardData(uint uFormat);

    [DllImport("user32.dll")]
    public static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool IsClipboardFormatAvailable(uint format);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GlobalLock(IntPtr hMem);

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GlobalUnlock(IntPtr hMem);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);

    [DllImport("kernel32.dll")]
    public static extern UIntPtr GlobalSize(IntPtr hMem);

    public const uint CF_UNICODETEXT = 13;
    public const uint GMEM_MOVEABLE = 0x0002;

    public static string GetText()
    {
        if (!IsClipboardFormatAvailable(CF_UNICODETEXT)) return null;
        if (!OpenClipboard(IntPtr.Zero)) return null;
        try
        {
            IntPtr hData = GetClipboardData(CF_UNICODETEXT);
            if (hData == IntPtr.Zero) return null;
            IntPtr pData = GlobalLock(hData);
            if (pData == IntPtr.Zero) return null;
            try { return Marshal.PtrToStringUni(pData); }
            finally { GlobalUnlock(hData); }
        }
        finally { CloseClipboard(); }
    }

    public static bool SetText(string text)
    {
        if (!OpenClipboard(IntPtr.Zero)) return false;
        try
        {
            EmptyClipboard();
            int bytes = (text.Length + 1) * 2;
            IntPtr hGlobal = GlobalAlloc(GMEM_MOVEABLE, (UIntPtr)bytes);
            if (hGlobal == IntPtr.Zero) return false;
            IntPtr pGlobal = GlobalLock(hGlobal);
            try { Marshal.Copy(text.ToCharArray(), 0, pGlobal, text.Length); }
            finally { GlobalUnlock(hGlobal); }
            SetClipboardData(CF_UNICODETEXT, hGlobal);
            return true;
        }
        finally { CloseClipboard(); }
    }

    // Message-only window via raw Win32
    public delegate IntPtr WndProcDelegate(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct WNDCLASS
    {
        public uint style;
        public WndProcDelegate lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public IntPtr hInstance;
        public IntPtr hIcon;
        public IntPtr hCursor;
        public IntPtr hbrBackground;
        public string lpszMenuName;
        public string lpszClassName;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public int ptX;
        public int ptY;
    }

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern ushort RegisterClassW(ref WNDCLASS lpWndClass);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr CreateWindowExW(
        uint dwExStyle, string lpClassName, string lpWindowName, uint dwStyle,
        int x, int y, int nWidth, int nHeight,
        IntPtr hWndParent, IntPtr hMenu, IntPtr hInstance, IntPtr lpParam);

    [DllImport("user32.dll")]
    public static extern IntPtr DefWindowProcW(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetMessageW(out MSG msg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

    [DllImport("user32.dll")]
    public static extern IntPtr DispatchMessageW(ref MSG msg);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool TranslateMessage(ref MSG msg);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool DestroyWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern void PostQuitMessage(int nExitCode);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetModuleHandle(string lpModuleName);

    public static readonly IntPtr HWND_MESSAGE = new IntPtr(-3);
    public const uint WM_CLIPBOARDUPDATE = 0x031D;
    public const uint WM_DESTROY = 0x0002;
}
'@

    Write-Host "   (event-driven - zero CPU when idle)" -ForegroundColor DarkCyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Platform: Windows (WM_CLIPBOARDUPDATE)" -ForegroundColor DarkGray
    Write-Host "Locale patterns: /en-gb/, /en-us/, /fr-fr/, /de/ etc."
    Write-Host "Press Ctrl+C to stop." -ForegroundColor Yellow
    Write-Host ""

    $processing = $false

    # WndProc callback - processes clipboard update messages
    $wndProc = [ClipboardNative+WndProcDelegate]{
        param([IntPtr]$hWnd, [uint]$msg, [IntPtr]$wParam, [IntPtr]$lParam)

        if ($msg -eq [ClipboardNative]::WM_CLIPBOARDUPDATE -and -not $script:processing) {
            $script:processing = $true
            try {
                $text = [ClipboardNative]::GetText()
                if ($text -and $text.Trim() -match '^https?://') {
                    $cleaned = Remove-UrlLocale -Text $text
                    if ($cleaned) {
                        [ClipboardNative]::SetText($cleaned) | Out-Null
                        Write-CleanedLog -Original $text.Trim() -Cleaned $cleaned
                    }
                }
            }
            finally { $script:processing = $false }
            return [IntPtr]::Zero
        }

        if ($msg -eq [ClipboardNative]::WM_DESTROY) {
            [ClipboardNative]::PostQuitMessage(0)
            return [IntPtr]::Zero
        }

        return [ClipboardNative]::DefWindowProcW($hWnd, $msg, $wParam, $lParam)
    }

    # Register window class and create message-only window
    $className = "UrlClipboardCleaner_$([System.Diagnostics.Process]::GetCurrentProcess().Id)"
    $wc = New-Object ClipboardNative+WNDCLASS
    $wc.lpfnWndProc = $wndProc
    $wc.hInstance = [ClipboardNative]::GetModuleHandle($null)
    $wc.lpszClassName = $className

    $atom = [ClipboardNative]::RegisterClassW([ref]$wc)
    if ($atom -eq 0) {
        Write-Host "ERROR: Failed to register window class." -ForegroundColor Red
        exit 1
    }

    $hwnd = [ClipboardNative]::CreateWindowExW(
        0, $className, "", 0,
        0, 0, 0, 0,
        [ClipboardNative]::HWND_MESSAGE, [IntPtr]::Zero, $wc.hInstance, [IntPtr]::Zero)

    if ($hwnd -eq [IntPtr]::Zero) {
        Write-Host "ERROR: Failed to create message window." -ForegroundColor Red
        exit 1
    }

    $registered = [ClipboardNative]::AddClipboardFormatListener($hwnd)
    if (-not $registered) {
        Write-Host "ERROR: Failed to register clipboard listener." -ForegroundColor Red
        exit 1
    }

    try {
        # Win32 message loop
        $msg = New-Object ClipboardNative+MSG
        while ([ClipboardNative]::GetMessageW([ref]$msg, [IntPtr]::Zero, 0, 0)) {
            [ClipboardNative]::TranslateMessage([ref]$msg) | Out-Null
            [ClipboardNative]::DispatchMessageW([ref]$msg) | Out-Null
        }
    }
    finally {
        [ClipboardNative]::RemoveClipboardFormatListener($hwnd) | Out-Null
        [ClipboardNative]::DestroyWindow($hwnd) | Out-Null
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
