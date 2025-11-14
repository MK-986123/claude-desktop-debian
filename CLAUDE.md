# CLAUDE.md - AI Assistant Guide for claude-desktop-debian

## Project Overview

This repository contains build scripts to run **Claude Desktop natively on Linux** systems. It repackages the official Windows Electron application for Debian-based distributions, producing either `.deb` packages or AppImages.

**Important**: This is an unofficial build script. The Claude Desktop application itself is subject to Anthropic's Consumer Terms.

### Key Facts
- **Primary Language**: Bash shell scripting
- **Target Platforms**: Debian-based Linux (Debian, Ubuntu, Linux Mint, MX Linux, etc.)
- **Architectures**: amd64 and arm64
- **Build Outputs**: `.deb` packages or `.AppImage` files
- **License**: Dual-licensed under MIT and Apache 2.0 (build scripts only)
- **Node Version**: Requires Node.js 24+ (automatically downloaded if not available)
- **Electron Version**: 39.x (with fallback to 38.x)

## Repository Structure

```
claude-desktop-debian/
├── build.sh                    # Main build orchestrator script
├── scripts/
│   ├── build-deb-package.sh   # Debian package builder
│   └── build-appimage.sh      # AppImage package builder
├── package.json               # Node dependencies (Electron, ASAR)
├── .github/
│   ├── workflows/             # CI/CD automation
│   │   ├── ci.yml            # Main CI workflow
│   │   ├── build-amd64.yml   # AMD64 build job
│   │   ├── build-arm64.yml   # ARM64 build job
│   │   ├── check-claude-version.yml  # Version monitoring
│   │   ├── shellcheck.yml    # Shell script linting
│   │   ├── codespell.yml     # Spell checking
│   │   └── test-flags.yml    # Flag parsing tests
│   └── agents/               # GitHub agent definitions
├── README.md                  # User-facing documentation
├── LICENSE-MIT               # MIT license
├── LICENSE-APACHE            # Apache 2.0 license
└── .codespellrc              # Codespell configuration
```

### Build Artifacts (Generated, not in repo)
```
build/                         # Created during build process
├── node_modules/             # Local Electron & ASAR install
├── claude-extract/           # Extracted Windows installer
├── electron-app/             # Staged application
└── package/                  # Debian package structure
```

## How It Works

### Build Process Flow

1. **Architecture Detection** (build.sh:4-27)
   - Detects system architecture (amd64 or arm64)
   - Sets appropriate download URLs and variables

2. **Dependency Installation** (build.sh:146-198)
   - Required tools: `p7zip`, `wget`, `wrestool`, `icotool`, `convert`, `dpkg-deb`
   - Automatically installs missing dependencies via `apt`

3. **Node.js Setup** (build.sh:204-298)
   - Requires Node.js 24+ (configurable via `CLAUDE_NODE_MIN_MAJOR`)
   - Downloads local Node.js v24.11.0 if system version inadequate
   - Supports custom Node.js path via `CLAUDE_NODE_PATH` environment variable

4. **Electron & ASAR Installation** (build.sh:299-365)
   - Installs Electron 39.x locally in build directory
   - Fallback to Electron 38.x if needed
   - Installs @electron/asar for package manipulation

5. **Windows Installer Download & Extraction** (build.sh:367-401)
   - Downloads official Claude Desktop Windows installer
   - Extracts using 7z
   - Locates and extracts `.nupkg` file
   - Detects version from filename

6. **Application Patching** (build.sh:403-643)
   - **Frame Fix**: Patches to use native Linux window decorations instead of custom titlebar
   - **Native Module Stub**: Replaces Windows `claude-native` module with Linux-compatible stub
   - **Tray Menu Fix**: Adds mutex guard to prevent concurrent tray menu operations
   - **Titlebar Detection**: Removes negation in titlebar detection logic
   - Copies locale files and resources

7. **Icon Processing** (build.sh:708-741)
   - Extracts icons from Windows executable
   - Converts to multiple sizes (16x16, 24x24, 32x32, 48x48, 64x64, 256x256)
   - Copies tray icons to Electron resources

8. **Package Creation** (build.sh:757-817)
   - Calls either `build-deb-package.sh` or `build-appimage.sh`
   - Creates launcher scripts with Wayland support
   - Generates desktop entry files
   - Packages all components

### Key Technical Implementations

#### Frame Fix Wrapper (build.sh:415-472)
```javascript
// Intercepts BrowserWindow creation to force native frames on Linux
Module.prototype.require = function(id) {
  if (id === 'electron') {
    module.BrowserWindow = class BrowserWindowWithFrame extends OriginalBrowserWindow {
      constructor(options) {
        if (process.platform === 'linux') {
          options.frame = true;
          delete options.titleBarStyle;
          delete options.titleBarOverlay;
        }
        super(options);
      }
    };
  }
  return module;
};
```

#### Native Module Stub (build.sh:504-539)
Provides Linux-compatible stubs for Windows-specific native functions:
- `getWindowsVersion()`, `setWindowEffect()`, `flashFrame()`, etc.
- `AuthRequest` class (returns unavailable, triggers browser fallback)
- `KeyboardKey` enum with key mappings

