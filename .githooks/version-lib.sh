MWT_VERSION_FILE=app/Sources/MWTKit/KitInfo.swift

read_version() {
  sed -n 's/.*version = "\(.*\)".*/\1/p' | head -n 1
}

is_semver() {
  printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
}

newer() {
  local IFS=.
  local a=($1)
  local b=($2)
  local i
  for i in 0 1 2; do
    if [ "$((10#${a[$i]}))" -gt "$((10#${b[$i]}))" ]; then return 0; fi
    if [ "$((10#${a[$i]}))" -lt "$((10#${b[$i]}))" ]; then return 1; fi
  done
  return 1
}

version_base() {
  if git rev-parse --verify -q refs/remotes/origin/main >/dev/null 2>&1; then
    echo origin/main
  elif [ "$(git symbolic-ref --short -q HEAD 2>/dev/null || true)" != "main" ] \
      && git rev-parse --verify -q refs/heads/main >/dev/null 2>&1; then
    echo main
  fi
}
