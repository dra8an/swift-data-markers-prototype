#!/bin/bash
F=(-package-name SwiftFoundation -I /tmp/deep-review/embedded-20261020/src/Sources/_FoundationCShims/include -enable-experimental-feature VariadicGenerics -enable-experimental-feature Lifetimes -enable-experimental-feature AddressableTypes -enable-experimental-feature AllowUnsafeAttribute -enable-experimental-feature BuiltinModule -enable-experimental-feature AccessLevelOnImport -enable-experimental-feature StrictConcurrency -enable-experimental-feature ImportMacroAliases -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility -DDATA_LEGACY_ABI)
for v in 6.0.2 6.1 6.2 6.3 6.4 6.4.2 6.5; do F+=(-enable-experimental-feature "AvailabilityMacro=FoundationPreview $v:macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26"); done
F+=("$@")
/tmp/deep-review/embedded-20261020/work/l2/mod.sh FoundationEssentials ${FE_DIR:-/tmp/deep-review/embedded-20261020/src/Sources/FoundationEssentials} "${F[@]}"
echo ALL DONE
