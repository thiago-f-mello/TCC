#!/bin/bash
set -e

DISCOVERIES=("lima" "dcfinder" "fastdc" "hydra")
CLEANINGS=("holoclean" "uniclean" "horizon")
DATASET="hospital"

echo "============================================================"
echo "INICIANDO SUÍTE DE BENCHMARKS - TCC LAYEREDCLEAN"
echo "============================================================"

for disc in "${DISCOVERIES[@]}"; do
    for clean in "${CLEANINGS[@]}"; do
        echo ""
        echo "############################################################"
        echo "Executando: Descoberta [$disc] + Limpeza [$clean]"
        echo "############################################################"
        
        ./pipelines.sh "$disc" "$clean" "$DATASET" || {
            echo "[AVISO] Falha ou interrupção na combinação: $disc + $clean"
            continue
        }
    done
done

echo ""
echo "============================================================"
echo "TODOS OS BENCHMARKS FORAM EXECUTADOS!"
echo "============================================================"