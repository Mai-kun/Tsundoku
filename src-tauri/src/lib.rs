use std::net::{SocketAddr, TcpStream};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use tauri::{
    menu::{MenuBuilder, MenuItem, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager, RunEvent, WebviewUrl, WebviewWindowBuilder, WindowEvent,
};
use tauri_plugin_shell::process::{Command, CommandEvent, CommandChild};
use tauri_plugin_shell::ShellExt;

/// Environment variable that overrides the port the desktop shell expects the
/// .NET server to listen on (forwarded to the server as `--port`).
const SERVER_PORT_ENV: &str = "TSUNDOKU_PORT";
const DEFAULT_SERVER_PORT: u16 = 5000;
/// How long to wait for a freshly spawned server to accept TCP connections.
const SERVER_STARTUP_TIMEOUT: Duration = Duration::from_secs(10);
/// Budget of a single TCP probe; keeps attach detection snappy at startup.
const PROBE_TIMEOUT: Duration = Duration::from_millis(300);

/// Lifecycle ownership of the .NET server. `managed == true` means the child
/// process was spawned by this app instance and must be terminated on exit;
/// `managed == false` means we attached to a server that was already running
/// (background service, systemd, docker) and its lifecycle is not ours.
struct ServerState {
    managed: Mutex<bool>,
    child: Mutex<Option<CommandChild>>,
}

fn is_server_running(port: u16) -> bool {
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    TcpStream::connect_timeout(&addr, PROBE_TIMEOUT).is_ok()
}

fn server_port() -> u16 {
    std::env::var(SERVER_PORT_ENV)
        .ok()
        .and_then(|port| port.trim().parse::<u16>().ok())
        .unwrap_or(DEFAULT_SERVER_PORT)
}

fn server_url(port: u16) -> String {
    format!("http://127.0.0.1:{port}")
}

fn show_main_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
    }
}

fn hide_main_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.hide();
    }
}

/// Frontend-selected behavior for the [X] button on the main window. The SPA
/// intercepts `close-requested` first and calls this with the user's choice.
#[tauri::command]
fn close_action(app: AppHandle, action: String) {
    match action.as_str() {
        // Tray agent mode: the window (and its webview memory) stay alive.
        "minimize_to_tray" => hide_main_window(&app),
        "close_gui" => {
            if let Some(window) = app.get_webview_window("main") {
                // Reload drops all in-memory JS state (heap, caches) so the hidden
                // webview releases memory; localStorage/cookies are kept, so the
                // saved preferences (language, on_close_action) survive.
                let _ = window.reload();
                let _ = window.hide();
            }
        }
        // Full shutdown: triggers RunEvent::Exit, which terminates a managed
        // server child and leaves an attached external server alone.
        "exit_all" => app.exit(0),
        _ => eprintln!("[tsundoku] unknown close action: {action}"),
    }
}

/// Lightweight console window pointing at the server's live log viewer. Closing
/// it only destroys this window: the app and the server keep running.
#[tauri::command]
fn open_logs_window(app: AppHandle) {
    show_or_create_logs_window(&app);
}

fn show_or_create_logs_window(app: &AppHandle) {
    if let Some(existing) = app.get_webview_window("logs") {
        let _ = existing.unminimize();
        let _ = existing.show();
        let _ = existing.set_focus();
        return;
    }

    let url = format!("{}/logs.html", server_url(server_port()));
    let parsed = match url.parse::<tauri::Url>() {
        Ok(url) => url,
        Err(err) => {
            eprintln!("[tsundoku] invalid logs window url {url}: {err}");
            return;
        }
    };

    // The main window is never destroyed (close is intercepted), so closing the
    // console can never be the last window and exit the whole app: the default
    // close behavior (destroy only this window) is exactly what we want.
    if let Err(err) = WebviewWindowBuilder::new(app, "logs", WebviewUrl::External(parsed))
        .title("Tsundoku — Консоль логов")
        .inner_size(1280.0, 680.0)
        .min_inner_size(950.0, 500.0)
        .build()
    {
        eprintln!("[tsundoku] failed to open logs window: {err}");
    }
}

