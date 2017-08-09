#!/usr/bin/env sh

./carthage.sh

carthage checkout --no-use-binaries
carthage build --platform ios --toolchain com.apple.dt.toolchain.Swift_3_0
