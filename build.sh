#!/bin/zsh

# Build for visionOS Simulator
xcodebuild -project triangle.xcodeproj \
  -scheme triangle \
  -destination 'platform=visionOS Simulator,name=Apple Vision Pro' \
  build

# Optional: Build for Release
# xcodebuild -project triangle.xcodeproj \
#   -scheme triangle \
#   -destination 'platform=visionOS Simulator,name=Apple Vision Pro' \
#   -configuration Release \
#   build
