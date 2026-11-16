#!/bin/bash
# Require updates to this image to be signed with cosign.pub
# (covers every variant so hosts can switch between them)
# ozcore* is the upcoming name for these images; trusting it now lets hosts
# `bootc switch --enforce-container-sigpolicy` to it once it's published

set -ouex pipefail

POLICY_TMP=$(mktemp)
cp /etc/containers/policy.json "$POLICY_TMP"
for repo in ucore-nas ucore-nas-minimal ozcore-hci ozcore-minimal; do
  jq --arg repo "ghcr.io/thewizardofozolins/${repo}" '.transports.docker[$repo] = [{
        "type": "sigstoreSigned",
        "keyPath": "/etc/pki/containers/ucore-nas.pub",
        "signedIdentity": {"type": "matchRepository"}
      }]' "$POLICY_TMP" >"${POLICY_TMP}.new"
  mv "${POLICY_TMP}.new" "$POLICY_TMP"
done
install -m 0644 "$POLICY_TMP" /etc/containers/policy.json
