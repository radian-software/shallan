#!/usr/bin/env bash

set -euo pipefail

: "${ARCH}"

root="$(git rev-parse --show-toplevel)"

server="${root}/server"
out="${server}/out"
packaging="${server}/packaging"

ver="$(< "${out}/version")"

pkg="$(mktemp -d)"
trap "rm -rf '$(printf '%q' "${pkg}")'" EXIT

mkdir -p "${pkg}/usr/sbin"
cp -T "${out}/shalland-linux-${ARCH}" "${pkg}/usr/sbin/shalland"

mkdir -p "${pkg}/usr/share/man/man8"
cp -T "${packaging}/shalland.8" "${pkg}/usr/share/man/man8/shalland.8"

mkdir -p "${pkg}/lib/systemd/system"
cp -T "${packaging}/shallan.service" "${pkg}/lib/systemd/system/shallan.service"

mkdir -p "${pkg}/DEBIAN"
cp -T "${packaging}/postinst" "${pkg}/DEBIAN/postinst"
cp -T "${packaging}/postrm" "${pkg}/DEBIAN/postrm"
sed "s/VERSION/${ver}/; s/ARCH/${ARCH}/" < "${packaging}/control" > "${pkg}/DEBIAN/control"

fakeroot dpkg-deb --build "${pkg}" "${out}/shalland-${ARCH}-${ver}.deb"
ln -sf "shalland-${ARCH}-${ver}.deb" "shalland-${ARCH}.deb"
