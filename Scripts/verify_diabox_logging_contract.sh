#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

required_patterns=(
  "Bubble complete packet"
  "Sensor gate crc"
  "Sensor gate state"
  "DiaBox current filter"
  "DiaBox history filter"
  "DiaBox storage candidate"
  "CGM glucose store completed"
  "CGM glucose store failed"
)

for pattern in "${required_patterns[@]}"; do
  if ! rg -q "$pattern" LibreTransmitter Loop; then
    echo "Missing log marker: $pattern" >&2
    exit 1
  fi
done

echo "DiaBox logging contract passed"
