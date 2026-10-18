#!/bin/bash
# Builds a bootable RenkuOS USB image with software screen rotation.
#
# Downloads the current RenkuOS x86_64 nightly anyboot image, builds the
# rotation-patched app_server and the touch_rotation input filter from the
# exact commit that nightly was built from, and copies them (with the
# settings that switch them on) into the image's home folder.
#
#   ./build-usb-image.sh [options]
#
#   -r, --rotation VALUE  display rotation (default: left_side_up)
#   -t, --touch VALUE     touch screen rotation, if it must differ
#   -o, --output FILE     image to write (default: renkuos-rotation-<build>.img)
#   -w, --work DIR        downloads, sources and build tree (default: ./work)
#   -j, --jobs N          parallel build jobs (default: nproc)
#       --iso FILE        use this anyboot ISO instead of downloading one;
#                         also pass --commit with the commit it was built from
#       --commit SHA      RenkuOS commit to build app_server from
#
# Rotation values: normal, left_side_up, bottom_up, right_side_up
# (or right/inverted/left, 90/180/270: picture turned clockwise).
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
KIT=$REPO/kit
RENKU=RenkuOS/Source
RENKU_GIT=https://github.com/$RENKU.git
BUILDTOOLS_GIT=https://github.com/haiku/buildtools.git
BUILDTOOLS_COMMIT=33d46bf5c300bd34cd07c596431e4545c754ac03	# known good
ARCH=x86_64

ROTATION=left_side_up
TOUCH=
OUT=
WORK=$PWD/work
JOBS=$(nproc)
ISO=
COMMIT=

die() { echo "error: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

while [ $# -gt 0 ]; do
	case "$1" in
	-r|--rotation) ROTATION=$2; shift ;;
	-t|--touch) TOUCH=$2; shift ;;
	-o|--output) OUT=$2; shift ;;
	-w|--work) WORK=$2; shift ;;
	-j|--jobs) JOBS=$2; shift ;;
	--iso) ISO=$2; shift ;;
	--commit) COMMIT=$2; shift ;;
	-h|--help) sed -n '2,/^set -e/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
	*) die "unknown option $1 (see --help)" ;;
	esac
	shift
done

valid_rotation() {
	case "$1" in
	normal|0|right|90|cw|left_side_up|inverted|180|upside_down|bottom_up\
	|left|270|ccw|right_side_up) return 0 ;;
	esac
	return 1
}
valid_rotation "$ROTATION" || die "unknown rotation '$ROTATION'"
[ -z "$TOUCH" ] || valid_rotation "$TOUCH" || die "unknown touch rotation '$TOUCH'"
[ -z "$ISO" ] || [ -n "$COMMIT" ] || die "--iso needs --commit"

missing=
for tool in git gcc g++ make bison flex makeinfo autoheader automake awk wget \
		nasm unzip python3 curl sfdisk sha256sum; do
	command -v $tool > /dev/null || missing="$missing $tool"
done
[ -z "$missing" ] || die "missing tools:$missing (see README.md)"

mkdir -p "$WORK"
WORK=$(cd "$WORK" && pwd)

# --- 1. the nightly image and the commit it was built from ---------------
if [ -z "$ISO" ]; then
	step "Looking up the current RenkuOS nightly"
	curl -fsSL "https://api.github.com/repos/$RENKU/releases/tags/nightly" \
		> "$WORK/nightly.json"
	read -r ISO_URL SUM_URL COMMIT BUILD < <(python3 - "$WORK/nightly.json" "$ARCH" <<'EOF'
import json, re, sys
release = json.load(open(sys.argv[1]))
arch = sys.argv[2]
assets = {a["name"]: a["browser_download_url"] for a in release["assets"]}
iso = [n for n in assets if n.endswith(".iso") and f"-{arch}-" in n]
if len(iso) != 1:
    sys.exit(f"expected one {arch} ISO in the nightly release, found {iso}")
commit = re.search(r"Commit\s*\|\s*([0-9a-f]{40})", release["body"])
build = re.search(r"Build\s*\|\s*`?(build\d+)", release["body"])
if not commit or not build:
    sys.exit("no Commit/Build line in the nightly release notes")
print(assets[iso[0]], assets[iso[0] + ".sha256"], commit[1], build[1])
EOF
	)
	echo "    $BUILD, commit $COMMIT"
	ISO=$WORK/$(basename "$ISO_URL")
	curl -fsSL "$SUM_URL" -o "$ISO.sha256"
	if ! (cd "$WORK" && sha256sum -c --quiet "$ISO.sha256" 2>/dev/null); then
		step "Downloading $(basename "$ISO")"
		curl -fL --progress-bar "$ISO_URL" -o "$ISO.part"
		mv "$ISO.part" "$ISO"
		(cd "$WORK" && sha256sum -c "$ISO.sha256") || die "checksum mismatch"
	fi
