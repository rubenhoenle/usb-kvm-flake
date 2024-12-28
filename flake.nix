{
  description = "USBKVM Nix Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, treefmt-nix, }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
      };

      usbkvmVersion = "0.1.0";

      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixpkgs-fmt.enable = true;
        programs.prettier = {
          enable = true;
          includes = [
            "*.md"
            "*.yaml"
            "*.yml"
          ];
        };
      };

      repo = pkgs.fetchFromGitHub {
        owner = "carrotIndustries";
        repo = "usbkvm";
        rev = "v${usbkvmVersion}";
        hash = "sha256-91Z2Y0O4GeCr7GVBHJ9wnMAgJ4WgxB74KgmJjrzzSNg=";
        fetchSubmodules = true;
      };

      fw-boot = pkgs.stdenv.mkDerivation {
        pname = "usbkvm-fw-boot";
        version = usbkvmVersion;
        src = repo;

        nativeBuildInputs = with pkgs; [
          python3
          gcc-arm-embedded
        ];

        buildPhase = ''
          cd fw/boot
          make
        '';

        installPhase = ''
          mkdir -p $out
          cp -r build $out
        '';
      };

      fw-usbkvm = pkgs.stdenv.mkDerivation {
        pname = "usbkvm-fw-usbkvm";
        version = usbkvmVersion;

        src = repo;

        nativeBuildInputs = with pkgs; [
          python3
          gcc-arm-embedded
        ];

        patchPhase = ''
          patchShebangs fw/usbkvm/write_header.py
        '';

        buildPhase = ''
          cd fw/usbkvm
          ls -lisa
          make
        '';

        installPhase = ''
          mkdir -p $out
          cp -r build $out
        '';
      };

      ms-tools-lib = pkgs.buildGoModule {
        pname = "usbkvm-ms-tools-lib";
        version = usbkvmVersion;

        src = "${repo}/app/ms-tools";
        vendorHash = "sha256-imHpsos7RDpATSZFWRxug67F7VgjRTT1SkLt7cWk6tU=";

        buildInputs = with pkgs; [
          hidapi
          udev
        ];

        prePatch = ''
            rm lib/mslib-test.c
          '';

        buildPhase = ''
            mkdir -p $out/
            go build -C lib/ -o $out/ -buildmode=c-archive mslib.go
          '';

        installPhase = "true";
      };

      app = pkgs.stdenv.mkDerivation rec {
        pname = "usbkvm-app";
        version = usbkvmVersion;
        src = repo;

        buildInputs = with pkgs; [
          gst_all_1.gstreamer
          gtkmm3
          hidapi
        ];

        nativeBuildInputs = with pkgs; [
          go
          pkg-config
          python3
          meson
          ninja
          makeWrapper
        ];

        prePatch = ''
          cp -rf ${fw-boot}/build fw/boot
          cp -rf ${fw-usbkvm}/build fw/usbkvm
        '';

        patches = [
          ./0001-app-meson.build-use-mslib-artifacts-precompiled-by-N.patch
        ];

        MSLIB_A_PRECOMPILED = "${ms-tools-lib}/mslib.a";
        MSLIB_H_PRECOMPILED = "${ms-tools-lib}/mslib.h";

        postPatch = ''
          ${pkgs.envsubst}/bin/envsubst -i app/meson.build -o app/meson.build.patched
          mv app/meson.build.patched app/meson.build
          cd app/
        '';

        postFixup = let
          GST_PLUGIN_PATH = pkgs.lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" (
            with pkgs;
            [
              gst_all_1.gst-plugins-base
              (gst_all_1.gst-plugins-good.override { gtkSupport = true; })
            ]
          );
        in
          pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
            wrapProgram $out/bin/usbkvm --prefix GST_PLUGIN_PATH : ${GST_PLUGIN_PATH}
          '';

        postInstall = ''
          mkdir -p $out/lib/udev/rules.d/
          cp $src/app/70-usbkvm.rules $out/lib/udev/rules.d/
        '';
      };

      app-from-tarball = pkgs.stdenv.mkDerivation {
        name = "usbkvm-app-from-tarball";
        src = builtins.fetchurl {
          url = "https://github.com/carrotIndustries/usbkvm/releases/download/v${usbkvmVersion}/usbkvm-v${usbkvmVersion}.tar.gz";
          sha256 = "01yzhqbrcxah08paxw1flmhw6igab3qwzly4yri6d45xq3vfw6mc";
        };

        postPatch = ''
          cd app/
        '';

        inherit (app)
          buildInputs
          nativeBuildInputs
          postFixup;
      };
    in
      {
        formatter = treefmtEval.config.build.wrapper;
        checks.formatter = treefmtEval.config.build.check self;

        packages = flake-utils.lib.flattenTree {
          default = app;
          fw-boot = fw-boot;
          fw-usbkvm = fw-usbkvm;
          tarball = app-from-tarball;
        };

        devShells.default = pkgs.mkShell {
          name = "usbkvm";

          packages = with pkgs; [
            pkg-config
            gcc
            gdb
            meson
            ninja
            gst_all_1.gstreamer
            go
            gtkmm3
            hidapi
            gst_all_1.gst-plugins-good
            (gst_all_1.gst-plugins-good.override { gtkSupport = true; })
            gst_all_1.gst-plugins-base
            udev
          ];
        };
      }
    );
}
