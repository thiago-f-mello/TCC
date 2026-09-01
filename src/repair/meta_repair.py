import sys
import os
import gc
from pathlib import Path
import pandas as pd
import torch

# Captura a raiz do repositório dinamicamente (2 níveis acima de src/repair/)
ROOT_DIR = Path(__file__).resolve().parent.parent.parent

# Tenta carregar o HoloClean do ambiente ou via diretório relativo[cite: 13]
HOLOCLEAN_PATH = os.environ.get(
    'HOLOCLEAN_DIR', 
    str((ROOT_DIR.parent / "holoclean").resolve())
)

if HOLOCLEAN_PATH not in sys.path:
    sys.path.append(HOLOCLEAN_PATH)

import holoclean
from detect import NullDetector, ViolationDetector
from repair.featurize import *


def executar_limpeza(caminho_dcs, caminho_saida, caminho_entrada, caminho_gabarito):
    try:
        use_cuda = torch.cuda.is_available()
        if use_cuda:
            print(f" -> [CUDA ATIVADO] Utilizando GPU: {torch.cuda.get_device_name(0)}")
            torch.cuda.empty_cache()
            torch.set_num_threads(1)
        else:
            print(" -> [AVISO] CUDA não disponível. Executando em modo CPU de thread única.")
            torch.set_num_threads(1)

        # 1. Configuração do HoloClean otimizada para o pipeline[cite: 13]
        hc = holoclean.HoloClean(
            db_name='holo',
            domain_thresh_1=0.05,
            domain_thresh_2=0.05,
            weak_label_thresh=0.999,
            max_domain=20,
            cor_strength=0.1,
            nb_cor_strength=0.4,
            epochs=1,
            convergence_threshold=1e-4,
            weight_decay=0.2,
            learning_rate=0.001,
            threads=1,
            batch_size=4,
            verbose=True,
            timeout=5*60000,
            feature_norm=False,
            weight_norm=False,
            print_fw=True
        ).session

        print(f"Lendo entrada: {caminho_entrada}")
        hc.load_data('hospital', caminho_entrada)

        hc.load_dcs(caminho_dcs)
        dcs = hc.get_dcs()
        hc.ds.set_constraints(dcs)

        detectors = [NullDetector(), ViolationDetector()]
        hc.detect_errors(detectors)

        try:
            hc.setup_domain()
            
            featurizers = [
                InitAttrFeaturizer(),
                OccurAttrFeaturizer(),
                FreqFeaturizer(),
                ConstraintFeaturizer(),
            ]
            
            # Limpeza preventiva da RAM antes da featurização e treino[cite: 13]
            gc.collect()
            if use_cuda:
                torch.cuda.empty_cache()

            hc.repair_errors(featurizers)

            # Limpeza de memória antes da avaliação (evita o crash posix_memalign)[cite: 13]
            gc.collect()
            if use_cuda:
                torch.cuda.empty_cache()

            print(f"Avaliando contra: {caminho_gabarito}")
            hc.evaluate(fpath=caminho_gabarito,
                        tid_col='tid',
                        attr_col='attribute',
                        val_col='correct_val')

            print("Gerando o dataset reparado...")
            hc.ds.get_inferred_values()
            hc.ds.get_repaired_dataset()

            df_final = hc.ds.repaired_data.df

            # Verifica quantas células foram realmente modificadas[cite: 13]
            df_entrada = pd.read_csv(caminho_entrada)
            
            # Remove colunas internas do gerenciamento do banco[cite: 13]
            cols_para_remover = ['_tid_', 'tid', 'attribute', 'correct_val']
            for col in cols_para_remover:
                if col in df_final.columns:
                    df_final = df_final.drop(columns=[col])

            # Garante a existência do diretório de saída antes de salvar
            Path(caminho_saida).resolve().parent.mkdir(parents=True, exist_ok=True)

            # Salva o arquivo limpo desta iteração[cite: 13]
            df_final.to_csv(caminho_saida, index=False)
            print(f"Sucesso! Iteração salva em: {caminho_saida}")
            
            # CRITÉRIO DE PARADA REAL[cite: 13]
            if df_final.equals(df_entrada):
                print("\n[INFO] O dataset final é idêntico ao de entrada. Nenhuma alteração feita.")
                sys.exit(10)  # Código 10 ativa o Early Stopping no Shell[cite: 13]
            else:
                sys.exit(0)   # Continua o pipeline[cite: 13]

        except ValueError as e:
            if "No objects to concatenate" in str(e):
                print("\n[EARLY SHUTDOWN] HoloClean atingiu saturação estrutural (Grafo vazio).")
                Path(caminho_saida).resolve().parent.mkdir(parents=True, exist_ok=True)
                pd.read_csv(caminho_entrada).to_csv(caminho_saida, index=False)
                sys.exit(10)
            else:
                raise e

    except SystemExit as e:
        sys.exit(e.code)
    except Exception as e:
        print(f"Erro fatal no pipeline de reparo: {str(e)}")
        sys.exit(1)


if __name__ == "__main__":
    if len(sys.argv) >= 5:
        executar_limpeza(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        print("[Reparo] Erro: Faltam parâmetros obrigatórios.")
        print("Uso: python meta_repair.py <regras.txt> <saida.csv> <entrada.csv> <gabarito.csv>")
        sys.exit(1)