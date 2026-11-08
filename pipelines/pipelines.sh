#!/bin/bash
set -e

DISCOVERY="$1"
CLEANING="$2"
DATASET="$3"

if [ -z "$DISCOVERY" ] || [ -z "$CLEANING" ] || [ -z "$DATASET" ]; then
    echo "Uso: $0 <ferramenta_descoberta> <ferramenta_limpeza> <base_de_dados>"
    echo "  Descoberta: lima, dcfinder, fastdc, hydra"
    echo "  Limpeza:    holoclean, uniclean, horizon"
    echo "  Base:       hospital"
    exit 1
fi

# ---------------------------------------------------------
# 1. DETECÇÃO DE CAMINHOS E AMBIENTE (GENÉRICO)
# ---------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
USER_HOME="$HOME"

CONDA_LOCATIONS=(
    "$USER_HOME/miniconda/etc/profile.d/conda.sh"
    "$USER_HOME/miniconda3/etc/profile.d/conda.sh"
    "$USER_HOME/anaconda3/etc/profile.d/conda.sh"
    "/opt/conda/etc/profile.d/conda.sh"
)

CONDA_PATH=""
for loc in "${CONDA_LOCATIONS[@]}"; do
    if [ -f "$loc" ]; then
        CONDA_PATH="$loc"
        break
    fi
done

if [ -z "$CONDA_PATH" ] && command -v conda &> /dev/null; then
    CONDA_PATH="$(conda info --base)/etc/profile.d/conda.sh"
fi

if [ -n "$CONDA_PATH" ] && [ -f "$CONDA_PATH" ]; then
    source "$CONDA_PATH"
    conda activate db_env
else
    echo "Erro: Não foi possível localizar a instalação do Conda."
    exit 1
fi

if [ -n "$CONDA_PREFIX" ]; then
    export PGDATA="$CONDA_PREFIX/var/lib/pgsql/data"
else
    export PGDATA="$USER_HOME/miniconda/envs/db_env/var/lib/pgsql/data"
fi

export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:32

# --- SUBINDO POSTGRESQL ---
"$ROOT_DIR/config/psql.sh"

# --- CAMINHOS DOS DATASETS E FERRAMENTAS ---
DCVALIDITY_DIR="${DCVALIDITY_DIR:-$ROOT_DIR/../DCValidity}"
HOLOCLEAN_DIR="${HOLOCLEAN_DIR:-$ROOT_DIR/../holoclean}"
LIMA_DIR="${LIMA_DIR:-$ROOT_DIR/../LIMA}"

if [ "$DATASET" = "hospital" ]; then
    HOSPITAL_DIRTY="${HOSPITAL_DIRTY:-$HOLOCLEAN_DIR/testdata/hospital.csv}"
    GABARITO_REAL="${GABARITO_REAL:-$HOLOCLEAN_DIR/testdata/hospital_clean.csv}"
    DATASET_ATUAL="$HOSPITAL_DIRTY"
else
    echo "Erro: Base de dados '$DATASET' desconhecida."
    exit 1
fi

MAX_ITERATIONS=10
mkdir -p "$ROOT_DIR/dcs/raw" "$ROOT_DIR/dcs/processed"

echo "============================================================"
echo "Iniciando Pipeline: Descoberta[$DISCOVERY] + Limpeza[$CLEANING] ($DATASET)"
echo "============================================================"

