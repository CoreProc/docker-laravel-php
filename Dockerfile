# Used for prod build.
FROM dunglas/frankenphp:php8.5-alpine

# Install dependencies.
RUN apk add --no-cache --virtual .build-deps \
    $PHPIZE_DEPS \
    autoconf \
    make \
    gcc \
    g++ \
    linux-headers \
    && apk add --no-cache \
    zip \
    unzip \
    libzip-dev \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    libmcrypt-dev \
    gd-dev \
    jpegoptim optipng pngquant gifsicle \
    curl-dev \
    oniguruma-dev \
    supervisor

# Use Supercronic for cron jobs. Latest releases available at https://github.com/aptible/supercronic/releases
ARG TARGETARCH
ENV SUPERCRONIC_VERSION=v0.2.47 \
    SUPERCRONIC_SHA1SUM_AMD64=712d2ece75da6f6e530192a151488578153e4e96 \
    SUPERCRONIC_SHA1SUM_ARM64=93323899ddca3f1198f1796a4bf4418ed1e7982e

RUN SUPERCRONIC="supercronic-linux-${TARGETARCH}" \
 && case "$TARGETARCH" in \
      amd64) SUPERCRONIC_SHA1SUM="$SUPERCRONIC_SHA1SUM_AMD64" ;; \
      arm64) SUPERCRONIC_SHA1SUM="$SUPERCRONIC_SHA1SUM_ARM64" ;; \
      *) echo "unsupported arch: $TARGETARCH" && exit 1 ;; \
    esac \
 && curl -fsSLO "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/${SUPERCRONIC}" \
 && echo "${SUPERCRONIC_SHA1SUM}  ${SUPERCRONIC}" | sha1sum -c - \
 && chmod +x "$SUPERCRONIC" \
 && mv "$SUPERCRONIC" /usr/local/bin/supercronic

# Install PHP extensions. opcache is not listed: PHP >= 8.5 builds it statically.
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install \
    gd \
    mysqli \
    pdo \
    pdo_mysql \
    bcmath \
    curl \
    mbstring \
    exif \
    pcntl \
    zip

# PIE (PHP's official extension installer) resolves extensions through
# Packagist and builds them from GitHub, so builds no longer depend on
# pecl.php.net, which returned 500/502 for hours during the October 21, 2026
# PHP security release. Pinned by digest; bump the tag and digest together.
COPY --from=ghcr.io/php/pie:1.5.2-bin@sha256:a254c78b51ca34daef0541fa1cf0147385c93ba5ca799868392275d947f00fe7 /pie /usr/bin/pie

# Install the Redis extension.
RUN pie install phpredis/phpredis:^6.3

# Install xdebug and pcov but don't enable them.
RUN pie install --skip-enable-extension xdebug/xdebug:^3.5 \
    && pie install --skip-enable-extension pecl/pcov:^1.0

# Copy composer executable.
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Delete gd-dev
RUN apk del gd-dev

# Clean up build dependencies and temporary files.
RUN apk del .build-deps \
    && rm -rf /tmp/pear \
    && docker-php-source delete