else
	[ -f "$ISO" ] || die "no such file: $ISO"
	ISO=$(cd "$(dirname "$ISO")" && pwd)/$(basename "$ISO")
	BUILD=$(basename "$ISO" .iso | grep -o 'build[0-9]*' || echo custom)
fi
OUT=${OUT:-$PWD/renkuos-rotation-$BUILD.img}

# --- 2. sources ----------------------------------------------------------
# fetch_commit <dir> <url> <commit>: get one commit, without history
fetch_commit() {
	if [ ! -d "$1/.git" ]; then
		git init -q "$1"
		git -C "$1" remote add origin "$2"
	fi
	git -C "$1" cat-file -e "$3^{commit}" 2>/dev/null \
		|| git -C "$1" fetch -q --depth 1 origin "$3"
}

step "Fetching buildtools"
fetch_commit "$WORK/buildtools" "$BUILDTOOLS_GIT" "$BUILDTOOLS_COMMIT"
git -C "$WORK/buildtools" checkout -q "$BUILDTOOLS_COMMIT"

step "Fetching RenkuOS source at $COMMIT"
SRC=$WORK/renkuos
fetch_commit "$SRC" "$RENKU_GIT" "$COMMIT"
# Start from a clean checkout of the commit, then apply the rotation patch
# and add the touch filter to the source tree, so jam builds it like any
# other input_server filter.
git -C "$SRC" checkout -q -f -B rotation "$COMMIT"
git -C "$SRC" clean -q -fd src/add-ons/input_server/filters
git -C "$SRC" -c user.name=build -c user.email=build@localhost \
	am -q "$KIT/display-rotation.patch" \
	|| { git -C "$SRC" am --abort; die "display-rotation.patch does not apply to $COMMIT"; }

FILTER=$SRC/src/add-ons/input_server/filters/touch_rotation
mkdir -p "$FILTER"
cp "$KIT/touch_rotation_filter/TouchRotationFilter.cpp" \
	"$KIT/touch_rotation_filter/DisplayRotation.h" "$FILTER/"
cat > "$FILTER/Jamfile" <<'EOF'
SubDir HAIKU_TOP src add-ons input_server filters touch_rotation ;

Addon touch_rotation
	: TouchRotationFilter.cpp
	: be input_server [ TargetLibstdc++ ] [ TargetLibsupc++ ]
	;
EOF
echo "SubInclude HAIKU_TOP src add-ons input_server filters touch_rotation ;" \
	>> "$SRC/src/add-ons/input_server/filters/Jamfile"

# --- 3. build ------------------------------------------------------------
step "Building jam"
JAM_DIR=$(ls -d "$WORK"/buildtools/jam/bin.* 2>/dev/null | head -1 || true)
if [ -z "$JAM_DIR" ] || [ ! -x "$JAM_DIR/jam" ]; then
	make -C "$WORK/buildtools/jam" > "$WORK/jam-build.log" 2>&1 \
		|| die "building jam failed, see $WORK/jam-build.log"
	JAM_DIR=$(ls -d "$WORK"/buildtools/jam/bin.* | head -1)
fi
export PATH=$JAM_DIR:$PATH