#### Wayland Support
Both launcher scripts detect and enable Wayland:
- Checks `$WAYLAND_DISPLAY` and `$XDG_SESSION_TYPE`
- Adds flags: `--ozone-platform=wayland`, `--enable-features=WaylandWindowDecorations,GlobalShortcutsPortal`
- Enables Wayland IME support

## Development Workflows

### Building Locally

```bash
# Build .deb package (default)
./build.sh

# Build AppImage
./build.sh --build appimage

# Build with custom options
./build.sh --build deb --clean no  # Keep intermediate files

# Test flag parsing without building
./build.sh --test-flags --build appimage
```

### Using npm Scripts

```bash
npm run build              # Default: ./build.sh
npm run build:deb         # Build .deb package
npm run build:appimage    # Build AppImage
```

### CI/CD Pipeline

**Trigger Conditions**:
- Push to `main` branch (if build scripts or workflows change)
- Pull requests to `main`
- Git tags matching `v*` (triggers release)
- Manual workflow dispatch

**Build Matrix**:
- **amd64**: Both .deb and AppImage
- **arm64**: Both .deb and AppImage
- Parallel execution for faster builds

**Quality Checks**:
- `shellcheck`: Shell script linting
- `codespell`: Spelling verification
- `test-flags`: Build script flag parsing tests

**Release Process** (on git tags):
1. Download all build artifacts (4 files: amd64/arm64 × deb/AppImage)
2. Create GitHub Release
3. Upload artifacts as release assets
4. AppImages include embedded update information for auto-updates

### Version Monitoring

The `check-claude-version.yml` workflow:
- Runs weekly (cron schedule)
- Checks for new Claude Desktop releases
- Opens an issue if new version detected
- Helps maintainers stay updated

## Key Conventions for AI Assistants

### Safety Rules

1. **Never Run as Root**
   - build.sh checks `$EUID` and exits if run as root (build.sh:35-40)
   - Prompts for sudo only when needed for specific operations

2. **Architecture-Specific Handling**
   - Always detect architecture first
   - Use appropriate download URLs and tool versions
   - Test both amd64 and arm64 paths when making changes

3. **Error Handling**
   - Use `set -euo pipefail` for strict error handling
   - Provide clear error messages with ❌ prefix
   - Clean up on failure

### Code Style

1. **Shell Scripting**
   - Use `shellcheck` compliant code
   - Quote variables: `"$VARIABLE"` not `$VARIABLE`
   - Use `[[ ]]` for conditionals, not `[ ]`
   - Proper error handling with explicit checks

2. **Output Formatting**
   - Use ANSI color codes: `\033[1;36m` for section headers
   - Use emoji indicators: ✓ (success), ❌ (error), ⚠️ (warning), 🚀 (action)
   - Clear section boundaries with `echo -e "\033[1;36m--- Section Name ---\033[0m"`

3. **Comments**
   - Document complex logic
   - Explain architecture-specific code
   - Reference line numbers when noting issues

### Testing Guidelines

1. **Local Testing**
   - Test on actual Debian-based system
   - Test both architectures if possible
   - Verify both .deb and AppImage outputs
   - Test with `--test-flags` for non-destructive verification

2. **CI Testing**
   - Verify workflow syntax before committing
   - Test matrix changes carefully
   - Check artifact naming consistency

3. **Integration Testing**
   - Install built package
   - Verify Claude Desktop launches
   - Test system tray integration
   - Test MCP configuration (~/.config/Claude/claude_desktop_config.json)
   - Test global hotkey (Ctrl+Alt+Space on X11)

### Common Tasks

#### Updating Electron Version

1. Edit `package.json` and `build.sh` Electron version references
2. Update `build.sh:324-332` version pinning logic
3. Test with both build formats
4. Verify Wayland compatibility

#### Adding New Dependencies

1. Update dependency check in `build.sh:156-178`
2. Add to `COMMON_DEPS`, `DEB_DEPS`, or `APPIMAGE_DEPS`
3. Test installation on clean system

#### Modifying Patching Logic

**Important**: Application patching is fragile and version-specific!

1. **Frame Fix** (build.sh:415-501)
   - Modifies how BrowserWindow is created
   - Changes require testing window behavior

2. **Titlebar Detection** (build.sh:547-587)
   - Uses regex to find and modify minified JavaScript
   - Pattern: `if(!VAR1 && VAR2)` → `if(VAR1 && VAR2)`
   - Must verify pattern exists and is unique

3. **Tray Menu Fix** (build.sh:589-641)
   - Dynamically extracts function/variable names
   - Adds mutex guard and DBus cleanup delay
   - Complex multi-step patching process

#### Updating Download URLs

Claude Desktop download URLs are hardcoded (build.sh:13-24):
```bash
# AMD64
CLAUDE_DOWNLOAD_URL="https://storage.googleapis.com/osprey-downloads-.../Claude-Setup-x64.exe"

# ARM64
CLAUDE_DOWNLOAD_URL="https://storage.googleapis.com/osprey-downloads-.../Claude-Setup-arm64.exe"
```

