# https://developers.home-assistant.io/docs/add-ons/configuration#add-on-dockerfile
ARG BUILD_FROM
FROM $BUILD_FROM
LABEL org.opencontainers.image.source=https://github.com/Erudition/home-assistant-addons
LABEL org.opencontainers.image.description="Tidy Recordings for Home Assistant"
LABEL org.opencontainers.image.licenses=MIT
# Execute during the build of the image
ARG TEMPIO_VERSION BUILD_ARCH
RUN \
    curl -sSLf -o /usr/bin/tempio \
    "https://github.com/home-assistant/tempio/releases/download/${TEMPIO_VERSION}/tempio_${BUILD_ARCH}"

# Copy root filesystem
COPY rootfs /

# Install requirements for add-on
RUN \
  apk add --no-cache \
    ffmpeg

# are all of those needed^

WORKDIR /data