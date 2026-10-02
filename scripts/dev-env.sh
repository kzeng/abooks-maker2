#!/usr/bin/env bash
# Source this file before local Flutter/Android development.
export FLUTTER_ROOT="$HOME/.local/flutter"
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="$HOME/.local/java/jdk-17.0.19+10"
export PATH="$FLUTTER_ROOT/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$JAVA_HOME/bin:$PATH"
export NO_PROXY="127.0.0.1,localhost,::1,${NO_PROXY:-}"
export no_proxy="$NO_PROXY"
