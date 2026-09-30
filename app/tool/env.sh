# Airlog shell setup for Git Bash (or any POSIX shell). Source it:
#   . tool/env.sh
#
# Respects SDK and cache locations that are already set. Where one is unset
# and its D:\dev default exists, it defaults there: C: is low on space, so
# caches never default to C:. Installs nothing. See tool/setup_toolchain.md.
export FLUTTER_SUPPRESS_ANALYTICS=true
if [ -z "${ANDROID_HOME:-}" ] && [ -n "${ANDROID_SDK_ROOT:-}" ]; then
  export ANDROID_HOME="$ANDROID_SDK_ROOT"
fi
_airlog_default() { # NAME PATH: export NAME=PATH when NAME is unset and PATH exists
  eval "_airlog_cur=\${$1:-}"
  if [ -z "$_airlog_cur" ] && [ -d "$2" ]; then export "$1=$2"; fi
}
_airlog_default FLUTTER_ROOT D:/dev/flutter
_airlog_default JAVA_HOME D:/dev/jdk17
_airlog_default ANDROID_HOME D:/dev/android-sdk
_airlog_default PUB_CACHE D:/dev/pub-cache
_airlog_default GRADLE_USER_HOME D:/dev/gradle
_airlog_default ANDROID_USER_HOME D:/dev/android-home
_airlog_default ANDROID_AVD_HOME D:/dev/avd
if [ -z "${ANDROID_SDK_ROOT:-}" ] && [ -n "${ANDROID_HOME:-}" ]; then
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
fi
# PATH entries in this shell's own form (D:/x -> /d/x under Git Bash).
_airlog_bin() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1"; fi
}
if [ -n "${ANDROID_HOME:-}" ]; then
  _airlog_sdk=$(_airlog_bin "$ANDROID_HOME")
  export PATH="$_airlog_sdk/platform-tools:$_airlog_sdk/cmdline-tools/latest/bin:$_airlog_sdk/emulator:$PATH"
fi
if [ -n "${JAVA_HOME:-}" ]; then export PATH="$(_airlog_bin "$JAVA_HOME")/bin:$PATH"; fi
if [ -n "${FLUTTER_ROOT:-}" ]; then export PATH="$(_airlog_bin "$FLUTTER_ROOT")/bin:$PATH"; fi
echo "Airlog env: Flutter ${FLUTTER_ROOT:-?} | JDK ${JAVA_HOME:-?} | SDK ${ANDROID_HOME:-?} | caches ${PUB_CACHE:-?}, ${GRADLE_USER_HOME:-?}"
unset -f _airlog_default _airlog_bin
unset _airlog_cur _airlog_sdk
