{ config, lib, pkgs, ... }:

let
  cfg = config.programs.breezy-gnome;
in
{
  options.programs.breezy-gnome = {
    enable = lib.mkEnableOption "Breezy Desktop for GNOME, a virtual XR desktop environment using supported XR glasses";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "The breezy-gnome package to use.";
    };

    enableUdevRules = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install udev rules for supported XR glasses hardware.";
    };

    enableSystemdService = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to enable the xr-driver systemd user service.
        When enabled, the service starts automatically on login and
        restarts if it crashes.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Install the package system-wide
    environment.systemPackages = [ cfg.package ];

    # udev rules for XR glasses hardware access
    services.udev.packages = lib.mkIf cfg.enableUdevRules [ cfg.package ];

    # Supplement the upstream udev rules with GROUP assignment.
    # The upstream rules rely on TAG+="uaccess" which depends on logind ACLs;
    # on NixOS the ACLs may not be applied reliably, so we also grant access
    # via the "users" group.
    services.udev.extraRules = lib.mkIf cfg.enableUdevRules ''
      SUBSYSTEM=="usb", ATTRS{idVendor}=="35ca", GROUP="users", MODE="0660"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="1bbb", GROUP="users", MODE="0660"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="04d2", GROUP="users", MODE="0660"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="3318", GROUP="users", MODE="0660"
      KERNEL=="uinput", SUBSYSTEM=="misc", GROUP="users", MODE="0660"
    '';

    # Ensure uinput module is loaded (needed for virtual input devices)
    boot.kernelModules = [ "uinput" ];

    # Install the systemd user service
    systemd.user.services.xr-driver = lib.mkIf cfg.enableSystemdService {
      description = "XR user-space driver";
      after = [ "network.target" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/xrDriver";
        Restart = "always";
        Environment = "LD_LIBRARY_PATH=${cfg.package}/lib/xr_driver";
        # Create config and state directories expected by xr_driver and breezy UI.
        # The upstream setup script creates these, but we skip it on NixOS.
        ConfigurationDirectory = "xr_driver";
        StateDirectory = "xr_driver";
      };
    };
  };
}
