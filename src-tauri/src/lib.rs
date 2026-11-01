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

/// On Linux this materializes the embedded window on demand (see
/// `ensure_main_window`); on Windows the window always exists from the config.
fn show_main_window(app: &AppHandle) {
    #[cfg(target_os = "linux")]
    let window = ensure_main_window(app);
    #[cfg(not(target_os = "linux"))]
    let window = app.get_webview_window("main");

    if let Some(window) = window {
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

/// [X] on the main window never destroys the webview: the frontend decides
/// between tray-agent mode and a full shutdown, showing a confirmation dialog
/// when no preference is saved yet.
fn intercept_main_window_close(window: &tauri::WebviewWindow) {
    let emitter = window.clone();
    window.on_window_event(move |event| {
        if let WindowEvent::CloseRequested { api, .. } = event {
            api.prevent_close();
            let _ = emitter.emit("close-requested", ());
        }
    });
}

/// Linux: with `windows: []` in tauri.linux.conf.json no WebKitGTK window (and
/// therefore no WebKitWebProcess / WebKitNetworkProcess) is created at startup,
/// saving ~80 MB of RAM in the common case where the UI lives in an external
/// browser. This helper materializes the embedded window on demand — only for
/// TSUNDOKU_FORCE_WEBKIT=1 debugging or as the very last open_ui_url fallback
/// when not even xdg-open worked.
#[cfg(target_os = "linux")]
fn ensure_main_window(app: &AppHandle) -> Option<tauri::WebviewWindow> {
    if let Some(window) = app.get_webview_window("main") {
        return Some(window);
    }

    eprintln!("[tsundoku] creating the embedded WebKitGTK window on demand");
    let window = WebviewWindowBuilder::new(app, "main", WebviewUrl::App("index.html".into()))
        .title("Tsundoku")
        .inner_size(1300.0, 850.0)
        .min_inner_size(900.0, 600.0)
        .center()
        .visible(false)
        .build()
        .ok()?;
    intercept_main_window_close(&window);

    // A freshly created release window lives on the bundled SPA origin, where
    // the relative /api URLs do not resolve; move it to the server origin.
    #[cfg(not(dev))]
    navigate_main_window(app, server_port());

    Some(window)
}

/// Chromium-family launchers tried (in order) for a dedicated `--app` window on
/// Linux, where the embedded WebKitGTK renderer is slow and frame-locked.
#[cfg(target_os = "linux")]
const CHROMIUM_BROWSERS: &[&str] = &[
    "chromium",
    "chromium-browser",
    "google-chrome-stable",
    "google-chrome",
    "brave-browser",
    "vivaldi",
    "microsoft-edge",
];

/// Resolves a bare binary name against `$PATH`.
#[cfg(target_os = "linux")]
fn find_in_path(bin: &str) -> Option<PathBuf> {
    let path = std::env::var_os("PATH")?;
    std::env::split_paths(&path)
        .map(|dir| dir.join(bin))
        .find(|candidate| candidate.is_file())
}

/// Opens `url` in an external browser, bypassing the embedded WebKitGTK window.
/// Cascade: Chromium-family `--app` window (native chrome-less window with an
/// isolated profile) -> default system browser tab -> as the very last resort
/// (even `xdg-open` failed) the laggy WebKitGTK window.
#[cfg(target_os = "linux")]
fn open_ui_url(app: &AppHandle, url: &str) {
    // Debug escape hatch: the user explicitly asked for the embedded window.
    if std::env::var("TSUNDOKU_FORCE_WEBKIT").as_deref() == Ok("1") {
        show_main_window(app);
        return;
    }

    // Step A: dedicated `--app` window via a Chromium-family browser.
    if std::env::var("TSUNDOKU_BROWSER_MODE").as_deref() != Ok("tab") {
        if let Some(browser) = CHROMIUM_BROWSERS.iter().find_map(|bin| find_in_path(bin)) {
            // The log console is a narrower utility window; the main UI targets
            // the 6-column grid.
            let window_size = if url.ends_with("/logs.html") {
                "1280,720"
            } else {
                "1400,900"
            };
            let profile_dir = match app.path().local_data_dir() {
                Ok(dir) => Some(dir.join("tsundoku-chromium-profile")),
                Err(err) => {
                    eprintln!("[tsundoku] failed to resolve local data dir: {err}");
                    None
                }
            };

            let mut command = std::process::Command::new(&browser);
            command
                .arg(format!("--app={url}"))
                .arg("--class=Tsundoku")
                .arg(format!("--window-size={window_size}"))
                // Native Wayland rendering instead of XWayland.
                .arg("--ozone-platform-hint=auto")
                // The isolated profile would otherwise trigger KWallet /
                // GNOME Keyring unlock prompts on every launch.
                .arg("--password-store=basic")
                .arg("--no-first-run")
                .arg("--no-default-browser-check")
                .arg("--disable-extensions")
                .arg("--disable-sync")
                .arg("--disable-translate")
                // Suppresses the "translate this page?" bubble on Japanese /
                // romaji titles, plus other unused popup surfaces.
                .arg("--disable-features=Translate,GlobalMediaControls,MediaRouter,OptimizationHints")
                .arg("--enable-gpu-rasterization")
                .arg("--enable-zero-copy")
                .arg("--ignore-gpu-blocklist")
                .arg("--force-dark-mode")
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null());
            if let Some(profile_dir) = &profile_dir {
                command.arg(format!("--user-data-dir={}", profile_dir.display()));
            }

            // The child intentionally outlives the agent: dropping the handle
            // leaves the browser window running after Tsundoku exits.
            match command.spawn() {
                Ok(_child) => {
                    eprintln!("[tsundoku] opened {url} in {} (--app window)", browser.display());
                    return;
                }
                Err(err) => {
                    eprintln!("[tsundoku] failed to launch {}: {err}", browser.display());
                }
            }
        }
    }

    // Step B: a tab in the user's default browser (Zen, Firefox, ...).
    // Shell::open is deprecated in favor of tauri-plugin-opener, but the shell
    // plugin is a project requirement here.
    #[allow(deprecated)]
    match app.shell().open(url, None::<tauri_plugin_shell::open::Program>) {
        Ok(()) => {
            eprintln!("[tsundoku] opened {url} in the default browser");
            return;
        }
        Err(err) => eprintln!("[tsundoku] failed to open {url} in the default browser: {err}"),
    }

    // Last resort only: no Chromium, no working xdg-open. A laggy UI beats none.
    eprintln!("[tsundoku] falling back to the embedded WebKitGTK window");
    show_main_window(app);
}

/// On Windows the WebView2 window is the fast, native UI: "open the UI" simply
/// means showing it.
#[cfg(not(target_os = "linux"))]
fn open_ui_url(_app: &AppHandle, _url: &str) {
    show_main_window(_app);
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

/// Label of the native MangaLib (SocialLib) login popup.
const MANGALIB_AUTH_WINDOW: &str = "auth_mangalib";

/// Polls the MangaLib session storage and hands the captured Bearer token to
/// the shell. Runs in every frame the auth window displays; the fingerprint
/// guard keeps a single invoke per distinct token/user pair.
const MANGALIB_AUTH_SCRIPT: &str = r#"(function () {
  if (window.__TSUNDOKU_AUTH_POLL__) return;
  window.__TSUNDOKU_AUTH_POLL__ = true;
  var lastSent = "";
  setInterval(function () {
    try {
      var raw = localStorage.getItem("auth");
      if (!raw) return;
      var parsed = JSON.parse(raw);
      var token =
        (parsed && parsed.token && parsed.token.access_token) ||
        (parsed && parsed.access_token) ||
        (parsed && typeof parsed.token === "string" ? parsed.token : null);
      if (!token || typeof token !== "string" || token.length < 20) return;
      var userId = "";
      if (parsed && parsed.user && parsed.user.id != null) userId = String(parsed.user.id);
      var fingerprint = token + "|" + userId;
      if (fingerprint === lastSent) return;
      lastSent = fingerprint;
      window.__TAURI_INTERNALS__.invoke("save_mangalib_auth", {
        token: token,
        userId: userId,
      });
    } catch (e) {}
  }, 500);
})();"#;

