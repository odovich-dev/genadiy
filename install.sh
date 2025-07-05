#!/bin/bash

# Установка зависимостей
sudo apt update && sudo apt install -y python3 python3-venv python3-pip curl screen git gnupg

# Установка Yarn (обновленный способ)
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/yarn.gpg >/dev/null
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt update && sudo apt install -y yarn

# Установка Node
curl -sSL https://raw.githubusercontent.com/zunxbt/installation/main/node.sh | bash

# Обновление переменных окружения для текущей сессии
export PATH="$HOME/.local/bin:$PATH"
source ~/.bashrc 2>/dev/null || true

# Установка глобальных npm пакетов (после установки Node)
sudo npm install -g yarn
sudo npm install -g n
sudo npm install encoding pino-pretty

# Установка LTS версии Node и конкретной версии
sudo n lts
n 20.18.0

# Проверка и убийство старых screen-сессий
screen -ls | grep "\.gensyn" | cut -d. -f1 | awk '{print $1}' | xargs -r kill

# Убиваем процессы, слушающие порт 3000 (node и туннель)
lsof -ti:3000 | xargs kill -9 2>/dev/null || true

# Обработка входных параметров
RECLONE="${1:-n}"                 # Параметр для управления клонированием (по умолчанию 'n')

# Работа с репозиторием RL Swarm
if [ "$RECLONE" == "y" ]; then
    echo "📥 Удаляю старую папку и клонирую заново..."
    rm -rf rl-swarm
    git clone https://github.com/odovich-dev/rl-swarm.git
    cd rl-swarm
else
    if [ ! -d "rl-swarm" ]; then
        echo "📥 Папка не найдена, клонирую..."
        git clone https://github.com/odovich-dev/rl-swarm.git
    fi
    cd rl-swarm
    echo "🔄 Обновляю репозиторий через git pull..."
    git pull
fi

# Проверяем наличие архива вида число.tar в /root
ARCHIVE_FOUND=$(find /root -maxdepth 1 -type f -name '[0-9]*.tar' | head -n 1)
if [ -n "$ARCHIVE_FOUND" ]; then
    echo "📦 Найден архив $ARCHIVE_FOUND. Распаковываю..."
    tar -xvf "$ARCHIVE_FOUND" -C /root
    echo "✅ Архив успешно распакован!"
    
    # Удаление файлов из папки temp-data
    if [ -d "/root/rl-swarm/modal-login/temp-data/" ]; then
        echo "🗑️  Удаляю файлы из /root/rl-swarm/modal-login/temp-data/..."
        rm -rf /root/rl-swarm/modal-login/temp-data/*
        echo "✅ Файлы из temp-data успешно удалены!"
    else
        echo "ℹ️  Папка /root/rl-swarm/modal-login/temp-data/ не найдена."
    fi
else
    echo "ℹ️  Архивов для распаковки не найдено."
fi

# Запуск в screen
screen -dmS gensyn bash -c 'cd ~/rl-swarm && if [ ! -d ".venv" ]; then python3 -m venv .venv; fi && source .venv/bin/activate && pip install --upgrade pip && pip install accelerate==1.7 && trap "" SIGINT && ./run_rl_swarm.sh; exec bash -i' &
disown
