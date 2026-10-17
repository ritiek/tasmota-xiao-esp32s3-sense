{
  description = "Tasmota firmware for Seeed Studio XIAO ESP32S3 Sense (OV3660, PDM mic, microSD)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    tasmota = {
      url = "github:arendst/Tasmota/v16.0.0";
      flake = false;
    };
    decode-config = {
      url = "github:tasmota/decode-config/v15.6.0";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, tasmota, decode-config }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "aarch64-linux" "x86_64-linux" ];
      env = "tasmota32s3-xiao-sense";

      # Tasmota's espressif32 platform needs pioarduino (PlatformIO fork) >= 6.2.0;
      # nixpkgs only has upstream platformio 6.1.x. Same version Tasmota CI pins.
      pioarduino = pkgs:
        let
          py = pkgs.python3.pkgs;
          core = py.buildPythonApplication rec {
            pname = "pioarduino";
            version = "6.2.0";
            format = "wheel";
            src = pkgs.fetchurl {
              url = "https://files.pythonhosted.org/packages/b7/d6/2a672a9cc93e7aff37f72a7d4a3ad6ad090452f1483063fd1f9d73794104/pioarduino-${version}-py3-none-any.whl";
              sha256 = "12e251cd3ee51e114ab3f12af74196358263a3983253d172b620d13ff9d9804f";
            };
            dependencies = with py; [
              bottle click colorama marshmallow pyelftools pyserial requests semantic-version
              tabulate certifi intelhex rich-click ajsonrpc starlette uvicorn wsproto
            ];
            dontCheckRuntimeDeps = true;
          };
        in
        pkgs.buildFHSEnv {
          pname = "pio";
          inherit (core) version;
          targetPkgs = p: [ core p.zlib p.git p.libusb1 p.ncurses p.udev p.cmake p.ninja p.uv ]
            ++ (with p.python3.pkgs; [ p.python3 setuptools pip wheel virtualenv ]);
          runScript = "pio";
        };
    in
    {
      packages = forAllSystems (system: { pio = pioarduino nixpkgs.legacyPackages.${system}; });

      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = [ (pioarduino pkgs) pkgs.esptool pkgs.rsync pkgs.git ];
            TASMOTA_SRC = "${tasmota}";
            DECODE_CONFIG_SRC = "${decode-config}";
          };
        });

      apps = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          app = name: runtimeInputs: text: {
            type = "app";
            program = pkgs.lib.getExe (pkgs.writeShellApplication { inherit name runtimeInputs text; });
          };
        in {
          # PlatformIO downloads its toolchains/framework into ./build/platformio, so the
          # build is not a pure Nix derivation; the Tasmota source and config are pinned.
          build = app "xiao-build" [ (pioarduino pkgs) pkgs.rsync pkgs.git pkgs.coreutils ] ''
            root=$PWD
            [ -f "$root/firmware/platformio_override.ini" ] || { echo "run from the repo root" >&2; exit 1; }
            src=$root/build/tasmota
            mkdir -p "$src"
            rsync -a --chmod=Du+w,Fu+w ${tasmota}/ "$src"/
            cp "$root/firmware/platformio_override.ini" "$src/platformio_override.ini"
            cp "$root/firmware/user_config_override.h" "$src/tasmota/user_config_override.h"
            export PLATFORMIO_CORE_DIR=$root/build/platformio
            cd "$src"
            # Build safeboot locally instead of downloading a prebuilt one for the factory image.
            pio run -e tasmota32s3-safeboot
            pio run -e ${env}
            mkdir -p "$root/build/out"
            cp build_output/firmware/${env}.bin build_output/firmware/${env}.factory.bin "$root/build/out/"
            ls -l "$root/build/out"
          '';

          # Full serial flash through the host the board is plugged into.
          flash = app "xiao-flash" [ pkgs.openssh ] ''
            host=''${XIAO_HOST:?set XIAO_HOST to the host the board is plugged into}
            img=''${1:-build/out/${env}.factory.bin}
            scp "$img" "$host:xiao/factory.bin"
            # shellcheck disable=SC2016
            ssh "$host" 'nix shell nixpkgs#esptool -c sh -c "sudo \$(command -v esptool) --chip esp32s3 --port /dev/ttyACM0 --baud 921600 write-flash --erase-all 0x0 ~/xiao/factory.bin"'
          '';
        });
    };
}
