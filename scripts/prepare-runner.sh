#!/usr/bin/env bash
set -euo pipefail
test "${GITHUB_ACTIONS:-}" = true

sudo rm -rf /usr/local/lib/android /usr/share/dotnet /opt/ghc \
  /opt/hostedtoolcache/CodeQL /usr/local/.ghcup /usr/local/share/powershell /usr/share/swift

# The Azure mirror delivered cross-GCC packages at only tens of KB/s during
# run 4. Use Ubuntu's own HTTPS archive, and install just the LLVM build needs.
sudo tee /etc/apt/sources.list.d/ubuntu.sources >/dev/null <<'EOF'
Types: deb
URIs: https://archive.ubuntu.com/ubuntu
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: https://security.ubuntu.com/ubuntu
Suites: noble-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF

APT_OPTIONS=(-o Acquire::Retries=2 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30)
sudo apt-get "${APT_OPTIONS[@]}" update -qq
sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
  apt-get "${APT_OPTIONS[@]}" install -y --no-install-recommends --no-upgrade \
  bc bison flex libssl-dev libelf-dev dwarves cpio build-essential patch \
  zip unzip curl git python3 lz4 zstd kmod
sudo apt-get clean
df -h
free -h
