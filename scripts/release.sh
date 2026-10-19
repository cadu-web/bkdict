#!/bin/bash
# Publica uma versão do BKDict: macOS (build universal, DMG + ZIP, appcast assinado) e Windows (ZIP compilado daqui),
# numa release do GitHub. O app do Mac acha a versão nova pelo appcast da release "latest" (SUFeedURL no
# Resources/Info.plist), e o do Windows avisa na bandeja (Core/Updater.cs).
#
# Antes de rodar: suba CFBundleShortVersionString (ex.: 0.2.0) e CFBundleVersion (inteiro, sempre maior) no
# Resources/Info.plist. A assinatura usa a chave privada do Sparkle no Keychain deste Mac (conta "bkdict"); sem ela,
# nenhuma atualização é aceita pelos apps já instalados. A versão do Windows sai do mesmo número.
# Requer: brew install create-dmg; .NET 10 SDK (dotnet); gh logado na cadu-web.
#
#   scripts/release.sh "O que mudou nesta versão"
set -euo pipefail
cd "$(dirname "$0")/.."

REPO=cadu-web/bkdict
NOTES=${1:?"passe as notas da versão: scripts/release.sh \"O que mudou\""}
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
TAG=v$VERSION
SPARKLE=.build/artifacts/sparkle/Sparkle/bin

command -v dotnet >/dev/null || { echo "dotnet não encontrado: instale o .NET 10 SDK" >&2; exit 1; }
if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
    echo "A release $TAG já existe. Suba a versão no Resources/Info.plist." >&2
    exit 1
fi

./build.sh --release

# O appcast lista só o ZIP (é o que o Sparkle baixa); o DMG é para quem instala pela primeira vez.
UPDATES="$(mktemp -d)"
cp "dist/BKDict-$VERSION.zip" "$UPDATES/"
"$SPARKLE/generate_appcast" --account bkdict \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    -o dist/appcast.xml "$UPDATES"
rm -rf "$UPDATES"

# Windows: compilado daqui (o .NET compila WPF fora do Windows com EnableWindowsTargeting), com o .NET embutido
# (~72 MB zipado) para a pessoa não precisar instalar o runtime antes.
python3 -I scripts/gen-windows-ico.py
WINDOWS="$(mktemp -d)/BKDict"
dotnet publish windows/Bkdict/Bkdict.csproj -c Release -r win-x64 --self-contained true \
    -p:EnableWindowsTargeting=true -p:Version="$VERSION" -o "$WINDOWS" >/dev/null
rm -f "dist/BKDict-windows-$VERSION.zip"
(cd "$(dirname "$WINDOWS")" && zip -qr - BKDict) > "dist/BKDict-windows-$VERSION.zip"
rm -rf "$(dirname "$WINDOWS")"

gh release create "$TAG" -R "$REPO" --latest --title "BKDict $VERSION" --notes "$NOTES" \
    "dist/BKDict-$VERSION.dmg" "dist/BKDict-$VERSION.zip" dist/appcast.xml "dist/BKDict-windows-$VERSION.zip"
echo "Publicada: https://github.com/$REPO/releases/tag/$TAG"
