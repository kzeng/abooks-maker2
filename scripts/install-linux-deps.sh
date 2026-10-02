#!/usr/bin/env bash
set -euo pipefail

if ! command -v sudo >/dev/null 2>&1; then
  echo 'sudo is required to install Ubuntu system dependencies.' >&2
  exit 1
fi

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  clang \
  cmake \
  ninja-build \
  pkg-config \
  libgtk-3-dev \
  liblzma-dev \
  libglu1-mesa \
  xz-utils \
  zip \
  unzip \
  curl \
  git \
  ffmpeg \
  android-sdk-platform-tools-common

sudo udevadm control --reload-rules
sudo udevadm trigger
echo 'Linux build dependencies and Android USB rules are installed.'
