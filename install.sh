#!/bin/bash

# Установка зависимостей
sudo apt update && sudo apt install -y python3 python3-venv python3-pip curl screen git gnupg

# Установка Yarn
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt update && sudo apt install -y yarn

# Установка Node
curl -sSL https://raw.githubusercontent.com/zunxbt/installation/main/node.sh | bash

# Проверка и убийство старых screen-сессий
killall screen 2>/dev/null || true

# Убиваем процессы, слушающие порт 3000 (node и туннель)
lsof -ti:3000 | xargs kill -9 2>/dev/null || true

# Обработка входных параметров
RECLONE="${3:-n}"                 # Параметр для управления клонированием (по умолчанию 'n')
MAX_STEPS="${1:-30}"             # По умолчанию 30
TORCH_DTYPE="${2:-16}"          # По умолчанию 16 = float16

# Обработка параметра torch_dtype
if [ "$TORCH_DTYPE" == "16" ]; then
    TORCH_DTYPE_TEXT="float16"
elif [ "$TORCH_DTYPE" == "32" ]; then
    TORCH_DTYPE_TEXT="float32"
else
    echo "❌ Неверное значение torch_dtype: $TORCH_DTYPE. Используй 16 или 32."
    exit 1
fi

echo "✅ Установка конфигурации: max_steps=$MAX_STEPS, torch_dtype=$TORCH_DTYPE_TEXT, reclone=$RECLONE"

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

# Обновление конфигурации
CONFIG_FILE="hivemind_exp/configs/mac/grpo-qwen-2.5-0.5b-deepseek-r1.yaml"

sed -i "s/^max_steps: .*/max_steps: $MAX_STEPS/" "$CONFIG_FILE"
sed -i "s/^torch_dtype: .*/torch_dtype: $TORCH_DTYPE_TEXT/" "$CONFIG_FILE"

echo "✅ Конфигурация успешно обновлена."

# Проверяем наличие архива вида число.tar в /root
ARCHIVE_FOUND=$(find /root -maxdepth 1 -type f -name '[0-9]*.tar' | head -n 1)
if [ -n "$ARCHIVE_FOUND" ]; then
    echo "📦 Найден архив $ARCHIVE_FOUND. Распаковываю..."
    tar -xvf "$ARCHIVE_FOUND" -C /root
    echo "✅ Архив успешно распакован!"
else
    echo "ℹ️  Архивов для распаковки не найдено."
fi

# Запуск в screen
screen -dmS gensyn bash -c 'cd ~/rl-swarm && python3 -m venv .venv && source .venv/bin/activate && trap "" SIGINT && ./run_rl_swarm.sh; exec bash -i' &
disown
