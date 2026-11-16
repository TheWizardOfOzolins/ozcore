#!/bin/bash
# Smoke test run inside a freshly built image, before it is published.
# Catches images that would build fine but break hosts, e.g. a signature
# policy that no longer trusts this image (hosts would refuse every later update).
#
# Usage (CI runs this): smoke.sh <image name> <variant> <expected materia version>

set -uo pipefail

IMAGE_NAME=${1:?image name}
VARIANT=${2:?variant}
MATERIA_VERSION=${3:?materia version}
REPO="ghcr.io/thewizardofozolins/${IMAGE_NAME}"

failures=0
check() {
  local desc=$1
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok   - ${desc}"
  else
    echo "FAIL - ${desc}"
    failures=$((failures + 1))
  fi
}

### Signature policy: hosts must keep trusting updates to this image
check "policy.json requires a sigstore signature for ${REPO}" \
  jq -e --arg r "$REPO" '.transports.docker[$r][0].type == "sigstoreSigned"' /etc/containers/policy.json
key=$(jq -r --arg r "$REPO" '.transports.docker[$r][0].keyPath // empty' /etc/containers/policy.json)
check "policy key exists (${key:-unset})" test -s "${key:-/nonexistent}"
check "registries.d enables sigstore attachments for ${REPO}" \
  grep -rqF "${REPO}:" /etc/containers/registries.d/

### Materia
check "materia runs and reports ${MATERIA_VERSION}" \
  bash -c "materia version | grep -qF '${MATERIA_VERSION#v}'"
check "materia-update.timer is enabled" systemctl is-enabled materia-update.timer

### Shared services and packages
check "podman.socket is enabled" systemctl is-enabled podman.socket
for pkg in tmux vim tree; do
  check "${pkg} is installed" command -v "$pkg"
done

### Variant layer
case "$VARIANT" in
  hci)
    check "targetcli is installed" command -v targetcli
    check "iscsid is enabled" systemctl is-enabled iscsid
    check "target is enabled" systemctl is-enabled target
    ;;
  minimal)
    check "targetcli is not installed" bash -c '! command -v targetcli'
    ;;
  *)
    echo "FAIL - unknown variant ${VARIANT}"
    failures=$((failures + 1))
    ;;
esac

if ((failures > 0)); then
  echo "${failures} check(s) failed"
  exit 1
fi
echo "All checks passed"
