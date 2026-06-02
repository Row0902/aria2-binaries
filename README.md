# aria2-binaries

Pre-built [aria2c](https://github.com/aria2/aria2) static binaries for multiple platforms.

Built automatically via GitHub Actions. Consumed by the [aria2 Python SDK](https://github.com/Row0902/aria2).

## Platforms

| Platform        | Arch                           | Binary                          |
| --------------- | ------------------------------ | ------------------------------- |
| Linux (glibc)   | x86_64                         | `aria2c-linux-x86_64`           |
| Linux (glibc)   | aarch64                        | `aria2c-linux-aarch64`          |
| Linux (glibc)   | armv7                          | `aria2c-linux-armv7`            |
| macOS           | x86_64 (Intel)                 | `aria2c-darwin-x86_64`          |
| macOS           | arm64 (Apple Silicon)          | `aria2c-darwin-arm64`           |
| Windows         | amd64                          | `aria2c-windows-amd64.exe`      |
| Android         | aarch64 (API 24+)              | `aria2c-android-aarch64`        |
| Android         | armv7 (API 24+)                | `aria2c-android-armv7`          |
| Android         | x86_64 (API 24+)               | `aria2c-android-x86_64`         |

## How it works

The source code is checked out from [aria2/aria2](https://github.com/aria2/aria2) at build time.
This repo contains only CI workflows and build scripts — no vendored source code.

### Dependencies built from source

- **Linux/macOS/Windows**: system package managers (apt, brew, MSYS2)
- **Android**: OpenSSL, expat, zlib, and c-ares are built from source via `scripts/build-android.sh`

### Features enabled

- HTTP/HTTPS, FTP, SFTP
- BitTorrent (DHT, PEX, MSE/PSE, UDP tracker)
- Metalink (v3, v4)
- JSON-RPC (HTTP) and XML-RPC
- Async DNS (c-ares)
- IPv6 with Happy Eyeballs
- Fully static — no runtime dependencies

## Release process

### Option 1: Tag-driven (recommended)

Push a version tag to trigger a full multi-platform build and automatic GitHub Release:

```bash
git tag v1.37.0
git push origin v1.37.0
```

The release workflow will:
1. Build all 9 platform/arch combinations in parallel
2. Generate SHA256 and MD5 checksums
3. Create a GitHub Release with all binaries + checksums + release notes

### Option 2: Manual dispatch

Trigger individual platform builds from the Actions tab for testing:

```bash
# Build only Linux (all 3 arches)
gh workflow run "Build aria2 (Linux)" -f version=1.37.0

# Build only macOS
gh workflow run "Build aria2 (macOS)" -f version=1.37.0

# Build only Windows
gh workflow run "Build aria2 (Windows)" -f version=1.37.0

# Build only Android (all 3 arches)
gh workflow run "Build aria2 (Android)" -f version=1.37.0
```

### Option 3: Full release via dispatch

```bash
gh workflow run "Release aria2 binaries" -f version=1.37.0
```

## Workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| `Release aria2 binaries` | Tag `v*` or dispatch | Full multi-platform build + GitHub Release |
| `Build aria2 (Linux)` | Dispatch only | Build/test individual Linux targets |
| `Build aria2 (macOS)` | Dispatch only | Build/test individual macOS targets |
| `Build aria2 (Windows)` | Dispatch only | Build/test individual Windows targets |
| `Build aria2 (Android)` | Dispatch only | Build/test individual Android targets |

## Scripts

- `scripts/build-android.sh` — Build aria2 for Android (all 3 arches) with all deps from source

## Versioning

This repo uses its own tags (`v1.37.0`, `v1.38.0`, etc.) matching upstream aria2 releases.
The tag name maps to the upstream version — no git tags exist upstream.

## Consuming from the SDK

The [aria2 Python SDK](https://github.com/Row0902/aria2) downloads the correct binary
for the current platform at build time via `hatch_build.py`. Each release here provides
the binaries consumed by the SDK's build hook.
