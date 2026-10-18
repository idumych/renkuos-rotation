# Screen rotation for RenkuOS / Haiku

Software screen rotation for [RenkuOS](https://github.com/RenkuOS/Source)
and Haiku. A patched `app_server` turns the whole desktop, and an
input_server filter turns touch screen input to match. It works with any
graphics driver (`intel_extreme`, VESA, framebuffer), because the rotation
happens when app_server copies its back buffer to the screen.

I made it for the Kootigers 8" pocket laptop, whose panel is mounted in
portrait. Haiku draws its desktop sideways on that panel.

**Status:** this is a personal patch, not part of RenkuOS or Haiku.
- I tested it on real hardware (the Kootigers) with a Haiku nightly
  (hrev60258). On that panel `left_side_up` gives an upright desktop, and
  touch taps land under the finger.
- I tested it in a VirtualBox VM: the desktop draws rotated and the USB
  tablet pointer lines up.
- RenkuOS images are built the same way. The app_server source is the same
  as in Haiku master.

## Contents

| Path | What it is |
|---|---|
| `build-usb-image.sh` | Run on Linux: builds a bootable RenkuOS USB image with rotation |
| `kit/display-rotation.patch` | The app_server patch |
| `kit/touch_rotation_filter/` | input_server filter that rotates touch screen coordinates |
| `kit/config/` | The settings file and the launch_daemon override that starts the patched app_server |
| `kit/build.sh` | Run on RenkuOS/Haiku itself: rebuilds and installs everything on a running system |

## Building the USB image (Linux)

`build-usb-image.sh` does the following:

1. Looks up the current RenkuOS x86_64 **nightly** on GitHub, downloads its
   anyboot ISO and checks the SHA256.
2. Fetches the RenkuOS source at the commit that nightly was built from,
   applies `display-rotation.patch` and adds the touch filter to the source
   tree. app_server has to match the system's libbe, so it is always built
   from the nightly's own commit.
3. Builds Haiku's cross compiler. This happens only on the first run and
   takes about 15 minutes on a 4-core machine. Later runs reuse it.
4. Builds `app_server`, `touch_rotation` and `bfs_shell`.
5. Copies the ISO and uses `bfs_shell` to add these files to its home
   folder:
   - `~/config/non-packaged/servers/app_server`
   - `~/config/non-packaged/add-ons/input_server/filters/touch_rotation`
   - `~/config/settings/launch/app_server_rotation`: starts the patched
     app_server instead of the stock one
   - `~/config/settings/display_rotation`: the rotation setting
   - `~/haiku-rotation/`: a copy of the kit, for rebuilding on the device
     later

### Prerequisites

You need about 10 GB of free disk space, a case-sensitive file system and
these packages:

```sh
# Arch / CachyOS / Manjaro
sudo pacman -S --needed base-devel git bison flex texinfo autoconf automake \
    gawk nasm wget unzip python zlib zstd curl util-linux

# Debian / Ubuntu
sudo apt install build-essential git bison flex texinfo autoconf automake \
    gawk nasm wget unzip python3 zlib1g-dev libzstd-dev curl fdisk
```

### Running it

```sh
git clone https://github.com/idumych/renkuos-rotation.git
cd renkuos-rotation
./build-usb-image.sh                      # rotation left_side_up (Kootigers)
./build-usb-image.sh -r right_side_up     # or choose another rotation
```

A first run took about 22 minutes on a 4-core machine, including the
download. The script writes the image to `renkuos-rotation-<build>.img` in the
current directory, with a `.sha256` file next to it. It keeps downloads,
sources and the build tree in `./work`. Options:

| Option | Meaning |
|---|---|
| `-r`, `--rotation VALUE` | Display rotation (default `left_side_up`; see the values table below) |
| `-t`, `--touch VALUE` | Touch screen rotation, if it must differ from the display |
| `-o`, `--output FILE` | Where to write the image |
| `-w`, `--work DIR` | Work directory (default `./work`) |
| `-j`, `--jobs N` | Parallel build jobs |
| `--iso FILE --commit SHA` | Use an ISO you already have. `SHA` must be the RenkuOS commit the ISO was built from |

Nightlies are replaced every night. Each run of the script picks up the
latest one and rebuilds app_server for it. Only the parts that changed
are rebuilt.

## Flashing

**This erases the stick.** Check the device name with `lsblk` every time,
because names can change when you replug the stick. The examples use
`/dev/sdX`.

```sh
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS      # find the stick
sudo umount /dev/sdX?* 2>/dev/null             # if anything got auto-mounted
sudo wipefs -a /dev/sdX                        # removes any old GPT, including its backup at the end of the disk
sudo dd if=renkuos-rotation-build00054.img of=/dev/sdX bs=4M oflag=direct conv=fsync status=progress
sync && sudo eject /dev/sdX
```

The `wipefs` step matters if the stick ever had a GPT partition table, for
example from another OS installer. GPT keeps a backup copy at the end of
the disk, and some UEFI firmware "repairs" the disk from that backup and
ignores the image's MBR.

The image is about 660 MB. The rest of the stick stays unused.

Boot the stick from the firmware's boot menu. The desktop should come up
already rotated.

## Changing the rotation

The rotation is set in **`~/config/settings/display_rotation`**
(`/boot/home/config/settings/display_rotation`). app_server and the touch
filter read it once, at startup, so **you must reboot after changing it**.

The file holds one line. Comments start with `#`.

```
display left_side_up
```

| Value | Aliases | Picture is turned (clockwise) | Use when the panel is mounted… |
|---|---|---|---|
| `normal` | `0` | not at all | the usual way (turns rotation off) |
| `left_side_up` | `right`, `90`, `cw` | 90° | so its left edge points up (the Kootigers) |
| `bottom_up` | `inverted`, `upside_down`, `180` | 180° | upside down |
| `right_side_up` | `left`, `270`, `ccw` | 270° | so its right edge points up |

The `*_side_up` names are the Linux/DRM panel orientation names; Vitruvian
OS uses `right_side_up` too. **If the desktop comes up upside down, switch to
the other `*_side_up` value.** On the Kootigers, `right_side_up` gives an
upside-down desktop and `left_side_up` gives an upright one.

### On the device

Open Terminal and run one of these:

```sh
StyledEdit ~/config/settings/display_rotation              # edit it in a window
echo "display right_side_up" > ~/config/settings/display_rotation
```

Then reboot (Deskbar menu → Shut down → Restart system).

### Touch screen

The touch filter uses the same rotation as the display, so taps land under
your finger. If the touch controller is mounted differently from the panel
(taps land in mirrored or turned positions), add a `touch` line:

```
display left_side_up
touch   right_side_up
```

Mice and touchpads are not affected. They move the pointer in the
directions you see on the screen, as they should.

### Before flashing

To bake a different setting into a new image, pass `-r` (and `-t` if you
need it):

```sh
./build-usb-image.sh -r bottom_up
```

### Screen resolution

After a 90° or 270° rotation, the Screen preferences list the rotated
resolutions, with width and height swapped. If the picture looks stretched,
pick the rotated resolution there.

### Turning it off

- **Rotation off, patched app_server still running:** `display normal`, then
  reboot.
- **Back to the stock app_server:** delete or rename the launch override,
  then reboot:

  ```sh
  mv ~/config/settings/launch/app_server_rotation ~/app_server_rotation.disabled
  ```

  The stock app_server in `/system` is never changed.
- **If the patched app_server does not start at all:** boot another
  RenkuOS/Haiku stick, mount the volume, and delete
  `home/config/settings/launch/app_server_rotation` on it.

## After updating RenkuOS

app_server must match the installed system libraries. If you update the
system (`pkgman update`), run the kit's build script on the device. It
fetches the source for the revision you are running and rebuilds:

```sh
cd ~/haiku-rotation && sh build.sh
```

You can also build a fresh image from the new nightly on Linux. If the
desktop does not come up after an update, use "Back to the stock
app_server" above.

## Limitations

- The rotation is read at startup. Changing it needs a reboot.
- While rotated, the cursor is drawn in software (no hardware cursor).
- Video overlays are off, so MediaPlayer draws through the normal path.
- BDirectWindow apps fall back to normal drawing or refuse to start.
  Full-screen BWindowScreen games draw straight to the panel, so they appear
  sideways.
- Turn off subpixel anti-aliasing in Appearance, because the subpixel order
  changes with rotation.
- Use 32-bit color. 16-, 15- and 24-bit also work; 8-bit does not.

## License

MIT, like Haiku and RenkuOS. See [LICENSE](LICENSE).
