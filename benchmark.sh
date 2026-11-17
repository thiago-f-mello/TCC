#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MAX_ITER=1
while getopts "n:" opt; do
    case $opt in
        n) MAX_ITER="$OPTARG" ;;
        *) echo "Uso: $0 [-n max_iteracoes]"; exit 1 ;;
    esac
done

DISCOVERIES=("lima" "dcfinder" "fastdc" "hydra")
CLEANINGS=("holoclean") 
DATASETS=("hospital" "adult" "flight") # Adicionadas as bases maiores aqui!

echo "============================================================"
echo "INICIANDO SUÍTE DE BENCHMARKS - TCC LAYEREDCLEAN (Max Iter: $MAX_ITER)"
echo "============================================================"

for dataset in "${DATASETS[@]}"; do
    for disc in "${DISCOVERIES[@]}"; do
        for clean in "${CLEANINGS[@]}"; do
            echo ""
            echo "############################################################"
            echo "Base: [$dataset] | Descoberta: [$disc] + Limpeza: [$clean]"
            echo "############################################################"
            
            "$SCRIPT_DIR/pipelines/pipelines.sh" "$disc" "$clean" "$dataset" -n "$MAX_ITER" || {
                echo "[AVISO] Falha ou interrupção na combinação: $disc + $clean no dataset $dataset"
                continue
            }
        done
    done
done

echo ""
echo "============================================================"
echo "TODOS OS BENCHMARKS FORAM EXECUTADOS!"
echo "============================================================"