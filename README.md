# VPS Node Kit

Готовый каркас репозитория для быстрой настройки VPS под Remnawave Node.

## Что внутри

- Красивое главное меню `ecl` с системной информацией.
- Сетевой тюнинг Ubuntu: `sysctl`, `nf_conntrack`, `nofile`.
- Защита: UFW, TrafficGuard-auto, Fail2Ban. IP панели не хранится в репозитории — скрипт спрашивает его при настройке UFW.
- Установка Remnawave Node через Docker Compose.
- Ограничение скорости клиентов через shaper-модуль из Reshala.
- Запуск внешнего z4r-скрипта отдельным пунктом.
- Проверки статуса: conntrack, TCP, limits, UFW, Fail2Ban, Docker, Remnawave, TrafficGuard.
- Отдельная кнопка перезапуска Remnawave Node с `docker compose pull/down/up/logs`.

## Как опубликовать на GitHub

1. Создай новый репозиторий, например `vps-node-kit`.
2. В файле `install.sh` замени:

```bash
REPO_OWNER="devisoff"
REPO_NAME="ecl-vps-kit"
BRANCH="main"
```

на свои значения.

3. Залей файлы:

```bash
git init
git add .
git commit -m "Initial VPS Node Kit"
git branch -M main
git remote add origin https://github.com/YOURNAME/vps-node-kit.git
git push -u origin main
```

## Установка одной командой

После публикации репозитория:

```bash
wget -O install.sh https://raw.githubusercontent.com/YOURNAME/vps-node-kit/main/install.sh \
  && bash install.sh \
  && ecl
```

## Локальный тест

Если ты распаковал архив на сервере:

```bash
cd vps-node-kit
sudo bash install.sh
```

## Важные замечания

- Модуль UFW сбрасывает старые правила. Перед запуском проверь SSH-порт, IP панели и порт ноды.
- Модуль Remnawave Node создаёт `/opt/remnanode/docker-compose.yml` и выставляет права `600`, потому что там хранится `SECRET_KEY`.
- Модуль ограничения скорости не копирует код Reshala в этот репозиторий. Он скачивает upstream в `/opt/reshala-shaper` и добавляет команду `vps-shaper`, чтобы открывать только меню шейпера.
- Модуль z4r по умолчанию просит подтверждение и не запускается без согласия.

## Команды после установки

```bash
ecl         # главное меню
vpskit      # старый алиас на то же меню
vps-shaper  # меню ограничения скорости, если установлен пункт 4
```
