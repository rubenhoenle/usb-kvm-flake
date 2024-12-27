git submodule update --init --recursive

nix-shell -p python3 gcc-arm-embedded-9

cd fw/boot/
make

cd fw/usbkvm/
make

----

nix-shell -p gst_all_1.gstreamer gtkmm3 meson hidapi go gst_all_1.gst-plugins-good gtk3 cmake pkg-config qemu udev ninja

cd app
meson setup build
meson compile -C build
