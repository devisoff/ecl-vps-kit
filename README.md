# ECL VPS Kit

Production-инсталлер для быстрой подготовки VPS под Remnawave Node.

Главная команда после установки:

```bash
ecl
```

## Быстрая установка

```bash
wget -O install.sh https://raw.githubusercontent.com/devisoff/ecl-vps-kit/main/install.sh \
  && bash install.sh \
  && ecl
```

## Что входит

- Обновление Ubuntu и установка базовых пакетов.
- Сетевой тюнинг Ubuntu для VPN-ноды.
- Настройка `nf_conntrack`, `sysctl`, BBR/fq, TCP-буферов и лимитов файловых дескрипторов.
- Защита через UFW, TrafficGuard-auto и Fail2Ban.
- Установка Remnawave Node в Docker Compose.
- Шейпер трафика на базе Reshala eBPF Traffic Shaper.
- Установка z4r.
- Быстрая проверка состояния компонентов.
- Быстрый перезапуск Remnawave Node.

## Меню

```text
0) Обновить Ubuntu и базовые пакеты
1) Сетевые настройки Ubuntu
2) Защита: UFW + TrafficGuard-auto + Fail2Ban
3) Установка Remnawave Node
4) Шейпер трафика
5) Установка z4r
6) Проверки состояния
7) Перезапустить Remnawave Node
8) Установить Сетевые настройки + Защита + Node
q) Выход
```

## Рекомендуемый порядок установки

Для новой VPS обычно достаточно выбрать пункт:

```text
8) Установить Сетевые настройки + Защита + Node
```

Он выполнит:

```text
0 → 1 → 2 → 3
```

После этого можно отдельно настроить:

```text
4) Шейпер трафика
5) Установка z4r
```

## Remnawave Node

Файл ноды создаётся в:

```text
/opt/remnanode/docker-compose.yml
```

Шаблон compose:

```yaml
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=${NODE_PORT}
      - SECRET_KEY=${SECRET_KEY}
```

Значения `NODE_PORT` и `SECRET_KEY` хранятся в:

```text
/opt/remnanode/.env
```

## Быстрый перезапуск ноды

В меню есть пункт:

```text
7) Перезапустить Remnawave Node
```

Он выполняет обновление образа и тихий перезапуск контейнера без открытия live-логов:

```bash
cd /opt/remnanode \
  && docker compose pull \
  && docker compose down \
  && docker compose up -d
```

## Шейпер трафика

Пункт меню:

```text
4) Шейпер трафика
```

Разделы:

```text
1) Создать / изменить правило
2) Просмотреть текущие правила
3) Статистика
4) Полное меню Reshala Shaper
5) Лог сервиса
6) Перезапустить движок
```

Быстрый запуск шейпера после установки:

```bash
ecl-shaper
```

## Проверки состояния

Пункт:

```text
6) Проверки состояния
```

Показывает короткий статус:

```text
Сетевые настройки: применены
Защита: UFW работает, TrafficGuard-auto работает, Fail2Ban работает
Remnawave Node: установлена
z4r: установлен / не установлен
Шейпер: установлен / не установлен
```

Из этого раздела можно перейти в статистику защиты, z4r или шейпер.

## Системная информация

В начале меню отображаются:

- ОС и ядро.
- Аптайм.
- Тип виртуализации.
- Публичный IP.
- Количество CPU и модель процессора.
- Load average.
- RAM и диск.
- Сетевой интерфейс, link speed и RX/TX трафик.
- Статус Docker.
- Статус Remnawave Node.

## Пути

```text
/opt/ecl-vps-kit                  основной каталог ECL VPS Kit
/etc/ecl-vps-kit/settings.env     сохранённые настройки
/opt/remnanode                    Remnawave Node
/opt/reshala-shaper               Reshala eBPF Traffic Shaper
/opt/z4r                          z4r
```

## Команды

```bash
ecl          # главное меню
ecl-shaper   # шейпер трафика
ecl-z4r      # z4r, если установлен
vpskit       # алиас для совместимости
```


## Удаление управляющего скрипта

Команда ниже удаляет только ECL VPS Kit и его быстрые команды. Она не удаляет Remnawave Node, Docker, UFW, Fail2Ban, TrafficGuard-auto, z4r, шейпер и сетевые настройки сервера.

```bash
sudo rm -rf /opt/ecl-vps-kit /etc/ecl-vps-kit \
  /usr/local/bin/ecl /usr/local/bin/vpskit \
  /usr/local/bin/ecl-shaper /usr/local/bin/ecl-z4r \
  /usr/bin/ecl /usr/bin/vpskit
```

## Требования

- Ubuntu 22.04/24.04.
- Root-доступ.
- systemd.
- Docker для Remnawave Node.
- Ядро Linux 5.4+ для eBPF-шейпера.
