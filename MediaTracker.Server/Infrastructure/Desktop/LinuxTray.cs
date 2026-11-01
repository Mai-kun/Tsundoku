using System.Runtime.InteropServices;

namespace MediaTracker.Server.Infrastructure.Desktop;

/// <summary>
/// Linux system tray via libayatana-appindicator3 + GTK3, loaded dynamically with
/// NativeLibrary so machines without the libraries (servers, containers, minimal
/// desktops) fall back to headless operation instead of crashing the web server.
/// GTK runs entirely on a dedicated background thread, including gtk_main().
/// </summary>
public static unsafe class LinuxTray
{
    private const string AppIndicatorLib = "libayatana-appindicator3.so.1";
    private const string AppIndicatorLibFallback = "libappindicator3.so.1";
    private const string GtkLib = "libgtk-3.so.0";

    private enum MenuAction
    {
        OpenUi = 1,
        OpenLogs = 2,
        Exit = 3,
    }

    private static Action _openUi = static () => { };
    private static Action _openLogs = static () => { };
    private static Action _exit = static () => { };

    public static bool TryStart(Action openUi, Action openLogs, Action exit)
    {
        _openUi = openUi;
        _openLogs = openLogs;
        _exit = exit;

        if (!NativeLibrary.TryLoad(GtkLib, out IntPtr gtk)
            || !NativeLibrary.TryLoad(AppIndicatorLib, out IntPtr appIndicator))
        {
            // Many distros still ship the legacy libappindicator3 name.
            if (!NativeLibrary.TryLoad(AppIndicatorLibFallback, out appIndicator))
            {
                Serilog.Log.Information(
                    "Tray: {Gtk} or {AppIndicator} not found — no tray icon (install libayatana-appindicator3)",
                    GtkLib, AppIndicatorLib);
                return false;
            }
        }

        var thread = new Thread(() => GtkThread(gtk, appIndicator))
        {
            IsBackground = true,
            Name = "Tsundoku-Tray-GTK",
        };
        thread.Start();
        return true;
    }

    // Default unmanaged calling convention (cdecl on x64 Linux) matches the fnptr type
    // used in g_signal_connect_data below.
    [UnmanagedCallersOnly]
    private static void OnMenuActivate(IntPtr menuItem, IntPtr userData)
    {
        try
        {
            switch ((MenuAction)(int)(nint)userData)
            {
                case MenuAction.OpenUi:
                    _openUi();
                    break;
                case MenuAction.OpenLogs:
                    _openLogs();
                    break;
                case MenuAction.Exit:
                    _exit();
                    break;
            }
        }
        catch (Exception error)
        {
            Serilog.Log.Warning(error, "Tray menu action failed");
        }
    }

