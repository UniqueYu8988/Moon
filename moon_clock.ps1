Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase
Add-Type -AssemblyName System.Windows.Forms
$ErrorActionPreference = "Stop"
$en = [System.Globalization.CultureInfo]::GetCultureInfo("en-US")

Add-Type @'
using System;
using System.Runtime.InteropServices;
[ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IClockDesktopWallpaper {
  void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string id, [MarshalAs(UnmanagedType.LPWStr)] string path);
  [return: MarshalAs(UnmanagedType.LPWStr)] string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string id);
  [return: MarshalAs(UnmanagedType.LPWStr)] string GetMonitorDevicePathAt(uint index);
  uint GetMonitorDevicePathCount();
  [PreserveSig] int GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string id, out MoonClockNative.PhysicalRect rect);
}
public static class MoonClockNative {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
  [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr childAfter, string className, string windowTitle);
  [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
  [DllImport("user32.dll")] public static extern IntPtr SetParent(IntPtr child, IntPtr parent);
  [DllImport("user32.dll")] public static extern uint GetDpiForSystem();
  [StructLayout(LayoutKind.Sequential)] public struct PhysicalRect {
    public int Left, Top, Right, Bottom;
    public int Width { get { return Right - Left; } }
    public int Height { get { return Bottom - Top; } }
  }
  [StructLayout(LayoutKind.Sequential)] public struct MonitorInfo {
    public int Size; public PhysicalRect Monitor, Work; public uint Flags;
  }
  public delegate bool MonitorProc(IntPtr monitor, IntPtr dc, ref PhysicalRect rect, IntPtr data);
  [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
  [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, MonitorProc callback, IntPtr data);
  [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
  [StructLayout(LayoutKind.Sequential)] public struct NativePoint { public int X, Y; }
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out PhysicalRect rect);
  [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr window);
  [DllImport("user32.dll")] static extern int MapWindowPoints(IntPtr from, IntPtr to, ref NativePoint point, uint count);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
  public static void AlignRenderedWindow(IntPtr window, double topFraction) {
    if (window == IntPtr.Zero) return;
    PhysicalRect target = GetTargetRect();
    IntPtr previous = SetThreadDpiAwarenessContext(new IntPtr(-4));
    try {
      PhysicalRect actual;
      if (!GetWindowRect(window, out actual)) return;
      NativePoint destination = new NativePoint();
      destination.X = target.Left + (target.Width - actual.Width) / 2;
      destination.Y = target.Top + (int)Math.Round(target.Height * topFraction);
      if (actual.Left == destination.X && actual.Top == destination.Y) return;
      IntPtr parent = GetParent(window);
      if (parent != IntPtr.Zero) MapWindowPoints(IntPtr.Zero, parent, ref destination, 1);
      SetWindowPos(window, IntPtr.Zero, destination.X, destination.Y, 0, 0, 0x1 | 0x4 | 0x10);
    } finally { SetThreadDpiAwarenessContext(previous); }
  }
  public static PhysicalRect GetTargetRect() {
    // IDesktopWallpaper uses the same physical rectangles as wallpaper placement.
    var type = Type.GetTypeFromCLSID(new Guid("C2CF3110-460E-4FC1-B9D0-8A1C0C9CC4BD"));
    var desktop = (IClockDesktopWallpaper)Activator.CreateInstance(type);
    PhysicalRect primary = new PhysicalRect(), portrait = new PhysicalRect();
    try {
      for (uint i = 0; i < desktop.GetMonitorDevicePathCount(); i++) {
        PhysicalRect rect;
        if (desktop.GetMonitorRECT(desktop.GetMonitorDevicePathAt(i), out rect) != 0 || rect.Width <= 0 || rect.Height <= 0) continue;
        if (primary.Width == 0 || (rect.Left == 0 && rect.Top == 0)) primary = rect;
        if (rect.Height > rect.Width && portrait.Width == 0) portrait = rect;
      }
    } finally { Marshal.ReleaseComObject(desktop); }
    return portrait.Width > 0 ? portrait : primary;
  }
  public const int GWL_EXSTYLE = -20;
  public const int GWL_STYLE = -16;
  public const int WS_EX_TRANSPARENT = 0x20;
  public const int WS_EX_TOOLWINDOW = 0x80;
  public const int WS_EX_NOACTIVATE = 0x8000000;
  public const int WS_POPUP = unchecked((int)0x80000000);
  public const int WS_CHILD = 0x40000000;
  public const uint WM_SPAWN_WORKER = 0x052C;
  public const uint SMTO_NORMAL = 0x0;
  public static IntPtr FindDesktopWorker() {
    IntPtr progman = FindWindow("Progman", null);
    IntPtr ignored;
    SendMessageTimeout(progman, WM_SPAWN_WORKER, IntPtr.Zero, IntPtr.Zero, SMTO_NORMAL, 1000, out ignored);
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr p) {
      IntPtr view = FindWindowEx(h, IntPtr.Zero, "SHELLDLL_DefView", null);
      if (view != IntPtr.Zero) found = FindWindowEx(IntPtr.Zero, h, "WorkerW", null);
      return found == IntPtr.Zero;
    }, IntPtr.Zero);
    return found;
  }
}
'@

