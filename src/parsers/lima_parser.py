#!/usr/bin/env python3
"""Converte a saída do LIMA para o formato de DCs do HoloClean.

Modo compatível com o pipeline atual do projeto:
- mantém DCs que tenham pelo menos um predicado EQ;
- ignora DCs compostas somente por IQ, pois o NullDetector/compilador SQL
  usado no cenário atual gera uma consulta com WHERE vazio para esse caso;
- preserva DCs compostas com EQ e IQ quando os predicados aparecem juntos
  na mesma linha;
- por compatibilidade com o parser anterior, exclui Address2 e Address3 por
  padrão. Essa lista pode ser alterada pela linha de comando.

Importante: o parser não combina linhas diferentes. Fazer isso sem conhecer
as dependências entre atributos inventaria regras que não estão na saída LIMA.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Iterable, List, Optional, Sequence

DEFAULT_EXCLUDED_COLUMNS = ("Address2", "Address3")
IDENTIFIER = r"[A-Za-z_][A-Za-z0-9_]*"
# Somente comparações entre atributos são necessárias para a saída LIMA
# apresentada. Operadores relacionais adicionais não são inferidos.
PREDICATE_RE = re.compile(
    rf"^\s*"
    rf"(?:(?P<left_alias>t1|t2)\.)?(?P<left_col>{IDENTIFIER})"
    rf"\s*(?P<op>!=|<>|==|=|\bNE\b|\bEQ\b)\s*"
    rf"(?:(?P<right_alias>t1|t2)\.)?(?P<right_col>{IDENTIFIER})"
    rf"\s*$",
    re.IGNORECASE,
)


def _find_repo_root() -> Path:
    """Localiza a raiz pelo diretório dcs ou pelo marcador .git."""
    here = Path(__file__).resolve().parent
    for candidate in (here, *here.parents):
        if (candidate / "dcs").is_dir() or (candidate / ".git").exists():
            return candidate
    # Fallback compatível com a localização original src/parsers/.
    return here.parent.parent.parent


ROOT_DIR = _find_repo_root()


def _split_top_level(expression: str, separator: str = "&") -> List[str]:
    """Divide uma conjunção sem separar conteúdo dentro de parênteses."""
    parts: List[str] = []
    start = 0
    depth = 0

    for index, char in enumerate(expression):
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth < 0:
                raise ValueError("parênteses desbalanceados")
        elif char == separator and depth == 0:
            parts.append(expression[start:index].strip())
            start = index + 1

    if depth != 0:
        raise ValueError("parênteses desbalanceados")

    parts.append(expression[start:].strip())
    return [part for part in parts if part]


def _parse_denial_line(line: str, line_number: int) -> List[str]:
    """Converte os predicados de uma linha LIMA em predicados HoloClean."""
    cleaned = line.strip()
    if not (cleaned.startswith("!(") and cleaned.endswith(")")):
        raise ValueError(
            f"linha {line_number}: formato esperado '!(predicado [& predicado])'"
        )

    # O ! externo representa a negação da conjunção da DC. O HoloClean recebe
    # os predicados internos, por isso removemos apenas o invólucro '!('.
    body = cleaned[2:-1].strip()
    if not body:
        raise ValueError(f"linha {line_number}: DC vazia")

    try:
        raw_predicates = _split_top_level(body)
    except ValueError as exc:
        raise ValueError(f"linha {line_number}: {exc}") from exc

    translated: List[str] = []
    for raw_predicate in raw_predicates:
        match = PREDICATE_RE.fullmatch(raw_predicate)
        if not match:
            raise ValueError(
                f"linha {line_number}: predicado não reconhecido: "
                f"{raw_predicate!r}"
            )

        left_alias = match.group("left_alias") or "t1"
        right_alias = match.group("right_alias") or "t2"
        left_col = match.group("left_col")
        right_col = match.group("right_col")
        operator = match.group("op").upper()

        hc_operator = "IQ" if operator in {"!=", "<>", "NE"} else "EQ"
        translated.append(
            f"{hc_operator}({left_alias}.{left_col},{right_alias}.{right_col})"
        )

    return translated


def parse_lima_output(
    input_file_path: str | Path,
    output_file_path: str | Path,
    excluded_columns: Optional[Iterable[str]] = DEFAULT_EXCLUDED_COLUMNS,
    require_equality: bool = True,
) -> int:
    """Converte o arquivo LIMA e grava DCs compatíveis com o cenário atual.

    Mantém a assinatura principal do parser anterior e retorna a quantidade
    de DCs gravadas, para não quebrar chamadas existentes no projeto.

    Args:
        input_file_path: arquivo de saída original do LIMA.
        output_file_path: arquivo de DCs que será carregado pelo HoloClean.
        excluded_columns: colunas que devem ser ignoradas. Por padrão,
            Address2 e Address3, como no parser anterior. Passe None ou uma
            coleção vazia para não excluir colunas.
        require_equality: quando True, descarta DCs que tenham somente IQ.
            Deve permanecer True para o compilador SQL do cenário descrito.
    """
    input_path = Path(input_file_path).expanduser().resolve()
    output_path = Path(output_file_path).expanduser().resolve()

    if not input_path.is_file():
        raise FileNotFoundError(f"Arquivo do LIMA não encontrado: {input_path}")
    if input_path == output_path:
        raise ValueError("entrada e saída devem ser arquivos diferentes")

    excluded = {name.casefold() for name in (excluded_columns or ())}
    constraints: List[str] = []
    seen = set()

    total_lines = 0
    ignored_blank_or_comment = 0
    skipped_excluded = 0
    skipped_without_eq = 0
    duplicates = 0

    with input_path.open("r", encoding="utf-8-sig") as source:
        for line_number, line in enumerate(source, start=1):
            total_lines += 1
            cleaned = line.strip()

            if not cleaned or cleaned.startswith("#"):
                ignored_blank_or_comment += 1
                continue

            predicates = _parse_denial_line(cleaned, line_number)

            # Não remova apenas um átomo de uma conjunção: isso alteraria a DC.
            columns_in_constraint = {
                column.casefold()
                for predicate in predicates
                for column in re.findall(r"(?:t1|t2)\.([A-Za-z_][A-Za-z0-9_]*)", predicate)
            }
            if columns_in_constraint.intersection(excluded):
                skipped_excluded += 1
                continue

            # O log do cenário atual mostra que uma regra só com IQ chega ao
            # compilador como WHERE vazio. IQ continua permitido quando existe
            # pelo menos um EQ na mesma DC.
            if require_equality and not any(
                predicate.startswith("EQ(") for predicate in predicates
            ):
                skipped_without_eq += 1
                continue

            constraint = "t1&t2&" + "&".join(predicates)
            if constraint in seen:
                duplicates += 1
                continue

            seen.add(constraint)
            constraints.append(constraint)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    content = "\n".join(constraints)
    if content:
        content += "\n"

    # Escrita atômica: evita deixar o arquivo final truncado se houver falha.
    temporary_path = output_path.with_name(output_path.name + ".tmp")
    try:
        temporary_path.write_text(content, encoding="utf-8")
        temporary_path.replace(output_path)
    finally:
        if temporary_path.exists():
            temporary_path.unlink()

    print(f"[LIMA Parser] Arquivo gerado: {output_path}")
    print(f"[LIMA Parser] Linhas lidas: {total_lines}")
    print(f"[LIMA Parser] DCs gravadas: {len(constraints)}")
    print(f"[LIMA Parser] DCs ignoradas (somente IQ): {skipped_without_eq}")
    print(f"[LIMA Parser] DCs ignoradas (colunas excluídas): {skipped_excluded}")
    print(f"[LIMA Parser] Duplicatas removidas: {duplicates}")
    print(f"[LIMA Parser] Linhas vazias/comentários: {ignored_blank_or_comment}")

    if skipped_without_eq:
        print(
            "[LIMA Parser] Aviso: as DCs somente com IQ foram descartadas "
            "para evitar o WHERE vazio observado no pipeline atual."
        )

    return len(constraints)


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Converte a saída do LIMA para DCs no formato do HoloClean."
    )
    parser.add_argument("input", help="arquivo original gerado pelo LIMA")
    parser.add_argument(
        "output",
        nargs="?",
        default=str(ROOT_DIR / "dcs" / "raw" / "dcs_lima_parsed.txt"),
        help="arquivo de saída (padrão: dcs/raw/dcs_lima_parsed.txt)",
    )
    parser.add_argument(
        "--exclude-columns",
        nargs="*",
        default=list(DEFAULT_EXCLUDED_COLUMNS),
        metavar="COLUNA",
        help=(
            "colunas ignoradas (padrão: Address2 Address3); "
            "use a opção sem valores para não excluir nenhuma"
        ),
    )
    parser.add_argument(
        "--allow-iq-only",
        action="store_true",
        help=(
            "não filtra DCs somente com IQ; use apenas se o compilador "
            "HoloClean do ambiente aceitar esse formato"
        ),
    )

    args = parser.parse_args(argv)
    try:
        parse_lima_output(
            args.input,
            args.output,
            excluded_columns=args.exclude_columns,
            require_equality=not args.allow_iq_only,
        )
    except (OSError, ValueError) as exc:
        print(f"[LIMA Parser] ERRO: {exc}", file=sys.stderr)
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