Monitor Anthropic's official releases and update when URLs change.

### Git Workflow

**Branch Naming**:
- Feature branches: `feature/description`
- Bug fixes: `fix/description`
- CI/CD branches: May use special prefixes like `claude/`

**Commit Messages**:
- Use conventional commits style
- Clear, descriptive messages
- Reference issues when applicable

**Pull Requests**:
- Trigger CI pipeline automatically
- Ensure all checks pass (shellcheck, codespell, builds)
- Test both architectures

### Configuration Files

#### MCP Configuration
- Location: `~/.config/Claude/claude_desktop_config.json`
- Not managed by this repository
- User-specific configuration

#### Application Logs
- **.deb**: `$XDG_CACHE_HOME/claude-desktop-debian/launcher.log` (or `~/.cache/`)
- **AppImage**: `$HOME/claude-desktop-launcher.log`

#### Desktop Integration
- Desktop file: `/usr/share/applications/claude-desktop.desktop` (.deb)
- Icons: `/usr/share/icons/hicolor/{size}/apps/claude-desktop.png`
- MIME type handler: `x-scheme-handler/claude`

## Important Notes for AI Assistants

### What to Modify

✅ **Safe to modify**:
- Build script structure and flow
- Dependency checking logic
- Error messages and user output
- CI/CD workflows
- Documentation
- Icon processing
- Package metadata

### What to Avoid

❌ **Dangerous to modify without deep testing**:
- Application patching logic (frame fix, titlebar detection, tray menu)
- Architecture detection
- Electron/Node.js version logic
- ASAR packing/unpacking
- Launcher script logic (especially Wayland detection)

⚠️ **Modify with extreme caution**:
- Download URLs (must match actual Claude Desktop releases)
- Package structure (affects installation)
- Desktop file format
- AppStream metadata format

### When Making Changes

1. **Understand the full context**: Read the relevant section of build.sh
2. **Check dependencies**: Ensure changes don't break downstream logic
3. **Preserve error handling**: Maintain robust error checking
4. **Test locally first**: Don't rely solely on CI
5. **Document changes**: Update comments and this file
6. **Consider both formats**: Changes may affect .deb and AppImage differently
7. **Architecture awareness**: Test or account for both amd64 and arm64

### Known Limitations

1. **Patching Fragility**: Application patching depends on internal structure of Claude Desktop, which may change with updates
2. **Windows Dependency**: Requires Windows installer as source material
3. **Unofficial Status**: Not officially supported by Anthropic
4. **AppImage Sandbox**: Requires `--no-sandbox` flag for AppImage due to Electron limitations
5. **X11 Hotkeys**: Global hotkeys only work on X11, not Wayland (uses Portal on Wayland)

### Troubleshooting Guide

**Build Failures**:
- Check Node.js version (must be 24+)
- Verify all dependencies installed
- Check download URLs still valid
- Review build logs in `build/` directory

**Runtime Issues**:
- Check launcher logs
- Verify Electron is bundled (.deb) or included (AppImage)
- Test with `--no-sandbox` flag if sandbox issues
- Check Wayland/X11 compatibility

**Patching Failures**:
- Claude Desktop structure may have changed
- Verify pattern matching in sed/grep commands
- Check app.asar.contents structure after extraction
- Review JavaScript file paths in build output

## Useful Commands

```bash
# Analyze build script
shellcheck build.sh scripts/*.sh

# Check spelling
codespell

# Extract and examine app.asar manually
npm install -g @electron/asar
asar extract app.asar app-contents
cd app-contents && find . -name "*.js" | xargs grep "BrowserWindow"

# Test package installation
sudo apt install ./claude-desktop_VERSION_ARCHITECTURE.deb

# Check package contents
dpkg -L claude-desktop

# Run AppImage with debug logging
./claude-desktop-*.AppImage --enable-logging

# Monitor launcher logs
tail -f ~/.cache/claude-desktop-debian/launcher.log  # .deb
tail -f ~/claude-desktop-launcher.log               # AppImage
```

## External Resources

- **Original Inspiration**: [k3d3's claude-desktop-linux-flake](https://github.com/k3d3/claude-desktop-linux-flake)
- **Alternative Implementation**: [emsi's claude-desktop](https://github.com/emsi/claude-desktop)
- **AppImage Documentation**: https://docs.appimage.org/
- **Electron Documentation**: https://www.electronjs.org/docs/latest/
- **Debian Packaging**: https://www.debian.org/doc/manuals/maint-guide/

## Maintenance Checklist

When Claude Desktop releases a new version:

- [ ] Update download URLs if changed
- [ ] Test extraction process
- [ ] Verify patching logic still works
- [ ] Check for new Windows native calls to stub
- [ ] Test on both amd64 and arm64
- [ ] Test both .deb and AppImage
- [ ] Update version references
- [ ] Create git tag and release

---

**Last Updated**: 2025-11-14
**Repository**: https://github.com/aaddrick/claude-desktop-debian
**Maintainer**: Claude Desktop Linux Maintainers
