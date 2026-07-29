#ifndef TUNNEL_BRIDGING_HEADER_H
#define TUNNEL_BRIDGING_HEADER_H

// Ядро Xray объявляем здесь, а не подключаем его заголовок из xcframework.
//
// Xcode складывает заголовки всех подключённых библиотек в один каталог
// include/, которым уже владеет модуль HevSocks5Tunnel. Его umbrella-заголовок
// про libXray.h ничего не знает, поэтому объявления оттуда до Swift не
// доходят. Весь API libXray — две функции с неизменной сигнатурой, так что
// объявить их напрямую надёжнее, чем воевать с модульными картами.
//
// Символы приходят из libXray.a на этапе линковки.

extern char *CGoInvoke(char *requestJSON);
extern void CGoFree(char *value);

#endif /* TUNNEL_BRIDGING_HEADER_H */
