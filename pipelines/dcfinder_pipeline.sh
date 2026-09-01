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
# Ajuste aqui se o diretório do DCValidity/HoloClean estiver em outro nível
DCVALIDITY_DIR="${DCVALIDITY_DIR:-$ROOT_DIR/../DCValidity}"
HOLOCLEAN_DIR="${HOLOCLEAN_DIR:-$ROOT_DIR/../holoclean}"

DCFINDER_JAR="$DCVALIDITY_DIR/algorithmJARs/DCFinder.jar"
HOSPITAL_DIRTY="${HOSPITAL_DIRTY:-$HOLOCLEAN_DIR/testdata/hospital.csv}"
GABARITO_REAL="${GABARITO_REAL:-$HOLOCLEAN_DIR/testdata/hospital_clean.csv}"

LINES="5000"
MAX_ITERATIONS=10
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:32

# --- INÍCIO DO PIPELINE INCREMENTAL ---
echo "Iniciando pipeline incremental com DCFinder + HoloClean..."
DATASET_ATUAL="$HOSPITAL_DIRTY"

for i in $(seq 1 $MAX_ITERATIONS); do
    echo "========================================="
    echo ">>> INICIANDO ITERAÇÃO $i <<<"
    echo "========================================="

    # PASSO 1: Descoberta de DCs com DCFinder
    echo "[PASSO 1.$i] Executando DCFinder..."
    cd "$DCVALIDITY_DIR"
    java -jar "$DCFINDER_JAR" "$DATASET_ATUAL" 0.00 "$LINES"
    cd "$ROOT_DIR"

    # PASSO 2: Parser das DCs (Metanome -> HoloClean)
    RAW_DC="$ROOT_DIR/dcs/raw/dcs_dcfinder_$i.txt"
    FILTERED_DC="$ROOT_DIR/dcs/processed/dcs_dcfinder_filtered_$i.txt"
    
    echo "[PASSO 2.$i] Convertendo formato das DCs..."
    python3 "$ROOT_DIR/src/parsers/meta_parser.py" "$RAW_DC"

    # PASSO 3: Módulo de Filtragem Sintática e Semântica
    echo "[PASSO 3.$i] Aplicando filtro de redundância e generalização..."
    python3 "$ROOT_DIR/src/filters/redundancy_filter.py" "$RAW_DC" "$FILTERED_DC"

    # PASSO 4: HoloClean (Reparo)
    echo "[PASSO 4.$i] Preparando banco de dados e executando HoloClean..."
    dropdb holo 2>/dev/null || true
    createdb -O holocleanuser holo 2>/dev/null || true

    SAIDA_CSV="$ROOT_DIR/dcs/processed/hospital_limpo_dcfinder_v$i.csv"

    # Permite capturar código de erro customizado (Early Stopping = 10)
    set +e
    python3 "$ROOT_DIR/src/repair/meta_repair.py" "$FILTERED_DC" "$SAIDA_CSV" "$DATASET_ATUAL" "$GABARITO_REAL"
    STATUS=$?
    set -e

    # CHECAGEM DE ESTABILIDADE (EARLY STOPPING)
    if [ $STATUS -eq 0 ] && cmp -s "$DATASET_ATUAL" "$SAIDA_CSV"; then
        echo "-> [AVISO] Nenhuma diferença encontrada entre entrada e saída."
        STATUS=10
    fi

    if [ $STATUS -eq 10 ]; then
        echo ""
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo ">> EARLY STOPPING DISPARADO NA ITERAÇÃO $i <<"
        echo "Motivo: Estabilidade semântica atingida."
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo ""
        break
    fi

    if [ $STATUS -ne 0 ]; then
        echo "Erro fatal no HoloClean durante a iteração $i (Status $STATUS)"
        exit 1
    fi

    DATASET_ATUAL="$SAIDA_CSV"
    echo ">>> Iteração $i finalizada com sucesso! <<<"
    echo ""
done

echo "[FIM] Pipeline concluído."