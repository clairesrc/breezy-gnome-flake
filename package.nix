{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  unzip,
  # xrDriver runtime deps
  libevdev,
  json_c,
  curl,
  openssl,
  wayland,
  libusb1,
  # UI app deps
  python3,
  gtk4,
  libadwaita,
  gst_all_1,
  glib,
  gobject-introspection,
  # Tools
  desktop-file-utils,
  bash,
  getopt,
  jq,
  coreutils,
  systemd,
}:

let
  version = "2.7.2";

  srcs = {
    x86_64-linux = fetchurl {
      url = "https://github.com/wheaney/breezy-desktop/releases/download/v${version}/breezyGNOME-x86_64.tar.gz";
      hash = "sha256-gNZvjmVBUgIw+IU78sKAoUE4oxU5anZ9xNnIRsviZPk=";
    };
    aarch64-linux = fetchurl {
      url = "https://github.com/wheaney/breezy-desktop/releases/download/v${version}/breezyGNOME-aarch64.tar.gz";
      hash = "sha256-FEDUKZ/bJs6Dst6xjieSLQ7JKGW28pDfx0YfhRJYcgw=";
    };
  };

  pythonEnv = python3.withPackages (ps: with ps; [
    pygobject3
    gst-python
  ]);
in
stdenv.mkDerivation {
  pname = "breezy-gnome";
  inherit version;

  src = srcs.${stdenv.hostPlatform.system}
    or (throw "Unsupported platform: ${stdenv.hostPlatform.system}");

  sourceRoot = "breezy_gnome";

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
    unzip
    gobject-introspection
    glib # for glib-compile-schemas
    desktop-file-utils # for update-desktop-database
  ];

  buildInputs = [
    # xrDriver linked libs
    libevdev
    json_c
    curl
    openssl
    wayland
    libusb1
    stdenv.cc.cc.lib # libstdc++

    # UI app GI deps
    gtk4
    libadwaita
    glib
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
  ];

  dontBuild = true;
  dontConfigure = true;

  # Prevent wrapGAppsHook from wrapping everything; we wrap manually
  dontWrapGApps = true;

  installPhase = ''
    runHook preInstall

    # --- XR Driver ---
    tar -xzf xrDriver.tar.gz

    # Binary
    install -Dm755 xr_driver/bin/xrDriver $out/bin/xrDriver

    # Vendor shared libraries (bundled with the release)
    mkdir -p $out/lib/xr_driver
    for lib in xr_driver/lib/*.so*; do
      # Only copy unique files, skip duplicate symlink targets
      install -Dm644 "$lib" "$out/lib/xr_driver/$(basename $lib)"
    done

    # CLI tool
    install -Dm755 xr_driver/bin/xr_driver_cli $out/bin/xr_driver_cli

    # udev rules
    mkdir -p $out/lib/udev/rules.d
    for rule in xr_driver/udev/*.rules; do
      install -Dm644 "$rule" "$out/lib/udev/rules.d/$(basename $rule)"
    done

    # systemd user service
    mkdir -p $out/lib/systemd/user
    substitute xr_driver/systemd/xr-driver.service $out/lib/systemd/user/xr-driver.service \
      --replace-fail '{ld_library_path}' "$out/lib/xr_driver" \
      --replace-fail '{bin_dir}' "$out/bin"

    # --- GNOME Extension ---
    extensionDir=$out/share/gnome-shell/extensions/breezydesktop@xronlinux.com
    mkdir -p $extensionDir
    unzip -q breezydesktop@xronlinux.com.shell-extension.zip -d $extensionDir

    # Compile extension-local schemas (GNOME Shell loads these directly)
    if [ -d $extensionDir/schemas ]; then
      glib-compile-schemas $extensionDir/schemas
    fi

    # --- GSettings schema ---
    mkdir -p $out/share/glib-2.0/schemas
    cp breezy_ui/data/glib-2.0/schemas/*.gschema.xml $out/share/glib-2.0/schemas/
    glib-compile-schemas $out/share/glib-2.0/schemas

    # --- Desktop application ---
    mkdir -p $out/share/breezydesktop
    cp -r breezy_ui/data/breezydesktop/* $out/share/breezydesktop/

    # Icons
    for size in 64 128 256 1024; do
      src="breezy_ui/data/icons/hicolor/''${size}x''${size}/apps/com.xronlinux.BreezyDesktop.png"
      if [ -f "$src" ]; then
        install -Dm644 "$src" \
          "$out/share/icons/hicolor/''${size}x''${size}/apps/com.xronlinux.BreezyDesktop.png"
      fi
    done

    # Locale files
    if [ -d breezy_ui/data/locale ]; then
      cp -r breezy_ui/data/locale $out/share/
    fi

    # Desktop file
    install -Dm644 breezy_ui/data/applications/com.xronlinux.BreezyDesktop.desktop \
      $out/share/applications/com.xronlinux.BreezyDesktop.desktop
    substituteInPlace $out/share/applications/com.xronlinux.BreezyDesktop.desktop \
      --replace-fail "Exec=breezydesktop" "Exec=$out/bin/breezydesktop"

    # --- Python UI launcher scripts ---
    install -Dm755 breezy_ui/bin/breezydesktop $out/libexec/breezydesktop-unwrapped
    install -Dm755 breezy_ui/bin/virtualdisplay $out/libexec/virtualdisplay-unwrapped

    # Patch the Python scripts to use our Nix paths
    substituteInPlace $out/libexec/breezydesktop-unwrapped \
      --replace-fail "appdir = os.getenv('APPDIR', xdg_data_home)" \
                     "appdir = os.getenv('APPDIR', '$out/share')"
    substituteInPlace $out/libexec/virtualdisplay-unwrapped \
      --replace-fail "appdir = os.getenv('APPDIR', xdg_data_home)" \
                     "appdir = os.getenv('APPDIR', '$out/share')"

    # Custom banner
    if [ -f custom_banner.png ]; then
      install -Dm644 custom_banner.png $out/share/breezydesktop/custom_banner.png
    fi

    runHook postInstall
  '';

  postFixup = ''
    # Set RUNPATH for xrDriver to find vendor libs
    patchelf --set-rpath "$out/lib/xr_driver:${lib.makeLibraryPath [
      libevdev json_c curl openssl wayland libusb1 stdenv.cc.cc.lib
    ]}" $out/bin/xrDriver

    # Wrap xr_driver_cli
    wrapProgram $out/bin/xr_driver_cli \
      --prefix PATH : ${lib.makeBinPath [ bash coreutils getopt jq curl systemd ]}

    # Determine the gsettings schema dir (wrapGAppsHook3 moves it)
    local schemaDir="$out/share/gsettings-schemas/$pname-$version/glib-2.0/schemas"

    # Wrap Python UI apps
    # GSETTINGS_SCHEMA_DIR is prepended so our schema takes priority over
    # any stale schemas in ~/.local/share from a previous manual installation
    makeWrapper ${pythonEnv}/bin/python3 $out/bin/breezydesktop \
      "''${gappsWrapperArgs[@]}" \
      --add-flags "$out/libexec/breezydesktop-unwrapped" \
      --add-flags "--skip-verification" \
      --set APPDIR "$out/share" \
      --set BINDIR "$out/bin" \
      --prefix XDG_DATA_DIRS : "$out/share" \
      --prefix GSETTINGS_SCHEMA_DIR : "$schemaDir" \
      --prefix GI_TYPELIB_PATH : "${lib.makeSearchPath "lib/girepository-1.0" [
        gtk4 libadwaita glib gst_all_1.gstreamer gst_all_1.gst-plugins-base gobject-introspection
      ]}"

    makeWrapper ${pythonEnv}/bin/python3 $out/bin/virtualdisplay \
      "''${gappsWrapperArgs[@]}" \
      --add-flags "$out/libexec/virtualdisplay-unwrapped" \
      --set APPDIR "$out/share" \
      --prefix XDG_DATA_DIRS : "$out/share" \
      --prefix GSETTINGS_SCHEMA_DIR : "$schemaDir" \
      --prefix GI_TYPELIB_PATH : "${lib.makeSearchPath "lib/girepository-1.0" [
        gtk4 libadwaita glib gst_all_1.gstreamer gst_all_1.gst-plugins-base gobject-introspection
      ]}"
  '';

  meta = {
    description = "Virtual XR desktop environment for GNOME using supported XR glasses";
    homepage = "https://github.com/wheaney/breezy-desktop";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    maintainers = [];
    mainProgram = "breezydesktop";
  };
}
