import sys
import re
import pandas as pd

class GenericDCCleaner:
    def __init__(self, df: pd.DataFrame):
        self.df = df
        self.equivalence_map = self._discover_equivalences()

    def _discover_equivalences(self) -> dict:
        """
        Descobre automaticamente colunas 1:1 no dataset.
        Se A -> B e B -> A de forma bijetora, são colunas equivalentes.
        """
        equivalences = {}
        cols = self.df.columns
        
        for i in range(len(cols)):
            for j in range(i + 1, len(cols)):
                col1, col2 = cols[i], cols[j]
                
                n_unique_col1 = self.df[col1].nunique(dropna=False)
                n_unique_col2 = self.df[col2].nunique(dropna=False)
                n_pairs = len(self.df[[col1, col2]].drop_duplicates())
                
                # Se o número de pares únicos for igual ao número de valores únicos em ambas
                if n_unique_col1 == n_pairs and n_unique_col2 == n_pairs:
                    if col2 not in equivalences:
                        equivalences[col2] = col1
                        
        return equivalences

    def _parse_and_normalize(self, dc_string: str) -> set:
        """
        Converte a string da DC traduzida em um conjunto ordenado de predicados.
        """
        raw_preds = [p.strip() for p in re.split(r'\s*&\s*|\s+AND\s+', dc_string)]
        normalized = set()
        
        for pred in raw_preds:
            p_clean = re.sub(r'\bt1\b', 'T1', pred, flags=re.IGNORECASE)
            p_clean = re.sub(r'\bt2\b', 'T2', p_clean, flags=re.IGNORECASE)
            
            # Aplica a substituição das colunas equivalentes
            for orig_col, target_col in self.equivalence_map.items():
                p_clean = re.sub(r'\b' + re.escape(orig_col) + r'\b', target_col, p_clean)
                
            normalized.add(p_clean)
            
        return normalized

    def _is_invalid(self, predicates: set) -> bool:
        """
        Detecta e descarta contradições sintáticas (ex: T1.A = T2.A e T1.A != T2.A).
        """
        eq_cols = set(re.findall(r'T1\.(\w+)\s*=\s*T2\.\1', " & ".join(predicates)))
        iq_cols = set(re.findall(r'T1\.(\w+)\s*!=\s*T2\.\1', " & ".join(predicates)))
        
        return len(eq_cols.intersection(iq_cols)) > 0

    def fit_transform(self, dc_list: list) -> list:
        """
        Aplica deduplicação, remoção de contradições e o algoritmo de subsumção (Minimal DCs).
        """
        parsed_dcs = []
        
        for raw_dc in dc_list:
            raw_dc = raw_dc.strip()
            if not raw_dc or raw_dc.startswith('#'):
                continue
                
            preds = self._parse_and_normalize(raw_dc)
            if not preds or self._is_invalid(preds):
                continue
                
            if preds not in [d['preds'] for d in parsed_dcs]:
                parsed_dcs.append({'preds': preds, 'raw': raw_dc})

        # Ordena da menor para a maior regra (regras menores são mais fortes/gerais)
        parsed_dcs.sort(key=lambda x: len(x['preds']))

        minimal_dcs = []
        for current in parsed_dcs:
            current_preds = current['preds']
            is_subsumed = False
            
            for smaller in minimal_dcs:
                # Se a menor é subconjunto da atual, a atual é uma redundância mais fraca
                if smaller['preds'].issubset(current_preds):
                    is_subsumed = True
                    break
                    
            if not is_subsumed:
                minimal_dcs.append(current)

        # Reconstrói as DCs tratadas no formato aceito pelo HoloClean
        return [" & ".join(sorted(list(d['preds']))) for d in minimal_dcs]

def main():
    if len(sys.argv) < 3:
        print("Uso: python redundancy_filter.py <PARSED_DC> <FILTERED_DC> [<DATASET_CSV>]")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]
    dataset_file = sys.argv[3] if len(sys.argv) > 3 else None

    # Lendo o conjunto de DCs parseadas
    with open(input_file, 'r', encoding='utf-8') as f:
        raw_dcs = f.readlines()

    # Carrega o dataset para inferir equivalências genéricas
    if dataset_file:
        df = pd.read_csv(dataset_file)
        cleaner = GenericDCCleaner(df)
        filtered_dcs = cleaner.fit_transform(raw_dcs)
    else:
        # Fallback sem o CSV (roda apenas subsumção simples)
        dummy_df = pd.DataFrame()
        cleaner = GenericDCCleaner(dummy_df)
        filtered_dcs = cleaner.fit_transform(raw_dcs)

    # Escrevendo as DCs filtradas/otimizadas para o HoloClean
    with open(output_file, 'w', encoding='utf-8') as f:
        for dc in filtered_dcs:
            f.write(f"{dc}\n")

    print(f"[Pruning] DCs de entrada: {len(raw_dcs)} | DCs após Pruning: {len(filtered_dcs)}")

if __name__ == "__main__":
    main()