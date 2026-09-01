#!/bin/bash
set -e

# Detecta a raiz do repositório a partir da localização do próprio script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Define caminhos dinâmicos usando o diretório HOME do usuário atual
CONDA_ENV_DIR="${CONDA_PREFIX:-$HOME/miniconda/envs/db_env}"
export PGDATA="${PGDATA:-$CONDA_ENV_DIR/var/lib/pgsql/data}"
LOG_FILE="$ROOT_DIR/postgres.log"

# --- PASSO 00: PostgreSQL ---
echo "[PASSO 0] Verificando PostgreSQL..."

if [ ! -d "$PGDATA" ]; then
    echo "[PASSO 0] Diretório PGDATA não encontrado. Inicializando banco em: $PGDATA"
    mkdir -p "$PGDATA"
    initdb -D "$PGDATA"
fi

if ! pg_ctl -D "$PGDATA" status > /dev/null 2>&1; then
    echo "[PASSO 0] Iniciando serviço do PostgreSQL..."
    pg_ctl -D "$PGDATA" -l "$LOG_FILE" start -w
else
    echo "[PASSO 0] PostgreSQL já está em execução."
fi

# Criação do usuário do HoloClean (se não existir)
createuser -s holocleanuser 2>/dev/null || true