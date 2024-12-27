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
            #python3 
            #gcc-arm-embedded-9
          ];
          buildInputs = with pkgs; [
            python3 
            gcc-arm-embedded-9
          ];
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
          ];
          nativeBuildInputs = with pkgs; [
            cmake
          ];
          buildPhase = ''
            ls -lisa .

            cp ${fw-boot}/build fw/boot
            cp ${fw-usbkvm}/build fw/usbkvm

            cd app
            mkdir build
            ${pkgs.meson}/bin/meson setup build
            #${pkgs.meson}/bin/meson compile -C build
          '';
          installPhase = ''
            mkdir -p $out/bin
            #cp app/build/usbkvm $out/bin
          '';
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