/// Opens the native MangaLib login popup (500x700). Re-shows an existing one.
#[tauri::command]
fn open_mangalib_auth_window(app: AppHandle) {
    if let Some(existing) = app.get_webview_window(MANGALIB_AUTH_WINDOW) {
        let _ = existing.unminimize();
        let _ = existing.show();
        let _ = existing.set_focus();
        return;
    }

    let url = match "https://mangalib.org/ru/login".parse::<tauri::Url>() {
        Ok(parsed) => parsed,
        Err(err) => {
            eprintln!("[tsundoku] invalid MangaLib auth url: {err}");
            return;
        }
    };

    if let Err(err) = WebviewWindowBuilder::new(&app, MANGALIB_AUTH_WINDOW, WebviewUrl::External(url))
        .title("Вход в MangaLib — Tsundoku")
        .inner_size(500.0, 700.0)
        .min_inner_size(380.0, 480.0)
        .initialization_script(MANGALIB_AUTH_SCRIPT)
        .build()
    {
        eprintln!("[tsundoku] failed to open MangaLib auth window: {err}");
    }
}

/// Receives the Bearer token captured by the auth window, closes that window
/// and hands the credential to the main UI, which persists it via the backend
/// settings API and shows the connected state. The token itself never leaves
/// the local machine.
#[tauri::command]
fn save_mangalib_auth(app: AppHandle, token: String, user_id: String) {
    let token = token.trim().to_string();
    if token.is_empty() {
        return;
    }

    if let Some(window) = app.get_webview_window(MANGALIB_AUTH_WINDOW) {
        let _ = window.close();
    }

    let _ = app.emit(
        "mangalib-authenticated",
        serde_json::json!({ "token": token, "userId": user_id }),
    );
}

