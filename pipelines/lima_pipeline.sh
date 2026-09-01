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
LIMA_DIR="${LIMA_DIR:-$ROOT_DIR/../LIMA}"
HOLOCLEAN_DIR="${HOLOCLEAN_DIR:-$ROOT_DIR/../holoclean}"

LIMA_JAR="$LIMA_DIR/target/LIMA-0.1.jar"
HOSPITAL_DIRTY="${HOSPITAL_DIRTY:-$HOLOCLEAN_DIR/testdata/hospital.csv}"
GABARITO_REAL="${GABARITO_REAL:-$HOLOCLEAN_DIR/testdata/hospital_clean.csv}"

LINES="5000"
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:32

# --- INÍCIO DO LOOP DE 5 ITERAÇÕES ---
DATASET_ATUAL="$HOSPITAL_DIRTY"
REGRAS_ANTERIOR=""

for i in {1..5}
do
    echo ""
    echo "============================================================"
    echo ">>> INICIANDO ITERAÇÃO $i DE 5 <<<"
    echo "Entrada: $(basename "$DATASET_ATUAL")"
    
    # ESTRATÉGIA DE DECAIMENTO DINÂMICO DE SOUNDNESS
    case $i in
        1) export SOUNDNESS="0.50" ;;
        2) export SOUNDNESS="0.40" ;;
        3) export SOUNDNESS="0.30" ;;
        4) export SOUNDNESS="0.20" ;;
        5) export SOUNDNESS="0.10" ;;
    esac
    
    echo "Soundness configurado para esta rodada: $SOUNDNESS"
    echo "============================================================"

    # PASSO 1: Descoberta com LIMA
    echo "[PASSO 1.$i] Executando LIMA..."
    cd "$LIMA_DIR"
    java -jar "$LIMA_JAR" "$DATASET_ATUAL" "$SOUNDNESS" "$LINES"

    if [ ! -s "output.txt" ]; then
        echo "ERRO: LIMA não gerou regras em $LIMA_DIR/output.txt"
        exit 1
    fi

    RAW_DC="$ROOT_DIR/dcs/raw/regras_lima_v$i.txt"
    cp "output.txt" "$RAW_DC"
    cd "$ROOT_DIR"

    # Comparação de Regras (Diff)
    if [ -n "$REGRAS_ANTERIOR" ]; then
        echo "[INFO] Comparando regras com a iteração anterior..."
        DIFF_FILE="$ROOT_DIR/dcs/processed/diff_regras_v$((i-1))_vs_v$i.txt"
        diff -y --suppress-common-lines "$REGRAS_ANTERIOR" "$RAW_DC" > "$DIFF_FILE" || true
    fi
    REGRAS_ANTERIOR="$RAW_DC"

    # PASSO 2: Parser das DCs LIMA (LIMA -> HoloClean)
    echo "[PASSO 2.$i] Traduzindo DCs do LIMA..."
    python3 "$ROOT_DIR/src/parsers/lima_parser.py" "$RAW_DC"

    # PASSO 3: Módulo de Filtragem Sintática e Semântica
    FILTERED_DC="$ROOT_DIR/dcs/processed/dcs_lima_filtered_v$i.txt"
    echo "[PASSO 3.$i] Aplicando filtro de redundância..."
    python3 "$ROOT_DIR/src/filters/redundancy_filter.py" "$RAW_DC" "$FILTERED_DC"

    # PASSO 4: HoloClean (Reparo)
    echo "[PASSO 4.$i] Preparando banco e executando HoloClean..."
    dropdb holo 2>/dev/null || true
    createdb -O holocleanuser holo 2>/dev/null || true

    SAIDA_CSV="$ROOT_DIR/dcs/processed/hospital_limpo_lima_v$i.csv"

    # Captura código de término customizado (Early Stopping = 10)
    set +e
    python3 "$ROOT_DIR/src/repair/lima_repair.py" "$FILTERED_DC" "$SAIDA_CSV" "$DATASET_ATUAL" "$GABARITO_REAL"
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
    echo ">>> Iteração $i finalizada com sucesso!"
done

echo ""
echo "============================================================"
echo "PIPELINE FINALIZADO COM CRITÉRIO DE PARADA!"
echo "Dataset Final Consolidado: $DATASET_ATUAL"
echo "============================================================"