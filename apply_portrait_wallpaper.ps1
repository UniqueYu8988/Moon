param(
    [Parameter(Mandatory = $true)]
    [string]$Wallpaper
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

public static class PortraitMoonWallpaper {
    public static string Apply(string path) {
        var type = Type.GetTypeFromCLSID(new Guid("C2CF3110-460E-4FC1-B9D0-8A1C0C9CC4BD"));
        var wallpaper = (IDesktopWallpaperMoon)Activator.CreateInstance(type);
        for (uint i = 0; i < wallpaper.GetMonitorDevicePathCount(); i++) {
            string id = wallpaper.GetMonitorDevicePathAt(i);
            MoonRect rect;
            wallpaper.GetMonitorRECT(id, out rect);
            if ((rect.Bottom - rect.Top) > (rect.Right - rect.Left)) {
                wallpaper.SetWallpaper(id, path);
                return wallpaper.GetWallpaper(id);
            }
        }
        throw new InvalidOperationException("Portrait monitor was not found.");
    }
}
'@

Add-Type $source
[PortraitMoonWallpaper]::Apply((Resolve-Path -LiteralPath $Wallpaper).Path)
