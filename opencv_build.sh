#/bin/bash

# Used virtualenv
# Execution steps
# 1. $ python3 -m venv .venv
# 2. $ source .venv/bin/activate
# 3. $ bash opencv_build.sh

# Python 3.9 or later is recommended
./.venv/bin/python platforms/ios/build_framework.py ios \
`cat ./opencv_option.txt` \
--build_only_specified_archs True \
--iphoneos_archs arm64 \
--iphoneos_deployment_target 16.0

./.venv/bin/python platforms/ios/build_framework.py ios_simulator \
`cat ./opencv_option.txt` \
--build_only_specified_archs True \
--iphonesimulator_archs 'arm64,x86_64' \
--iphoneos_deployment_target 16.0

xcodebuild -create-xcframework  \
-framework ios/opencv2.framework \
-framework ios_simulator/opencv2.framework \
-output opencv2.xcframework
