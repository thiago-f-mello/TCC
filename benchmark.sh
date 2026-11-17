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
CLEANINGS=("holoclean") # Adicione "uniclean" e "horizon" aqui assim que criar os scripts em src/repair/
DATASET="hospital"

echo "============================================================"
echo "INICIANDO SUÍTE DE BENCHMARKS - TCC LAYEREDCLEAN (Max Iter: $MAX_ITER)"
echo "============================================================"

for disc in "${DISCOVERIES[@]}"; do
    for clean in "${CLEANINGS[@]}"; do
        echo ""
        echo "############################################################"
        echo "Executando: Descoberta [$disc] + Limpeza [$clean] (Iterações: $MAX_ITER)"
        echo "############################################################"
        
        "$SCRIPT_DIR/pipelines/pipelines.sh" "$disc" "$clean" "$DATASET" -n "$MAX_ITER" || {
            echo "[AVISO] Falha ou interrupção na combinação: $disc + $clean"
            continue
        }
    done
done

echo ""
echo "============================================================"
echo "TODOS OS BENCHMARKS FORAM EXECUTADOS!"
echo "============================================================"