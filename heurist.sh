#!/bin/bash
# Miniconda安装路径
MINICONDA_PATH="$HOME/miniconda"
CONDA_EXECUTABLE="$MINICONDA_PATH/bin/conda"

# 检查是否以root用户运行脚本
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以root用户权限运行。"
    echo "请尝试使用 'sudo -i' 命令切换到root用户，然后再次运行此脚本。"
    exit 1
fi

# 确保 conda 被正确初始化
ensure_conda_initialized() {
    if [ -f "$HOME/.bashrc" ]; then
        source "$HOME/.bashrc"
    fi
    if [ -f "$CONDA_EXECUTABLE" ]; then
        eval "$("$CONDA_EXECUTABLE" shell.bash hook)"
    fi
}

# 检查并安装 Conda
function install_conda() {
    if [ -f "$CONDA_EXECUTABLE" ]; then
        echo "Conda 已安装在 $MINICONDA_PATH"
        ensure_conda_initialized
    else
        echo "Conda 未安装，正在安装..."
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
        bash miniconda.sh -b -p $MINICONDA_PATH
        rm miniconda.sh
        
        # 初始化 conda
        "$CONDA_EXECUTABLE" init
        ensure_conda_initialized
        
        echo 'export PATH="$HOME/miniconda/bin:$PATH"' >> ~/.bashrc
        source ~/.bashrc
    fi
    
    # 验证 conda 是否可用
    if command -v conda &> /dev/null; then
        echo "Conda 安装成功，版本: $(conda --version)"
    else
        echo "Conda 安装可能成功，但无法在当前会话中使用。"
        echo "请在脚本执行完成后，重新登录或运行 'source ~/.bashrc' 来激活 Conda。"
    fi
}

# 检查并安装 Node.js 和 npm
function install_nodejs_and_npm() {
    if command -v node > /dev/null 2>&1; then
        echo "Node.js 已安装，版本: $(node -v)"
    else
        echo "Node.js 未安装，正在安装..."
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        sudo apt-get install -y nodejs git
    fi
    if command -v npm > /dev/null 2>&1; then
        echo "npm 已安装，版本: $(npm -v)"
    else
        echo "npm 未安装，正在安装..."
        sudo apt-get install -y npm
    fi
}

# 检查并安装 PM2
function install_pm2() {
    if command -v pm2 > /dev/null 2>&1; then
        echo "PM2 已安装，版本: $(pm2 -v)"
    else
        echo "PM2 未安装，正在安装..."
        npm install pm2@latest -g
    fi
}

function install_node() {
    read -p "请输入你的钱包地址,0X开头: " MINER_ADDR
    apt update
    apt install curl sudo git iptables python-env build-essential wget bc jq make gcc nano npm -y
    install_conda
    ensure_conda_initialized
    install_nodejs_and_npm
    install_pm2
    echo "克隆 Heurist 仓库"
    git clone https://github.com/heurist-network/miner-release.git
    cd miner-release

    conda create --name heurist-miner python=3.11
    conda activate heurist-miner
    pip install -r requirements.txt

    if [ ! -f .env ]; then
        touch .env
    fi
    echo "MINER_ID_0=$MINER_ADDR" >> .env

    # 生成验证者地址
    echo "生成验证者地址..."
    python /root/miner-release/auth/generator.py

    # 提示用户备份验证者地址
    echo "请备份生成的验证者地址，地址文件位于 ~/.heurist-keys/。"
    read -p "确认已备份验证者地址后，按回车继续..."

    echo "选择启动的矿工:"
    echo "1. Stable Diffusion(SD)"
    echo "2. Large Language Model(LLM)(首次安装请选择LLM)"
    read -p "确认你的选择 (1 or 2): " choice

    if [ "$choice" -eq 1 ]; then
        echo "可用的 Stable Diffusion 模型:"
        echo "1. Stable Diffusion 1.5 checkpoint and LoRA (0.3x, 最低 GPU: 3070, 4060Ti, A4000)"
        echo "2. Stable Diffusion XL checkpoint (1x, 最低 GPU: 3090, 4080, A4500)"
        echo "3. Stable Diffusion XL LoRA (1.2x, 最低 GPU: 3090, 4080, A4500)"
        echo "4. Flux (0, 官方暂时已经禁用, 最低 GPU: 4090, A100)"
        read -p "选择模型 (1-4): " sd_model_choice

        case $sd_model_choice in
            1)
                sd_model_id="sd-miner-1.5"
                ;;
            2)
                sd_model_id="sd-miner-xl"
                ;;
            3)
                sd_model_id="sd-miner-xl-lora"
                ;;
            4)
                echo "Flux 模型暂时禁用，无法启动。"
                exit 1
                ;;
            *)
                echo "无效选择，退出."
                exit 1
                ;;
        esac

        echo "启动 SD 矿工..."
        pm2 start python --name "sd-miner" -- sd-miner.py --model "$sd_model_id"
    elif [ "$choice" -eq 2 ]; then
        echo "可用的 LLM 模型:"
        echo "1. dolphin-2.9-llama3-8b (0.5x, 24GB VRAM)"
        echo "2. hermes-3-llama3.1-8b (0.5x, 24GB VRAM)"
        echo "3. theia-llama-3.1-8b (0.5x, 24GB VRAM)"
        echo "4. openhermes-mixtral-8x7b-gptq (1x, 40GB VRAM)"
        read -p "选择模型 (1-4): " model_choice

        case $model_choice in
            1)
                model_id="dolphin-2.9-llama3-8b"
                ;;
            2)
                model_id="hermes-3-llama3.1-8b"
                ;;
            3)
                model_id="theia-llama-3.1-8b"
                ;;
            4)
                model_id="openhermes-mixtral-8x7b-gptq"
                ;;
            *)
                echo "无效选择，退出."
                exit 1
                ;;
        esac

        echo "启动 LLM 矿工..."
        pm2 start ./llm-miner-starter.sh --name "llm-miner" -- "$model_id"
    else
        echo "错误选择,退出."
        exit 1
    fi
}

# 主菜单
function main_menu() {
    clear
    echo "脚本以及教程由推特用户大赌哥 @y95277777 编写，免费开源，请勿相信收费"
    echo "=========================Heurist节点安装======================================="
    echo "节点社区 Telegram 群组:https://t.me/niuwuriji"
    echo "节点社区 Telegram 频道:https://t.me/niuwuriji"
    echo "请选择要执行的操作:"
    echo "1. 安装矿工节点"
 
    read -p "请输入选项（1-）: " OPTION
    case $OPTION in
    1) install_node ;;
    esac
}

# 显示主菜单
main_menu
