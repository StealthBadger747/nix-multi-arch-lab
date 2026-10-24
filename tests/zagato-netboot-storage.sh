#!/usr/bin/env bash
set -euo pipefail
# Pass the evaluated mkfs-containerd script; only temporary regular files are tested.
source_script=${1:?expected evaluated mkfs-containerd script}
work=$(mktemp -d /tmp/zagato-storage-test.XXXXXX)
trap 'rm -rf "$work"' EXIT
sed -e 's|^[[:space:]]*DISK=.*|DISK="$1"|' \
    -e 's/\[ ! -b "$DISK" \]/[ ! -f "$DISK" ]/' "$source_script" > "$work/format.sh"
img="$work/disk.img"
truncate -s 32M "$img"
bash "$work/format.sh" "$img"
before=$(sha256sum "$img")
bash "$work/format.sh" "$img"
[ "$(sha256sum "$img")" = "$before" ]
echo 'PASS: existing filesystem preserved byte for byte'
e2label "$img" unexpected
before=$(sha256sum "$img")
if bash "$work/format.sh" "$img"; then exit 1; fi
[ "$(sha256sum "$img")" = "$before" ]
echo 'PASS: unexpected label refused unchanged'
rm "$img"
truncate -s 32M "$img"
printf '\125\252' | dd of="$img" bs=1 seek=510 conv=notrunc status=none
before=$(sha256sum "$img")
if bash "$work/format.sh" "$img"; then exit 1; fi
[ "$(sha256sum "$img")" = "$before" ]
echo 'PASS: partition signature refused unchanged'
