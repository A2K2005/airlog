# Optional: source tool/env.sh after setting your SDK paths.
export FLUTTER_SUPPRESS_ANALYTICS=true
if [ -n "${FLUTTER_ROOT:-}" ]; then export PATH="$FLUTTER_ROOT/bin:$PATH"; fi
if [ -n "${JAVA_HOME:-}" ]; then export PATH="$JAVA_HOME/bin:$PATH"; fi
if [ -n "${ANDROID_HOME:-}" ]; then
  export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$PATH"
fi
