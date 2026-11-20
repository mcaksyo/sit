FROM php:8.3-cli AS php-runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends git unzip libpq-dev librabbitmq-dev \
    && docker-php-ext-install pdo_pgsql pcntl \
    && pecl install amqp-2.1.2 \
    && docker-php-ext-enable amqp \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
WORKDIR /app
ENV COMPOSER_ALLOW_SUPERUSER=1 SYMFONY_DOCKER=0

FROM php-runtime AS orders
COPY order-service/ ./
RUN composer install --no-interaction --prefer-dist --no-progress --no-scripts \
    && test -f vendor/autoload_runtime.php \
    && mkdir -p var \
    && chown www-data:www-data var
USER www-data

FROM php-runtime AS notifications
COPY notification-service/ ./
RUN composer install --no-interaction --prefer-dist --no-progress --no-scripts \
    && test -f vendor/autoload_runtime.php \
    && mkdir -p var \
    && chown www-data:www-data var
USER www-data
