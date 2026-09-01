import sys
import re
from pathlib import Path

# Captura a raiz do projeto dinamicamente (2 níveis acima de src/filters/)
ROOT_DIR = Path(__file__).resolve().parent.parent.parent


def parse_and_normalize_dc(dc_line):
    """
    Normaliza a DC tratando a comutatividade do AND (&).
    Descarta regras com contradições (EQ e IQ no mesmo atributo).
    """
    line = dc_line.strip()
    if not line or line.startswith("#"):
        return None, None

    parts = line.split('&')
    prefix = []
    predicates = []
    
    for p in parts:
        p = p.strip()
        if p in ['t1', 't2']:
            prefix.append(p)
        else:
            predicates.append(p)

    # 1. Filtro Semântico: Detecta contradições (EQ e IQ no mesmo atributo)
    eq_attrs = set()
    iq_attrs = set()
    for pred in predicates:
        match = re.match(r'(EQ|IQ)\(([^)]+)\)', pred)
        if match:
            op, args = match.group(1), match.group(2)
            if op == 'EQ':
                eq_attrs.add(args)
            elif op == 'IQ':
                iq_attrs.add(args)
            
    if eq_attrs.intersection(iq_attrs):
        return None, None  # Descarta regra contraditória

    # 2. Normalização Sintática: Ordena os predicados para eliminar permutações
    sorted_predicates = tuple(sorted(predicates))
    prefix_str = "&".join(prefix)
    
    return prefix_str, set(sorted_predicates)


def filter_and_generalize_dcs(raw_dcs):
    """
    Aplica filtragem sintática (deduplicação/canonização) 
    e semântica (subsumpção/generalização e contradição).
    """
    valid_dcs = []

    # Passo 1: Limpeza sintática e eliminação de contradições
    for line in raw_dcs:
        prefix, preds = parse_and_normalize_dc(line)
        if preds and preds not in [p[1] for p in valid_dcs]:
            valid_dcs.append((prefix, preds))

    # Passo 2: Filtro Semântico de Subsumpção / Generalização
    # Ordena pelo tamanho (DCs com menos predicados são mais genéricas)
    valid_dcs.sort(key=lambda x: len(x[1]))

    minimal_dcs = []
    for prefix, preds in valid_dcs:
        is_subsumed = False
        for _, min_preds in minimal_dcs:
            # Se uma regra menor é subconjunto desta, a maior é redundante/específica
            if min_preds.issubset(preds):
                is_subsumed = True
                break
        if not is_subsumed:
            minimal_dcs.append((prefix, preds))

    # Passo 3: Reconstrução das strings padronizadas
    output_lines = []
    for prefix, preds in minimal_dcs:
        sorted_preds_str = "&".join(sorted(list(preds)))
        if prefix:
            output_lines.append(f"{prefix}&{sorted_preds_str}")
        else:
            output_lines.append(sorted_preds_str)

    return output_lines


def process_file(input_path, output_path):
    """
    Lê o arquivo de entrada, aplica o filtro e escreve no arquivo de saída.
    Garante que o caminho seja um objeto Path seguro.
    """
    input_file = Path(input_path).resolve()
    output_file = Path(output_path).resolve()

    if not input_file.exists():
        raise FileNotFoundError(f"Arquivo de entrada não encontrado: {input_file}")

    # Garante que o diretório de destino exista
    output_file.parent.mkdir(parents=True, exist_ok=True)

    with open(input_file, 'r', encoding='utf-8') as f:
        raw_dcs = f.readlines()

    filtered_dcs = filter_and_generalize_dcs(raw_dcs)

    with open(output_file, 'w', encoding='utf-8') as f:
        for dc in filtered_dcs:
            f.write(f"{dc}\n")

    return len(raw_dcs), len(filtered_dcs)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("[DC-Filter] Erro: Parâmetros de entrada e saída são obrigatórios.")
        print("Uso: python redundancy_filter.py <arquivo_entrada> <arquivo_saida>")
        sys.exit(1)

    inp = sys.argv[1]
    out = sys.argv[2]

    total_in, total_out = process_file(inp, out)
    print(f"[DC-Filter] Processado com sucesso: {inp} -> {out}")
    print(f"[DC-Filter] Linhas originais: {total_in} | Linhas otimizadas: {total_out}")