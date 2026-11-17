"""Gera requisitos.md e cronograma.md a partir de conteudo.py."""
import conteudo as C
from pathlib import Path
H = Path(__file__).parent
md = [f"# Requisitos priorizados — {C.PROJETO}\n", f"{C.TEMA}\n",
      "Prioridade: **Alta** = essencial para o MVP · **Média** = entra na entrega final · **Baixa** = complementar.\n",
      "## Requisitos funcionais\n", "| ID | Requisito | Uso do banco de dados | Prioridade | Por quê |", "|---|---|---|---|---|"]
md += [f"| {a} | {b} | {c} | {p} | {j} |" for a, b, c, p, j in C.RF]
md += ["\n## Requisitos não funcionais\n", "| ID | Requisito | Onde é atendido | Prioridade |", "|---|---|---|---|"]
md += [f"| {a} | {b} | {c} | {p} |" for a, b, c, p in C.RNF]
md += ["\n## SGBD e tecnologias\n", "| Camada | Tecnologia | Justificativa |", "|---|---|---|"]
md += [f"| {a} | {b} | {c} |" for a, b, c in C.TECNOLOGIAS]
(H / "requisitos.md").write_text("\n".join(md) + "\n")
cr = ["# Cronograma consolidado da A3\n", "| Atividade | Entrega | Responsável | Depende de | Impedimentos | Status |", "|---|---|---|---|---|---|"]
cr += [f"| {a} | {b} | {c} | {d} | {e} | {C.STATUS[s][0]} |" for a, b, c, d, e, s in C.CRONOGRAMA]
(H / "cronograma.md").write_text("\n".join(cr) + "\n")
print("ok")
