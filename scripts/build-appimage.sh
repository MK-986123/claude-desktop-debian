#!/bin/bash
set -e

# Arguments passed from the main script
VERSION="$1"
ARCHITECTURE="$2"
WORK_DIR="$3" # The top-level build directory (e.g., ./build)
APP_STAGING_DIR="$4" # Directory containing the prepared app files (e.g., ./build/electron-app)
PACKAGE_NAME="$5"
# MAINTAINER and DESCRIPTION might not be directly used by AppImage tools but passed for consistency

echo "--- Starting AppImage Build ---"
echo "Version: $VERSION"
echo "Architecture: $ARCHITECTURE"
echo "Work Directory: $WORK_DIR"
echo "App Staging Directory: $APP_STAGING_DIR"
echo "Package Name: $PACKAGE_NAME"

COMPONENT_ID="io.github.aaddrick.claude-desktop-debian"
# Define AppDir structure path
APPDIR_PATH="$WORK_DIR/${COMPONENT_ID}.AppDir"
rm -rf "$APPDIR_PATH"
mkdir -p "$APPDIR_PATH/usr/bin"
mkdir -p "$APPDIR_PATH/usr/lib"
mkdir -p "$APPDIR_PATH/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$APPDIR_PATH/usr/share/applications"

echo "📦 Staging application files into AppDir..."
# Copy node_modules first to set up Electron directory structure
if [ -d "$APP_STAGING_DIR/node_modules" ]; then
    echo "Copying node_modules from staging to AppDir..."
    cp -a "$APP_STAGING_DIR/node_modules" "$APPDIR_PATH/usr/lib/"
fi

# Install app.asar in Electron's resources directory where process.resourcesPath points
RESOURCES_DIR="$APPDIR_PATH/usr/lib/node_modules/electron/dist/resources"
mkdir -p "$RESOURCES_DIR"
if [ -f "$APP_STAGING_DIR/app.asar" ]; then
    cp -a "$APP_STAGING_DIR/app.asar" "$RESOURCES_DIR/"
fi
if [ -d "$APP_STAGING_DIR/app.asar.unpacked" ]; then
    cp -a "$APP_STAGING_DIR/app.asar.unpacked" "$RESOURCES_DIR/"
fi
echo "✓ Application files copied to Electron resources directory"

# Ensure Electron is bundled within the AppDir for portability
# Check if electron was copied into the staging dir's node_modules
# The actual executable is usually inside the 'dist' directory
BUNDLED_ELECTRON_PATH="$APPDIR_PATH/usr/lib/node_modules/electron/dist/electron"
echo "Checking for executable at: $BUNDLED_ELECTRON_PATH"
if [ ! -x "$BUNDLED_ELECTRON_PATH" ]; then # Check if it exists and is executable
    echo "❌ Electron executable not found or not executable in staging area ($BUNDLED_ELECTRON_PATH)."
    echo "   AppImage requires Electron to be bundled. Ensure the main script copies it correctly."
    exit 1
fi
# Ensure the bundled electron is executable (redundant check, but safe)
chmod +x "$BUNDLED_ELECTRON_PATH"

# --- Create AppRun Script ---
echo "🚀 Creating AppRun script..."
# Note: We use $VERSION and $PACKAGE_NAME from the build script environment here
# They will be embedded into the AppRun script.
cat > "$APPDIR_PATH/AppRun" << EOF
#!/bin/bash
set -e

# Find the location of the AppRun script and the AppImage file itself
APPDIR=\$(dirname "\$0")

# Define log file path in user's home directory
LOG_FILE="\$HOME/claude-desktop-launcher.log"

echo "--- Claude Desktop AppImage Launcher Start ---" >> "\$LOG_FILE"
echo "Timestamp: \$(date)" >> "\$LOG_FILE"
echo "Arguments: \$@" >> "\$LOG_FILE"

export ELECTRON_FORCE_IS_PACKAGED=true

