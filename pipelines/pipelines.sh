#!/bin/bash
set -e

DISCOVERY="$1"
CLEANING="$2"
DATASET="$3"
MAX_ITERATIONS=10

if [ "$4" = "-n" ] && [ -n "$5" ]; then
    MAX_ITERATIONS="$5"
fi

if [ -z "$DISCOVERY" ] || [ -z "$CLEANING" ] || [ -z "$DATASET" ]; then
    echo "Uso: $0 <ferramenta_descoberta> <ferramenta_limpeza> <base_de_dados> [-n max_iteracoes]"
    exit 1
fi

# ---------------------------------------------------------
# 1. DETECÇÃO DE CAMINHOS E AMBIENTE (/tmp + árvore TCC)
# ---------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="/tmp/$USER/tcc_env"

CONDA_LOCATIONS=(
    "$WORK_DIR/miniconda3/etc/profile.d/conda.sh"
    "$HOME/miniconda3/etc/profile.d/conda.sh"
    "$HOME/miniconda/etc/profile.d/conda.sh"
)

CONDA_PATH=""
for loc in "${CONDA_LOCATIONS[@]}"; do
    if [ -f "$loc" ]; then
        CONDA_PATH="$loc"
        break
    fi
done

if [ -n "$CONDA_PATH" ]; then
    source "$CONDA_PATH"
    conda activate db_env
else
    echo "Erro: Não foi possível localizar o Conda em $WORK_DIR/miniconda3."
    exit 1
fi

export PGDATA="${CONDA_PREFIX}/var/lib/pgsql/data"
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:32

# --- SUBINDO POSTGRESQL ---
"$ROOT_DIR/config/psql.sh"

# --- CAMINHOS DOS DATASETS E DEPENDÊNCIAS EM /tmp ---
JAR_DIR="$ROOT_DIR/algorithmJARs"
DCVALIDITY_DIR="$WORK_DIR/deps/DCValidity"
HOLOCLEAN_DIR="$WORK_DIR/deps/HoloClean"
LIMA_DIR="$WORK_DIR/deps/LIMA"
UNICLEAN_DIR="$WORK_DIR/deps/UniClean"
HORIZON_DIR="$WORK_DIR/deps/Horizon"

# Exporta PYTHONPATH para que o Python encontre o HoloClean/UniClean/Horizon em /tmp
export PYTHONPATH="$HOLOCLEAN_DIR:$UNICLEAN_DIR:$HORIZON_DIR:$ROOT_DIR/src:$PYTHONPATH"

if [ "$DATASET" = "hospital" ]; then
    HOSPITAL_DIRTY="$HOLOCLEAN_DIR/testdata/hospital.csv"
    GABARITO_REAL="$HOLOCLEAN_DIR/testdata/hospital_clean.csv"
    DATASET_ATUAL="$HOSPITAL_DIRTY"
elif [ "$DATASET" = "adult" ]; then
    DATASET_ATUAL="$HOLOCLEAN_DIR/testdata/AdultFull.csv"
    # Se houver um gabarito limpo específico,ponha aqui. Caso contrário, aponte para o target ou ajuste:
    GABARITO_REAL="$HOLOCLEAN_DIR/testdata/AdultFull.csv" # ajuste se tiver uma versão clean separada
elif [ "$DATASET" = "flight" ]; then
    DATASET_ATUAL="$HOLOCLEAN_DIR/testdata/flight.csv"
    GABARITO_REAL="$HOLOCLEAN_DIR/testdata/flight_clean.csv"
elif [ "$DATASET" = "met" ]; then
    DATASET_ATUAL="$HOLOCLEAN_DIR/testdata/met_1000.csv"
    GABARITO_REAL="$HOLOCLEAN_DIR/testdata/met_1000.csv"
else
    echo "Erro: Base de dados '$DATASET' desconhecida."
    exit 1
fi

mkdir -p "$ROOT_DIR/dcs/raw" "$ROOT_DIR/dcs/processed"

echo "============================================================"
echo "Iniciando Pipeline: Descoberta[$DISCOVERY] + Limpeza[$CLEANING] ($DATASET) | Max Iter: $MAX_ITERATIONS"
echo "============================================================"

