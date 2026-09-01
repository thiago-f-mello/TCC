#!/bin/bash
set -e

# --- DETECÇÃO DINÂMICA DA RAIZ DO PROJETO ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- AMBIENTE CONDA ---
if [ -n "$CONDA_EXE" ]; then
    CONDA_SH="$(dirname "$CONDA_EXE")/../etc/profile.d/conda.sh"
    if [ -f "$CONDA_SH" ]; then
        source "$CONDA_SH"
        conda activate db_env 2>/dev/null || true
    fi
fi

# --- SUBINDO POSTGRESQL ---
"$ROOT_DIR/config/psql.sh"

# --- DEFINIÇÃO DE CAMINHOS RELATIVOS ---
DCVALIDITY_DIR="${DCVALIDITY_DIR:-$ROOT_DIR/../DCValidity}"
HOLOCLEAN_DIR="${HOLOCLEAN_DIR:-$ROOT_DIR/../holoclean}"

HYDRA_JAR="$DCVALIDITY_DIR/algorithmJARs/hydra.jar"
HOSPITAL_DIRTY="${HOSPITAL_DIRTY:-$HOLOCLEAN_DIR/testdata/hospital.csv}"
GABARITO_REAL="${GABARITO_REAL:-$HOLOCLEAN_DIR/testdata/hospital_clean.csv}"

LINES="2000"
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:32

# --- EXECUÇÃO ÚNICA DO PIPELINE (TESTE DE SANIDADE) ---
echo "========================================="
echo ">>> INICIANDO EXECUÇÃO ÚNICA (TESTE) <<<"
echo "========================================="

DATASET_ENTRADA="$HOSPITAL_DIRTY"
RAW_DC="$ROOT_DIR/dcs/raw/dcs_hydra_test.txt"
FILTERED_DC="$ROOT_DIR/dcs/processed/dcs_hydra_test_filtered.txt"
SAIDA_CSV="$ROOT_DIR/dcs/processed/hospital_limpo_hydra_teste.csv"

# PASSO 1: Descoberta de DCs com Hydra
echo "[PASSO 1] Executando Hydra para descobrir restrições..."
cd "$DCVALIDITY_DIR"
java -jar "$HYDRA_JAR" "$DATASET_ENTRADA" 0.00 "$LINES"
cd "$ROOT_DIR"

# PASSO 2: Conversão de Formato das DCs (Metanome -> HoloClean)
echo "[PASSO 2] Traduzindo a sintaxe lógica das DCs..."
python3 "$ROOT_DIR/src/parsers/meta_parser.py" "$RAW_DC"

# PASSO 3: Módulo de Filtragem Sintática e Semântica
echo "[PASSO 3] Aplicando filtro de redundância e generalização..."
python3 "$ROOT_DIR/src/filters/redundancy_filter.py" "$RAW_DC" "$FILTERED_DC"

# PASSO 4: HoloClean (Reparo)
echo "[PASSO 4] Preparando banco de dados e executando HoloClean..."
dropdb holo 2>/dev/null || true
createdb -O holocleanuser holo 2>/dev/null || true

python3 "$ROOT_DIR/src/repair/meta_repair.py" "$FILTERED_DC" "$SAIDA_CSV" "$DATASET_ENTRADA" "$GABARITO_REAL"
STATUS=$?

if [ $STATUS -ne 0 ]; then
    echo "Erro fatal durante a execução do HoloClean!"
    exit 1
fi

echo "========================================="
echo ">>> Teste concluído com sucesso! <<<"
echo "Resultado salvo em: $SAIDA_CSV"
echo "========================================="