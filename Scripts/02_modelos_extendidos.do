/*===========================================================================
  SCRIPT 02: Modelos Extendidos — VAR/VECM, OCMT y Ensemble Ponderado
  Proyecto:  Pronósticos de Empleo Agrícola en EE.UU. — Extensión
  Autor:     Antonio Gutiérrez Arango
  Fecha:     Mayo 2026

  Descripción:
    Extiende el paper anterior (Script 01) agregando tres modelos:
      Modelo 6: VAR/VECM bivariado (ln_emp_agr ~ ln_inv_manuf)
      Modelo 7: OCMT — selección de variables de alta dimensión (CKP 2018)
                → Variable dependiente: dd_ln_emp = ∆∆₁₂ ln(empleo)
                → Conjunto activo: L1 de D.ln_* (rezago 1 de primera dif.)
                → Variables seleccionadas como regresores en ARIMA(1,1,1)(1,1,1)₁₂
      Modelo 8: Ensemble ponderado (Granger y Ramanathan 1984, Método C)

  Corrección B-O:
    Se aplica inline al terminar cada estimación (VECM en §4.3, OCMT en §5.4).
    Los modelos 1–5 llegan con yhat_*_BO ya calculados desde project_forecasts.dta
    (generados en Script 01), por lo que NO existe una sección centralizada de B-O.

  Variables omitidas del conjunto activo OCMT por missing values:
    AWHAETP, BAMLH0A0HYM2, DTWEXBGS, USALOLITONOSTSAM, PCU111111111

  Conjunto activo final OCMT: 15 variables candidatas

  Prerequisitos:
    - Haber ejecutado Script 01 (genera project_forecasts.dta con yhat_*_BO)
    - Paquetes: ssc install ocmt; ssc install estout
===========================================================================*/

clear all
set more off

*===========================================================================
**# 0. CONFIGURACIÓN
*===========================================================================

global main    "C:\Users\anton\OneDrive\Documentos\GitHub\Pronósticos de Empleo Agrícola en EEUU"
global graphs  "${main}\Outputs\Graphs"
global tables  "${main}\Outputs\Tables"
global raw     "${main}\Data\Raw"
global clean   "${main}\Data\Clean"

*===========================================================================
**# 1. CARGAR BASE LIMPIA E IMPORTAR 12 NUEVAS VARIABLES DE FRED
*===========================================================================

/*
  project_forecasts.dta ya contiene (de Script 01):
    yhat_naive_BO, yhat_hw_BO, yhat_base_BO, yhat_ctrl_BO, yhat_comp_BO
    así como yhat_hw_ln, yhat_sarima_base_ln, yhat_sarima_ctrl_ln, yhat_sarima_comp_ln

  Variables importadas nuevas (12):
    Mercado laboral:      PAYEMS, UNRATE
    Precios macro:        CPIAUCSL, PPIACO
    Monetario/financiero: FEDFUNDS, GS10, T10Y2Y, M2SL
    Insumos:              DCOILWTICO
    Actividad real:       INDPRO, HOUST, RSXFS

  Variables excluidas por missing values:
    AWHAETP, BAMLH0A0HYM2, DTWEXBGS, USALOLITONOSTSAM, PCU111111111
*/

import fred PAYEMS UNRATE CPIAUCSL PPIACO ///
    FEDFUNDS GS10 T10Y2Y M2SL ///
    DCOILWTICO INDPRO HOUST RSXFS, ///
    daterange(2000-01-01 2025-09-30) aggregate(monthly) nosummary clear

gen date = mofd(daten)
format date %tm
tempfile nuevas_vars
save `nuevas_vars'

* Cargar base del paper anterior (con yhat_*_BO ya calculados)
use "${clean}\project_forecasts.dta", clear

* Verificar que las variables B-O de los primeros 5 modelos existen
foreach v in yhat_naive_BO yhat_hw_BO yhat_base_BO yhat_ctrl_BO yhat_comp_BO {
    capture confirm variable `v'
    if _rc != 0 {
        di as error "ERROR: `v' no encontrada en project_forecasts.dta"
        di as error "       Asegúrese de haber ejecutado Script 01 correctamente."
        exit 1
    }
}
di "OK: todas las variables B-O de modelos 1-5 encontradas en project_forecasts.dta"

* Merge con nuevas variables
merge 1:1 date using `nuevas_vars', nogenerate ///
    keepusing(PAYEMS UNRATE CPIAUCSL PPIACO ///
              FEDFUNDS GS10 T10Y2Y M2SL ///
              DCOILWTICO INDPRO HOUST RSXFS)

*===========================================================================
**# 2. TRANSFORMACIONES Y VERIFICACIÓN DE MISSING VALUES
*===========================================================================

rename PAYEMS     payems
rename UNRATE     unrate
rename CPIAUCSL   cpiaucsl
rename PPIACO     ppiaco
rename FEDFUNDS   fedfunds
rename GS10       gs10
rename T10Y2Y     t10y2y
rename M2SL       m2sl
rename DCOILWTICO wti
rename INDPRO     indpro
rename HOUST      houst
rename RSXFS      rsxfs

* Variables positivas → logaritmos
foreach v in payems cpiaucsl ppiaco m2sl wti indpro houst rsxfs {
    gen ln_`v' = ln(`v')
}
* Variables tipo tasa: unrate fedfunds gs10 t10y2y → sin log

*---------------------------------------------------------------------------
* 2.1 Verificación de missing values — conjunto activo OCMT
*---------------------------------------------------------------------------

di _newline "══════════════════════════════════════════════════════════"
di "  VERIFICACIÓN DE MISSING VALUES — VARIABLES DEL ACTIVO OCMT"
di "══════════════════════════════════════════════════════════"

local flag_miss = 0
foreach v in ln_inv_manuf ln_ppi_farm ln_salario_min ///
             ln_payems ln_cpiaucsl ln_ppiaco ln_m2sl ln_wti ///
             ln_indpro ln_houst ln_rsxfs unrate fedfunds gs10 t10y2y {
    qui count if missing(`v')
    if r(N) > 0 {
        di as error "  ADVERTENCIA: `v' tiene `r(N)' missing — excluir del activo"
        local flag_miss = 1
    }
}
if `flag_miss' == 0 di "  OK: ninguna variable tiene missing values."
di "══════════════════════════════════════════════════════════"

* Guardar base extendida
save "${clean}\project_extended.dta", replace

*===========================================================================
**# 3. PRUEBAS ADF — NUEVAS VARIABLES
*===========================================================================

di _newline(2) "══════════════════════════════════════════════════════════"
di "     ADF — 12 NUEVAS VARIABLES  (niveles vs primera diferencia)"
di "══════════════════════════════════════════════════════════"
di "  Variable              Niveles              Primera Dif."
di "                      Zt      p            Zt      p"
di "──────────────────────────────────────────────────────────"

foreach v in ln_payems ln_cpiaucsl ln_ppiaco ln_m2sl ln_wti ///
             ln_indpro ln_houst ln_rsxfs unrate fedfunds gs10 t10y2y {
    qui dfuller `v', lags(12) trend
    local z0 = r(Zt)
    local p0 = r(p)
    qui dfuller D.`v', lags(12) trend
    local z1 = r(Zt)
    local p1 = r(p)
    di "  " %-22s "`v'" %6.3f `z0' "  " %5.3f `p0' "     " %6.3f `z1' "  " %5.3f `p1'
}
di "──────────────────────────────────────────────────────────"
di "  H0: raíz unitaria. VC tendencia 5% = -3.43"
di "══════════════════════════════════════════════════════════"

