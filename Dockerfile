# The game host is pure Dart, but pubspec.yaml declares the Flutter SDK as a
# dependency of the app as a whole, so `pub get` needs Flutter on disk even
# though nothing in the server's import chain touches it. So: install Flutter to
# resolve the real pubspec.lock, compile a native binary, ship only the binary.
#
# Flutter is fetched the same way tool/netlify_build.sh fetches it, pinned to the
# same version, so the host and the web app are built against one SDK.
FROM dart:stable AS build

ARG FLUTTER_VERSION=3.44.6
ENV FLUTTER_ROOT=/opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"

RUN apt-get update \
  && apt-get install -y --no-install-recommends git curl unzip ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && git clone --depth 1 --branch "$FLUTTER_VERSION" \
       https://github.com/flutter/flutter.git "$FLUTTER_ROOT" \
  && git config --global --add safe.directory "$FLUTTER_ROOT" \
  && flutter --version

WORKDIR /app

# Resolve dependencies before copying source so this layer survives code edits.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY bin/ bin/
COPY lib/ lib/

# Self-contained native executable, so the runtime image needs no Dart SDK.
RUN dart compile exe bin/server.dart -o /app/server

FROM debian:bookworm-slim

# The binary links against the system TLS and name-resolution libraries.
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && useradd --create-home --shell /usr/sbin/nologin app

COPY --from=build /app/server /usr/local/bin/canastra-host

USER app

# Fly injects PORT; this is the fallback for a plain `docker run`.
ENV PORT=8080
EXPOSE 8080

CMD ["/usr/local/bin/canastra-host"]
