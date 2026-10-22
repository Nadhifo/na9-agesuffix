#!/bin/bash
# Build NA9AgeSuffix jadi .deb (tanpa Theos). Jalankan di Mac dengan Xcode + `brew install ldid dpkg`.
set -euo pipefail
cd "$(dirname "$0")"
OUT=build; rm -rf "$OUT"; mkdir -p "$OUT/pkg/DEBIAN" "$OUT/pkg/Library/MobileSubstrate/DynamicLibraries"

xcrun -sdk iphoneos clang -arch arm64 -arch arm64e -dynamiclib -fobjc-arc \
  -miphoneos-version-min=14.0 -framework UIKit -framework Foundation \
  -install_name @rpath/NA9AgeSuffix.dylib \
  -o "$OUT/pkg/Library/MobileSubstrate/DynamicLibraries/NA9AgeSuffix.dylib" Tweak.m
ldid -S "$OUT/pkg/Library/MobileSubstrate/DynamicLibraries/NA9AgeSuffix.dylib"

cp NA9AgeSuffix.plist "$OUT/pkg/Library/MobileSubstrate/DynamicLibraries/"
cp control "$OUT/pkg/DEBIAN/control"
cp "$OUT/pkg/Library/MobileSubstrate/DynamicLibraries/NA9AgeSuffix.dylib" "$OUT/NA9AgeSuffix.dylib"

dpkg-deb --root-owner-group -Zgzip -b "$OUT/pkg" "$OUT/com.na9.agesuffix_1.0.0_iphoneos-arm64e.deb"
echo; echo "Selesai:"; ls -la "$OUT"/*.deb "$OUT"/NA9AgeSuffix.dylib