for i in $(seq 1 $MAX_ITERATIONS); do
    echo "--------------------------------------------------"
    echo ">>> ITERAÇÃO $i / $MAX_ITERATIONS <<<"
    echo "--------------------------------------------------"

    RAW_DC="$ROOT_DIR/dcs/raw/dcs_${DISCOVERY}_${i}.txt"
    PARSED_DC="$ROOT_DIR/dcs/raw/dcs_${DISCOVERY}_parsed_${i}.txt"
    FILTERED_DC="$ROOT_DIR/dcs/processed/dcs_${DISCOVERY}_filtered_${i}.txt"

    # --- PASSO 1: DESCOBERTA DE DCs ---
    case "$DISCOVERY" in
        dcfinder)
            LINES="5000"
            cd "$DCVALIDITY_DIR"
            java -jar "$DCVALIDITY_DIR/algorithmJARs/DCFinder.jar" "$DATASET_ATUAL" 0.00 "$LINES"
            [ -f "output.txt" ] && mv output.txt "$RAW_DC" || { echo "Erro: DCFinder não gerou output.txt"; exit 1; }
            cd "$ROOT_DIR"
            python3 "$ROOT_DIR/src/parsers/meta_parser.py" "$RAW_DC" "$PARSED_DC" "$DATASET_ATUAL"
            ;;
        fastdc)
            LINES="100"
            cd "$DCVALIDITY_DIR"
            java -jar "$DCVALIDITY_DIR/algorithmJARs/FastDC.jar" "$DATASET_ATUAL" 0.00 "$LINES"
            [ -f "output.txt" ] && mv output.txt "$RAW_DC" || { echo "Erro: FastDC não gerou output.txt"; exit 1; }
            cd "$ROOT_DIR"
            python3 "$ROOT_DIR/src/parsers/meta_parser.py" "$RAW_DC" "$PARSED_DC" "$DATASET_ATUAL"
            ;;
        hydra)
            LINES="3000"
            cd "$DCVALIDITY_DIR"
            java -jar "$DCVALIDITY_DIR/algorithmJARs/hydra.jar" "$DATASET_ATUAL" 0.00 "$LINES"
            [ -f "output.txt" ] && mv output.txt "$RAW_DC" || { echo "Erro: Hydra não gerou output.txt"; exit 1; }
            cd "$ROOT_DIR"
            python3 "$ROOT_DIR/src/parsers/meta_parser.py" "$RAW_DC" "$PARSED_DC" "$DATASET_ATUAL"
            ;;
        lima)
            LINES="5000"
            case $i in
                1) SOUNDNESS="0.50" ;;
                2) SOUNDNESS="0.40" ;;
                3) SOUNDNESS="0.30" ;;
                4) SOUNDNESS="0.20" ;;
                *) SOUNDNESS="0.10" ;;
            esac
            IFILE="$(realpath "$DATASET_ATUAL" 2>/dev/null || echo "$DATASET_ATUAL")"
            cp "$IFILE" "$LIMA_DIR/hospital_temp.csv"
            cd "$LIMA_DIR"
            java -jar "$LIMA_DIR/target/LIMA-0.1.jar" "hospital_temp.csv" "$SOUNDNESS" "$LINES"
            rm -f "hospital_temp.csv"
            [ -s "output.txt" ] && cp "output.txt" "$RAW_DC" || { echo "Erro: LIMA não gerou output.txt"; exit 1; }
            cd "$ROOT_DIR"
            python3 "$ROOT_DIR/src/parsers/lima_parser.py" "$RAW_DC" "$PARSED_DC"
            ;;
        *)
            echo "Erro: Ferramenta de descoberta inválida ($DISCOVERY)."
            exit 1
            ;;
    esac

    # --- PASSO 2: FILTRAGEM (PRUNING) ---
    python3 "$ROOT_DIR/src/filters/redundancy_filter.py" "$PARSED_DC" "$FILTERED_DC" "$DATASET_ATUAL"

    # --- PASSO 3: REPARO / LIMPEZA ---
    SAIDA_CSV="$ROOT_DIR/dcs/processed/${DATASET}_limpo_${DISCOVERY}_${CLEANING}_v${i}.csv"

    set +e
    case "$CLEANING" in
        holoclean)
            dropdb holo 2>/dev/null || true
            createdb -O holocleanuser holo 2>/dev/null || true
            if [ "$DISCOVERY" = "lima" ]; then
                python3 "$ROOT_DIR/src/repair/lima_repair.py" "$FILTERED_DC" "$SAIDA_CSV" "$DATASET_ATUAL" "$GABARITO_REAL"
            else
                python3 "$ROOT_DIR/src/repair/meta_repair.py" "$FILTERED_DC" "$SAIDA_CSV" "$DATASET_ATUAL" "$GABARITO_REAL"
            fi
            ;;
        uniclean)
            # Ajuste o script Python correspondente ao uniclean se necessário
            python3 "$ROOT_DIR/src/repair/uniclean_repair.py" "$FILTERED_DC" "$SAIDA_CSV" "$DATASET_ATUAL" "$GABARITO_REAL"
            ;;
        horizon)
            # Ajuste o script Python correspondente ao horizon se necessário
            python3 "$ROOT_DIR/src/repair/horizon_repair.py" "$FILTERED_DC" "$SAIDA_CSV" "$DATASET_ATUAL" "$GABARITO_REAL"
            ;;
        *)
            echo "Erro: Ferramenta de limpeza inválida ($CLEANING)."
            exit 1
            ;;
    esac
    STATUS=$?
    set -e

    # Checagem de Early Stopping (Estabilidade)
    if [ $STATUS -eq 0 ] && cmp -s "$DATASET_ATUAL" "$SAIDA_CSV"; then
        STATUS=10
    fi

    if [ $STATUS -eq 10 ]; then
        echo ">> EARLY STOPPING DISPARADO NA ITERAÇÃO $i (Estabilidade semântica atingida) <<"
        break
    fi

    if [ $STATUS -ne 0 ]; then
        echo "Erro fatal na limpeza com $CLEANING na iteração $i (Status $STATUS)"
        exit 1
    fi

    DATASET_ATUAL="$SAIDA_CSV"
    echo ">>> Iteração $i finalizada com sucesso! <<<"
done

echo "[FIM] Pipeline $DISCOVERY + $CLEANING concluído com sucesso!"