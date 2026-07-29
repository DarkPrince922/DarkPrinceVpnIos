#!/usr/bin/env bash
# Скачивает LibXray.xcframework — ядро Xray, собранное под Apple-платформы.
# Библиотека большая (~100 МБ архив), поэтому в репозитории её не держим.
set -euo pipefail

VERSION="${LIBXRAY_VERSION:-v26.7.28}"
ASSET="libxray-apple-cgo.zip"
URL="https://github.com/XTLS/libXray/releases/download/${VERSION}/${ASSET}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="${ROOT}/Vendor"
TARGET="${VENDOR}/LibXray.xcframework"

if [ -d "${TARGET}" ] && [ "${1:-}" != "--force" ]; then
    echo "LibXray.xcframework уже на месте (${TARGET}). Обновить: $0 --force"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "Скачиваю libXray ${VERSION}…"
curl -fSL --retry 3 -o "${TMP}/${ASSET}" "${URL}"

echo "Распаковываю…"
unzip -q "${TMP}/${ASSET}" -d "${TMP}/unpacked"

SRC="$(find "${TMP}/unpacked" -maxdepth 3 -name 'LibXray.xcframework' -type d | head -n1)"
if [ -z "${SRC}" ]; then
    echo "В архиве нет LibXray.xcframework — проверьте версию ${VERSION}" >&2
    exit 1
fi

mkdir -p "${VENDOR}"
rm -rf "${TARGET}"
cp -R "${SRC}" "${TARGET}"

# Xcode складывает заголовки всех xcframework'ов в один каталог include/, и
# две библиотеки со своими module.modulemap дерутся за одно и то же имя файла
# («Multiple commands produce …/include/module.modulemap»). Модульная карта
# hev-socks5-tunnel приходит из чужого пакета, поэтому убираем свою: заголовок
# libXray.h подключается через bridging header расширения.
find "${TARGET}" -name 'module.modulemap' -delete

echo "Готово: ${TARGET}"