function Get-Ordinal([int]$day) {
    if ($day -ge 11 -and $day -le 13) { return "${day}th" }
    switch ($day % 10) {
        1 { return "${day}st" }
        2 { return "${day}nd" }
        3 { return "${day}rd" }
        default { return "${day}th" }
    }
}

$window = New-Object System.Windows.Window
$window.WindowStyle = [System.Windows.WindowStyle]::None
$window.ResizeMode = [System.Windows.ResizeMode]::NoResize
$window.AllowsTransparency = $true
$window.Background = [System.Windows.Media.Brushes]::Transparent
$window.ShowInTaskbar = $false
$window.ShowActivated = $false
$window.Topmost = $false

$script:lastPlacement = ""
$script:clockMode = ""
$script:dpiScale = [MoonClockNative]::GetDpiForSystem() / 96.0
function Set-ClockPlacement {
    $bounds = [MoonClockNative]::GetTargetRect()
    if ($bounds.Width -le 0) { return }
    $portrait = $bounds.Height -gt $bounds.Width

    $mode = if ($portrait) { "portrait" } else { "landscape" }
    $placement = "{0},{1},{2},{3}|{4}" -f $bounds.Left, $bounds.Top, $bounds.Width, $bounds.Height, $mode
    if ($placement -eq $script:lastPlacement) { return }

    if ($portrait) {
        # These are the exact WPF values from the original portrait clock.
        # Only the horizontal coordinate is translated between desktop pixels
        # and WPF units so the 150%-scaled window remains centered.
        $window.Width = 430
        $window.Height = 145
        $renderedWidth = $window.Width * $script:dpiScale
        $window.Left = ($bounds.Left + (($bounds.Width - $renderedWidth) / 2)) / $script:dpiScale
        $window.Top = ($bounds.Top + ($bounds.Height * 0.245)) / $script:dpiScale
    } else {
        $desiredWidth = 800
        $desiredHeight = 224
        $window.Width = $desiredWidth / $script:dpiScale
        $window.Height = $desiredHeight / $script:dpiScale
        $window.Left = ($bounds.Left + (($bounds.Width - $desiredWidth) / 2)) / $script:dpiScale
        $window.Top = ($bounds.Top + ($bounds.Height * 0.04)) / $script:dpiScale
    }
    $script:clockMode = $mode
    $script:lastPlacement = $placement
}
Set-ClockPlacement

$grid = New-Object System.Windows.Controls.Grid
$grid.Background = [System.Windows.Media.Brushes]::Transparent
$window.Content = $grid

$time = New-Object System.Windows.Controls.TextBlock
$time.HorizontalAlignment = "Stretch"
$time.TextAlignment = [System.Windows.TextAlignment]::Center
$time.VerticalAlignment = "Top"
$time.FontFamily = New-Object System.Windows.Media.FontFamily("Bahnschrift SemiBold")
$time.FontSize = 54
$time.FontStretch = [System.Windows.FontStretches]::Expanded
$time.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(235,235,235,235))
$time.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{ BlurRadius = 7; ShadowDepth = 0; Opacity = 0.28; Color = [System.Windows.Media.Colors]::White }
[void]$grid.Children.Add($time)