    private static void GtkThread(IntPtr gtk, IntPtr appIndicator)
    {
        try
        {
            var gtkInitCheck = (delegate* unmanaged<IntPtr, IntPtr, int>)NativeLibrary.GetExport(
                gtk, "gtk_init_check");
            var gtkMenuNew = (delegate* unmanaged<IntPtr>)NativeLibrary.GetExport(gtk, "gtk_menu_new");
            var gtkMenuItemNewWithLabel = (delegate* unmanaged<byte*, IntPtr>)NativeLibrary.GetExport(
                gtk, "gtk_menu_item_new_with_label");
            var gtkSeparatorMenuItemNew = (delegate* unmanaged<IntPtr>)NativeLibrary.GetExport(
                gtk, "gtk_separator_menu_item_new");
            var gtkMenuShellAppend = (delegate* unmanaged<IntPtr, IntPtr, void>)NativeLibrary.GetExport(
                gtk, "gtk_menu_shell_append");
            var gtkWidgetShow = (delegate* unmanaged<IntPtr, void>)NativeLibrary.GetExport(gtk, "gtk_widget_show");
            var gSignalConnectData = (delegate* unmanaged<IntPtr, byte*, IntPtr, IntPtr, IntPtr, int, ulong>)
                NativeLibrary.GetExport(gtk, "g_signal_connect_data");

            var appIndicatorNew = (delegate* unmanaged<byte*, byte*, int, IntPtr>)NativeLibrary.GetExport(
                appIndicator, "app_indicator_new");
            var appIndicatorSetStatus = (delegate* unmanaged<IntPtr, int, void>)NativeLibrary.GetExport(
                appIndicator, "app_indicator_set_status");
            var appIndicatorSetIconFull = (delegate* unmanaged<IntPtr, byte*, byte*, void>)NativeLibrary.GetExport(
                appIndicator, "app_indicator_set_icon_full");
            var appIndicatorSetTitle = (delegate* unmanaged<IntPtr, byte*, void>)NativeLibrary.GetExport(
                appIndicator, "app_indicator_set_title");
            var appIndicatorSetMenu = (delegate* unmanaged<IntPtr, IntPtr, void>)NativeLibrary.GetExport(
                appIndicator, "app_indicator_set_menu");

            // gtk_init_check(NULL, NULL): returns FALSE when no display server is reachable
            // (SSH session, CI) — degrade to headless instead of killing the process.
            if (gtkInitCheck(IntPtr.Zero, IntPtr.Zero) == FALSE)
            {
                Serilog.Log.Information("Tray: no display server available (gtk_init_check failed) — continuing headless");
                return;
            }

            var menu = gtkMenuNew();

            AddItem(gtkMenuShellAppend, gtkWidgetShow, gSignalConnectData, menu,
                gtkMenuItemNewWithLabel(Utf8("Открыть Tsundoku")), "Открыть Tsundoku", (int)MenuAction.OpenUi);
            AddItem(gtkMenuShellAppend, gtkWidgetShow, gSignalConnectData, menu,
                gtkMenuItemNewWithLabel(Utf8("Консоль логов")), "Консоль логов", (int)MenuAction.OpenLogs);
            AddItem(gtkMenuShellAppend, gtkWidgetShow, gSignalConnectData, menu,
                gtkSeparatorMenuItemNew(), null, 0);
            AddItem(gtkMenuShellAppend, gtkWidgetShow, gSignalConnectData, menu,
                gtkMenuItemNewWithLabel(Utf8("Выход")), "Выход", (int)MenuAction.Exit);
            gtkWidgetShow(menu);

            // APP_INDICATOR_CATEGORY_APPLICATION_STATUS = 1, APP_INDICATOR_STATUS_ACTIVE = 1.
            // The themed name is the fallback when the file-based icon below cannot be loaded.
            var indicator = appIndicatorNew(Utf8("tsundoku"), Utf8("applications-other"), 1);
            appIndicatorSetStatus(indicator, 1);
            appIndicatorSetTitle(indicator, Utf8("Tsundoku"));

            var iconPath = FindIconPath();
            if (iconPath is not null)
            {
                appIndicatorSetIconFull(indicator, Utf8(iconPath), Utf8("Tsundoku"));
            }
            else
            {
                Serilog.Log.Information("Tray: no icon file found next to the binary — using the system fallback icon");
            }

            appIndicatorSetMenu(indicator, menu);
            Serilog.Log.Information("System tray icon created");

            // Blocks this background thread until the process exits.
            ((delegate* unmanaged<void>)NativeLibrary.GetExport(gtk, "gtk_main"))();
        }
        catch (Exception error)
        {
            Serilog.Log.Warning(error, "Tray thread failed — continuing without a tray icon");
        }
    }

    private static void AddItem(
        delegate* unmanaged<IntPtr, IntPtr, void> shellAppend,
        delegate* unmanaged<IntPtr, void> show,
        delegate* unmanaged<IntPtr, byte*, IntPtr, IntPtr, IntPtr, int, ulong> connectData,
        IntPtr menu,
        IntPtr item,
        string? label,
        int action)
    {
        if (label is not null)
        {
            connectData(item, Utf8("activate"),
                (IntPtr)(void*)(delegate* unmanaged<IntPtr, IntPtr, void>)&OnMenuActivate,
                (IntPtr)(nint)action, IntPtr.Zero, 0);
        }

        shellAppend(menu, item);
        show(item);
    }

    private static string? FindIconPath()
    {
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "wwwroot", "icon-192.png"),
            Path.Combine(AppContext.BaseDirectory, "wwwroot", "icon-512.png"),
            "/usr/share/tsundoku/wwwroot/icon-192.png",
        };
        return candidates.FirstOrDefault(File.Exists);
    }

    private static byte* Utf8(string value) => (byte*)Marshal.StringToCoTaskMemUTF8(value);

    private const int FALSE = 0;
}
