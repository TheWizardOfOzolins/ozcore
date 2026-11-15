#!/bin/bash
# Set up Materia

set -ouex pipefail

install -d -m 0700 /etc/materia

# renovate: datasource=github-releases depName=stryan/materia
MATERIA_VERSION=v0.8.1
case "$(uname -m)" in
  x86_64)  MATERIA_ARCH=amd64 ;;
  aarch64) MATERIA_ARCH=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

MATERIA_TARBALL="materia-${MATERIA_VERSION}-${MATERIA_ARCH}.tar.gz"
MATERIA_URL="https://github.com/stryan/materia/releases/download/${MATERIA_VERSION}"
WORKDIR=$(mktemp -d)
cd "$WORKDIR"

curl -fsSL -O "${MATERIA_URL}/${MATERIA_TARBALL}"
curl -fsSL -O "${MATERIA_URL}/SHA256SUMS"
curl -fsSL -O "${MATERIA_URL}/SHA256SUMS.cosign.bundle"

# The release signs SHA256SUMS with the maintainer's key (build_files/keys/materia.pub);
# checking the tarball against the verified sums means no per-version checksums live in this repo
/ctx/tools/cosign verify-blob \
  --key /ctx/keys/materia.pub \
  --bundle SHA256SUMS.cosign.bundle \
  SHA256SUMS
# Match the exact filename so a missing entry fails instead of being skipped
grep -E "^[0-9a-f]{64}  ${MATERIA_TARBALL}\$" SHA256SUMS | sha256sum -c -

tar -xzf "$MATERIA_TARBALL"
install -m 0755 bin/materia /usr/bin/materia
install -d /usr/share/man/man1 /usr/share/man/man5
install -m 0644 man/man1/*.1 /usr/share/man/man1/
install -m 0644 man/man5/*.5 /usr/share/man/man5/

cd /
rm -rf "$WORKDIR"

systemctl enable materia-update.timer