GEN=$SRC/generated.$ARCH
mkdir -p "$GEN"
if [ ! -f "$GEN/build/BuildConfig" ]; then
	step "Configuring and building the cross compiler (takes a while, once)"
	(cd "$GEN" && ../configure --cross-tools-source "$WORK/buildtools" \
		--build-cross-tools $ARCH -j"$JOBS") > "$WORK/configure.log" 2>&1 \
		|| { tail -20 "$WORK/configure.log"; die "configure failed, see $WORK/configure.log"; }
fi

step "Building app_server, touch_rotation and bfs_shell"
(cd "$GEN" && jam -q -j"$JOBS" app_server touch_rotation '<build>bfs_shell') \
	> "$WORK/build.log" 2>&1 \
	|| { tail -20 "$WORK/build.log"; die "build failed, see $WORK/build.log"; }

OBJ=$GEN/objects/haiku/$ARCH/release
APP_SERVER=$OBJ/servers/app/app_server
TOUCH_FILTER=$OBJ/add-ons/input_server/filters/touch_rotation/touch_rotation
BFS_SHELL=$(find "$GEN/objects" -path '*/tools/bfs_shell/bfs_shell' -type f | head -1)
for f in "$APP_SERVER" "$TOUCH_FILTER" "$BFS_SHELL"; do
	[ -x "$f" ] || die "build output missing: $f"
done

# --- 4. image ------------------------------------------------------------
step "Writing $OUT"
# The anyboot image's first partition is the BFS system volume
read -r BFS_START BFS_SIZE < <(sfdisk --json "$ISO" | python3 -c '
import json, sys
parts = json.load(sys.stdin)["partitiontable"]["partitions"]
bfs = [p for p in parts if p["type"] == "eb"]
if len(bfs) != 1:
    sys.exit("no BFS partition in the image")
print(bfs[0]["start"], bfs[0]["size"])')

cp --sparse=always "$ISO" "$OUT"

SETTINGS=$WORK/display_rotation
{
	sed '/^display /,$d' "$KIT/config/display_rotation"
	echo "display $ROTATION"
	echo
	if [ -n "$TOUCH" ]; then
		echo "touch $TOUCH"
	else
		echo "# Only needed if the touch screen ends up turned differently from the picture"
		echo "#touch $ROTATION"
	fi
} > "$SETTINGS"

H=/myfs/home
{
	echo "checkfs"
	echo "mkdir -p $H/config/non-packaged/servers"
	echo "mkdir -p $H/config/non-packaged/add-ons/input_server/filters"
	echo "mkdir -p $H/config/settings/launch"
	echo "cp :$APP_SERVER $H/config/non-packaged/servers/app_server"
	echo "cp :$TOUCH_FILTER $H/config/non-packaged/add-ons/input_server/filters/touch_rotation"
	echo "cp :$KIT/config/app_server_rotation $H/config/settings/launch/app_server_rotation"
	echo "cp :$SETTINGS $H/config/settings/display_rotation"
	echo "cp -r :$KIT $H/haiku-rotation"
	echo "ls $H/config/non-packaged/servers"
	echo "ls $H/config/non-packaged/add-ons/input_server/filters"
	echo "ls $H/config/settings/launch"
	echo "sync"
	echo "checkfs"
	echo "quit"
} | "$BFS_SHELL" --start-offset $((BFS_START * 512)) \
	--end-offset $(((BFS_START + BFS_SIZE) * 512)) "$OUT" \
	> "$OUT.log" 2>&1 || true
if grep -qiE "invalid|could not|error|failed|busy|no space" "$OUT.log" \
		|| ! grep -q "touch_rotation" "$OUT.log"; then
	cat "$OUT.log"
	die "copying files into the image failed, see $OUT.log"
fi

(cd "$(dirname "$OUT")" && sha256sum "$(basename "$OUT")") > "$OUT.sha256"

echo
echo "Done: $OUT"
echo "  RenkuOS $BUILD (commit ${COMMIT:0:10}), rotation: display $ROTATION${TOUCH:+, touch $TOUCH}"
echo "  sha256: $(cut -d' ' -f1 "$OUT.sha256")"
echo "Write it to a USB stick as described in README.md (\"Flashing\")."
