# ECL VPS Kit

ECL VPS Kit — интерактивный установщик для быстрой подготовки VPS под Remnawave Node.

Проект собирает в одном меню сетевые настройки Ubuntu, базовую защиту сервера, установку Remnawave Node, модуль ограничения скорости клиентов, z4r и проверки состояния.

## Быстрый запуск

```bash
wget -O install.sh https://raw.githubusercontent.com/devisoff/ecl-vps-kit/main/install.sh \
  && bash install.sh \
  && ecl
```

После первой установки меню можно открыть в любой момент командой:

```bash
ecl
```

## Поддерживаемая система

Рекомендуемая среда:

- Ubuntu 24.04 LTS;
- root-доступ;
- чистый VPS без конфликтующих firewall-правил;
- публичный IPv4;
- Docker устанавливается автоматически при установке ноды.

## Меню

```text
1) Сетевые настройки Ubuntu
2) Защита: UFW + TrafficGuard-auto + Fail2Ban
3) Установка Remnawave Node
4) Ограничение скорости клиентов
5) Установка z4r
6) Проверки состояния
7) Перезапустить Remnawave Node
8) Установить всё по порядку
0) Выход
```

## Что делает каждый модуль

### 1. Сетевые настройки Ubuntu

Применяет параметры для VPN-ноды:

- `nf_conntrack`;
- BBR + `fq`;
- расширенные conntrack-лимиты;
- диапазон ephemeral ports `10000 65535`;
- TCP buffers и очереди;
- `somaxconn`, `netdev_max_backlog`;
- системный лимит файловых дескрипторов;
- systemd-сервис `conntrack-tune.service`.

### 2. Защита

Настраивает:

- UFW;
- входящий доступ к `443/tcp`;
- доступ к порту ноды по allowlist;
- ICMP echo-request;
- TrafficGuard-auto;
- Fail2Ban для SSH.

Перед применением модуль предупреждает о сбросе UFW-правил.

### 3. Remnawave Node

Выполняет:

- `apt update && apt upgrade -y`;
- установку Docker через официальный install-script Docker;
- создание `/opt/remnanode`;
- создание `.env`;
- создание базового `docker-compose.yml`, если он отсутствует или подтверждена перезапись;
- запуск контейнера через `docker compose up -d`.

Рабочая директория ноды:

```text
/opt/remnanode
```

### 4. Ограничение скорости клиентов

Устанавливает shaper-модуль из репозитория `DonMatteoVPN/Reshala-Remnawave-Bedolaga` в отдельную директорию:

```text
/opt/reshala-shaper
```

Команда запуска после установки:

```bash
ecl-shaper
```

### 5. z4r

Запускает внешний установщик:

```bash
https://raw.githubusercontent.com/IndeecFOX/z4r/4/z4r
```

Перед запуском требуется подтверждение.

### 6. Проверки состояния

Показывает:

- conntrack;
- TCP congestion control и qdisc;
- диапазон портов;
- очереди;
- socket buffers;
- лимиты файловых дескрипторов;
- UFW;
- Fail2Ban;
- Docker;
- Remnawave Node;
- TrafficGuard-статистику, если лог существует.

### 7. Перезапуск Remnawave Node

Выполняет:

```bash
cd /opt/remnanode \
  && docker compose pull \
  && docker compose down \
  && docker compose up -d \
  && docker compose logs -f
```

## Пути установки

```text
/opt/ecl-vps-kit          основной установщик
/usr/local/bin/ecl        команда запуска меню
/usr/local/bin/ecl-shaper команда запуска speed limiter
/opt/remnanode            Remnawave Node
/opt/reshala-shaper       speed limiter
/etc/ecl-vps-kit          локальные параметры установщика
```

## Безопасность

Скрипт меняет сетевые параметры, UFW, Fail2Ban, Docker и systemd-настройки. Перед использованием на рабочем сервере рекомендуется первый запуск на тестовой VPS.

Перед публикацией любых изменений проверь, что в репозитории нет приватных ключей, токенов, паролей, UUID клиентов, `.env`-файлов и персональных конфигураций.

## Обновление установщика на сервере

```bash
wget -O install.sh https://raw.githubusercontent.com/devisoff/ecl-vps-kit/main/install.sh \
  && bash install.sh
```

После обновления:

```bash
ecl
```
