# ozcore

Custom [uCore](https://github.com/ublue-os/ucore) images for a home NAS. They add iSCSI target support and [Materia](https://github.com/stryan/materia) for GitOps-managed Quadlets.

## Variants

Each image is built on the [uCore](https://github.com/ublue-os/ucore) image of the same name, so `ozcore-<variant>` is always `ucore-<variant>` plus the additions below.

| Image | Built on | Notes |
| --- | --- | --- |
| `ghcr.io/thewizardofozolins/ozcore-hci` | `ghcr.io/ublue-os/ucore-hci:stable` | Includes ZFS, Cockpit, libvirt, etc. from `ucore-hci`, plus the iSCSI target |
| `ghcr.io/thewizardofozolins/ozcore-minimal` | `ghcr.io/ublue-os/ucore-minimal:stable` | No ZFS, Cockpit, virtualization or iSCSI target |

Both are built from the same `Containerfile` (selected with the `VARIANT` build arg, `hci` or `minimal`), are published for `linux/amd64` and `linux/arm64`, and are signed with the same key. Swap `ozcore-hci` for `ozcore-minimal` in the commands below to use the minimal variant.

## What's included

On top of the base image:

| Addition | Details |
| --- | --- |
| Packages | `tmux`, `vim`, `tree` (plus `targetcli` on hci) |
| iSCSI (hci only) | `iscsid` and `target` enabled at boot |
| Podman | `podman.socket` enabled |
| Materia | `/usr/bin/materia` and its man pages, plus `materia-update.timer` (runs every 5 min). See [Materia setup](#materia-setup) |
| Signature policy | The host only accepts updates to this image that are signed with [`cosign.pub`](cosign.pub) |
| Quieter login | `coreos-container-signing-migration-motd.service` disabled |

## Installing / switching to this image

From an existing uCore (or any bootc) host:

```bash
# 1. Switch to the image. The current deployment doesn't trust its key yet, so don't enforce signatures.
sudo bootc switch ghcr.io/thewizardofozolins/ozcore-hci:latest
sudo systemctl reboot

# 2. Now that the policy and key are installed, switch again with signature enforcement.
sudo bootc switch --enforce-container-sigpolicy ghcr.io/thewizardofozolins/ozcore-hci:latest
sudo systemctl reboot
```

After step 2, `bootc upgrade` and the automatic updates from `rpm-ostreed-automatic.timer` refuse images that aren't signed with this repo's key.

For fresh installs, see [Disk images](#disk-images).

### Migrating from `ucore-nas`

These images were previously published as `ucore-nas` (hci) and `ucore-nas-minimal`. Those packages no longer receive updates. Recent `ucore-nas` images already trust the new names, so a single enforced switch is enough:

```bash
# Confirm the running image trusts the new names (both should be listed)
jq '.transports.docker | keys' /etc/containers/policy.json | grep ozcore

sudo bootc switch --enforce-container-sigpolicy ghcr.io/thewizardofozolins/ozcore-hci:latest   # or ozcore-minimal
sudo systemctl reboot
```

If `ozcore` isn't listed, the host is on an older image: either `sudo bootc upgrade` and reboot first, or follow the two-step switch above.

### Updates

uCore's `rpm-ostreed-automatic.timer` checks for a new image daily (`AutomaticUpdatePolicy=stage`). It downloads and stages the update but never reboots; the update is applied on the next manual reboot. To check status or update by hand:

```bash
rpm-ostree status          # shows a staged deployment, if any
sudo bootc upgrade         # fetch + stage now
sudo systemctl reboot      # boot into it
```

Automatic reboots (`bootc-fetch-apply-updates.timer`) are deliberately left disabled so that iSCSI clients aren't disconnected unexpectedly.

## Materia setup

The image ships Materia but **no config or secrets**. The image is public, so the Git source and keys are provisioned per host. `materia-update.service` doesn't run until all of these exist:

| File | Purpose |
| --- | --- |
| `/etc/materia/config.toml` | Copy from `/usr/share/materia/config.toml.example` and set your repo URL |
| `/etc/materia/materia_key` | SSH deploy key with read access to the Materia repo |
| `/etc/materia/known_hosts` | Host key of your Git server (`ssh-keyscan -p <port> <host>`) |

`/etc/materia/key.txt` (an age identity) is optional. It's only needed if the repo keeps attributes in age-encrypted vaults, in which case `config.toml` also needs the `[age]` section from the example.

Files in `/etc` persist across image updates. They can also be supplied via Butane/Ignition at install time.

### With Ansible (recommended)

[`ansible/materia.yml`](ansible/materia.yml) writes all of the above and runs Materia once whenever something changed. Python is already on the host (uCore pulls it in with `tuned`), so no bootstrapping is needed.

```bash
cd ansible
cp inventory.example.yml inventory.yml   # git-ignored; add your hosts, repo URL and vaulted deploy key
ansible-vault encrypt_string --stdin-name materia_ssh_private_key < ~/.ssh/materia_deploy
ansible-playbook -i inventory.yml materia.yml --ask-vault-pass
```

| Variable | Default | Purpose |
| --- | --- | --- |
| `materia_repo_url` | required | SSH URL of the repo (`ssh://git@host:port/user/repo.git` or `git@host:user/repo.git`) |
| `materia_ssh_private_key` | required | Deploy key contents |
| `materia_branch` | `main` | Branch Materia deploys |
| `materia_known_hosts` | fetched with `ssh-keyscan` from the host | Pin the Git server's host key instead of trusting the first scan |
| `materia_git_host`, `materia_git_port` | parsed from the URL | Where to scan, if the URL doesn't say |
| `materia_age_key` | unset | age identity. When set, `key.txt` is written and the `[age]` engine is enabled |
| `materia_age_base_dir` | `attributes` | Directory of age vaults in the repo |
| `materia_config_extra` | unset | Raw TOML appended to `config.toml`, e.g. a `[file]` or `[sops]` table |
| `materia_run_now` | `true` | Run `materia-update.service` after a change instead of waiting for the timer |

The playbook leaves an existing `key.txt` alone when `materia_age_key` isn't set. Hosts on an image from before `key.txt` became optional still skip the service without it, so the playbook stops with a message telling you to update the image first (or to set `materia_age_key`).

### By hand

```bash
sudo cp /usr/share/materia/config.toml.example /etc/materia/config.toml
sudo $EDITOR /etc/materia/config.toml
sudo install -m 0600 materia_key /etc/materia/
sudo install -m 0644 known_hosts /etc/materia/
sudo install -m 0600 key.txt /etc/materia/      # only if you use the [age] engine
sudo systemctl start materia-update.service     # run once now instead of waiting for the timer
journalctl -u materia-update.service
```

## Build

- **CI:** [`build.yml`](.github/workflows/build.yml) builds both variants daily (06:30 UTC), on pushes to `main`, and on PRs, each for amd64 and arm64 on native runners. Images from `main` are pushed to GHCR as multi-arch `latest`, `latest.YYYYMMDD` and `YYYYMMDD` tags (plus per-platform `latest-amd64` / `latest-arm64`), then signed with cosign and given signed SBOMs (see [SBOMs](#sboms)). If any build fails, the multi-arch tags are left untouched for that run.
- **Checks:** every build (PRs included) runs [`tests/smoke.sh`](tests/smoke.sh) inside the new image before anything is pushed. It checks that the signature policy still trusts the image's own name with an existing key, Materia runs at the pinned version, the expected services are enabled and the variant's packages are present. After signing, CI verifies every signature against `cosign.pub` and confirms it's stored as a legacy `.sig` tag, the format podman and bootc need. Either failure would otherwise leave hosts silently unable to update.
- **Lint:** [`lint.yml`](.github/workflows/lint.yml) runs shellcheck on `build_files/` and `tests/`, `just --fmt --check`, actionlint, ansible-lint on `ansible/` (versions pinned in [`ansible/requirements-lint.txt`](ansible/requirements-lint.txt)), and a Syft run that validates [`.github/syft.yaml`](.github/syft.yaml) on every PR and push to `main`. It's a separate check, so a lint failure doesn't block image builds or automerges. Run shellcheck locally with `just lint`.
- **Dependencies:** [Renovate](.github/renovate.json5) updates GitHub Actions, runner images (except `build-disk.yml`, held on 24.04 for bootc-image-builder), bootc-image-builder, the base images and the Materia version in `build_files/common/30-materia.sh`. PRs are rebased whenever `main` moves.
  - **Base images** are pinned by digest, one per variant, in the `Containerfile`. Renovate opens a PR when `:stable` moves and automerges it once the build passes, so every base update is a revertable commit.
  - **Materia** is downloaded from its GitHub release and verified at build time: `SHA256SUMS` is checked with the maintainer's cosign key ([`build_files/keys/materia.pub`](build_files/keys/materia.pub)), then the tarball is checked against it. No per-version hashes live in the repo, so patch releases automerge; minor releases wait for review since Materia is pre-1.0. If upstream rotates its key, replace `materia.pub`.
- **Layout:**
  - `Containerfile` – pinned base images (one per variant) and build entrypoint
  - `build_files/build.sh` – orchestrator: applies the `common` layer, then the `${VARIANT}` layer
  - `build_files/common/*.sh` – build steps for every image (signing policy, packages, Materia)
  - `build_files/hci/*.sh`, `build_files/minimal/*.sh` – build steps for one image only (e.g. iSCSI on hci)
  - `system_files/common/` – files copied as-is into every image root (systemd units, configs)
  - `system_files/hci/`, `system_files/minimal/` – files copied into that image only
  - `disk_config/` – bootc-image-builder configs for disk images
  - `tests/smoke.sh` – checks run inside each freshly built image before it's published
  - `ansible/` – playbook that provisions Materia's per-host config and keys

  Scripts in each layer run in name order, so prefix them with a number (`10-`, `20-`, …). To add something to every image, drop a script or file under `common/`; to add it to one image, put it under that variant's folder.

### Building locally

```bash
just build              # builds localhost/ozcore-hci:latest with podman
VARIANT=minimal just build   # builds localhost/ozcore-minimal:latest
just build-qcow2        # VM disk image from the local build
just run-vm-qcow2       # boot it in a VM
```

## Disk images

[`build-disk.yml`](.github/workflows/build-disk.yml) (manual dispatch) builds a qcow2 and an Anaconda installer ISO from the published image and platform (amd64 or arm64) you choose. The ISO installs and then runs `bootc switch` to that image (e.g. `ghcr.io/thewizardofozolins/ozcore-hci:latest`). Afterwards, do step 2 of [Installing](#installing--switching-to-this-image) to enforce signatures.

## Verifying signatures

```bash
cosign verify --key cosign.pub ghcr.io/thewizardofozolins/ozcore-hci:latest
```

CI signs with `--new-bundle-format=false` so that signatures are stored as legacy `.sig` tags. podman and bootc can't verify cosign v3's new bundle format, so don't remove that flag.

## SBOMs

Every image published from `main` gets an [SPDX](https://spdx.dev/) JSON SBOM, generated by [Syft](https://github.com/anchore/syft) from the published image. It lists every RPM (from uCore and this repo's layer), the Go modules built into binaries such as Materia and podman, and Python packages. Kernel modules and per-file listings are left out (see [`.github/syft.yaml`](.github/syft.yaml)); they made the SBOM ~55 MB without adding anything a scanner uses. There's one SBOM per platform image, since amd64 and arm64 package builds differ.

Each SBOM is published two ways:

- **As a signed cosign attestation on the image**, using the same key as the image signatures, so it lives as long as the image does. Unlike the image signatures, it isn't recorded in the public Rekor transparency log, which rejects documents this large, so verifying it needs `--insecure-ignore-tlog=true`. The signature is still checked against `cosign.pub`; only the public log entry is skipped.
- **As a workflow artifact** (`sbom-<image>-<platform>`) on the [build run](.github/workflows/build.yml), kept for 90 days.

Attestations are attached to each platform image, not the multi-arch tag, so look up the platform digest first:

```bash
IMAGE=ghcr.io/thewizardofozolins/ozcore-hci
DIGEST=$(skopeo inspect --raw "docker://${IMAGE}:latest" \
  | jq -r '.manifests[] | select(.platform.architecture == "amd64") | .digest')

# Verifies the signature and prints the SBOM
cosign verify-attestation --key cosign.pub --insecure-ignore-tlog=true --type spdxjson "${IMAGE}@${DIGEST}" \
  | jq -r '.payload' | base64 -d | jq '.predicate' > sbom.spdx.json
```

The `sbom` job runs after images are published and signed, so if it fails the release still goes out. Re-run the job within 7 days (while the build's digest artifacts are kept) to attach the missing SBOMs; the SBOM itself is uploaded as an artifact before attaching, so it's available even if attaching fails.
