param(
    [Parameter(Mandatory = $true)]
    [string]$PortraitWallpaper,
    [Parameter(Mandatory = $true)]
    [string]$LandscapeWallpaper
)

$source = @'
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IDesktopWallpaperMoon {
    void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorId, [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
    [return: MarshalAs(UnmanagedType.LPWStr)] string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorId);
    [return: MarshalAs(UnmanagedType.LPWStr)] string GetMonitorDevicePathAt(uint monitorIndex);
    uint GetMonitorDevicePathCount();
    [PreserveSig] int GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorId, out MoonRect displayRect);
    void SetBackgroundColor(uint color); uint GetBackgroundColor();
    void SetPosition(int position); int GetPosition();
    void SetSlideshow(IntPtr items); IntPtr GetSlideshow();
    void SetSlideshowOptions(int options, uint tick); void GetSlideshowOptions(out int options, out uint tick);
    void AdvanceSlideshow([MarshalAs(UnmanagedType.LPWStr)] string monitorId, int direction);
    int GetStatus(); void Enable([MarshalAs(UnmanagedType.Bool)] bool enable);
}

[StructLayout(LayoutKind.Sequential)]
struct MoonRect { public int Left, Top, Right, Bottom; }

public static class AdaptiveMoonWallpaper {
    public static string Apply(string portraitPath, string landscapePath) {
        var type = Type.GetTypeFromCLSID(new Guid("C2CF3110-460E-4FC1-B9D0-8A1C0C9CC4BD"));
        var wallpaper = (IDesktopWallpaperMoon)Activator.CreateInstance(type);
        string firstActive = null;
        bool foundPortrait = false;

        // A disconnected monitor can remain in IDesktopWallpaper with a zero-size
        // rectangle, so only positive-size rectangles participate in selection.
        for (uint i = 0; i < wallpaper.GetMonitorDevicePathCount(); i++) {
            string id = wallpaper.GetMonitorDevicePathAt(i);
            MoonRect rect;
            wallpaper.GetMonitorRECT(id, out rect);
            int width = rect.Right - rect.Left;
            int height = rect.Bottom - rect.Top;
            if (width <= 0 || height <= 0) continue;
            if (firstActive == null) firstActive = id;
            if (height > width) {
                wallpaper.SetWallpaper(id, portraitPath);
                foundPortrait = true;
            }
        }

        // In the usual desk setup only the portrait secondary monitor changes;
        // landscape monitors retain their existing Artemis wallpaper. When the
        // laptop is used alone, its active landscape panel receives this layout.
        if (!foundPortrait) {
            if (firstActive == null) throw new InvalidOperationException("No active monitor was found.");
            wallpaper.SetWallpaper(firstActive, landscapePath);
            return "landscape|" + wallpaper.GetWallpaper(firstActive);
        }
        return "portrait|" + portraitPath;
    }
}
'@

Add-Type $source
[AdaptiveMoonWallpaper]::Apply(
    (Resolve-Path -LiteralPath $PortraitWallpaper).Path,
    (Resolve-Path -LiteralPath $LandscapeWallpaper).Path
)