/// Portable layout check: `bin/tsundoku-server` next to the executable
/// (`Tsundoku-Portable/Tsundoku` + `Tsundoku-Portable/bin/tsundoku-server`).
fn portable_server_bin() -> Option<PathBuf> {
    let bin = std::env::current_exe()
        .ok()?
        .parent()?
        .join("bin")
        .join("tsundoku-server");
    bin.is_file().then_some(bin)
}

/// Restore the executable bit on a staged binary that lost it (an extracted or
/// hand-repacked AppImage may ship the sidecar non-executable).
#[cfg(target_os = "linux")]
fn ensure_executable(path: &Path) {
    use std::os::unix::fs::PermissionsExt;
    if let Ok(meta) = std::fs::metadata(path) {
        if meta.permissions().mode() & 0o111 == 0 {
            let mut perms = meta.permissions();
            perms.set_mode(perms.mode() | 0o111);
            if std::fs::set_permissions(path, perms).is_ok() {
                eprintln!("[tsundoku] restored executable bit on {}", path.display());
            }
        }
    }
}

/// Navigate the release webview from the bundled splash page to the server UI
/// (the SPA uses relative /api URLs, so it must live on the server's origin).
/// Dev builds keep the Vite dev server, whose proxy already targets the API.
#[cfg(not(dev))]
fn navigate_main_window(app: &AppHandle, port: u16) {
    let Some(window) = app.get_webview_window("main") else {
        return;
    };
    match server_url(port).parse::<tauri::Url>() {
        Ok(url) => {
            if let Err(err) = window.navigate(url) {
                eprintln!("[tsundoku] failed to navigate to server UI: {err}");
            }
        }
        Err(err) => eprintln!("[tsundoku] invalid server url: {err}"),
    }
}

