{
  description = "Breezy Desktop for GNOME - virtual XR desktop environment for supported XR glasses on Linux";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      packages = forAllSystems (system: {
        breezy-gnome = (pkgsFor system).callPackage ./package.nix { };
        default = self.packages.${system}.breezy-gnome;
      });

      nixosModules = {
        breezy-gnome = import ./module.nix;
        default = self.nixosModules.breezy-gnome;
      };

      checks = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in
        {
          # Verify the package builds
          package = self.packages.${system}.breezy-gnome;

          # NixOS module integration test (headless, no full GNOME needed)
          module-test = pkgs.testers.runNixOSTest {
            name = "breezy-gnome-module";

            nodes.machine = { pkgs, ... }: {
              imports = [ self.nixosModules.breezy-gnome ];
              programs.breezy-gnome.enable = true;
            };

            testScript = let
              pkg = self.packages.${system}.breezy-gnome;
            in ''
              machine.wait_for_unit("multi-user.target")

              # Verify binaries are in PATH
              machine.succeed("which xrDriver")
              machine.succeed("which xr_driver_cli")
              machine.succeed("which breezydesktop")
              machine.succeed("which virtualdisplay")

              # Verify udev rules are installed
              machine.succeed("test -f /etc/udev/rules.d/70-viture-xr.rules")
              machine.succeed("test -f /etc/udev/rules.d/70-xreal-xr.rules")
              machine.succeed("test -f /etc/udev/rules.d/70-rokid-xr.rules")
              machine.succeed("test -f /etc/udev/rules.d/70-rayneo-xr.rules")
              machine.succeed("test -f /etc/udev/rules.d/70-uinput-xr.rules")

              # Verify the uinput kernel module is loaded
              machine.succeed("lsmod | grep uinput")

              # Verify the GNOME extension files exist in the package
              machine.succeed(
                  "test -f ${pkg}/share/gnome-shell/extensions/breezydesktop@xronlinux.com/metadata.json"
              )

              # Verify the GSettings schema is compiled
              machine.succeed(
                  "find ${pkg}/share/gsettings-schemas -name gschemas.compiled | grep -q ."
              )

              # Verify the desktop file is installed
              machine.succeed(
                  "test -f ${pkg}/share/applications/com.xronlinux.BreezyDesktop.desktop"
              )

              # Verify the systemd user service unit is installed
              machine.succeed("test -f /etc/systemd/user/xr-driver.service")

              # Verify the service file references valid paths
              machine.succeed("grep '${pkg}/bin/xrDriver' /etc/systemd/user/xr-driver.service")

              # Verify xrDriver can start without segfaulting (timeout = runs ok)
              machine.succeed("timeout 2 xrDriver || test $? -eq 124")
            '';
          };
        }
      );

      # Development shell for working on this flake
      devShells = forAllSystems (system: {
        default = (pkgsFor system).mkShell {
          packages = with (pkgsFor system); [
            nixpkgs-fmt
          ];
        };
      });
    };
}
