# Used for prod build.
FROM php:8.3-fpm-alpine3.20

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
    nginx \
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

# Install PHP extensions.
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install \
    gd \
    mysqli \
    pdo \
    pdo_mysql \
    bcmath \
    curl \
    opcache \
    mbstring \
    exif \
    pcntl \
    zip

# Install Redis extension.
RUN pecl install redis \
    && docker-php-ext-enable redis

# Install xdebug and pcov but don't enable it.
RUN pecl install xdebug pcov

# Copy composer executable.
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Delete gd-dev
RUN apk del gd-dev

# Clean up build dependencies and temporary files.
RUN apk del .build-deps \
    && rm -rf /tmp/pear \
    && docker-php-source delete