/// Spawn the .NET server as a child process (Case B: nothing was listening on
/// the port when the app started). A missing or failing binary is logged
/// instead of aborting the app so the shell still opens.
fn spawn_server(app: AppHandle, port: u16) {
    tauri::async_runtime::spawn(async move {
        let state = app.state::<ServerState>();
        {
            let guard = state.child.lock().unwrap();
            if guard.is_some() {
                return;
            }
        }

        // AppImage: the runtime mount root ($APPDIR). Tauri stages the sidecar
        // next to the GUI binary in $APPDIR/usr/bin, and the bundle resources
        // (libe_sqlite3.so, wwwroot/) in $APPDIR/usr/lib/Tsundoku.
        let appimage_dir = std::env::var_os("APPDIR").map(PathBuf::from);

        // Portable layout: the server binary sits in <exe_dir>/bin together with
        // libe_sqlite3.so; the SPA assets live in <exe_dir>/wwwroot. Bundled
        // (AppImage/deb) layout: both ship as Tauri resources in resource_dir.
        let (mut command, library_dir, content_root): (Command, Option<PathBuf>, Option<PathBuf>) =
            if let Some(bin) = portable_server_bin() {
                let bin_dir = bin.parent().expect("portable bin dir").to_path_buf();
                eprintln!(
                    "[tsundoku] using portable server binary: {}",
                    bin.display()
                );
                let cmd = app.shell().command(&bin);
                (
                    cmd,
                    Some(bin_dir.clone()),
                    bin_dir.parent().map(|root| root.to_path_buf()),
                )
            } else {
                let cmd = match app.shell().sidecar("tsundoku-server") {
                    Ok(command) => command,
                    Err(err) => {
                        eprintln!(
                            "[tsundoku] sidecar 'tsundoku-server' not found: {err}. \
                             Build it with `dotnet publish MediaTracker.Server -c Release` and copy \
                             the binary to src-tauri/binaries/tsundoku-server-<target-triple>."
                        );
                        return;
                    }
                };
                // The sidecar resolves to <exe_dir>/tsundoku-server; make sure a
                // non-executable stage does not fail the spawn with EACCES.
                if let Some(exe_dir) = std::env::current_exe()
                    .ok()
                    .and_then(|exe| exe.parent().map(|dir| dir.to_path_buf()))
                {
                    ensure_executable(&exe_dir.join("tsundoku-server"));
                }
                let resource_dir = app.path().resource_dir().ok();
                (cmd, resource_dir.clone(), resource_dir)
            };

        if let Some(root) = &content_root {
            // The .NET host is built without argv (WebApplication.CreateBuilder()
            // in Program.cs), so a --contentRoot argument is silently ignored;
            // DOTNET_CONTENTROOT is the channel the generic host does read.
            command = command.args(["--contentRoot", &root.to_string_lossy()]);
            command = command.env("DOTNET_CONTENTROOT", root);
        }
        // The server binary is a bare NativeAOT executable: its native SQLite
        // library is loaded as a sibling file, found through LD_LIBRARY_PATH
        // (the dll sits next to the exe on Windows).
        #[cfg(target_os = "linux")]
        {
            let mut dirs: Vec<PathBuf> = Vec::new();
            if let Some(appdir) = &appimage_dir {
                dirs.push(appdir.join("usr/lib/Tsundoku"));
                dirs.push(appdir.join("usr/lib"));
                dirs.push(appdir.clone());
            }
            if let Some(dir) = &library_dir {
                dirs.push(dir.clone());
            }
            if let Some(exe_dir) = std::env::current_exe()
                .ok()
                .and_then(|exe| exe.parent().map(|dir| dir.to_path_buf()))
            {
                dirs.push(exe_dir);
            }
            let ld = std::env::var("LD_LIBRARY_PATH").unwrap_or_default();
            for part in ld.split(':').filter(|part| !part.is_empty()) {
                dirs.push(PathBuf::from(part));
            }
            let mut seen = std::collections::HashSet::new();
            let joined = dirs
                .into_iter()
                .filter(|dir| seen.insert(dir.clone()))
                .map(|dir| dir.to_string_lossy().into_owned())
                .collect::<Vec<_>>()
                .join(":");
            if !joined.is_empty() {
                command = command.env("LD_LIBRARY_PATH", joined);
            }
        }
        command = command.args(["--port", port.to_string().as_str()]);

        match command.spawn() {
            Ok((mut rx, child)) => {
                eprintln!("[tsundoku] server process spawned on port {port}");
                *state.child.lock().unwrap() = Some(child);
                // Pipe the server console into ours: without this a startup crash
                // (missing native lib, unresolvable wwwroot, port conflict) dies
                // silently and the GUI only shows a generic error page.
                tauri::async_runtime::spawn(async move {
                    while let Some(event) = rx.recv().await {
                        match event {
                            CommandEvent::Stdout(line) => {
                                println!("[Server] {}", String::from_utf8_lossy(&line));
                            }
                            CommandEvent::Stderr(line) => {
                                eprintln!("[Server ERR] {}", String::from_utf8_lossy(&line));
                            }
                            CommandEvent::Terminated(_) => {
                                eprintln!("[tsundoku] server process exited");
                                break;
                            }
                            _ => {}
                        }
                    }
                });
            }
            Err(err) => {
                eprintln!("[tsundoku] failed to spawn server: {err}");
                return;
            }
        }

        // Block until the server accepts TCP connections (runs on a blocking
        // thread so the async runtime stays responsive).
        let ready = tauri::async_runtime::spawn_blocking(move || {
            let deadline = Instant::now() + SERVER_STARTUP_TIMEOUT;
            while Instant::now() < deadline {
                if is_server_running(port) {
                    return true;
                }
                std::thread::sleep(Duration::from_millis(250));
            }
            false
        })
        .await
        .unwrap_or(false);

        if !ready {
            eprintln!("[tsundoku] server did not become ready in time; keeping bundled page");
            return;
        }

        #[cfg(not(dev))]
        navigate_main_window(&app, port);
    });
}

