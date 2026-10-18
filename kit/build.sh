#!/bin/sh
# Builds the rotation-patched app_server and the touch filter on Haiku,
# and installs them into ~/config/non-packaged. Run it from this folder.
#
#   sh build.sh            build for the Haiku you are running right now
#   sh build.sh r1beta6    build from a given branch or hrev tag instead
set -e

KIT=$(cd "$(dirname "$0")" && pwd)
SRC=${HAIKU_SRC:-$HOME/haiku-src}
ARCH=$(getarch)

# app_server must match the installed libbe, so build the same revision
if [ -n "$1" ]; then
	REV=$1
else
	REV=$(uname -v | awk '{print $1}')	# e.g. hrev59950
fi
echo "Building app_server from $REV for $ARCH"

# RenkuOS reports e.g. build00054-g8abe804: fetch that commit from its GitHub
case "$REV" in
build*-g*)
	if [ ! -d "$SRC/.git" ]; then
		mkdir -p "$SRC" && cd "$SRC" && git init -q \
			&& git remote add origin https://github.com/RenkuOS/Source.git \
			&& git fetch --filter=blob:none origin main \
			&& git checkout -q "${REV##*-g}"
	fi
	;;
esac

# hrev tags exist only on Haiku's own git, not on the GitHub mirror
if [ ! -d "$SRC/.git" ]; then
	git clone --depth 1 --branch "$REV" https://review.haiku-os.org/haiku "$SRC" \
		|| { mkdir -p "$SRC" && cd "$SRC" && git init -q \
			&& git remote add origin https://review.haiku-os.org/haiku \
			&& git fetch --depth 1 origin tag "$REV" \
			&& git checkout -q "$REV"; }
fi

cd "$SRC"
if ! git log -1 --format=%s | grep -q "software display rotation"; then
	git -c user.name=local -c user.email=local@localhost \
		am "$KIT/display-rotation.patch"
fi

mkdir -p "generated.$ARCH"
cd "generated.$ARCH"
[ -f build/BuildConfig ] || ../configure --target-arch "$ARCH"
jam -q app_server

BIN=$(find objects -path '*/servers/app/app_server' -type f | head -1)
[ -n "$BIN" ] || { echo "app_server binary not found"; exit 1; }

DEST=$(finddir B_USER_NONPACKAGED_DIRECTORY)/servers
mkdir -p "$DEST"
cp "$BIN" "$DEST/app_server"
echo "Installed $DEST/app_server"

# touch screen filter
cd "$KIT/touch_rotation_filter"
make install
echo "Installed touch_rotation input filter"

# settings, unless already there
SETTINGS=$(finddir B_USER_SETTINGS_DIRECTORY)
[ -f "$SETTINGS/display_rotation" ] \
	|| cp "$KIT/config/display_rotation" "$SETTINGS/display_rotation"
mkdir -p "$SETTINGS/launch"
cp "$KIT/config/app_server_rotation" "$SETTINGS/launch/app_server_rotation"

echo
echo "Done. Edit $SETTINGS/display_rotation if needed, then reboot."
