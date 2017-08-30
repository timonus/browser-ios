#!/usr/bin/env sh

./carthage.sh

carthage checkout --no-use-binaries
carthage build --platform ios