for i in $(seq 1 $MAX_ITERATIONS); do
    echo "--------------------------------------------------"
    echo ">>> ITERAÇÃO $i / $MAX_ITERATIONS <<<"
    echo "--------------------------------------------------"

    RAW_DC="$ROOT_DIR/dcs/raw/dcs_${DISCOVERY}_${i}.txt"
    PARSED_DC="$ROOT_DIR/dcs/raw/dcs_${DISCOVERY}_parsed_${i}.txt"

    # --- PASSO 1: DESCOBERTA DE DCs E PARSER ---
    case "$DISCOVERY" in
        dcfinder)
            LINES="5000"
            cd "$DCVALIDITY_DIR"
            rm -f output.txt
            java -jar "$JAR_DIR/dcfinder.jar" "$DATASET_ATUAL" 0.00 "$LINES"
            [ -f "output.txt" ] && mv output.txt "$RAW_DC" || { echo "Erro: dcfinder não gerou output.txt"; exit 1; }
            cd "$ROOT_DIR"
            python3 "$ROOT_DIR/src/parsers/meta_parser.py" "$RAW_DC" "$PARSED_DC" "$DATASET_ATUAL"
            ;;
        fastdc)
            LINES="100"
            cd "$DCVALIDITY_DIR"
            rm -f output.txt
            java -jar "$JAR_DIR/FastDC.jar" "$DATASET_ATUAL" 0.00 "$LINES"
            [ -f "output.txt" ] && mv output.txt "$RAW_DC" || { echo "Erro: FastDC não gerou output.txt"; exit 1; }
            cd "$ROOT_DIR"
            python3 "$ROOT_DIR/src/parsers/meta_parser.py" "$RAW_DC" "$PARSED_DC" "$DATASET_ATUAL"
            ;;
        hydra)
            LINES="3000"
            cd "$DCVALIDITY_DIR"
            rm -f output.txt
            java -jar "$JAR_DIR/hydra.jar" "$DATASET_ATUAL" 0.00 "$LINES"
            [ -f "output.txt" ] && mv output.txt "$RAW_DC" || { echo "Erro: Hydra não gerou output.txt"; exit 1; }
            cd "$ROOT_DIR"
            python3 "$ROOT_DIR/src/parsers/meta_parser.py" "$RAW_DC" "$PARSED_DC" "$DATASET_ATUAL"
            ;;
        lima)
            LINES="5000"
            case $i in
                1) SOUNDNESS="0.90" ;;
                2) SOUNDNESS="0.80" ;;
                3) SOUNDNESS="0.70" ;;
                4) SOUNDNESS="0.60" ;;
                *) SOUNDNESS="0.50" ;;
            esac
            IFILE="$(realpath "$DATASET_ATUAL" 2>/dev/null || echo "$DATASET_ATUAL")"
            cp "$IFILE" "$LIMA_DIR/hospital_temp.csv"
            cd "$LIMA_DIR"
            rm -f output.txt
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

    # --- PASSO 2: REPARO / LIMPEZA ---
    SAIDA_CSV="$ROOT_DIR/dcs/processed/${DATASET}_limpo_${DISCOVERY}_${CLEANING}_v${i}.csv"

    set +e
    case "$CLEANING" in
        holoclean)
            dropdb holo 2>/dev/null || true
            createdb -O holocleanuser holo 2>/dev/null || true
            if [ "$DISCOVERY" = "lima" ]; then
                python3 "$ROOT_DIR/src/repair/lima_repair.py" "$PARSED_DC" "$SAIDA_CSV" "$DATASET_ATUAL" "$GABARITO_REAL"
            else
                python3 "$ROOT_DIR/src/repair/meta_repair.py" "$PARSED_DC" "$SAIDA_CSV" "$DATASET_ATUAL" "$GABARITO_REAL"
            fi
            ;;
        uniclean)
            python3 "$ROOT_DIR/src/repair/uniclean_repair.py" "$PARSED_DC" "$SAIDA_CSV" "$DATASET_ATUAL" "$GABARITO_REAL"
            ;;
        horizon)
            python3 "$ROOT_DIR/src/repair/horizon_repair.py" "$PARSED_DC" "$SAIDA_CSV" "$DATASET_ATUAL" "$GABARITO_REAL"
            ;;
        *)
            echo "Erro: Ferramenta de limpeza inválida ($CLEANING)."
            exit 1
            ;;
    esac
    STATUS=$?
    set -e

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