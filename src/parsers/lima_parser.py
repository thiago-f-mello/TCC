import getpass
import os
import re
import sys
from pathlib import Path

# Captura a raiz do repositório dinamicamente (2 níveis acima de src/parsers/)
ROOT_DIR = Path(__file__).resolve().parent.parent.parent

OP_MAP = {
    '!=': 'IQ',
    '<>': 'IQ',
    '<=': 'LTE',
    '>=': 'GTE',
    '=': 'EQ',
    '<': 'LT',
    '>': 'GT',
    'NE': 'IQ',
    'EQ': 'EQ',
}


def parse_lima_output(input_file_path, output_file_path):
    """
    Lê o output.txt do LIMA e converte para a sintaxe nativa do HoloClean,
    exigindo no mínimo 2 predicados válidos por DC.
    """
    input_path = Path(input_file_path).resolve()
    output_path = Path(output_file_path).resolve()

    if not input_path.exists():
        raise FileNotFoundError(f"Arquivo do LIMA não encontrado: {input_path}")

    output_path.parent.mkdir(parents=True, exist_ok=True)

    regras_finais = []
    with open(input_path, 'r', encoding='utf-8') as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or not line.startswith('!'):
                continue

            # Remove wrapper externo !( ... ) e divide por '&' ou '^'
            clean = line.replace('!(', '').replace(')', '').replace(' ', '')
            parts = [p.strip() for p in re.split(r'[&^]', clean) if p.strip()]

            traduzidas = []
            for p in parts:
                m = re.match(r'^([A-Za-z0-9_]+)(!=|<>|<=|>=|=|<|>)([A-Za-z0-9_]+)$', p)
                if m:
                    col1, op, col2 = m.group(1), m.group(2), m.group(3)
                    hc_op = OP_MAP[op]
                    traduzidas.append(f"{hc_op}(t1.{col1},t2.{col2})")
                    continue

                if p.endswith('EQ'):
                    col = p[:-2]
                    traduzidas.append(f"EQ(t1.{col},t2.{col})")
                elif p.endswith('NE'):
                    col = p[:-2]
                    traduzidas.append(f"IQ(t1.{col},t2.{col})")

            # Trava: Exige no mínimo 2 predicados na DC
            if len(traduzidas) >= 2:
                linha_hc = "t1&t2&" + "&".join(traduzidas)
                regras_finais.append(linha_hc)

    with open(output_path, 'w', encoding='utf-8') as f:
        if regras_finais:
            f.write('\n'.join(regras_finais) + '\n')

    return len(regras_finais)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("[LIMA Parser] Erro: Informe ao menos o arquivo de entrada.")
        print("Uso: python lima_parser.py <caminho_input_lima> [caminho_output_dc]")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) >= 3 else ROOT_DIR / "dcs" / "raw" / "dcs_lima_parsed.txt"

    qtd = parse_lima_output(input_file, output_file)
    print(f"[LIMA Parser] Sucesso! {qtd} DCs convertidas para {output_file}")