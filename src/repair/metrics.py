import pandas as pd

# Monkeypatch para compatibilidade entre HoloClean antigo e pandas moderno
_orig_set_option = pd.set_option
def _patched_set_option(pat, val, *args, **kwargs):
    if pat == 'display.max_colwidth' and val == -1:
        val = None
    return _orig_set_option(pat, val, *args, **kwargs)
pd.set_option = _patched_set_option


def avaliar_reparo(hc, caminho_gabarito):
    """
    Executa o avaliador oficial do HoloClean com todas as métricas nativas.
    """
    print(f"Avaliando contra: {caminho_gabarito}")
    hc.evaluate(
        fpath=caminho_gabarito,
        tid_col='tid',
        attr_col='attribute',
        val_col='correct_val'
    )