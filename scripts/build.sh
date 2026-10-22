#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-debug}"

swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION"
BIN_DIR="$(swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION" --show-bin-path)"
printf '构建完成：%s/AgentPet\n' "$BIN_DIR"
