using System.Runtime.InteropServices;

namespace MediaTracker.Server.Infrastructure.Desktop;

/// <summary>
/// Windows system tray via Shell_NotifyIconW on a hidden Win32 message window —
/// full NativeAOT compatibility with zero external dependencies. Right-click opens
/// a Win32 popup menu (TrackPopupMenuEx with TPM_RETURNCMD), left-click opens the UI.
/// </summary>
public static unsafe partial class WindowsTray
{
    private const uint WmApp = 0x8000; // WM_APP
    private const uint WmTrayCallback = WmApp + 1;

    private enum MenuAction
    {
        OpenUi = 1,
        OpenLogs = 2,
        Exit = 3,
    }

    private static Action _openUi = static () => { };
    private static Action _openLogs = static () => { };
    private static Action _exit = static () => { };

    private static IntPtr _window;
    private static IntPtr _icon;

    public static bool TryStart(Action openUi, Action openLogs, Action exit)
    {
        _openUi = openUi;
        _openLogs = openLogs;
        _exit = exit;

        var thread = new Thread(MessageLoop)
        {
            IsBackground = true,
            Name = "Tsundoku-Tray-Win32",
        };
        thread.Start();
        return true;
    }

    /// <summary>Removes the tray icon when the host shuts down so it does not linger.</summary>
    public static void Shutdown()
    {
        if (_window != IntPtr.Zero)
        {
            PostMessageW(_window, 0x0010 /* WM_CLOSE */, IntPtr.Zero, IntPtr.Zero);
        }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvStdcall)])]
    private static IntPtr WndProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        switch (msg)
        {
            case WmTrayCallback:
                // lParam low word: mouse message sent to the icon.
                var mouse = (uint)(long)lParam & 0xFFFF;
                const uint WmLButtonUp = 0x0202;
                const uint WmRButtonUp = 0x0205;
                if (mouse == WmLButtonUp)
                {
                    Safe(_openUi);
                }
                else if (mouse == WmRButtonUp)
                {
                    ShowContextMenu(hWnd);
                }

                return IntPtr.Zero;

            case 0x0111: // WM_COMMAND
                var id = (uint)(long)wParam & 0xFFFF;
                switch ((MenuAction)id)
                {
                    case MenuAction.OpenUi: Safe(_openUi); break;
                    case MenuAction.OpenLogs: Safe(_openLogs); break;
                    case MenuAction.Exit: Safe(_exit); break;
                }

                return IntPtr.Zero;

            case 0x0010: // WM_CLOSE
                RemoveIcon(hWnd);
                DestroyWindow(hWnd);
                _window = IntPtr.Zero;
                PostQuitMessage(0);
                return IntPtr.Zero;
        }

        return DefWindowProcW(hWnd, msg, wParam, lParam);
    }

    private static void MessageLoop()
    {
        try
        {
            _window = CreateMessageWindow();
            if (_window == IntPtr.Zero)
            {
                Serilog.Log.Warning("Tray: failed to create the message window — continuing without a tray icon");
                return;
            }

            if (!AddIcon(_window))
            {
                Serilog.Log.Warning("Tray: Shell_NotifyIconW failed — continuing without a tray icon");
                return;
            }

            Serilog.Log.Information("System tray icon created");

            // Pump messages until the host shuts down (WM_CLOSE arrives from StopAsync).
            while (GetMessageW(out var msg, IntPtr.Zero, 0, 0) > 0)
            {
                _ = TranslateMessage(in msg);
                _ = DispatchMessageW(in msg);
            }
        }
        catch (Exception error)
        {
            Serilog.Log.Warning(error, "Tray thread failed — continuing without a tray icon");
        }
    }

    private static void ShowContextMenu(IntPtr hWnd)
    {
        var menu = CreatePopupMenu();

        void Add(uint id, string label)
        {
            var info = new MENUITEMINFOW
            {
                cbSize = (uint)sizeof(MENUITEMINFOW),
                fMask = MIIM_ID | MIIM_STRING | MIIM_STATE,
                fState = MFS_ENABLED,
                wID = id,
                dwTypeData = (IntPtr)CoTaskUtf8(label),
            };
            _ = InsertMenuItemW(menu, uint.MaxValue, 0, in info);
        }

        Add((uint)MenuAction.OpenUi, "Открыть Tsundoku");
        Add((uint)MenuAction.OpenLogs, "Консоль логов");
        _ = AppendMenuW(menu, 0x00000800 /* MF_SEPARATOR */, 0, null);
        Add((uint)MenuAction.Exit, "Выход");

        // TrackPopupMenuEx needs the window in the foreground or it dismisses instantly.
        _ = SetForegroundWindow(hWnd);
        var point = new POINT();
        _ = GetCursorPos(ref point);
        // TPM_RETURNCMD returns the selected id directly instead of posting WM_COMMAND.
        var selected = TrackPopupMenuEx(menu, 0x0100 /* TPM_RETURNCMD */ | 0x0002 /* TPM_RIGHTBUTTON */,
            point.X, point.Y, hWnd, IntPtr.Zero);
        _ = DestroyMenu(menu);

        if (selected != 0)
        {
            PostMessageW(hWnd, 0x0111 /* WM_COMMAND */, (nint)selected, IntPtr.Zero);
        }
    }

    private static IntPtr CreateMessageWindow()
    {
        var classNamePtr = Marshal.StringToHGlobalUni("TsundokuTrayWindow");
        var wndClass = new WNDCLASSEXW
        {
            cbSize = (uint)sizeof(WNDCLASSEXW),
            lpfnWndProc = (IntPtr)(void*)(delegate* unmanaged[Stdcall]<IntPtr, uint, IntPtr, IntPtr, IntPtr>)&WndProc,
            lpszClassName = classNamePtr,
            hInstance = GetModuleHandleW(null),
        };
        var atom = RegisterClassExW(in wndClass);
        if (atom == 0)
        {
            Marshal.FreeHGlobal(classNamePtr);
            return IntPtr.Zero;
        }

        // HWND_MESSAGE: an invisible message-only window.
        var window = CreateWindowExW(0, "TsundokuTrayWindow", "Tsundoku", 0, 0, 0, 0, 0,
            (IntPtr)(-3) /* HWND_MESSAGE */, IntPtr.Zero, wndClass.hInstance, IntPtr.Zero);
        Marshal.FreeHGlobal(classNamePtr);
        return window;
    }

    private static bool AddIcon(IntPtr hWnd)
    {
        _icon = LoadTrayIcon();

        var data = new NOTIFYICONDATAW
        {
            cbSize = (uint)sizeof(NOTIFYICONDATAW),
            hWnd = hWnd,
            uID = 1,
            uFlags = 0x1 /* NIF_MESSAGE */ | 0x2 /* NIF_ICON */ | 0x4 /* NIF_TIP */,
            uCallbackMessage = WmTrayCallback,
            hIcon = _icon,
        };
        // The struct is a local, so its fixed buffer is already pinned: index it directly.
        var chars = "Tsundoku".AsSpan();
        for (var i = 0; i < chars.Length && i < 126; i++)
        {
            data.szTip[i] = chars[i];
        }

        return Shell_NotifyIconW(0 /* NIM_ADD */, in data) != 0;
    }

    private static void RemoveIcon(IntPtr hWnd)
    {
        if (_window == IntPtr.Zero)
        {
            return;
        }

        var data = new NOTIFYICONDATAW
        {
            cbSize = (uint)sizeof(NOTIFYICONDATAW),
            hWnd = hWnd,
            uID = 1,
        };
        _ = Shell_NotifyIconW(2 /* NIM_DELETE */, in data);
        if (_icon != IntPtr.Zero)
        {
            _ = DestroyIcon(_icon);
            _icon = IntPtr.Zero;
        }
    }

    private static IntPtr LoadTrayIcon()
    {
        // The application icon embedded into the exe (ApplicationIcon / default AOT icon).
        if (Environment.ProcessPath is { } exePath
            && ExtractIconExW(exePath, 0, out IntPtr large, out IntPtr small, 1) > 0)
        {
            _ = DestroyIcon(large);
            if (small != IntPtr.Zero)
            {
                return small;
            }
        }

        return LoadIconW(IntPtr.Zero, (IntPtr)32512 /* IDI_APPLICATION */);
    }

    private static byte* CoTaskUtf8(string value) => (byte*)Marshal.StringToCoTaskMemUTF8(value);

    private static void Safe(Action action)
    {
        try
        {
            action();
        }
        catch (Exception error)
        {
            Serilog.Log.Warning(error, "Tray action failed");
        }
    }

    private struct WNDCLASSEXW
    {
        public uint cbSize;
        public uint style;
        public IntPtr lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public IntPtr hInstance;
        public IntPtr hIcon;
        public IntPtr hCursor;
        public IntPtr hbrBackground;
        public IntPtr lpszMenuName;
        public IntPtr lpszClassName;
        public IntPtr hIconSm;
    }

    private struct NOTIFYICONDATAW
    {
        public uint cbSize;
        public IntPtr hWnd;
        public uint uID;
        public uint uFlags;
        public uint uCallbackMessage;
        public IntPtr hIcon;
        public fixed char szTip[128];
        public uint dwState;
        public uint dwStateMask;
        public fixed char szInfo[256];
        public uint uVersion;
        public fixed char szInfoTitle[64];
        public uint dwInfoFlags;
        public Guid guidItem;
        public IntPtr hBalloonIcon;
    }

    private struct MENUITEMINFOW
    {
        public uint cbSize;
        public uint fMask;
        public uint fType;
        public uint fState;
        public uint wID;
        public IntPtr hSubMenu;
        public IntPtr hbmpChecked;
        public IntPtr hbmpUnchecked;
        public uint dwItemData;
        public IntPtr dwTypeData;
        public uint cch;
        public IntPtr hbmpItem;
    }

    private struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public POINT pt;
        public uint lPrivate;
    }

    private struct POINT
    {
        public int X;
        public int Y;
    }

    private const uint MIIM_ID = 0x2;
    private const uint MIIM_STRING = 0x40;
    private const uint MIIM_STATE = 0x1;
    private const uint MFS_ENABLED = 0x3;

    [LibraryImport("user32.dll", EntryPoint = "RegisterClassExW", SetLastError = true)]
    private static partial ushort RegisterClassExW(in WNDCLASSEXW lpWndClass);

    [LibraryImport("user32.dll", EntryPoint = "CreateWindowExW", StringMarshalling = StringMarshalling.Utf16, SetLastError = true)]
    private static partial IntPtr CreateWindowExW(
        uint dwExStyle, string lpClassName, string lpWindowName, uint dwStyle,
        int x, int y, int nWidth, int nHeight, IntPtr hWndParent, IntPtr hMenu, IntPtr hInstance, IntPtr lpParam);

    [LibraryImport("user32.dll")]
    private static partial IntPtr DefWindowProcW(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [LibraryImport("user32.dll")]
    private static partial int GetMessageW(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

    [LibraryImport("user32.dll")]
    private static partial int TranslateMessage(in MSG lpMsg);

    [LibraryImport("user32.dll")]
    private static partial IntPtr DispatchMessageW(in MSG lpMsg);

    [LibraryImport("user32.dll")]
    private static partial void PostQuitMessage(int nExitCode);

    [LibraryImport("user32.dll")]
    private static partial IntPtr PostMessageW(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [LibraryImport("user32.dll")]
    private static partial int DestroyWindow(IntPtr hWnd);

    [LibraryImport("user32.dll")]
    private static partial int SetForegroundWindow(IntPtr hWnd);

    [LibraryImport("user32.dll")]
    private static partial int GetCursorPos(ref POINT lpPoint);

    [LibraryImport("user32.dll")]
    private static partial IntPtr CreatePopupMenu();

    [LibraryImport("user32.dll", EntryPoint = "AppendMenuW", StringMarshalling = StringMarshalling.Utf16)]
    private static partial int AppendMenuW(IntPtr hMenu, uint uFlags, nuint uIDNewItem, string? lpNewItem);

    [LibraryImport("user32.dll")]
    private static partial int InsertMenuItemW(IntPtr hMenu, uint uItem, int fByPosition, in MENUITEMINFOW lpmi);

    [LibraryImport("user32.dll")]
    private static partial uint TrackPopupMenuEx(IntPtr hMenu, uint uFlags, int x, int y, IntPtr hWnd, IntPtr tpmParams);

    [LibraryImport("user32.dll")]
    private static partial int DestroyMenu(IntPtr hMenu);

    [LibraryImport("user32.dll")]
    private static partial IntPtr LoadIconW(IntPtr hInstance, IntPtr lpIconName);

    [LibraryImport("user32.dll")]
    private static partial int DestroyIcon(IntPtr hIcon);

    [LibraryImport("shell32.dll", SetLastError = true)]
    private static partial int Shell_NotifyIconW(uint dwMessage, in NOTIFYICONDATAW lpData);

    [LibraryImport("shell32.dll", EntryPoint = "ExtractIconExW", StringMarshalling = StringMarshalling.Utf16)]
    private static partial uint ExtractIconExW(string lpszFile, int nIconIndex, out IntPtr phiconLarge, out IntPtr phiconSmall, uint nIcons);

    [LibraryImport("kernel32.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial IntPtr GetModuleHandleW(string? lpModuleName);
}