# Detect Wayland session
IS_WAYLAND=false
if [ -n "\$WAYLAND_DISPLAY" ]; then
    IS_WAYLAND=true
    echo "Wayland detected (WAYLAND_DISPLAY=\$WAYLAND_DISPLAY)" >> "\$LOG_FILE"
elif [ "\${XDG_SESSION_TYPE:-}" = "wayland" ]; then
    IS_WAYLAND=true
    echo "Wayland detected (XDG_SESSION_TYPE=wayland)" >> "\$LOG_FILE"
fi

# Path to the bundled Electron executable
ELECTRON_EXEC="\$APPDIR/usr/lib/node_modules/electron/dist/electron"
# App is now in Electron's resources directory
APP_PATH="\$APPDIR/usr/lib/node_modules/electron/dist/resources/app.asar"

# Base command arguments array
# Conditional sandbox for AppImage: check if we can use sandbox
ELECTRON_ARGS=("\$APP_PATH")
NEED_NO_SANDBOX=false
if [ "\$(id -u)" -eq 0 ]; then
    NEED_NO_SANDBOX=true
    echo "Running as root, disabling sandbox" >> "\$LOG_FILE"
else
    # Check if unprivileged user namespaces are available
    CLONE_SETTING="\$(sysctl -n kernel.unprivileged_userns_clone 2>/dev/null || echo 1)"
    if [ "\$CLONE_SETTING" = "0" ]; then
        NEED_NO_SANDBOX=true
        echo "Unprivileged user namespaces disabled, disabling sandbox" >> "\$LOG_FILE"
    fi
fi
if [ "\$NEED_NO_SANDBOX" = true ]; then
    ELECTRON_ARGS+=("--no-sandbox")
fi

# Add Wayland-specific flags (for Electron 38+, --ozone-platform=auto is default)
if [ "\$IS_WAYLAND" = true ]; then
    echo "Adding Wayland compatibility flags" >> "\$LOG_FILE"
    ELECTRON_ARGS+=("--ozone-platform=wayland")
    ELECTRON_ARGS+=("--enable-features=WaylandWindowDecorations,GlobalShortcutsPortal")
    ELECTRON_ARGS+=("--enable-wayland-ime")
    ELECTRON_ARGS+=("--wayland-text-input-version=3")
    echo "Enabled native Wayland support with GlobalShortcuts Portal" >> "\$LOG_FILE"
fi

# Change to HOME directory before exec'ing Electron to avoid CWD permission issues
cd "\$HOME" || exit 1

# Execute Electron with app path, flags, and script arguments
echo "Executing: \$ELECTRON_EXEC \${ELECTRON_ARGS[@]} \$@" >> "\$LOG_FILE"
exec "\$ELECTRON_EXEC" "\${ELECTRON_ARGS[@]}" "\$@" >> "\$LOG_FILE" 2>&1
EOF
chmod +x "$APPDIR_PATH/AppRun"
echo "✓ AppRun script created (with logging to \$HOME/claude-desktop-launcher.log, --no-sandbox, and Wayland support)"

# --- Create Desktop Entry (Bundled inside AppDir) ---
echo "📝 Creating bundled desktop entry..."
# This is the desktop file *inside* the AppImage, used by tools like appimaged
cat > "$APPDIR_PATH/$COMPONENT_ID.desktop" << EOF
[Desktop Entry]
Name=Claude
Exec=AppRun %u
Icon=$COMPONENT_ID
Type=Application
Terminal=false
Categories=Network;Utility;
Comment=Claude Desktop for Linux
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
X-AppImage-Version=$VERSION
X-AppImage-Name=Claude Desktop
EOF
# Also place it in the standard location for tools like appimaged and validation
mkdir -p "$APPDIR_PATH/usr/share/applications"
cp "$APPDIR_PATH/$COMPONENT_ID.desktop" "$APPDIR_PATH/usr/share/applications/"
echo "✓ Bundled desktop entry created and copied to usr/share/applications/"

