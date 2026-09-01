import sys
import re
from pathlib import Path
import pandas as pd

# Captura a raiz do repositório dinamicamente (2 níveis acima de src/parsers/)
ROOT_DIR = Path(__file__).resolve().parent.parent.parent


def gerar_mapeamento_schema_dinamico(caminho_csv):
    """
    Lê o cabeçalho do CSV original para mapear os nomes das colunas
    sem espaços e em lowercase para o case exato do arquivo (Ex: providernumber -> ProviderNumber).
    """
    csv_file = Path(caminho_csv).resolve()
    if not csv_file.exists():
        print(f"[Meta-Parser] Aviso: CSV não encontrado em {csv_file}. Usando strings padrão.")
        return {}
    try:
        df_headers = pd.read_csv(csv_file, nrows=0)
        return {col.replace(" ", "").lower().strip(): col for col in df_headers.columns}
    except Exception as e:
        print(f"[Meta-Parser] Erro ao ler cabeçalhos do CSV: {e}")
        return {}


def converter_linha_metanome(linha, mapa_schema):
    linha = linha.strip()
    # Valida se a linha possui o formato esperado do FastDC/Metanome/Hydra
    if not linha.startswith('¬(') or not linha.endswith(')'):
        return None
    
    # Remove o prefixo ¬( e o sufixo )
    conteudo = linha[2:-1]
    # Divide os predicados individuais separados por ^
    predicados_brutos = conteudo.split('^')
    
    operadores = {'==': 'EQ', '<>': 'IQ'}
    traduzidas = []
    possui_iq = False
    possui_eq = False  # Flag crucial para evitar o erro "WHERE )" no HoloClean
    
    for pred in predicados_brutos:
        op_encontrado = None
        for op in operadores.keys():
            if op in pred:
                op_encontrado = op
                break
        
        if not op_encontrado:
            continue
            
        esq, dir_side = pred.split(op_encontrado)
        
        # Divide os caminhos (ex: t0.hospital.csv.HospitalName)
        partes_esq = esq.strip().split('.')
        partes_dir = dir_side.strip().split('.')
        
        if len(partes_esq) < 2 or len(partes_dir) < 2:
            continue
            
        # Mapeia as tuplas do Metanome (t0, t1) para o padrão HoloClean (t1, t2)
        tupla_esq = 't1' if partes_esq[0] == 't0' else 't2'
        tupla_dir = 't1' if partes_dir[0] == 't0' else 't2'
        
        # Pega o nome bruto da coluna (último elemento após os pontos)
        col_esq_bruta = partes_esq[-1]
        col_dir_bruta = partes_dir[-1]
        
        # Ajusta o case da coluna de acordo com o Schema real do CSV
        col_esq = mapa_schema.get(col_esq_bruta.lower().strip(), col_esq_bruta)
        col_dir = mapa_schema.get(col_dir_bruta.lower().strip(), col_dir_bruta)
        
        op_hc = operadores[op_encontrado]
        if op_hc == 'IQ':
            possui_iq = True
        elif op_hc == 'EQ':
            possui_eq = True
            
        traduzidas.append(f"{op_hc}({tupla_esq}.{col_esq},{tupla_dir}.{col_dir})")
        
    if traduzidas:
        # --- REGRA DE PROTEÇÃO ---
        # Se a restrição não possui NENHUM predicado de igualdade (EQ), o HoloClean 
        # ignora os operadores IQ, gerando uma cláusula vazia na query SQL.
        if not possui_eq:
            return None
            
        # Se a regra só gerou igualdades (EQ), injetamos a coluna identificadora de segurança
        if not possui_iq:
            col_id = mapa_schema.get('providernumber')
            if not col_id and mapa_schema:
                col_id = list(mapa_schema.values())[0]
            else:
                col_id = 'ProviderNumber'
                
            traduzidas.append(f"IQ(t1.{col_id},t2.{col_id})")
            
        return "t1&t2&" + "&".join(traduzidas)
    
    return None


def parse_meta_output(input_path, output_path, dataset_path=None):
    inp_file = Path(input_path).resolve()
    out_file = Path(output_path).resolve()

    if not inp_file.exists():
        raise FileNotFoundError(f"[Meta-Parser] Arquivo de entrada não encontrado: {inp_file}")

    out_file.parent.mkdir(parents=True, exist_ok=True)

    # Carrega o mapeamento do schema CSV
    ds_path = dataset_path if dataset_path else ROOT_DIR / ".." / "holoclean" / "testdata" / "hospital.csv"
    mapa_schema = gerar_mapeamento_schema_dinamico(ds_path)

    regras_finais = []
    with open(inp_file, 'r', encoding='utf-8', errors='ignore') as f_in:
        for line in f_in:
            regra = converter_linha_metanome(line, mapa_schema)
            if regra:
                regras_finais.append(regra)

    with open(out_file, 'w', encoding='utf-8') as f_out:
        for r in regras_finais:
            f_out.write(r + '\n')

    return len(regras_finais)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("[Meta-Parser] Erro: Informe ao menos o arquivo de entrada.")
        print("Uso: python meta_parser.py <caminho_input_meta> [caminho_output_dc] [caminho_dataset_csv]")
        sys.exit(1)

    inp = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) >= 3 else ROOT_DIR / "dcs" / "raw" / "dcs_meta_parsed.txt"
    ds = sys.argv[3] if len(sys.argv) >= 4 else None

    qtd = parse_meta_output(inp, out, ds)
    print(f"[Meta-Parser] Sucesso! {qtd} regras convertidas e salvas em {out}")