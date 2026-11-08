#!/bin/bash
set -e
# setup.sh - Preparação do ambiente TCC com dependências isoladas em deps/

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_DIR="$PROJECT_ROOT/deps"

echo "Iniciando a montagem do ambiente TCC em: $PROJECT_ROOT"

# 1. Instalar o Miniconda3 (se não existir)
if [ ! -d "$HOME/miniconda3" ]; then
    echo "Baixando e instalando Miniconda..."
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh
    bash ~/miniconda.sh -b -p $HOME/miniconda3
    rm ~/miniconda.sh
    export PATH="$HOME/miniconda3/bin:$PATH"
    conda init bash
fi

# 2. Criar ambiente Conda 'db_env' (Python 3.8, PostgreSQL, Java 11, Maven)
echo "Criando/verificando ambiente Conda 'db_env'..."
source "$HOME/miniconda3/bin/activate"
if conda env list | grep -q "db_env"; then
    echo "-> Ambiente 'db_env' já existe."
else
    conda create -n db_env python=3.8 postgresql openjdk=11 maven -c conda-forge -y
fi
conda activate db_env

# 3. Configurar PGDATA do PostgreSQL local
if [ -n "$CONDA_PREFIX" ]; then
    export PGDATA="$CONDA_PREFIX/var/lib/pgsql/data"
else
    export PGDATA="$HOME/miniconda3/envs/db_env/var/lib/pgsql/data"
fi
if [ ! -d "$PGDATA" ]; then
    initdb -D "$PGDATA" || true
fi

# 4. Instalar PyTorch com CUDA e dependências Python
echo "Instalando PyTorch e dependências do pipeline..."
conda install pytorch torchvision torchaudio pytorch-cuda=11.8 -c pytorch -c nvidia -y || conda install pytorch torchvision torchaudio cpuonly -c pytorch -y
pip install --upgrade pip
pip install pandas numpy psycopg2-binary scikit-learn tqdm

# 5. Criar diretório deps/ e clonar repositórios oficiais corretos
mkdir -p "$DEPS_DIR"
cd "$DEPS_DIR"

echo "Clonando repositórios oficiais em $DEPS_DIR..."
[ ! -d "LIMA" ] && git clone https://github.com/NoSocAlgroc/LIMA.git
[ ! -d "HoloClean" ] && git clone https://github.com/HoloClean/HoloClean.git
[ ! -d "metanome-algorithms" ] && git clone https://github.com/HPI-Information-Systems/metanome-algorithms.git

# 6. Compilar LIMA com Maven
if [ -d "LIMA" ]; then
    echo "Compilando LIMA com Maven..."
    cd LIMA
    mvn clean package -DskipTests
    cd "$DEPS_DIR"
fi

# 7. Permissões de execução dos scripts do projeto
cd "$PROJECT_ROOT"
chmod +x config/psql.sh pipelines/pipelines.sh benchmark.sh setup.sh teardown.sh 2>/dev/null || true

echo "Ambiente configurado com sucesso! Para ativar, utilize: conda activate db_env"