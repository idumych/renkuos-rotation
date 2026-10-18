# Screen rotation for RenkuOS / Haiku (personal patch)

Turns the whole desktop in software, like "right side up" on Vitruvian OS.
Works with `intel_extreme`, VESA and framebuffer drivers alike.

## Install (on the RenkuOS or Haiku machine)

A USB image built with `build-usb-image.sh` already has all of this
installed; use these steps to rebuild after a system update.

1. Install the build tools if you don't have them: `pkgman install jam`
   (git and gcc are part of a normal Haiku install).
2. Copy this folder to the machine and run:

       sh build.sh

   It fetches the source for the revision you are running (from
   `uname -v`: a RenkuOS `build…-g<commit>` or a Haiku hrev tag),
   applies `display-rotation.patch`, builds only `app_server`, and
   installs:
   - `~/config/non-packaged/servers/app_server` (patched app_server)
   - `~/config/settings/launch/app_server_rotation` (starts it instead of the stock one)
   - `~/config/settings/display_rotation` (the setting, defaults to `left_side_up`)
   - the `touch_rotation` input_server filter (only matters with a touch screen)

   On R1/beta6 use `sh build.sh r1beta6` if `uname -v` doesn't give an hrev
   tag. The patch does not apply to beta5 or older.
3. Reboot.

## Changing it

Edit `~/config/settings/display_rotation`, then reboot:

    display left_side_up      # or right_side_up, bottom_up, normal
                              # or right / inverted / left (clockwise 90/180/270)

If the desktop is upside down, use the other side. Screen preferences then
lists rotated resolutions (e.g. 1280×720 instead of 720×1280).

## Going back

Delete `~/config/settings/launch/app_server_rotation` and reboot; the stock
app_server is untouched. If the patched one won't start at all, boot from a
Haiku USB stick and delete that file from your home folder.

## Limitations

- Rotation is read once at startup; changes need a reboot.
- The cursor is drawn in software while rotated (no hardware cursor).
- Video overlays are off, so MediaPlayer draws through the normal path.
- BDirectWindow apps fall back or refuse to start; full-screen BWindowScreen
  games draw straight to the panel and will be sideways.
- Turn off subpixel anti-aliasing in Appearance (the subpixel order changes).
- Use 32-bit color (16/15/24-bit also work, 8-bit doesn't).
- After a Haiku update, re-run `build.sh`: app_server must match the
  installed system.