$line = New-Object System.Windows.Controls.Border
$line.Width = 270
$line.Height = 1.2
$line.Background = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(190,230,230,230))
$line.HorizontalAlignment = "Center"
$line.VerticalAlignment = "Top"
$line.Margin = New-Object System.Windows.Thickness(0,74,0,0)
[void]$grid.Children.Add($line)

$date = New-Object System.Windows.Controls.TextBlock
$date.HorizontalAlignment = "Stretch"
$date.TextAlignment = [System.Windows.TextAlignment]::Center
$date.VerticalAlignment = "Top"
$date.Margin = New-Object System.Windows.Thickness(0,84,0,0)
$date.FontFamily = New-Object System.Windows.Media.FontFamily("Bahnschrift SemiCondensed")
$date.FontSize = 19
$date.FontStretch = [System.Windows.FontStretches]::Expanded
$date.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(210,220,220,220))
[void]$grid.Children.Add($date)

$script:lastTypographyMode = ""
function Set-ClockTypography {
    if ($script:clockMode -eq $script:lastTypographyMode) { return }
    if ($script:clockMode -eq "portrait") {
        $time.FontSize = 54
        $line.Width = 270
        $line.Margin = New-Object System.Windows.Thickness(0,74,0,0)
        $date.FontSize = 19
        $date.Margin = New-Object System.Windows.Thickness(0,84,0,0)
    } else {
        $time.FontSize = 80 / $script:dpiScale
        $line.Width = 420 / $script:dpiScale
        $line.Margin = New-Object System.Windows.Thickness(0,(112 / $script:dpiScale),0,0)
        $date.FontSize = 30 / $script:dpiScale
        $date.Margin = New-Object System.Windows.Thickness(0,(130 / $script:dpiScale),0,0)
    }
    $script:lastTypographyMode = $script:clockMode
}
Set-ClockTypography

$window.Add_SourceInitialized({
    $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
    $style = [MoonClockNative]::GetWindowLong($helper.Handle, [MoonClockNative]::GWL_EXSTYLE)
    [MoonClockNative]::SetWindowLong(
        $helper.Handle,
        [MoonClockNative]::GWL_EXSTYLE,
        $style -bor [MoonClockNative]::WS_EX_TRANSPARENT -bor [MoonClockNative]::WS_EX_TOOLWINDOW -bor [MoonClockNative]::WS_EX_NOACTIVATE
    ) | Out-Null
    $worker = [MoonClockNative]::FindDesktopWorker()
    if ($worker -ne [IntPtr]::Zero) {
        $oldStyle = [MoonClockNative]::GetWindowLong($helper.Handle, [MoonClockNative]::GWL_STYLE)
        [MoonClockNative]::SetWindowLong(
            $helper.Handle,
            [MoonClockNative]::GWL_STYLE,
            ($oldStyle -band (-bnot [MoonClockNative]::WS_POPUP)) -bor [MoonClockNative]::WS_CHILD
        ) | Out-Null
        [MoonClockNative]::SetParent($helper.Handle, $worker) | Out-Null
    }
})

function Update-Clock {
    $now = Get-Date
    $time.Text = $now.ToString("HH:mm")
    $date.Text = "{0}, {1}. {2}, {3}" -f $now.ToString("ddd", $en), $now.ToString("MMM", $en), (Get-Ordinal $now.Day), $now.Year
}

function Align-RenderedClock {
    $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
    $fraction = if ($script:clockMode -eq "portrait") { 0.245 } else { 0.04 }
    [MoonClockNative]::AlignRenderedWindow($helper.Handle, $fraction)
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({ Set-ClockPlacement; Set-ClockTypography; Update-Clock; Align-RenderedClock })
Update-Clock
$window.Add_Closed({ $timer.Stop() })
$timer.Start()
[void]$window.ShowDialog()
