#!/bin/bash
# teardown.sh - Faxina completa na /home e no /tmp da máquina atual
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAR_DIR="$PROJECT_ROOT/algorithmJARs"
WORK_DIR="/tmp/$USER/tcc_env"

echo "🔥 Iniciando faxina geral do ambiente..."

# 1. Desativar Conda se estiver ativo
if command -v conda &> /dev/null; then
    conda deactivate 2>/dev/null || true
fi

# 2. Limpar resquícios antigos da /home (libera a cota)
echo "🗑️ Removendo instalações antigas da /home..."
rm -rf "$HOME/miniconda3" "$HOME/.conda" "$HOME/.pyenv"
rm -rf "$HOME/.m2" "$HOME/.cache/pip" "$HOME/.cache/conda"
rm -rf "$PROJECT_ROOT/deps" "$JAR_DIR"

# 3. Limpar ambiente temporário em /tmp
echo "🗑️ Removendo ambiente temporário em $WORK_DIR..."
rm -rf "$WORK_DIR"

echo "✅ Faxina concluída!"
echo "📊 Status atual da tua cota de disco no DINF:"
quota -s 2>/dev/null || quota 2>/dev/null || df -h "$HOME"