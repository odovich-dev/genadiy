#!/bin/bash

# Установка зависимостей
sudo apt update && sudo apt install -y python3 python3-venv python3-pip curl screen git gnupg

# Установка Yarn
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt update && sudo apt install -y yarn

# Установка Node
curl -sSL https://raw.githubusercontent.com/zunxbt/installation/main/node.sh | bash

# Клонирование RL Swarm
rm -rf rl-swarm && git clone https://github.com/odovich-dev/rl-swarm.git
cd rl-swarm

# Обработка входных параметров
MAX_STEPS="${1:-30}"            # По умолчанию 30
TORCH_DTYPE="${2:-16}"          # По умолчанию 16 = float16

# Конвертируем dtype в текст
if [ "$TORCH_DTYPE" == "16" ]; then
    TORCH_DTYPE_TEXT="float16"
elif [ "$TORCH_DTYPE" == "32" ]; then
    TORCH_DTYPE_TEXT="float32"
else
    echo "❌ Неверное значение torch_dtype: $TORCH_DTYPE. Используй 16 или 32."
    exit 1
fi

echo "✅ Установка конфигурации: max_steps=$MAX_STEPS, torch_dtype=$TORCH_DTYPE_TEXT"

# Обновление конфигурации
CONFIG_FILE="hivemind_exp/configs/mac/grpo-qwen-2.5-0.5b-deepseek-r1.yaml"

# Заменяем max_steps
sed -i "s/^max_steps: .*/max_steps: $MAX_STEPS/" "$CONFIG_FILE"

# Заменяем torch_dtype
sed -i "s/^torch_dtype: .*/torch_dtype: $TORCH_DTYPE_TEXT/" "$CONFIG_FILE"

echo "✅ Конфигурация успешно обновлена."

# Запуск в screen
screen -S gensyn -dm bash -c 'cd ~/rl-swarm && python3 -m venv .venv && source .venv/bin/activate && ./run_rl_swarm.sh'
