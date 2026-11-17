#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_NAME="${USER:-tfm22}"
WORK_DIR="/tmp/$USER_Name/tcc_env"

echo "🧹 Limpando arquivos gerados nos experimentos..."

# 1. Limpa DCs brutas e processadas na raiz do projeto (mantendo o .gitkeep se houver)
if [ -d "$PROJECT_DIR/dcs/raw" ]; then
    find "$PROJECT_DIR/dcs/raw" -type f ! -name '.gitkeep' -delete
    echo " -> Removidos arquivos de dcs/raw/"
fi

if [ -d "$PROJECT_DIR/dcs/processed" ]; then
    find "$PROJECT_DIR/dcs/processed" -type f ! -name '.gitkeep' -delete
    echo " -> Removidos arquivos de dcs/processed/"
fi

# 2. Limpa a pasta de logs de execução
if [ -d "$PROJECT_DIR/logs" ]; then
    rm -rf "$PROJECT_DIR/logs"
    echo " -> Removidos logs de execução (pasta logs/)"
fi

# 3. Limpeza opcional dos resultados em /tmp (caso queira resetar tudo das ferramentas)
if [ -d "$WORK_DIR" ]; then
    read -p "Deseja também limpar os arquivos temporários e caches em /tmp (UniClean/HoloClean)? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$WORK_DIR/deps/UniClean/Uniclean_cleaned_data"
        rm -rf "$WORK_DIR/deps/UniClean/Uniclean_results"
        echo " -> Limpos caches e resultados temporários em /tmp"
    fi
fi

echo "✨ Limpeza concluída com sucesso! Ambiente pronto para novos testes."