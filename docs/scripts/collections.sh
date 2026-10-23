#!/bin/bash
F=(-package-name SwiftCollections -enable-upcoming-feature MemberImportVisibility -enable-experimental-feature BuiltinModule -enable-experimental-feature Lifetimes -enable-experimental-feature InoutLifetimeDependence -enable-experimental-feature AddressableParameters -enable-experimental-feature AddressableTypes -enable-experimental-feature SuppressedAssociatedTypesWithDefaults)
for v in "5.0:macOS 10.14.4" "5.1:macOS 10.15" "5.6:macOS 12.3" "5.7:macOS 13.0" "5.8:macOS 13.3" "5.9:macOS 14.0" "5.10:macOS 14.4" "6.0:macOS 15.0" "6.1:macOS 15.4" "6.2:macOS 26.0" "6.3:macOS 26.4" "6.4:macOS 9999" "6.5:macOS 9999"; do F+=(-enable-experimental-feature "AvailabilityMacro=SwiftStdlib ${v%%:*}: ${v#*:}"); done
/tmp/deep-review/embedded-20261020/work/l2/mod.sh InternalCollectionsUtilities /Users/draganm4/Projects/dra8an/swift-collections/Sources/InternalCollectionsUtilities "${F[@]}"
/tmp/deep-review/embedded-20261020/work/l2/mod.sh ContainersPreview /Users/draganm4/Projects/dra8an/swift-collections/Sources/ContainersPreview "${F[@]}"
/tmp/deep-review/embedded-20261020/work/l2/mod.sh DequeModule /Users/draganm4/Projects/dra8an/swift-collections/Sources/DequeModule "${F[@]}"
/tmp/deep-review/embedded-20261020/work/l2/mod.sh OrderedCollections /Users/draganm4/Projects/dra8an/swift-collections/Sources/OrderedCollections "${F[@]}"
/tmp/deep-review/embedded-20261020/work/l2/mod.sh _RopeModule /Users/draganm4/Projects/dra8an/swift-collections/Sources/RopeModule "${F[@]}" -swift-version 5
echo ALL DONE
