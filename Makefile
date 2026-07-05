build-push:
	@docker buildx build --platform linux/amd64,linux/arm64 -t coreproc/laravel-php:8.3-frankenphp-alpine . --push
