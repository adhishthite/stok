#!/bin/bash
# Copyright 2026 Adhish Thite
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
app="${1:?Pass the built Stok.app path}"
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/build/package"
codesign --verify --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$root/build/package/Stok.zip"
echo "Created $root/build/package/Stok.zip (local development build; not notarized)"
