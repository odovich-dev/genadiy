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
rm -rf rl-swarm && git clone https://github.com/zunxbt/rl-swarm.git
cd rl-swarm

# Обновление конфигурации
cat > hivemind_exp/configs/mac/grpo-qwen-2.5-0.5b-deepseek-r1.yaml <<EOF
# Model arguments
model_revision: main
torch_dtype: float32 
bf16: false
tf32: false

# Dataset arguments
dataset_id_or_path: 'openai/gsm8k'

# Training arguments
max_steps: 15 
gradient_accumulation_steps: 4
gradient_checkpointing: false 
learning_rate: 5.0e-7
lr_scheduler_type: cosine
warmup_ratio: 0.03

# GRPO arguments
use_vllm: false
num_generations: 2
per_device_train_batch_size: 1
beta: 0.001
max_prompt_length: 256
max_completion_length: 384

# Logging arguments
logging_strategy: steps
logging_steps: 2
report_to:
- tensorboard
save_strategy: "steps"
save_steps: 25
seed: 42

# Script arguments
max_rounds: 10000

# Model-specific arguments
model_name_or_path: unsloth/Qwen2.5-0.5B-Instruct
output_dir: runs/gsm8k/multinode/Qwen2.5-0.5B-Instruct-Gensyn-Swarm
EOF

# Запуск в screen
screen -S gensyn -dm bash -c 'cd ~/rl-swarm && python3 -m venv .venv && source .venv/bin/activate && printf "A\n0.5\n" | ./run_rl_swarm.sh'