# --- Copy Icons ---
echo "🎨 Copying icons..."
# Use the 256x256 icon as the main AppImage icon
ICON_SOURCE_PATH="$WORK_DIR/claude_6_256x256x32.png"
if [ -f "$ICON_SOURCE_PATH" ]; then
    # Standard location within AppDir
    cp "$ICON_SOURCE_PATH" "$APPDIR_PATH/usr/share/icons/hicolor/256x256/apps/${COMPONENT_ID}.png"
    # Top-level icon (used by appimagetool) - Should match the Icon field in the .desktop file
    cp "$ICON_SOURCE_PATH" "$APPDIR_PATH/${COMPONENT_ID}.png"
    # Top-level icon without extension (fallback for some tools)
    cp "$ICON_SOURCE_PATH" "$APPDIR_PATH/${COMPONENT_ID}"
    # Hidden .DirIcon (fallback for some systems/tools)
    cp "$ICON_SOURCE_PATH" "$APPDIR_PATH/.DirIcon"
    echo "✓ Icon copied to standard path, top-level (.png and no ext), and .DirIcon"
else
    echo "Warning: Missing 256x256 icon at $ICON_SOURCE_PATH. AppImage icon might be missing."
fi

# --- Create AppStream Metadata ---
echo "📄 Creating AppStream metadata..."
METADATA_DIR="$APPDIR_PATH/usr/share/metainfo"
mkdir -p "$METADATA_DIR"

# Use the package name for the appdata file name (seems required by appimagetool warning)
# Use reverse-DNS for component ID and filename, following common practice
APPDATA_FILE="$METADATA_DIR/${COMPONENT_ID}.appdata.xml" # Filename matches component ID

# Generate the AppStream XML file
# Use MIT license based on LICENSE-MIT file in repo
# ID follows reverse DNS convention
cat > "$APPDATA_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>$COMPONENT_ID</id>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>MIT</project_license>
  <developer id="io.github.aaddrick">
    <name>aaddrick</name>
  </developer>

  <name>Claude Desktop</name>
  <summary>Unofficial desktop client for Claude AI</summary>

  <description>
    <p>
      Provides a desktop experience for interacting with Claude AI, wrapping the web interface.
    </p>
  </description>

  <launchable type="desktop-id">${COMPONENT_ID}.desktop</launchable> <!-- Reference the actual .desktop file -->

  <icon type="stock">${COMPONENT_ID}</icon> <!-- Use the icon name from .desktop -->
  <url type="homepage">https://github.com/aaddrick/claude-desktop-debian</url>
  <screenshots>
      <screenshot type="default">
          <image>https://github.com/user-attachments/assets/93080028-6f71-48bd-8e59-5149d148cd45</image>
      </screenshot>
  </screenshots>
  <provides>
    <binary>AppRun</binary> <!-- Provide the actual binary -->
  </provides>

  <categories>
    <category>Network</category>
    <category>Utility</category>
  </categories>

  <content_rating type="oars-1.1" />

  <releases>
    <release version="$VERSION" date="$(date +%Y-%m-%d)">
      <description>
        <p>Version $VERSION.</p>
      </description>
    </release>
  </releases>

</component>
EOF
echo "✓ AppStream metadata created at $APPDATA_FILE"


# --- Get appimagetool ---
APPIMAGETOOL_PATH=""
if command -v appimagetool &> /dev/null; then
    APPIMAGETOOL_PATH=$(command -v appimagetool)
    echo "✓ Found appimagetool in PATH: $APPIMAGETOOL_PATH"
elif [ -f "$WORK_DIR/appimagetool-x86_64.AppImage" ]; then # Check for specific arch first
    APPIMAGETOOL_PATH="$WORK_DIR/appimagetool-x86_64.AppImage"
    echo "✓ Found downloaded x86_64 appimagetool: $APPIMAGETOOL_PATH"
elif [ -f "$WORK_DIR/appimagetool-aarch64.AppImage" ]; then # Check for other arch
    APPIMAGETOOL_PATH="$WORK_DIR/appimagetool-aarch64.AppImage"
    echo "✓ Found downloaded aarch64 appimagetool: $APPIMAGETOOL_PATH"