*===========================================================================
**# 4. MODELO 6 — VAR/VECM BIVARIADO
*===========================================================================

/*
  Sistema bivariado: (ln_emp_agr, ln_inv_manuf).
  Estrategia (Levendis, 2018, Cap. 12):
    Paso 1: varsoc  → rezago óptimo
    Paso 2: vecrank → prueba de traza de Johansen (H0: r=0)
    Paso 3: VECM (cointegración confirmada)
    Paso 4: fcast compute → pronóstico dinámico 36 pasos en logs
    Paso 5: Corrección B-O inline → yhat_vec_BO en niveles
*/

*---------------------------------------------------------------------------
* 4.1 Selección de rezagos (varsoc)
*---------------------------------------------------------------------------

di _newline "─── VAR/VECM: Selección de rezagos (varsoc) ───"
varsoc ln_emp_agr ln_inv_manuf if train==1, maxlag(13)

local opt_lag = 4   // Seleccionado por SBIC — ajustar si es necesario
di "Rezago óptimo asignado: `opt_lag'"

*---------------------------------------------------------------------------
* 4.2 Prueba de cointegración de Johansen (vecrank)
*---------------------------------------------------------------------------

di _newline "─── VAR/VECM: Prueba de Johansen (vecrank) ───"
vecrank ln_emp_agr ln_inv_manuf if train==1, ///
    trend(constant) lags(`opt_lag') max levela

local r_johansen = 1   // Cointegración confirmada — ajustar si cambia
di "Rango de cointegración: `r_johansen'"

*---------------------------------------------------------------------------
* 4.3 Estimación VECM + corrección B-O inline
*---------------------------------------------------------------------------

di _newline "==> Cointegración (r=`r_johansen'). Estimando VECM."

vec ln_emp_agr ln_inv_manuf if train==1, ///
    trend(constant) lags(`opt_lag') rank(`r_johansen')
estimates store vec_model

*--- Paso 1: Varianza residual → sigma2 para corrección B-O
predict resid_vec, equation(#1) residuals
qui summarize resid_vec if train==1
scalar sigma2_vec = r(Var)
drop resid_vec

di "sigma2_vec   = " %10.8f scalar(sigma2_vec)
di "Factor B-O   = " %10.8f exp(scalar(sigma2_vec) / 2)

*--- Paso 2: Fitted values in-sample → necesarios para estimar el ensemble
* predict equation(#1) sin la opción residuals devuelve valores ajustados
* (one-step-ahead) para las observaciones donde train==1
predict yhat_vec_fit_ln, equation(#1)
label var yhat_vec_fit_ln "VECM — ajuste in-sample ln(empleo)"

gen yhat_vec_fit_BO = exp(yhat_vec_fit_ln) * exp(scalar(sigma2_vec) / 2) if train==1
label var yhat_vec_fit_BO "VECM — ajuste in-sample B-O (miles de personas)"

*--- Paso 3: Pronóstico dinámico fuera de muestra (36 pasos — período test)
fcast compute yvec_, step(36) dynamic(tm(2022m10))

gen yhat_vec_ln = yvec_ln_emp_agr if test==1
label var yhat_vec_ln "VECM — pronóstico ln(empleo)"

gen yhat_vec_BO = exp(yhat_vec_ln) * exp(scalar(sigma2_vec) / 2)
label var yhat_vec_BO "VECM — pronóstico B-O (miles de personas)"

*--- Verificación de cobertura
count if missing(yhat_vec_fit_BO) & train==1
if r(N) > 0 di as error "ADVERTENCIA: `r(N)' faltantes en yhat_vec_fit_BO (train)"

count if missing(yhat_vec_BO) & test==1
if r(N) > 0 di as error "ADVERTENCIA: `r(N)' faltantes en yhat_vec_BO (test)"

*--- Gráfico VECM — período test en niveles B-O
twoway ///
    (tsline emp_agr     if test==1, lcolor(black) lwidth(medthin)) ///
    (tsline yhat_vec_BO if test==1, lcolor(navy)  lwidth(medthin) lpattern(dash)), ///
    title("VECM — período test (B-O corregido)", size(medsmall)) ///
    ytitle("Miles de personas", size(small)) xtitle("") ///
    legend(order(1 "Observado" 2 "VECM (B-O)") position(6) rows(1) size(small)) ///
    graphregion(color(white))
graph export "${graphs}\Forecast_VEC_BO.png", replace

*===========================================================================
**# 5. MODELO 7 — OCMT (One Covariate at a Time, Multiple Testing)
*===========================================================================

/*
  Implementación en dos pasos (Chudik, Kapetanios y Pesaran 2018;
  Núñez y Otero 2021):

  PASO 1 — Selección (OCMT):
    Variable dependiente: dd_ln_emp = ∆∆₁₂ ln(empleo) — estacionaria
    Conjunto activo (n=15): L1 de D.ln_* / D.tasa  (rezago 1 de primera dif.)
      → el predictor de t usa información observable en t-1
      → válido para pronóstico fuera de muestra
    Variables preseleccionadas (zvar): L1–L4 de dd_ln_emp
    Parámetros CKP: δ=1, δ*=2, p=5%

  PASO 2 — Estimación y pronóstico:
    Variables externas seleccionadas → regresores en ARIMA(1,1,1)(1,1,1)₁₂
    Si OCMT no selecciona ninguna → modelo = SARIMA base
    Corrección B-O aplicada inline con e(sigma)² (MLE)
*/

*---------------------------------------------------------------------------
* 5.1 Variable dependiente doble-diferenciada
*---------------------------------------------------------------------------

gen dd_ln_emp = D.S12.ln_emp_agr
label var dd_ln_emp "∆∆₁₂ ln(empleo agrícola)"

qui dfuller dd_ln_emp if train==1, lags(12) trend
di "ADF dd_ln_emp: Zt = " %6.3f r(Zt) "  p = " %5.3f r(p) "  (esperado: estacionaria)"

* Rezagos propios — preseleccionados en OCMT (zvar)
forvalues k = 1/4 {
    gen Lk`k'_dd = L`k'.dd_ln_emp
    label var Lk`k'_dd "L`k'.∆∆₁₂ ln(empleo)"
}

*---------------------------------------------------------------------------
* 5.2 Conjunto activo: L1 de D.ln_* y D.tasa (n=15 candidatos)
*---------------------------------------------------------------------------

/*
  Cada variable del activo es el rezago 1 de su primera diferencia:
    L1.D.ln_v = (ln_v[t-1] - ln_v[t-2]) para variables log
    L1.D.v    = (v[t-1] - v[t-2])        para tasas
  
  Esto garantiza que al pronosticar el período t:
    · La variable dependiente dd_ln_emp[t] es la que se quiere predecir
    · Los predictores L1.D.* usan información de t-1 (ya conocida)
    → Diseño válido para evaluación fuera de muestra
*/

* Primera diferencia de cada variable del activo
foreach v in ln_inv_manuf ln_ppi_farm ln_salario_min ///
             ln_payems ln_cpiaucsl ln_ppiaco ln_m2sl ln_wti ///
             ln_indpro ln_houst ln_rsxfs {
    gen Dact_`v' = D.`v'
    label var Dact_`v' "Δ `v' (activo OCMT)"
}

foreach v in unrate fedfunds gs10 t10y2y {
    gen Dact_`v' = D.`v'
    label var Dact_`v' "Δ `v' (activo OCMT)"
}

* Construir lista del activo: L1 de cada Dact_
local active_set ""
foreach v in ln_inv_manuf ln_ppi_farm ln_salario_min ///
             ln_payems ln_cpiaucsl ln_ppiaco ln_m2sl ln_wti ///
             ln_indpro ln_houst ln_rsxfs unrate fedfunds gs10 t10y2y {
    local active_set "`active_set' L.Dact_`v'"
}

di _newline "Conjunto activo OCMT (n=15 candidatos — L1.D.*):"
di "`active_set'"

*---------------------------------------------------------------------------
* 5.3 Aplicar OCMT sobre muestra de entrenamiento
*---------------------------------------------------------------------------

di _newline "─── OCMT: Selección de variables ───"
ocmt dd_ln_emp `active_set' if train==1, ///
    delta1(1) delta2(2) signif(5) ///
    zvar(Lk1_dd Lk2_dd Lk3_dd Lk4_dd)

local ocmt_all_selected = r(regressors)
di _newline "Regresores seleccionados por OCMT (incluye zvar):"
di "`ocmt_all_selected'"

/*
  Las variables externas tienen prefijo "L.Dact_".
  Se mapean a su variable en niveles logarítmicos para el ARIMA-X:
    L.Dact_ln_payems → ln_payems
    L.Dact_unrate    → unrate
  El ARIMA maneja internamente la diferenciación de la variable dependiente.
*/

local ocmt_ext_vars ""
foreach v of local ocmt_all_selected {
    if strpos("`v'", "Dact_") > 0 {
        local base = subinstr("`v'", "L.Dact_", "", 1)
        local ocmt_ext_vars "`ocmt_ext_vars' `base'"
    }
}

di _newline "Variables externas seleccionadas por OCMT:"
if "`ocmt_ext_vars'" == "" {
    di "  (ninguna — OCMT equivale a SARIMA base)"
}
else {
    di "  `ocmt_ext_vars'"
}

*---------------------------------------------------------------------------
* 5.4 Estimación ARIMA(1,1,1)(1,1,1)₁₂ con variables OCMT + B-O inline
*---------------------------------------------------------------------------

di _newline "─── OCMT: Estimación SARIMA-X ───"

if "`ocmt_ext_vars'" != "" {
    arima ln_emp_agr `ocmt_ext_vars' if train==1, ///
        arima(1,1,1) sarima(1,1,1,12) nolog
}
else {
    arima ln_emp_agr if train==1, ///
        arima(1,1,1) sarima(1,1,1,12) nolog
    di "  Nota: OCMT no seleccionó variables externas → modelo = SARIMA base."
}

estimates store ocmt_model

* e(sigma) = desviación estándar MLE del término de innovación
* Es el σ correcto para la corrección B-O en modelos ARIMA
scalar sigma2_ocmt = e(sigma)^2
di "e(sigma) OCMT    = " %10.8f e(sigma)
di "sigma2_ocmt      = " %10.8f scalar(sigma2_ocmt)
di "Factor B-O       = " %10.8f exp(scalar(sigma2_ocmt) / 2)

* Pronóstico en escala logarítmica (train + test)
predict yhat_ocmt_ln, y
label var yhat_ocmt_ln "OCMT-SARIMA — pronóstico ln(empleo)"

* Corrección B-O inline → niveles (miles de personas)
gen yhat_ocmt_BO = exp(yhat_ocmt_ln) * exp(scalar(sigma2_ocmt) / 2)
label var yhat_ocmt_BO "OCMT-SARIMA — pronóstico B-O (miles de personas)"

count if missing(yhat_ocmt_BO) & test==1
if r(N) > 0 di as error "ADVERTENCIA: `r(N)' faltantes en yhat_ocmt_BO"

* Gráfico OCMT — período test en niveles B-O
twoway ///
    (tsline emp_agr      if test==1, lcolor(black) lwidth(medthin)) ///
    (tsline yhat_ocmt_BO if test==1, lcolor(teal)  lwidth(medthin) lpattern(dash)), ///
    title("OCMT-SARIMA — período test (B-O corregido)", size(medsmall)) ///
    ytitle("Miles de personas", size(small)) xtitle("") ///
    legend(order(1 "Observado" 2 "OCMT-SARIMA (B-O)") position(6) rows(1) size(small)) ///
    graphregion(color(white))
graph export "${graphs}\Forecast_OCMT_BO.png", replace

/*
  ─────────────────────────────────────────────────────────────
  NOTA: La sección centralizada de corrección B-O (§6 anterior)
  ha sido eliminada. Cada modelo aplica B-O al terminar:
    § 4.3  VECM  → yhat_vec_BO  (usando sigma2 de residuos VEC)
    § 5.4  OCMT  → yhat_ocmt_BO (usando e(sigma)² del ARIMA)
    § 01   Mod. 1–5 → yhat_*_BO guardados en project_forecasts.dta
  ─────────────────────────────────────────────────────────────
*/

*===========================================================================
**# 6. MODELO 8 — ENSEMBLE PONDERADO (Granger y Ramanathan 1984, Método B)
*===========================================================================

/*
  Nota metodológica:
    OCMT no seleccionó variables externas → yhat_ocmt_BO = yhat_base_BO
    (colinealidad perfecta). El ensemble opera con 4 modelos distintos:
    HW, SARIMA base, SARIMA + controles y VAR/VECM.

  Method C (sin restricciones) produjo pesos inestables para el VECM
  (coeficiente > 400) debido al ajuste casi perfecto de sus fitted values
  in-sample, lo que hace el peso no transferible al período test.

  Se usa Method B (G-R 1984): pesos restringidos a sumar 1.
  Equivale a regresar (emp_agr - f_ref) sobre (f_j - f_ref) sin constante,
  donde f_ref = yhat_base_BO (modelo de referencia).
  El peso del modelo de referencia = 1 - suma de los demás pesos.
  Method B es insesgado si los componentes individuales son insesgados.
*/

di _newline "─── Ensemble Granger-Ramanathan (Método B — pesos restringidos) ───"

* Verificar cobertura train
foreach v in yhat_hw_BO yhat_base_BO yhat_ctrl_BO yhat_vec_fit_BO {
    qui count if !missing(`v') & train==1
    di "  `v' en train: `r(N)' obs."
}

*--- Implementación Method B:
* Regresión de (y - f_ref) sobre (f_j - f_ref) sin constante
* Referencia: yhat_base_BO (SARIMA base)

gen ens_y_ref  = emp_agr      - yhat_base_BO if train==1
gen ens_hw_ref = yhat_hw_BO   - yhat_base_BO if train==1
gen ens_ct_ref = yhat_ctrl_BO - yhat_base_BO if train==1
gen ens_vc_ref = yhat_vec_fit_BO - yhat_base_BO if train==1

label var ens_y_ref  "y - referencia (train)"
label var ens_hw_ref "HW - referencia (train)"
label var ens_ct_ref "SARIMA+ctrl - referencia (train)"
label var ens_vc_ref "VECM fit - referencia (train)"

regress ens_y_ref ens_hw_ref ens_ct_ref ens_vc_ref if train==1, noconstant

* Recuperar pesos individuales
scalar w_hw  = _b[ens_hw_ref]
scalar w_ct  = _b[ens_ct_ref]
scalar w_vc  = _b[ens_vc_ref]
* Peso del modelo de referencia: garantiza que la suma = 1
scalar w_bas = 1 - scalar(w_hw) - scalar(w_ct) - scalar(w_vc)

di _newline "Pesos del ensemble (Método B — suman 1 por construcción):"
di "  α_HW:           " %8.4f scalar(w_hw)
di "  α_SARIMA base:  " %8.4f scalar(w_bas)
di "  α_SARIMA+ctrl:  " %8.4f scalar(w_ct)
di "  α_VAR/VECM:     " %8.4f scalar(w_vc)
di "  Suma:           " %8.4f (scalar(w_hw) + scalar(w_bas) + scalar(w_ct) + scalar(w_vc))
di "  Nota: OCMT omitido (colineal con SARIMA base — sin variables externas seleccionadas)"

*--- Pronóstico ensemble en período test (pesos transferidos)
* Para VECM se usa yhat_vec_BO (pronóstico dinámico test)
* El peso w_vc estimado sobre fitted values train se aplica al pronóstico test:
* ambos capturan la misma fuente de información del VECM

gen yhat_ens = scalar(w_hw)  * yhat_hw_BO    ///
             + scalar(w_bas) * yhat_base_BO  ///
             + scalar(w_ct)  * yhat_ctrl_BO  ///
             + scalar(w_vc)  * yhat_vec_BO   ///
             if test==1

label var yhat_ens "Ensemble G-R Método B (pesos restringidos)"

count if missing(yhat_ens) & test==1
if r(N) > 0 di as error "ADVERTENCIA: `r(N)' faltantes en ensemble test"

* Gráfico ensemble
twoway ///
    (tsline emp_agr  if test==1, lcolor(black)  lwidth(medthick)) ///
    (tsline yhat_ens if test==1, lcolor(maroon) lwidth(medthin) lpattern(dash)), ///
    title("Ensemble G-R Método B — período test", size(medsmall)) ///
    ytitle("Miles de personas", size(small)) xtitle("") ///
    legend(order(1 "Observado" 2 "Ensemble (G-R B)") position(6) rows(1) size(small)) ///
    graphregion(color(white))
graph export "${graphs}\Forecast_Ensemble.png", replace

*===========================================================================
**# 7. MÉTRICAS DE EVALUACIÓN — 8 MODELOS (B-O CORREGIDOS)
*===========================================================================

gen e_naive_bo = emp_agr - yhat_naive_BO if test==1
gen e_hw_bo    = emp_agr - yhat_hw_BO    if test==1
gen e_base_bo  = emp_agr - yhat_base_BO  if test==1
gen e_ctrl_bo  = emp_agr - yhat_ctrl_BO  if test==1
gen e_comp_bo  = emp_agr - yhat_comp_BO  if test==1
gen e_vec_bo   = emp_agr - yhat_vec_BO   if test==1
gen e_ocmt_bo  = emp_agr - yhat_ocmt_BO  if test==1
gen e_ens      = emp_agr - yhat_ens      if test==1

foreach m in naive_bo hw_bo base_bo ctrl_bo comp_bo vec_bo ocmt_bo ens {
    gen e2_`m'  = e_`m'^2
    gen ape_`m' = abs(e_`m' / emp_agr) * 100 if test==1
}

foreach m in naive_bo hw_bo base_bo ctrl_bo comp_bo vec_bo ocmt_bo ens {
    qui summarize e2_`m'  if test==1
    scalar RMSE_`m' = sqrt(r(mean))
    qui summarize ape_`m' if test==1
    scalar MAPE_`m' = r(mean)
}

foreach m in hw_bo base_bo ctrl_bo comp_bo vec_bo ocmt_bo ens {
    scalar U_`m' = RMSE_`m' / RMSE_naive_bo
}

di _newline(2)
di "═══════════════════════════════════════════════════════════════"
di "     MÉTRICAS DE EVALUACIÓN — PERÍODO TEST (B-O corregido)"
di "═══════════════════════════════════════════════════════════════"
di "  Modelo                  RMSE       MAPE (%)    Theil U"
di "───────────────────────────────────────────────────────────────"
di "  Naïve estacional    " %8.3f RMSE_naive_bo "   " %8.3f MAPE_naive_bo "     1.000"
di "  Holt-Winters        " %8.3f RMSE_hw_bo    "   " %8.3f MAPE_hw_bo    "   " %8.3f U_hw_bo
di "  SARIMA base         " %8.3f RMSE_base_bo  "   " %8.3f MAPE_base_bo  "   " %8.3f U_base_bo
di "  SARIMA + controles  " %8.3f RMSE_ctrl_bo  "   " %8.3f MAPE_ctrl_bo  "   " %8.3f U_ctrl_bo
di "  SARIMA completo     " %8.3f RMSE_comp_bo  "   " %8.3f MAPE_comp_bo  "   " %8.3f U_comp_bo
di "  VAR/VECM            " %8.3f RMSE_vec_bo   "   " %8.3f MAPE_vec_bo   "   " %8.3f U_vec_bo
di "  OCMT-SARIMA         " %8.3f RMSE_ocmt_bo  "   " %8.3f MAPE_ocmt_bo  "   " %8.3f U_ocmt_bo
di "  Ensemble (G-R C)    " %8.3f RMSE_ens      "   " %8.3f MAPE_ens      "   " %8.3f U_ens
di "───────────────────────────────────────────────────────────────"
di "  RMSE en miles de personas. U = RMSE_modelo / RMSE_naïve."
di "═══════════════════════════════════════════════════════════════"

*===========================================================================
**# 8. TEST DE DIEBOLD-MARIANO — COMPARACIONES EXTENDIDAS
*===========================================================================

/*
  Los nombres dm_A, dm_B, dm_C ya existen en project_forecasts.dta
  (comparaciones del Script 01 entre los modelos SARIMA).
  Las nuevas comparaciones usan el prefijo dm2_ para evitar conflicto.

  Comparaciones:
    dm2_A: SARIMA base vs Holt-Winters
    dm2_B: SARIMA base vs VAR/VECM
    dm2_C: SARIMA base vs OCMT-SARIMA
    dm2_D: SARIMA base vs Ensemble
    dm2_E: VAR/VECM    vs OCMT-SARIMA
    dm2_F: OCMT-SARIMA vs Ensemble
*/

qui count if test==1
local T_test   = r(N)
local lags_hac = floor(`T_test'^(1/3))
di _newline "Obs. test: `T_test'  Lags HAC: `lags_hac'"

gen dm2_A = e2_base_bo - e2_hw_bo
gen dm2_B = e2_base_bo - e2_vec_bo
gen dm2_C = e2_base_bo - e2_ocmt_bo
gen dm2_D = e2_base_bo - e2_ens
gen dm2_E = e2_vec_bo  - e2_ocmt_bo
gen dm2_F = e2_ocmt_bo - e2_ens

label var dm2_A "DM2: SARIMA base vs HW (B-O)"
label var dm2_B "DM2: SARIMA base vs VAR/VECM (B-O)"
label var dm2_C "DM2: SARIMA base vs OCMT (B-O)"
label var dm2_D "DM2: SARIMA base vs Ensemble (B-O)"
label var dm2_E "DM2: VAR/VECM vs OCMT (B-O)"
label var dm2_F "DM2: OCMT vs Ensemble (B-O)"

foreach c in A B C D E F {
    qui summarize dm2_`c' if test==1
    scalar dm2_`c'_mean = r(mean)
    newey dm2_`c' if test==1, lag(`lags_hac')
    scalar dm2_`c'_stat = _b[_cons] / _se[_cons]
    test _cons
    scalar dm2_`c'_pval = r(p)
    local p = scalar(dm2_`c'_pval)
    if      `p' < 0.01  local sig2_`c' "***"
    else if `p' < 0.05  local sig2_`c' "**"
    else if `p' < 0.10  local sig2_`c' "*"
    else                 local sig2_`c' ""
}

di _newline(2)
di "══════════════════════════════════════════════════════════════════════"
di "              TEST DE DIEBOLD-MARIANO (extendido)"
di "══════════════════════════════════════════════════════════════════════"
di "  Comp.  Modelo 1          vs Modelo 2         Media d_t  DM stat  p-val"
di "──────────────────────────────────────────────────────────────────────"
di "  A    SARIMA base        vs HW            " %9.2f scalar(dm2_A_mean) "  " %6.3f scalar(dm2_A_stat) "`sig2_A'"  "  " %6.4f scalar(dm2_A_pval)
di "  B    SARIMA base        vs VAR/VECM      " %9.2f scalar(dm2_B_mean) "  " %6.3f scalar(dm2_B_stat) "`sig2_B'"  "  " %6.4f scalar(dm2_B_pval)
di "  C    SARIMA base        vs OCMT          " %9.2f scalar(dm2_C_mean) "  " %6.3f scalar(dm2_C_stat) "`sig2_C'"  "  " %6.4f scalar(dm2_C_pval)
di "  D    SARIMA base        vs Ensemble      " %9.2f scalar(dm2_D_mean) "  " %6.3f scalar(dm2_D_stat) "`sig2_D'"  "  " %6.4f scalar(dm2_D_pval)
di "  E    VAR/VECM            vs OCMT          " %9.2f scalar(dm2_E_mean) "  " %6.3f scalar(dm2_E_stat) "`sig2_E'"  "  " %6.4f scalar(dm2_E_pval)
di "  F    OCMT-SARIMA         vs Ensemble      " %9.2f scalar(dm2_F_mean) "  " %6.3f scalar(dm2_F_stat) "`sig2_F'"  "  " %6.4f scalar(dm2_F_pval)
di "──────────────────────────────────────────────────────────────────────"
di "  d_t = e²(M1) - e²(M2). Newey-West (`lags_hac' lags). *** p<0.01 ** p<0.05 * p<0.10"
di "══════════════════════════════════════════════════════════════════════"

*===========================================================================
**# 9. GRÁFICOS COMPARATIVOS — DESDE 2019 CON LÍNEA DE CORTE TRAIN/TEST
*===========================================================================

/*
  Ambas gráficas muestran desde 2019m1 hasta el final de la muestra (2025m9).
  La línea vertical roja marca el inicio del período test (2022m10).

  Período previo a la línea: ajuste in-sample de cada modelo
  Período posterior:          pronóstico fuera de muestra (test)

  Nota: yhat_vec_BO y yhat_ens solo tienen valores en el período test.
        yhat_*_BO de modelos SARIMA/HW tienen valores en ambos períodos.
*/

*---------------------------------------------------------------------------
* 9.1 Gráfico completo — 8 modelos
*---------------------------------------------------------------------------

twoway ///
    (tsline emp_agr       if date >= tm(2019m1), lcolor(black)     lwidth(medthick)) ///
    (tsline yhat_naive_BO if test==1, lcolor(gs10)      lwidth(thin)     lpattern(dash)) ///
    (tsline yhat_hw_BO    if test==1, lcolor(orange)    lwidth(thin)     lpattern(dash)) ///
    (tsline yhat_base_BO  if test==1, lcolor(green)     lwidth(thin)     lpattern(dash)) ///
    (tsline yhat_ctrl_BO  if test==1, lcolor(purple)    lwidth(thin)     lpattern(dash)) ///
    (tsline yhat_comp_BO  if test==1, lcolor(cranberry) lwidth(thin)     lpattern(dash)) ///
    (tsline yhat_vec_BO   if test==1, lcolor(navy)      lwidth(thin)     lpattern(dash)) ///
    (tsline yhat_ocmt_BO  if test==1, lcolor(teal)      lwidth(thin)     lpattern(dash)) ///
    (tsline yhat_ens      if test==1, lcolor(maroon)    lwidth(medthick) lpattern(shortdash)), ///
    tline(2022m10, lcolor(red) lwidth(thin) lpattern(dash)) ///
    title("Comparación de pronósticos — todos los modelos (B-O)", size(medsmall)) ///
    ytitle("Miles de personas", size(small)) xtitle("") ///
    note("Línea roja: inicio período test (2022m10). Pronósticos en niveles B-O.", size(vsmall)) ///
    legend(order(1 "Observado" 2 "Naïve" 3 "HW" 4 "SARIMA base" ///
                 5 "SARIMA+ctrl" 6 "SARIMA comp." 7 "VAR/VECM" ///
                 8 "OCMT" 9 "Ensemble") ///
           position(6) rows(2) size(vsmall)) ///
    graphregion(color(white))
graph export "${graphs}\Forecast_Todos_2019.png", replace width(1800)

*---------------------------------------------------------------------------
* 9.2 Gráfico focalizado — 4 modelos clave
*---------------------------------------------------------------------------

twoway ///
    (tsline emp_agr      if date >= tm(2019m1), lcolor(black)  lwidth(medthick)) ///
    (tsline yhat_base_BO if test==1, lcolor(green)  lwidth(medthin)  lpattern(dash)) ///
    (tsline yhat_vec_BO  if test==1, lcolor(navy)   lwidth(medthin)  lpattern(dash)) ///
    (tsline yhat_ocmt_BO if test==1, lcolor(teal)   lwidth(medthin)  lpattern(dash)) ///
    (tsline yhat_ens     if test==1, lcolor(maroon) lwidth(medthick) lpattern(shortdash)), ///
    tline(2022m10, lcolor(red) lwidth(thin) lpattern(dash)) ///
    title("Modelos clave vs Ensemble — desde 2019 (B-O)", size(medsmall)) ///
    ytitle("Miles de personas", size(small)) xtitle("") ///
    note("Línea roja: inicio período test (2022m10). Pronósticos en niveles B-O.", size(vsmall)) ///
    legend(order(1 "Observado" 2 "SARIMA base" 3 "VAR/VECM" 4 "OCMT" 5 "Ensemble") ///
           position(6) rows(1) size(small)) ///
    graphregion(color(white))
graph export "${graphs}\Forecast_Clave_2019.png", replace width(1400)

*===========================================================================
**# 10. EXPORTAR TABLAS (Excel y LaTeX)
*===========================================================================

*---------------------------------------------------------------------------
* 10.1 Tabla de variables del conjunto activo OCMT
*---------------------------------------------------------------------------

putexcel set "${tables}\Variables_OCMT.xlsx", replace sheet("Activo_OCMT")
putexcel A1 = "Variables del Conjunto Activo OCMT"
putexcel A2 = "Código FRED"
putexcel B2 = "Descripción"
putexcel C2 = "Categoría"
putexcel D2 = "Forma en activo"
putexcel A3  = "LNU02034560"
putexcel B3  = "Empleo agrícola (dep.)"
putexcel C3  = "Empleo"
putexcel D3  = "Var. dependiente"
putexcel A4  = "A33ATI"
putexcel B4  = "Inventarios maq. agrícola"
putexcel C4  = "Capital"
putexcel D4  = "L1.D.ln"
putexcel A5  = "WPU01"
putexcel B5  = "PPI productos agrícolas"
putexcel C5  = "Precios ag."
putexcel D5  = "L1.D.ln"
putexcel A6  = "FEDMINFRMWG"
putexcel B6  = "Salario mínimo agrícola"
putexcel C6  = "Costos laborales"
putexcel D6  = "L1.D.ln"
putexcel A7  = "PAYEMS"
putexcel B7  = "Empleo total no agrícola"
putexcel C7  = "Mercado laboral"
putexcel D7  = "L1.D.ln"
putexcel A8  = "UNRATE"
putexcel B8  = "Tasa de desempleo"
putexcel C8  = "Mercado laboral"
putexcel D8  = "L1.D."
putexcel A9  = "CPIAUCSL"
putexcel B9  = "IPC general"
putexcel C9  = "Precios macro"
putexcel D9  = "L1.D.ln"
putexcel A10 = "PPIACO"
putexcel B10 = "PPI todos los commodities"
putexcel C10 = "Precios macro"
putexcel D10 = "L1.D.ln"
putexcel A11 = "FEDFUNDS"
putexcel B11 = "Tasa fondos federales"
putexcel C11 = "Monetario"
putexcel D11 = "L1.D."
putexcel A12 = "GS10"
putexcel B12 = "Bono Tesoro 10 años"
putexcel C12 = "Financiero"
putexcel D12 = "L1.D."
putexcel A13 = "T10Y2Y"
putexcel B13 = "Spread curva 10Y-2Y"
putexcel C13 = "Financiero"
putexcel D13 = "L1.D."
putexcel A14 = "M2SL"
putexcel B14 = "Masa monetaria M2"
putexcel C14 = "Monetario"
putexcel D14 = "L1.D.ln"
putexcel A15 = "DCOILWTICO"
putexcel B15 = "Precio petróleo WTI"
putexcel C15 = "Insumos"
putexcel D15 = "L1.D.ln"
putexcel A16 = "INDPRO"
putexcel B16 = "Producción industrial"
putexcel C16 = "Actividad real"
putexcel D16 = "L1.D.ln"
putexcel A17 = "HOUST"
putexcel B17 = "Inicios de construcción"
putexcel C17 = "Uso del suelo"
putexcel D17 = "L1.D.ln"
putexcel A18 = "RSXFS"
putexcel B18 = "Ventas minoristas ex-gas"
putexcel C18 = "Demanda interna"
putexcel D18 = "L1.D.ln"
putexcel A20 = "Variables excluidas (missing values):"
putexcel A21 = "AWHAETP, BAMLH0A0HYM2, DTWEXBGS, USALOLITONOSTSAM, PCU111111111"
di "Tabla de variables OCMT exportada."

*---------------------------------------------------------------------------
* 10.2 Tabla de métricas — 8 modelos
*---------------------------------------------------------------------------

local rmse_naive = RMSE_naive_bo
local rmse_hw    = RMSE_hw_bo
local rmse_base  = RMSE_base_bo
local rmse_ctrl  = RMSE_ctrl_bo
local rmse_comp  = RMSE_comp_bo
local rmse_vec   = RMSE_vec_bo
local rmse_ocmt  = RMSE_ocmt_bo
local rmse_ens   = RMSE_ens

local mape_naive = MAPE_naive_bo
local mape_hw    = MAPE_hw_bo
local mape_base  = MAPE_base_bo
local mape_ctrl  = MAPE_ctrl_bo
local mape_comp  = MAPE_comp_bo
local mape_vec   = MAPE_vec_bo
local mape_ocmt  = MAPE_ocmt_bo
local mape_ens   = MAPE_ens

local u_hw   = U_hw_bo
local u_base = U_base_bo
local u_ctrl = U_ctrl_bo
local u_comp = U_comp_bo
local u_vec  = U_vec_bo
local u_ocmt = U_ocmt_bo
local u_ens  = U_ens

putexcel set "${tables}\Metricas_8Modelos.xlsx", replace sheet("Metricas_BO")
putexcel A1  = "Métricas de evaluación — 8 modelos (corrección B-O)"
putexcel A2  = "Modelo"
putexcel B2  = "RMSE"
putexcel C2  = "MAPE (%)"
putexcel D2  = "Theil U"
putexcel A3  = "Naïve estacional"
putexcel B3  = `rmse_naive'
putexcel C3  = `mape_naive'
putexcel D3  = 1
putexcel A4  = "Holt-Winters"
putexcel B4  = `rmse_hw'
putexcel C4  = `mape_hw'
putexcel D4  = `u_hw'
putexcel A5  = "SARIMA base"
putexcel B5  = `rmse_base'
putexcel C5  = `mape_base'
putexcel D5  = `u_base'
putexcel A6  = "SARIMA + controles"
putexcel B6  = `rmse_ctrl'
putexcel C6  = `mape_ctrl'
putexcel D6  = `u_ctrl'
putexcel A7  = "SARIMA completo"
putexcel B7  = `rmse_comp'
putexcel C7  = `mape_comp'
putexcel D7  = `u_comp'
putexcel A8  = "VAR/VECM"
putexcel B8  = `rmse_vec'
putexcel C8  = `mape_vec'
putexcel D8  = `u_vec'
putexcel A9  = "OCMT-SARIMA"
putexcel B9  = `rmse_ocmt'
putexcel C9  = `mape_ocmt'
putexcel D9  = `u_ocmt'
putexcel A10 = "Ensemble (G-R C)"
putexcel B10 = `rmse_ens'
putexcel C10 = `mape_ens'
putexcel D10 = `u_ens'
putexcel A12 = "RMSE en miles de personas."
putexcel A13 = "U = RMSE_modelo / RMSE_naïve."
putexcel A14 = "B-O: yhat_BO = exp(yhat_ln) x exp(sigma2/2)."
di "Tabla de métricas exportada."

*---------------------------------------------------------------------------
* 10.3 Tabla DM extendida — Excel
*---------------------------------------------------------------------------

local dmA_mean = dm2_A_mean
local dmA_stat = dm2_A_stat
local dmA_pval = dm2_A_pval
local dmB_mean = dm2_B_mean
local dmB_stat = dm2_B_stat
local dmB_pval = dm2_B_pval
local dmC_mean = dm2_C_mean
local dmC_stat = dm2_C_stat
local dmC_pval = dm2_C_pval
local dmD_mean = dm2_D_mean
local dmD_stat = dm2_D_stat
local dmD_pval = dm2_D_pval
local dmE_mean = dm2_E_mean
local dmE_stat = dm2_E_stat
local dmE_pval = dm2_E_pval
local dmF_mean = dm2_F_mean
local dmF_stat = dm2_F_stat
local dmF_pval = dm2_F_pval

putexcel set "${tables}\DieboldMariano_Extendido.xlsx", replace sheet("DM_Extendido")
putexcel A1 = "Test de Diebold-Mariano Extendido — 6 comparaciones"
putexcel A2 = "Comp."
putexcel B2 = "Modelo 1"
putexcel C2 = "vs"
putexcel D2 = "Modelo 2"
putexcel E2 = "Media d_t"
putexcel F2 = "DM stat"
putexcel G2 = "p-valor"
putexcel H2 = "Sig."
putexcel A3 = "A"
putexcel B3 = "SARIMA base"
putexcel C3 = "vs"
putexcel D3 = "Holt-Winters"
putexcel E3 = `dmA_mean'
putexcel F3 = `dmA_stat'
putexcel G3 = `dmA_pval'
putexcel H3 = "`sig2_A'"
putexcel A4 = "B"
putexcel B4 = "SARIMA base"
putexcel C4 = "vs"
putexcel D4 = "VAR/VECM"
putexcel E4 = `dmB_mean'
putexcel F4 = `dmB_stat'
putexcel G4 = `dmB_pval'
putexcel H4 = "`sig2_B'"
putexcel A5 = "C"
putexcel B5 = "SARIMA base"
putexcel C5 = "vs"
putexcel D5 = "OCMT-SARIMA"
putexcel E5 = `dmC_mean'
putexcel F5 = `dmC_stat'
putexcel G5 = `dmC_pval'
putexcel H5 = "`sig2_C'"
putexcel A6 = "D"
putexcel B6 = "SARIMA base"
putexcel C6 = "vs"
putexcel D6 = "Ensemble"
putexcel E6 = `dmD_mean'
putexcel F6 = `dmD_stat'
putexcel G6 = `dmD_pval'
putexcel H6 = "`sig2_D'"
putexcel A7 = "E"
putexcel B7 = "VAR/VECM"
putexcel C7 = "vs"
putexcel D7 = "OCMT-SARIMA"
putexcel E7 = `dmE_mean'
putexcel F7 = `dmE_stat'
putexcel G7 = `dmE_pval'
putexcel H7 = "`sig2_E'"
putexcel A8 = "F"
putexcel B8 = "OCMT-SARIMA"
putexcel C8 = "vs"
putexcel D8 = "Ensemble"
putexcel E8 = `dmF_mean'
putexcel F8 = `dmF_stat'
putexcel G8 = `dmF_pval'
putexcel H8 = "`sig2_F'"
putexcel A10 = "Newey-West (`lags_hac' lags). H0: igual capacidad predictiva."
putexcel A11 = "d_t = e2(M1) - e2(M2). *** p<0.01  ** p<0.05  * p<0.10"
di "Tabla DM extendida exportada."

*---------------------------------------------------------------------------
* 10.4 Tabla métricas — LaTeX
*---------------------------------------------------------------------------

local s_rmse_naive : display %6.3f `rmse_naive'
local s_rmse_hw    : display %6.3f `rmse_hw'
local s_rmse_base  : display %6.3f `rmse_base'
local s_rmse_ctrl  : display %6.3f `rmse_ctrl'
local s_rmse_comp  : display %6.3f `rmse_comp'
local s_rmse_vec   : display %6.3f `rmse_vec'
local s_rmse_ocmt  : display %6.3f `rmse_ocmt'
local s_rmse_ens   : display %6.3f `rmse_ens'

local s_mape_naive : display %5.3f `mape_naive'
local s_mape_hw    : display %5.3f `mape_hw'
local s_mape_base  : display %5.3f `mape_base'
local s_mape_ctrl  : display %5.3f `mape_ctrl'
local s_mape_comp  : display %5.3f `mape_comp'
local s_mape_vec   : display %5.3f `mape_vec'
local s_mape_ocmt  : display %5.3f `mape_ocmt'
local s_mape_ens   : display %5.3f `mape_ens'

local s_u_hw   : display %5.3f `u_hw'
local s_u_base : display %5.3f `u_base'
local s_u_ctrl : display %5.3f `u_ctrl'
local s_u_comp : display %5.3f `u_comp'
local s_u_vec  : display %5.3f `u_vec'
local s_u_ocmt : display %5.3f `u_ocmt'
local s_u_ens  : display %5.3f `u_ens'

file open tex using "${tables}\Metricas_8Modelos.tex", write replace
file write tex "\begin{table}[htbp]" _n
file write tex "\centering" _n
file write tex "\caption{M\'{e}tricas de precisi\'{o}n predictiva --- per\'{i}odo fuera de muestra (B-O corregido)}" _n
file write tex "\label{tab:metricas_8modelos}" _n
file write tex "\begin{tabular}{lccc}" _n
file write tex "\toprule" _n
file write tex "Modelo & RMSE & MAPE (\%) & Theil \$U\$ \\" _n
file write tex "\midrule" _n
file write tex "Na\`{i}ve estacional  & `s_rmse_naive' & `s_mape_naive' & 1.000 \\" _n
file write tex "Holt-Winters         & `s_rmse_hw'    & `s_mape_hw'    & `s_u_hw'   \\" _n
file write tex "SARIMA base          & `s_rmse_base'  & `s_mape_base'  & `s_u_base' \\" _n
file write tex "SARIMA + controles   & `s_rmse_ctrl'  & `s_mape_ctrl'  & `s_u_ctrl' \\" _n
file write tex "SARIMA completo      & `s_rmse_comp'  & `s_mape_comp'  & `s_u_comp' \\" _n
file write tex "VAR/VECM             & `s_rmse_vec'   & `s_mape_vec'   & `s_u_vec'  \\" _n
file write tex "OCMT-SARIMA          & `s_rmse_ocmt'  & `s_mape_ocmt'  & `s_u_ocmt' \\" _n
file write tex "\midrule" _n
file write tex "\textbf{Ensemble (G-R C)} & \textbf{`s_rmse_ens'} & \textbf{`s_mape_ens'} & \textbf{`s_u_ens'} \\" _n
file write tex "\bottomrule" _n
file write tex "\multicolumn{4}{p{0.75\textwidth}}{\footnotesize RMSE en miles de personas. " _n
file write tex "\$U = \text{RMSE}_{\text{modelo}} / \text{RMSE}_{\text{na\`{i}ve}}\$. " _n
file write tex "Correcci\'{o}n B-O: \$\hat{y}^{\text{BO}} = \exp(\hat{y}^{\ln}) \times \exp(\hat{\sigma}^2/2)\$. " _n
file write tex "En negrita el mejor modelo.}" _n
file write tex "\end{tabular}" _n
file write tex "\end{table}" _n
file close tex
di "Tabla LaTeX de métricas exportada."

*---------------------------------------------------------------------------
* 10.5 Tabla DM extendida — LaTeX
*---------------------------------------------------------------------------

local s_dmA_mean : display %8.2f `dmA_mean'
local s_dmA_stat : display %6.3f `dmA_stat'
local s_dmA_pval : display %6.4f `dmA_pval'
local s_dmB_mean : display %8.2f `dmB_mean'
local s_dmB_stat : display %6.3f `dmB_stat'
local s_dmB_pval : display %6.4f `dmB_pval'
local s_dmC_mean : display %8.2f `dmC_mean'
local s_dmC_stat : display %6.3f `dmC_stat'
local s_dmC_pval : display %6.4f `dmC_pval'
local s_dmD_mean : display %8.2f `dmD_mean'
local s_dmD_stat : display %6.3f `dmD_stat'
local s_dmD_pval : display %6.4f `dmD_pval'
local s_dmE_mean : display %8.2f `dmE_mean'
local s_dmE_stat : display %6.3f `dmE_stat'
local s_dmE_pval : display %6.4f `dmE_pval'
local s_dmF_mean : display %8.2f `dmF_mean'
local s_dmF_stat : display %6.3f `dmF_stat'
local s_dmF_pval : display %6.4f `dmF_pval'

file open tex2 using "${tables}\DieboldMariano_Extendido.tex", write replace
file write tex2 "\begin{table}[htbp]" _n
file write tex2 "\centering" _n
file write tex2 "\caption{Test de Diebold-Mariano --- comparaciones extendidas}" _n
file write tex2 "\label{tab:dm_extendido}" _n
file write tex2 "\begin{tabular}{clcrcrc}" _n
file write tex2 "\toprule" _n
file write tex2 "Comp. & Modelo 1 & vs & Modelo 2 & Media \$d_t\$ & DM stat & \$p\$-valor \\" _n
file write tex2 "\midrule" _n
file write tex2 "A & SARIMA base  & vs & Holt-Winters  & `s_dmA_mean' & `s_dmA_stat'`sig_A' & `s_dmA_pval' \\" _n
file write tex2 "B & SARIMA base  & vs & VAR/VECM      & `s_dmB_mean' & `s_dmB_stat'`sig_B' & `s_dmB_pval' \\" _n
file write tex2 "C & SARIMA base  & vs & OCMT-SARIMA   & `s_dmC_mean' & `s_dmC_stat'`sig_C' & `s_dmC_pval' \\" _n
file write tex2 "D & SARIMA base  & vs & Ensemble      & `s_dmD_mean' & `s_dmD_stat'`sig_D' & `s_dmD_pval' \\" _n
file write tex2 "E & VAR/VECM     & vs & OCMT-SARIMA   & `s_dmE_mean' & `s_dmE_stat'`sig_E' & `s_dmE_pval' \\" _n
file write tex2 "F & OCMT-SARIMA  & vs & Ensemble      & `s_dmF_mean' & `s_dmF_stat'`sig_F' & `s_dmF_pval' \\" _n
file write tex2 "\bottomrule" _n
file write tex2 "\multicolumn{7}{p{0.90\textwidth}}{\footnotesize \$d_t = e^2_{M1} - e^2_{M2}\$. " _n
file write tex2 "Errores Newey-West (`lags_hac' rezagos). \$H_0\$: igual precisi\'{o}n predictiva. " _n
file write tex2 "*** \$p<0{,}01\$, ** \$p<0{,}05\$, * \$p<0{,}10\$.}" _n
file write tex2 "\end{tabular}" _n
file write tex2 "\end{table}" _n
file close tex2
di "Tabla DM LaTeX exportada."

*===========================================================================
**# 11. GUARDAR BASE FINAL EXTENDIDA
*===========================================================================

save "${clean}\project_forecasts_extended.dta", replace
di _newline "Base final guardada: project_forecasts_extended.dta"
di "====== SCRIPT 02 COMPLETADO ======"
