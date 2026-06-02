# aria2-binaries

Pre-built [aria2c](https://github.com/aria2/aria2) static binaries for multiple platforms.

These binaries are built automatically via GitHub Actions and published as release artifacts.
Consumed by the [aria2 Python SDK](https://github.com/Row0902/aria2) via its build hook.

## Platforms

| Platform | Arch | Binary name |
|---|---|---|
| Linux (glibc) | x86_64 | \`aria2c-linux-x86_64\` |
| Linux (glibc) | aarch64 | \`aria2c-linux-aarch64\` |
| Linux (glibc) | armv7 | \`aria2c-linux-armv7\` |
| macOS | x86_64 | \`aria2c-darwin-x86_64\` |
| macOS | arm64 (Apple Silicon) | \`aria2c-darwin-arm64\` |
| Windows | amd64 | \`aria2c-windows-amd64.exe\` |
| Android | aarch64 | \`aria2c-android-aarch64\` |
| Android | armv7 | \`aria2c-android-armv7\` |
| Android | x86_64 | \`aria2c-android-x86_64\` |

## Usage

Add a release tag (e.g. \`release-1.37.0\`) and the workflows will build and publish automatically.

## Release process

1. Push a tag matching an aria2 release (e.g. \`release-1.37.0\`)
2. Workflows build for all platforms in parallel
3. A GitHub release is created with all binaries attached