fn setup_tray(app: &tauri::App) -> tauri::Result<()> {
    let show = MenuItem::with_id(app, "show", "Открыть Tsundoku", true, None::<&str>)?;
    let open_logs = MenuItem::with_id(app, "open-logs", "Консоль логов", true, None::<&str>)?;
    let open_browser =
        MenuItem::with_id(app, "open-browser", "Открыть в браузере", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Выход", true, None::<&str>)?;

    let menu = MenuBuilder::new(app)
        .item(&show)
        .item(&open_logs)
        .item(&open_browser)
        .item(&PredefinedMenuItem::separator(app)?)
        .item(&quit)
        .build()?;

    // The trayIcon block in tauri.conf.json already creates a bare tray with id
    // "main"; drop it and rebuild it here so the menu and click handlers attach.
    let _ = app.remove_tray_by_id("main");

    TrayIconBuilder::with_id("main")
        .icon(app.default_window_icon().expect("default window icon").clone())
        .tooltip("Tsundoku")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "show" => show_main_window(app),
            "open-logs" => show_or_create_logs_window(app),
            "open-browser" => {
                // Shell::open is deprecated in favor of tauri-plugin-opener, but the
                // shell plugin is a project requirement here; opening with the system
                // default handler needs no Program argument.
                #[allow(deprecated)]
                if let Err(err) = app.shell().open(server_url(server_port()), None::<tauri_plugin_shell::open::Program>) {
                    eprintln!("[tsundoku] failed to open browser: {err}");
                }
            }
            // Triggers RunEvent::Exit below, which terminates the managed server.
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                let app = tray.app_handle();
                if let Some(window) = app.get_webview_window("main") {
                    if window.is_visible().unwrap_or(false) && window.is_focused().unwrap_or(false)
                    {
                        hide_main_window(app);
                    } else {
                        show_main_window(app);
                    }
                }
            }
        })
        .build(app)?;

    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        // Must be the first registered plugin: the second launch forwards here
        // and dies immediately instead of spawning a duplicate tray icon and a
        // second server-management layer over the same port.
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.unminimize();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_notification::init())
        .invoke_handler(tauri::generate_handler![close_action, open_logs_window])
        .manage(ServerState {
            managed: Mutex::new(false),
            child: Mutex::new(None),
        })
        .setup(|app| {
            // SIGINT/SIGTERM (Ctrl+C, systemd stop, session end) must route through
            // the same cleanup path as the tray: app.exit triggers RunEvent::Exit,
            // which terminates the managed server process.
            let handle = app.handle().clone();
            if let Err(err) = ctrlc::set_handler(move || {
                eprintln!("[tsundoku] shutdown signal received");
                handle.exit(0);
            }) {
                eprintln!("[tsundoku] failed to install signal handler: {err}");
            }

            let port = server_port();
            let state = app.state::<ServerState>();
            if is_server_running(port) {
                // Case A: an external server (background service, systemd, docker)
                // already owns the port; attach to it and never touch its lifecycle.
                eprintln!(
                    "[Tauri] Existing Tsundoku server detected on port {port}. Attaching without spawning a child process."
                );
                *state.managed.lock().unwrap() = false;
            } else {
                // Case B: we spawn the server and own its lifecycle.
                *state.managed.lock().unwrap() = true;
                spawn_server(app.handle().clone(), port);
            }

            // Background startup (autostart, shortcuts): start hidden in the tray.
            if std::env::args().any(|arg| arg == "--tray" || arg == "--minimized") {
                hide_main_window(app.handle());
            }

            // [X] on the main window never destroys the webview: the frontend
            // decides between tray-agent mode and a full shutdown, showing a
            // confirmation dialog when no preference is saved yet.
            if let Some(main_window) = app.get_webview_window("main") {
                let window = main_window.clone();
                main_window.on_window_event(move |event| {
                    if let WindowEvent::CloseRequested { api, .. } = event {
                        api.prevent_close();
                        let _ = window.emit("close-requested", ());
                    }
                });
            }

            setup_tray(app)?;
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|app, event| {
            if let RunEvent::Exit = event {
                let state = app.state::<ServerState>();
                if *state.managed.lock().unwrap() {
                    if let Some(child) = state.child.lock().unwrap().take() {
                        let _ = child.kill();
                        eprintln!("[tsundoku] spawned server terminated");
                    }
                } else {
                    eprintln!("[tsundoku] leaving the externally managed server running");
                }
            }
        });
}
