{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, treefmt-nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        treefmtEval = treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixpkgs-fmt.enable = true;
          programs.prettier = {
            enable = true;
            includes = [ "*.md" "*.yaml" "*.yml" ];
          };
        };

        repo = pkgs.fetchFromGitHub {
          owner = "carrotIndustries";
          repo = "usbkvm";
          fetchSubmodules = true;
          rev = "v0.0.19";
          hash = "sha256-ZYS4strz85jR20kFtUpfqYhgb4p+G8VsVfJwO8sF5FM=";
        };

        fw-boot = pkgs.stdenv.mkDerivation {
          name = "usbkvm-fw-boot";
          src = repo;
          nativeBuildInputs = with pkgs; [
            python3
            gcc-arm-embedded-9
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
          name = "usbkvm-fw-usbkvm";
          src = repo;
          nativeBuildInputs = with pkgs; [
            python3
            gcc-arm-embedded-9
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
          name = "usbkvm-ms-tools-lib";

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

        app = pkgs.stdenv.mkDerivation {
          name = "usbkvm-app";
          src = repo;
          buildInputs = with pkgs; [
            #gstreamer
            gst_all_1.gstreamer
            #gtkmm 3.0
            gtkmm3
            #gst-plugin-gtk
            #gst-plugins-good
            gst_all_1.gst-plugins-good
            hidapi
            go

            pkg-config
            python3
            ms-tools-lib
          ];

          nativeBuildInputs = with pkgs; [
            meson
            ninja
          ];

          prePatch = ''
            cp -rf ${fw-boot}/build fw/boot
            cp -rf ${fw-usbkvm}/build fw/usbkvm
          '';

          patches = [
            ./0001-app-meson.build-use-mslib-artifacts-precompiled-by-N.patch
          ];

          postPatch = ''
            ${pkgs.envsubst}/bin/envsubst -i app/meson.build -o app/meson.build.patched
            mv app/meson.build.patched app/meson.build
            cd app/
          '';

          MSLIB_A_PRECOMPILED = "${ms-tools-lib}/mslib.a";
          MSLIB_H_PRECOMPILED = "${ms-tools-lib}/mslib.h";

          # buildPhase = ''
          #   # ls -lisa .
          #   # cd app
          #   # mkdir build
          #   ${pkgs.meson}/bin/meson setup build
          #   #${pkgs.meson}/bin/meson compile -C build
          # '';
          # installPhase = ''
          #   mkdir -p $out/bin
          #   #cp app/build/usbkvm $out/bin
          # '';
        };

        app-from-tarball = pkgs.stdenv.mkDerivation {
          name = "usbkvm-app-from-tarball";
          src = builtins.fetchurl {
        url = "https://github.com/carrotIndustries/usbkvm/releases/download/v0.1.0/usbkvm-v0.1.0.tar.gz";
        sha256 = "01yzhqbrcxah08paxw1flmhw6igab3qwzly4yri6d45xq3vfw6mc";
      };
          buildInputs = with pkgs; [
            #gstreamer
            gst_all_1.gstreamer
            #gtkmm 3.0
            gtkmm3
            #gst-plugin-gtk
            #gst-plugins-good
            gst_all_1.gst-plugins-good
            hidapi
            go

            pkg-config
            python3

            gst_all_1.gstreamer gtkmm3 meson hidapi go gst_all_1.gst-plugins-good gtk3 cmake pkg-config qemu udev ninja
          ];
          nativeBuildInputs = with pkgs; [
            cmake
          ];
          dontUseCmakeConfigure = true;
          buildPhase = ''
            ls -lisa .

            #cd app
            mkdir build
            ${pkgs.meson}/bin/meson build
            #${pkgs.meson}/bin/meson compile -C build
          '';
          installPhase = ''
            mkdir -p $out/bin
            #cp app/build/usbkvm $out/bin
          '';
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
      }
    );
}
