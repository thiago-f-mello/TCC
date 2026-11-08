#!/bin/bash
# teardown.sh - Limpeza completa do ambiente, caches e pastas deps/

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_DIR="$PROJECT_ROOT/deps"

echo "Iniciando limpeza total do ambiente TCC..."

# 1. Desativar ambientes Conda ativos
if command -v conda &> /dev/null; then
    echo "Desativando Conda..."
    conda deactivate 2>/dev/null || true
fi

# 2. Remover Miniconda3 e .conda do home
echo "Removendo Miniconda3 e .conda..."
rm -rf ~/miniconda3 ~/.conda

# 3. Limpar diretório deps/ do projeto
echo "Removendo pasta $DEPS_DIR..."
rm -rf "$DEPS_DIR"

# 4. Limpeza profunda de caches (Maven, Pip, Conda, HoloClean)
echo "Limpando caches de build e pacotes..."
rm -rf ~/.m2/repository/*
rm -rf ~/.cache/pip/*
rm -rf ~/.cache/conda/*
rm -rf ~/.cache/holoclean/*
rm -rf ~/.cache/*

# 5. Exibir cota final de disco
echo "Cota de disco restante:"
quota -v 2>/dev/null || true

echo "Terraplanagem concluída!"