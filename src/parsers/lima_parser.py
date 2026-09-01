import sys
from pathlib import Path

# Captura a raiz do repositório dinamicamente (2 níveis acima de src/parsers/)
ROOT_DIR = Path(__file__).resolve().parent.parent.parent


def parse_lima_output(input_file_path, output_file_path):
    """
    Lê o output.txt do LIMA e converte as regras de '!(col EQ) & !(col NE)'
    para a sintaxe nativa do HoloClean: 't1&t2&EQ(t1.col,t2.col)&IQ(t1.col,t2.col)'.
    """
    input_path = Path(input_file_path).resolve()
    output_path = Path(output_file_path).resolve()

    if not input_path.exists():
        raise FileNotFoundError(f"Arquivo do LIMA não encontrado: {input_path}")

    # Garante que a pasta de destino (ex: dcs/raw/) exista
    output_path.parent.mkdir(parents=True, exist_ok=True)

    regras_finais = []
    with open(input_path, 'r', encoding='utf-8') as f:
        for line in f:
            if '&' in line:
                # 1. Remove operadores sintáticos do LIMA, espaços e parênteses
                clean = line.strip().replace('!(', '').replace(')', '').replace(' ', '')
                
                # 2. Divide os predicados pelo operador lógico &
                parts = [p.strip() for p in clean.split('&') if p.strip()]
                
                # 3. Traduz os predicados para a sintaxe de tuplas (t1, t2) do HoloClean
                traduzidas = []
                for p in parts:
                    if 'EQ' in p:
                        col = p.split('EQ')[0]
                        traduzidas.append(f"EQ(t1.{col},t2.{col})")
                    elif 'NE' in p:
                        col = p.split('NE')[0]
                        traduzidas.append(f"IQ(t1.{col},t2.{col})")
                
                # 4. Monta a regra com o prefixo 't1&t2&' padronizado
                if traduzidas:
                    linha_hc = "t1&t2&" + "&".join(traduzidas)
                    regras_finais.append(linha_hc)

    # Escreve o resultado no arquivo final
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(regras_finais) + '\n')

    return len(regras_finais)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("[LIMA Parser] Erro: Informe ao menos o arquivo de entrada.")
        print("Uso: python lima_parser.py <caminho_input_lima> [caminho_output_dc]")
        sys.exit(1)

    input_file = sys.argv[1]

    # Se não informar a saída, salva por padrão em dcs/raw/
    if len(sys.argv) >= 3:
        output_file = sys.argv[2]
    else:
        output_file = ROOT_DIR / "dcs" / "raw" / "dcs_lima_parsed.txt"

    qtd = parse_lima_output(input_file, output_file)
    print(f"[LIMA Parser] Sucesso! {qtd} DCs convertidas para {output_file}")