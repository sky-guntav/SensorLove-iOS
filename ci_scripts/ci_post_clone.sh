#!/bin/sh
# Makes the Xcode project from project.yml with XcodeGen (the project is not kept in the repo).
# Xcode Cloud runs this file by its name right after cloning.
set -e
cd "${CI_PRIMARY_REPOSITORY_PATH:-$(dirname "$0")/..}"

# NDI (VIDEO, DEPTH): this team's builds fetch NDI's SDK for Apple from NDI itself and check it is the very file chosen. A new one
# stops the build: read its licence, then set its SHA-256 here. Anyone else's build goes without NDI (project.yml: #if NDI). The
# SDK never goes in the repo (its licence): headers and libndi_ios.a land in Vendor/NDI, its third-party licences in WebUI (ABOUT).
NDI_PKG=https://downloads.ndi.tv/SDK/NDI_SDK_Mac/Install_NDI_SDK_v6_Apple.pkg
NDI_SHA256=5aa101a01b00494724c60b7e1e15b5d1743bf9c68b61739c22ac54932dde95fb   # NDI 6.3.2.0, 2026-04-13 (225,463,783 bytes)
NDI_BRIDGE= NDI_INCLUDE= NDI_LDFLAGS= NDI_FLAG=
# this team's build: the app's bundle ID, which no other team can build (Xcode Cloud's CI_TEAM_ID is its own ID, not BNQTTX5CD8)
if [ "$CI_BUNDLE_ID" = com.skyfly.SensorLove ] && [ -n "$NDI_SHA256" ]; then
  curl -fsSL "$NDI_PKG" -o /tmp/ndi.pkg
  echo "$NDI_SHA256  /tmp/ndi.pkg" | shasum -a 256 -c -
  rm -rf /tmp/ndi && pkgutil --expand-full /tmp/ndi.pkg /tmp/ndi
  sdk=$(find /tmp/ndi -type d -name "NDI SDK for Apple" | head -n 1)
  mkdir -p Vendor/NDI/lib && cp -R "$sdk/include" Vendor/NDI/ && cp "$sdk/lib/iOS/libndi_ios.a" Vendor/NDI/lib/
  cp "$sdk/licenses/libndi_licenses.txt" WebUI/ndi-licenses.txt   # its open-source parts' licences, which go with the binary: ABOUT shows them
  lipo -info Vendor/NDI/lib/libndi_ios.a
  # once, in the log: the calls Apple asks a reason for (PrivacyInfo.xcprivacy), and any cryptography (export compliance)
  nm -u Vendor/NDI/lib/libndi_ios.a 2>/dev/null | grep -E '_(mach_absolute_time|mach_continuous_time|clock_gettime|stat|fstat|lstat|fstatat|statfs|fstatfs|getattrlist|NSFileSystemFreeSize|systemUptime)$|SSL|CCCrypt|SecKey|EVP_' | sort -u || true
  NDI_BRIDGE=App/NDI.h NDI_INCLUDE='$(SRCROOT)/Vendor/NDI/include' NDI_FLAG=NDI
  NDI_LDFLAGS='-L$(SRCROOT)/Vendor/NDI/lib -lndi_ios -lc++ -lz -framework Accelerate -framework AudioToolbox -framework CoreMedia -framework CoreVideo -framework VideoToolbox'   # what libndi_ios.a asks for (its undefined symbols, read 2026-10-15)
fi
export NDI_BRIDGE NDI_INCLUDE NDI_LDFLAGS NDI_FLAG

# DEPTH's DETAIL AI: Depth Anything V2 Small, Apple's Core ML conversion (Apache-2.0), from Hugging Face at one fixed revision,
# each file checked (a changed file stops the build). Xcode builds it into the app (project.yml: Models). Not in the repo (49 MB);
# a build that cannot fetch it goes without (App/Detail.swift: Detail.built)
DA=https://huggingface.co/apple/coreml-depth-anything-v2-small/resolve/cfef6f6f2a70783dedc0bfae40cecbc2052285d3/DepthAnythingV2SmallF16.mlpackage
DM=Models/DepthAnythingV2SmallF16.mlpackage
rm -rf Models && mkdir -p "$DM/Data/com.apple.CoreML/weights"
if curl -fsSL "$DA/Manifest.json" -o "$DM/Manifest.json" && curl -fsSL "$DA/Data/com.apple.CoreML/model.mlmodel" -o "$DM/Data/com.apple.CoreML/model.mlmodel" \
   && curl -fsSL "$DA/Data/com.apple.CoreML/weights/weight.bin" -o "$DM/Data/com.apple.CoreML/weights/weight.bin"; then
  shasum -a 256 -c - <<EOF
2883ae290c48fe916dc5ececac03a7d847fa277165a49ef5652fa1d2b9cb55f7  $DM/Manifest.json
44ac97a3efcfd52113183fb2862ff59cd0368e9ec2e30a90a54980dd11407042  $DM/Data/com.apple.CoreML/model.mlmodel
fa60d9b6a155734f59029ebb882fd54e549bfaee3539c1a9cbd2cbbab64a0fed  $DM/Data/com.apple.CoreML/weights/weight.bin
EOF
else
  echo "DETAIL: the model did not download; this build goes without it"; rm -rf Models
fi

# a ready release, not brew: brew updates itself first, which took minutes
curl -fsSL https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip -o /tmp/xcodegen.zip
unzip -q -o /tmp/xcodegen.zip -d /tmp
BUILD_NUMBER="${CI_BUILD_NUMBER:-$BUILD_NUMBER}" /tmp/xcodegen/bin/xcodegen generate