else
    echo "🛠️ Downloading appimagetool..."
    # Determine architecture for download URL
    TOOL_ARCH=""
    case "$ARCHITECTURE" in # Use target ARCHITECTURE passed to script
        "amd64") TOOL_ARCH="x86_64" ;;
        "arm64") TOOL_ARCH="aarch64" ;;
        *) echo "❌ Unsupported architecture for appimagetool download: $ARCHITECTURE"; exit 1 ;;
    esac

    APPIMAGETOOL_URL="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${TOOL_ARCH}.AppImage"
    APPIMAGETOOL_PATH="$WORK_DIR/appimagetool-${TOOL_ARCH}.AppImage"

    if wget -q -O "$APPIMAGETOOL_PATH" "$APPIMAGETOOL_URL"; then
        chmod +x "$APPIMAGETOOL_PATH"
        echo "✓ Downloaded appimagetool to $APPIMAGETOOL_PATH"
    else
        echo "❌ Failed to download appimagetool from $APPIMAGETOOL_URL"
        rm -f "$APPIMAGETOOL_PATH" # Clean up partial download
        exit 1
    fi
fi

# --- Build AppImage ---
echo "📦 Building AppImage..."
OUTPUT_FILENAME="${PACKAGE_NAME}-${VERSION}-${ARCHITECTURE}.AppImage"
OUTPUT_PATH="$WORK_DIR/$OUTPUT_FILENAME"

# --- Prepare Update Information (GitHub Actions only) ---
# Check if running in GitHub Actions workflow
if [ "$GITHUB_ACTIONS" = "true" ]; then
    echo "🔄 Running in GitHub Actions - embedding update information for automatic updates..."
    
    # Check if zsyncmake is available (required for generating .zsync files)
    if ! command -v zsyncmake &> /dev/null; then
        echo "⚠️ zsyncmake not found. Installing zsync package for .zsync file generation..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y zsync
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y zsync
        elif command -v zypper &> /dev/null; then
            sudo zypper install -y zsync
        else
            echo "⚠️ Cannot install zsync automatically. .zsync files may not be generated."
        fi
    fi

    # Format: gh-releases-zsync|<username>|<repository>|<tag>|<filename-pattern>
    # Using 'latest' tag to always point to the most recent release
    UPDATE_INFO="gh-releases-zsync|aaddrick|claude-desktop-debian|latest|claude-desktop-*-${ARCHITECTURE}.AppImage.zsync"
    echo "Update info: $UPDATE_INFO"

    # Execute appimagetool with update information
    export ARCH="$ARCHITECTURE"
    echo "Using ARCH=$ARCH" # Debug output
    if "$APPIMAGETOOL_PATH" --updateinformation "$UPDATE_INFO" "$APPDIR_PATH" "$OUTPUT_PATH"; then
        echo "✓ AppImage built successfully with embedded update info: $OUTPUT_PATH"
        # Check if zsync file was generated
        ZSYNC_FILE="${OUTPUT_PATH}.zsync"
        if [ -f "$ZSYNC_FILE" ]; then
            echo "✓ zsync file generated: $ZSYNC_FILE"
            echo "📤 zsync file will be included in release artifacts"
        else
            echo "⚠️ zsync file not generated (zsyncmake may not be installed)"
        fi
    else
        echo "❌ Failed to build AppImage using $APPIMAGETOOL_PATH"
        exit 1
    fi
else
    echo "🏠 Running locally - building AppImage without update information"
    echo "   (Update info and zsync files are only generated in GitHub Actions for releases)"
    
    # Execute appimagetool without update information
    export ARCH="$ARCHITECTURE"
    echo "Using ARCH=$ARCH" # Debug output
    if "$APPIMAGETOOL_PATH" "$APPDIR_PATH" "$OUTPUT_PATH"; then
        echo "✓ AppImage built successfully: $OUTPUT_PATH"
    else
        echo "❌ Failed to build AppImage using $APPIMAGETOOL_PATH"
        exit 1
    fi
fi

echo "--- AppImage Build Finished ---"

exit 0