/// Opens the WebView inspector for the calling window (F12 / Ctrl+Shift+I from
/// the UI, or the tray item). Available in release builds via the `devtools`
/// feature; without it this command simply does nothing.
#[tauri::command]
fn open_devtools(window: tauri::WebviewWindow) {
    window.open_devtools();
}

fn show_or_create_logs_window(app: &AppHandle) {
    // The log console is just another page of the server UI: on Linux it goes
    // to the external browser cascade like every other window.
    #[cfg(target_os = "linux")]
    {
        open_ui_url(app, &format!("{}/logs.html", server_url(server_port())));
    }

    #[cfg(not(target_os = "linux"))]
    {
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

        // The main window is never destroyed (close is intercepted), so closing
        // the console can never be the last window and exit the whole app: the
        // default close behavior (destroy only this window) is exactly what we
        // want.
        if let Err(err) = WebviewWindowBuilder::new(app, "logs", WebviewUrl::External(parsed))
            .title("Tsundoku — Консоль логов")
            .inner_size(1280.0, 680.0)
            .min_inner_size(950.0, 500.0)
            .build()
        {
            eprintln!("[tsundoku] failed to open logs window: {err}");
        }
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
/// instead of aborting the app so the shell still opens. `open_ui_on_ready`
/// opens the UI as soon as the port accepts TCP connections (suppressed for
/// background startups like `--tray`).
fn spawn_server(app: AppHandle, port: u16, open_ui_on_ready: bool) {
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

        if open_ui_on_ready {
            #[cfg(target_os = "linux")]
            open_ui_url(&app, &server_url(port));
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
    let devtools = MenuItem::with_id(app, "devtools", "Инструменты разработчика", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Выход", true, None::<&str>)?;

    let menu = MenuBuilder::new(app)
        .item(&show)
        .item(&open_logs)
        .item(&open_browser)
        .item(&devtools)
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
            "show" => {
                #[cfg(target_os = "linux")]
                open_ui_url(app, &server_url(server_port()));
                #[cfg(not(target_os = "linux"))]
                show_main_window(app);
            }
            "open-logs" => show_or_create_logs_window(app),
            "devtools" => {
                if let Some(window) = app.get_webview_window("main") {
                    window.open_devtools();
                }
            },
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
                // On Linux there is no visible native window to toggle: a left
                // click always surfaces the UI in the external browser.
                #[cfg(target_os = "linux")]
                open_ui_url(app, &server_url(server_port()));
                #[cfg(not(target_os = "linux"))]
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
    // Linux/WebKitGTK: keep the webview on the GPU path. WebKit defaults to
    // software compositing in some environments, which renders frames on the
    // CPU and locks the UI to the compositor's ~60 Hz step; forcing the
    // compositing mode sends the whole page through the accelerated renderer.
    // The DISABLE_* switches (set by workarounds for old driver crashes) turn
    // exactly that path off, so they must not survive into our process.
    #[cfg(target_os = "linux")]
    {
        for disabled_gpu_var in ["WEBKIT_DISABLE_COMPOSITING_MODE", "WEBKIT_DISABLE_DMABUF_RENDERER"] {
            if std::env::var_os(disabled_gpu_var).is_some() {
                eprintln!("[tsundoku] removing {disabled_gpu_var}: GPU rendering is required for high-FPS UI");
                std::env::remove_var(disabled_gpu_var);
            }
        }
        std::env::set_var("WEBKIT_FORCE_COMPOSITING_MODE", "1");
    }

    tauri::Builder::default()
        // Must be the first registered plugin: the second launch forwards here
        // and dies immediately instead of spawning a duplicate tray icon and a
        // second server-management layer over the same port.
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            // A second launch means the user wants to see the UI: on Linux that
            // is the external browser cascade, on Windows the native window.
            #[cfg(target_os = "linux")]
            open_ui_url(app, &server_url(server_port()));
            #[cfg(not(target_os = "linux"))]
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.unminimize();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_notification::init())
        .invoke_handler(tauri::generate_handler![
            close_action,
            open_logs_window,
            open_devtools,
            open_mangalib_auth_window,
            save_mangalib_auth
        ])
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
            // Background startup (autostart, shortcuts): stay in the tray and
            // do not surface the UI automatically.
            let background = std::env::args().any(|arg| arg == "--tray" || arg == "--minimized");

            let state = app.state::<ServerState>();
            if is_server_running(port) {
                // Case A: an external server (background service, systemd, docker)
                // already owns the port; attach to it and never touch its lifecycle.
                eprintln!(
                    "[Tauri] Existing Tsundoku server detected on port {port}. Attaching without spawning a child process."
                );
                *state.managed.lock().unwrap() = false;
                if !background {
                    #[cfg(target_os = "linux")]
                    open_ui_url(app.handle(), &server_url(port));
                }
            } else {
                // Case B: we spawn the server and own its lifecycle. The UI opens
                // via open_ui_url once the port is ready (see spawn_server).
                *state.managed.lock().unwrap() = true;
                spawn_server(app.handle().clone(), port, !background);
            }

            // Linux: the embedded WebKitGTK renderer freezes and is locked to
            // ~60 FPS, so the UI lives in an external browser instead. The
            // hidden window only keeps the Tauri event loop (and the tray)
            // alive. TSUNDOKU_FORCE_WEBKIT=1 restores the classic embedded
            // window for debugging.
            #[cfg(target_os = "linux")]
            {
                if std::env::var("TSUNDOKU_FORCE_WEBKIT").as_deref() == Ok("1") {
                    show_main_window(app.handle());
                } else {
                    hide_main_window(app.handle());
                    eprintln!(
                        "[tsundoku] Linux: embedded WebKitGTK window hidden; UI opens in the external browser (TSUNDOKU_FORCE_WEBKIT=1 to restore)"
                    );
                }
            }

            // Background startup (autostart, shortcuts): start hidden in the tray.
            if background {
                hide_main_window(app.handle());
            }

            // [X] on the main window never destroys the webview: the frontend
            // decides between tray-agent mode and a full shutdown, showing a
            // confirmation dialog when no preference is saved yet. On Linux
            // there is no window at startup — ensure_main_window attaches the
            // same handler when it materializes one on demand.
            if let Some(main_window) = app.get_webview_window("main") {
                intercept_main_window_close(&main_window);
            }

            setup_tray(app)?;
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|app, event| match event {
            // On Linux the config ships zero windows: without this guard the
            // run loop would end the process as soon as the last (auxiliary)
            // window closes or when no window exists at all. `code.is_none()`
            // means a window-driven exit request; an explicit app.exit(0)
            // (tray "Выход", Ctrl+C, SPA "exit_all") carries a code and must
            // proceed to RunEvent::Exit, which terminates the managed server.
            RunEvent::ExitRequested { code, api, .. } => {
                if code.is_none() {
                    api.prevent_exit();
                }
            }
            RunEvent::Exit => {
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
            _ => {}
        });
}
