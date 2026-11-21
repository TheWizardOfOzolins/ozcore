# Image variant: hci or minimal (selects the uCore base image and which variant layer build.sh applies)
ARG VARIANT=hci

# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files
COPY cosign.pub /system_files/common/etc/pki/containers/ozcore.pub
## cosign is only needed at build time, to verify signed upstream release artifacts
COPY --from=ghcr.io/sigstore/cosign/cosign:v3.1.4@sha256:0f06154836d2de34f887a5c273506d52ca43edaa1d9e53e6510fa78a48f69c2d /ko-app/cosign /tools/cosign

# Base Images
## One stage per variant so Renovate can pin and bump each digest independently;
## only the stage selected by VARIANT is pulled and built
FROM ghcr.io/ublue-os/ucore-hci:stable@sha256:daea6fce6bdfafaf9a4c47ce005e15b0cd543f907d1d554352d2124a824b829e AS base-hci
FROM ghcr.io/ublue-os/ucore-minimal:stable@sha256:2c54cfb982fcafdd55fa9dfb5745a066354746d76537555ca734404671130c0b AS base-minimal

FROM base-${VARIANT}
ARG VARIANT

## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:latest
# FROM ghcr.io/ublue-os/bluefin-nvidia:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:41
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### MODIFICATIONS
## build.sh applies the shared layer, then the variant layer:
##   build_files/common/*.sh + system_files/common/     -> every image
##   build_files/${VARIANT}/*.sh + system_files/${VARIANT}/ -> that image only

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    VARIANT=${VARIANT} /ctx/build.sh && \
    ostree container commit
    
### LINTING
## Verify final image and contents are correct.
RUN bootc container lint