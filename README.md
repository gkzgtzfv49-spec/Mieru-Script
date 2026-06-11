# 🔐 Mieru-Script

Простой скрипт для установки и управления [mieru](https://github.com/enfein/mieru) — прокси для обхода цензуры на Ubuntu.  
mieru маскирует трафик под случайный шум — DPI не может его обнаружить и заблокировать.

---

## ⚡ Быстрая установка

```bash
bash <(curl -sSL https://raw.githubusercontent.com/gkzgtzfv49-spec/Mieru-Script/main/mieru.sh)
```

> Требуется Ubuntu 20.04 / 22.04 / 24.04, root доступ. Домен не нужен.

---

## 🔒 Что такое mieru

- Трафик выглядит как случайный шум — DPI не может его идентифицировать
- Не требует домена и TLS-сертификата
- Поддерживает TCP и UDP транспорт
- Встроенная поддержка BBR для быстрого UDP

---

## 📋 Возможности скрипта

- **Автоустановка** — последняя версия mita за один запуск
- **Управление пользователями** — добавить, удалить с именами
- **Конфиги для клиентов** — готовый YAML для Karing и JSON для нативного клиента
- **Выбор порта и протокола** — TCP или UDP
- **Короткая команда** — после установки просто пиши `mieru-manage`

---

## 📱 Клиенты

| Платформа | Клиент | Ссылка |
|---|---|---|
| Windows | mieru | [Скачать](https://github.com/enfein/mieru/releases) |
| macOS | mieru | [Скачать](https://github.com/enfein/mieru/releases) |
| Android | mieru | [Скачать](https://github.com/enfein/mieru/releases) |
| iOS | Karing | [App Store](https://apps.apple.com/app/karing/id6472431552) |
| Windows / macOS | Karing | [Скачать](https://github.com/KaringX/karing/releases) |
| Android | NekoBox | [Скачать](https://github.com/MatsuriDayo/NekoBoxForAndroid/releases) |

---

## 🖥 Управление

После установки:

```bash
mieru-manage
```

### Меню

```
Порты:         2080
Пользователей: 2
Статус mita:   RUNNING

── Пользователи ──
1. Показать всех
2. Добавить пользователя
3. Удалить пользователя
4. Показать конфиг для клиента

── Сервер ──
5. Перенастроить (сменить порт/протокол)
6. Перезапустить mita
7. Статус и логи
8. Обновить скрипт
```

---

## ⚙️ Конфиги для клиентов

При выборе пункта **4** скрипт выводит готовые конфиги:

### Clash / Karing (YAML)
```yaml
proxies:
  - name: ivan
    type: mieru
    server: 51.195.34.209
    port: 2080
    transport: TCP
    udp: true
    username: ivan
    password: ваш_пароль
    multiplexing: MULTIPLEXING_HIGH
```

### mieru нативный (client_config.json)
```json
{
  "profile": [{
    "ipAddress": "51.195.34.209",
    "portBindings": [{"port": 2080, "protocol": "TCP_PROXY_PROTOCOL"}],
    "user": [{"name": "ivan", "password": "ваш_пароль"}]
  }]
}
```

---

## 📋 Требования

- Ubuntu 20.04 / 22.04 / 24.04
- Root доступ
- Открытый порт (любой от 1025 до 65535)
- **Домен не нужен**

---

## 📄 Лицензия

MIT
