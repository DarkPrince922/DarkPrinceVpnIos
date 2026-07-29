# DarkPrince VPN — iOS

iOS-клиент к той же связке, что и Android-приложение: панель **Remnawave** и
кабинет **Bedolaga**. Подписка, тарифы, баланс, устройства — те же эндпоинты,
тот же формат подписки (Xray JSON с роутингом и балансировщиками).

> **Статус: код не скомпилирован ни разу.** У автора нет macOS, а собрать
> iOS-приложение без неё невозможно. Всё, что здесь лежит, написано «на
> бумаге» и требует первой сборки живым человеком с Xcode. Ошибки компиляции
> на первом проходе — ожидаемое явление, а не признак того, что что-то пошло
> не так.

## Как устроено

Схема повторяет Android один в один:

```
   пакеты
 приложений          NEPacketTunnelProvider
     │                       │
     ▼                       ▼
   TUN  ──►  hev-socks5-tunnel  ──►  SOCKS 127.0.0.1:10808  ──►  Xray-core
                (Tun2SocksKit)                                   (libXray)
```

* **libXray** (`XTLS/libXray`) — то же ядро Xray, что и на Android, собранное
  под Apple. Ест ровно тот же JSON-конфиг, который отдаёт панель, поэтому
  роутинг, правила и балансировщики сохраняются целиком: мы подменяем в нём
  только `inbounds` на локальный SOCKS.
* **hev-socks5-tunnel** через пакет `Tun2SocksKit` — тот же мост TUN → SOCKS,
  что и в Android-сборке.

Почему это должно влезть в лимит памяти расширения (около 50 МБ): libXray под
iOS сам ограничивает Go-рантайм 30 МБ и раз в секунду возвращает память
системе. Мост на C почти ничего не занимает. Это главный технический риск
проекта, и проверяется он первым же запуском на устройстве.

## Сборка

Нужны macOS, Xcode 15+ и [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
./scripts/fetch-libxray.sh          # скачает LibXray.xcframework в Vendor/
export DEVELOPMENT_TEAM=XXXXXXXXXX  # Team ID из аккаунта разработчика
xcodegen generate                   # создаст DarkPrinceVPN.xcodeproj
open DarkPrinceVPN.xcodeproj
```

Дальше — обычная сборка на устройство. **На симуляторе VPN не работает:**
Network Extension запускается только на живом iPhone.

### Что нужно от аккаунта разработчика

* App ID `ru.darkprince.vpn` и `ru.darkprince.vpn.tunnel`;
* capability **Network Extensions** (packet-tunnel-provider) на обоих;
* App Group `group.ru.darkprince.vpn` на обоих;
* Keychain Sharing с группой `ru.darkprince.vpn` на обоих.

Для публикации в App Store аккаунт должен быть **от организации**: Apple не
пропускает VPN-приложения от индивидуальных разработчиков.

## Структура

```
Sources/
  Shared/     код, общий для приложения и расширения
    ProxyProfile.swift      модель узла подписки
    LinkParser.swift        разбор подписки: Xray JSON, base64, ссылки
    XrayConfigBuilder.swift сборка конфига ядра
    SharedStore.swift       настройки и кэш в контейнере App Group, токены в Keychain
    TunnelMessage.swift     протокол общения приложения с расширением
  App/        приложение (SwiftUI)
    Vpn/VpnManager.swift    управление профилем VPN в системе
  Tunnel/     сетевое расширение
    PacketTunnelProvider.swift
    LibXrayBridge.swift     обёртка над C-API libXray
```

## Чего на iOS не будет

**Раздельного туннелирования по приложениям.** «Только выбранные» и «Кроме
выбранных» на iOS доступны исключительно через MDM — обычному приложению из
App Store такой API не дают. Частично заменяется правилами по доменам и адресам
внутри конфига, которые и так задаются на панели.
