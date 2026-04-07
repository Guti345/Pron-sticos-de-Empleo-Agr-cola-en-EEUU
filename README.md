# Capital Físico y Empleo Agrícola en EE.UU.
**Autor:** Antonio Gutiérrez Arango — Universidad del Rosario, Abril 2026

---

## Motivación

La producción agrícola en Estados Unidos se ha triplicado en los últimos 60 años mientras el empleo en el sector ha caído un 76%. Este trabajo evalúa si esa acumulación de capital físico —aproximada por los inventarios de maquinaria agrícola— mejora los pronósticos de corto plazo del empleo agrícola, comparando cinco modelos de series de tiempo sobre datos mensuales del FRED (2000–2025).

---

## Datos

Todas las series provienen del [FRED](https://fred.stlouisfed.org/) en frecuencia mensual.

| Variable | Código FRED | Descripción | Unidad |
|----------|------------|-------------|--------|
| Empleo agrícola | `LNU02034560` | Nivel de empleo — sector agrícola | Miles de personas |
| Capital físico | `A33ATI` | Inventarios de maquinaria agrícola | Millones USD |
| PPI agrícola | `WPU01` | Índice de precios al productor agrícola | Índice (1982=100) |
| Salario mínimo | `FEDMINFRMWG` | Salario mínimo federal agrícola | USD por hora |

---

## Estructura del repositorio

```
.
├── Data/
│   ├── Raw/                        # Datos crudos descargados desde FRED
│   └── Clean/                      # Base procesada y base con pronósticos
│
├── Scripts/
│   └── proyecto_final.do           # Script principal en Stata
│
├── Outputs/
│   ├── Graphs/                     # Figuras exportadas (.png)
│   └── Tables/                     # Tablas exportadas (.xlsx y .tex)
│
└── Paper/
    ├── main.tex                    # Documento en LaTeX
    └── ref.bib                     # Referencias bibliográficas
```

---

## Requisitos

- **Stata** 16 o superior con los paquetes `estout` y `kpss` (`ssc install`)
- **LaTeX** — Overleaf o distribución local con `pdflatex`
- Conexión a internet para la primera importación desde FRED (`import fred`)