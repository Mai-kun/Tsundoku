# Sidecar binaries

`tauri.conf.json` declares the .NET server as an external (sidecar) binary:

```
"externalBin": ["binaries/tsundoku-server"]
```

Tauri requires the file to carry the Rust target triple as a suffix, e.g.:

- `binaries/tsundoku-server-x86_64-unknown-linux-gnu`
- `binaries/tsundoku-server-x86_64-pc-windows-msvc.exe`
- `binaries/tsundoku-server-aarch64-apple-darwin`

The shell also expects the SQLite native library next to the sidecar
(`libe_sqlite3.so` on Linux, `e_sqlite3.dll` on Windows) — the Tauri bundle ships
it as a resource and the app points the .NET host at it via `--contentRoot` /
`LD_LIBRARY_PATH`. Both files are produced by `dotnet publish`:

```sh
dotnet publish MediaTracker.Server -c Release -r linux-x64 -o dist/server
cp dist/server/Tsundoku.Server src-tauri/binaries/tsundoku-server-x86_64-unknown-linux-gnu
cp dist/server/libe_sqlite3.so src-tauri/binaries/libe_sqlite3.so
```

`build-linux.sh` does all of this for you. The files themselves are ignored by
git — they are build artifacts.
