#!/bin/bash

set -euo pipefail

CLT_FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

if [[ -d "$CLT_FRAMEWORKS/Testing.framework" ]]; then
    exec swift test --triple "$(uname -m)-apple-macosx14.0" \
        --disable-xctest --enable-swift-testing \
        -Xswiftc -F -Xswiftc "$CLT_FRAMEWORKS" \
        -Xlinker -F -Xlinker "$CLT_FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$CLT_FRAMEWORKS"
fi

exec swift test
