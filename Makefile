build-push:
	@docker buildx build --platform linux/amd64,linux/arm64 -t coreproc/laravel-php:8.4-fpm-alpine . --push
