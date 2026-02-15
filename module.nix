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
      };
    };
  };
}
