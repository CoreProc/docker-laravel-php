#!/usr/bin/env bash
# Smoke-test a built image. Usage: smoke-test.sh <image> [supercronic-version]
#
# Beyond "php -v", this loads every extension the variants install and makes
# one real call into the libraries most likely to break when Alpine packages
# are upgraded under an already-compiled PHP (libxml2, libpng/libjpeg/
# freetype, libzip, curl, oniguruma). xdebug and pcov are installed but not
# enabled, so they are loaded explicitly.
set -euo pipefail

image=$1
want=${2:-}

docker run --rm -e WANT="$want" "$image" sh -ec '
  php -v
  v=$(supercronic -version)
  echo "supercronic ${v}"
  [ -z "$WANT" ] || [ "$v" = "$WANT" ]
  echo "* * * * * true" > /tmp/ct
  supercronic -test /tmp/ct
  php -d extension=pcov -r "exit(extension_loaded(\"pcov\") ? 0 : 1);"
  php -d zend_extension=xdebug -r "exit(extension_loaded(\"xdebug\") ? 0 : 1);"'

docker run --rm -i "$image" php <<'PHP'
<?php
$want = ['bcmath', 'curl', 'dom', 'exif', 'gd', 'mbstring', 'mysqli', 'pcntl',
         'pdo', 'pdo_mysql', 'redis', 'xml', 'zip', 'Zend OPcache'];
$missing = array_values(array_filter($want, fn ($e) => !extension_loaded($e)));
if ($missing) {
    fwrite(STDERR, 'missing extensions: ' . implode(', ', $missing) . "\n");
    exit(1);
}

function check(string $what, bool $ok): void
{
    if (!$ok) {
        fwrite(STDERR, "failed: {$what}\n");
        exit(1);
    }
}

$gd = gd_info();
check('gd FreeType support', $gd['FreeType Support']);
$im = imagecreatetruecolor(8, 8);
foreach (['imagepng', 'imagejpeg'] as $encode) {
    ob_start();
    $encode($im);
    check($encode, strlen(ob_get_clean()) > 50);
}

$path = tempnam(sys_get_temp_dir(), 'zip');
$zip = new ZipArchive();
check('zip write', $zip->open($path, ZipArchive::OVERWRITE) === true
    && $zip->addFromString('a.txt', 'ok') && $zip->close());
check('zip read', $zip->open($path) === true && $zip->getFromName('a.txt') === 'ok');

$doc = new DOMDocument();
check('libxml2 parse', $doc->loadXML('<a><b>ok</b></a>') && $doc->documentElement->textContent === 'ok');
check('curl', curl_version()['version'] !== '');
check('mbstring', mb_strtoupper('é') === 'É');
check('bcmath', bcadd('0.1', '0.2', 1) === '0.3');

echo "extensions ok\n";
PHP
