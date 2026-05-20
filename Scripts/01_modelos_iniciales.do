/*===========================================================================
  SCRIPT 01: Modelos Iniciales — Naïve, Holt-Winters y SARIMA (3 variantes)
  Proyecto:  Pronósticos de Empleo Agrícola en EE.UU. — Extensión
  Autor:     Antonio Gutiérrez Arango
  Fecha:     Mayo 2026

  Descripción:
    Replica y extiende el paper anterior estimando los 5 modelos base:
      Modelo 1: Naïve estacional
      Modelo 2: Holt-Winters (multiplicativo vía logaritmos)
      Modelo 3: SARIMA(1,1,1)(1,1,1)₁₂ base
      Modelo 4: SARIMA(1,1,1)(1,1,1)₁₂ + controles (PPI y salario mínimo)
      Modelo 5: SARIMA(1,1,1)(1,1,1)₁₂ completo (+ capital físico)

  Corrección de retransformación — Beauchamp y Olson (1973):
    Todos los modelos que pronostican en escala logarítmica (HW, SARIMA)
    producen pronósticos sesgados al invertir la exponencial sin corrección,
    ya que E[exp(ŷ_ln + ε)] ≠ exp(ŷ_ln) cuando ε ~ N(0, σ²).
    
    La corrección lognormal exacta (Beauchamp y Olson 1973) establece:
      ŷ_BO = exp(ŷ_ln) × exp(σ̂²/2)
    
    donde σ̂² es la varianza de los residuos en escala logarítmica sobre
    la muestra de entrenamiento:
      · Para SARIMA: σ̂² = e(rmse)² (estimador MLE, recuperado inmediatamente
        tras la estimación de arima, antes de restaurar cualquier otro modelo)
      · Para Holt-Winters: σ̂² = Var(ln y_t − ŷ_hw_ln) sobre el período train
      · Para Naïve: σ̂² = 0 (sin estimación de parámetros; sin sesgo inducido
        por retransformación — el pronóstico ya está en niveles)
    
    Todas las métricas de evaluación (RMSE, MAPE, Theil U) y los tests de
    Diebold-Mariano se calculan exclusivamente sobre los pronósticos B-O
    corregidos, garantizando comparabilidad entre modelos.

  Outputs generados:
    · project_clean_data.dta    → base limpia con las 4 series originales
    · project_forecasts.dta     → base con pronósticos B-O de los 5 modelos
    · Outputs/Tables/           → Excel + LaTeX de ADF, coeficientes SARIMA,
                                   métricas y Diebold-Mariano
    · Outputs/Graphs/           → todas las figuras del análisis
===========================================================================*/

clear all
set more off

*===========================================================================
**# 0. ESTRUCTURA DEL PROYECTO
*===========================================================================

cd "C:\Users\anton\OneDrive\Documentos\GitHub\Pronósticos de Empleo Agrícola en EEUU\Scripts"

global main    "C:\Users\anton\OneDrive\Documentos\GitHub\Pronósticos de Empleo Agrícola en EEUU"
global graphs  "${main}\Outputs\Graphs"
global tables  "${main}\Outputs\Tables"
global raw     "${main}\Data\Raw"
global clean   "${main}\Data\Clean"

*===========================================================================
**# 1. IMPORTACIÓN Y PREPARACIÓN DE DATOS
*===========================================================================

import fred LNU02034560 A33ATI WPU01 FEDMINFRMWG, ///
    daterange(2000-01-01 2025-09-30) aggregate(monthly) nosummary clear

export excel "${raw}\FRED_data.xlsx", replace firstrow(varlabels)
save         "${raw}\FRED_Data.dta",  replace

rename LNU02034560 emp_agr
rename A33ATI       inv_manuf
rename WPU01        ppi_farm
rename FEDMINFRMWG  salario_min

gen date = mofd(daten)
format date %tm
tsset date, monthly
order datestr daten date

foreach var in emp_agr inv_manuf ppi_farm salario_min {
    gen ln_`var' = ln(`var')
}

save "${clean}\project_clean_data.dta", replace

summarize emp_agr inv_manuf ppi_farm salario_min
summarize ln_emp_agr ln_inv_manuf ln_ppi_farm ln_salario_min

*===========================================================================
**# 2. ANÁLISIS EXPLORATORIO
*===========================================================================

*---------------------------------------------------------------------------
* 2.1 Series de tiempo — gráfico combinado 2×2
*---------------------------------------------------------------------------

tsline emp_agr, ///
    lcolor(blue) ///
    tline(2008m9, lcolor(green) lpattern(dash)) ///
    tline(2020m3, lcolor(orange) lpattern(dash)) ///
    title("Empleo agrícola", size(small)) ///
    ytitle("Miles de personas", size(vsmall)) xtitle("") ///
    ylabel(, labsize(vsmall) angle(0)) xlabel(, labsize(vsmall) angle(45)) ///
    graphregion(color(white)) plotregion(margin(small)) scheme(s2color) ///
    name(g_emp, replace)
graph export "${graphs}\Employment_ts.png", replace

tsline inv_manuf, ///
    lcolor(red) ///
    tline(2008m9, lcolor(green) lpattern(dash)) ///
    tline(2020m3, lcolor(orange) lpattern(dash)) ///
    title("Capital físico agrícola", size(small)) ///
    ytitle("Millones USD", size(vsmall)) xtitle("") ///
    ylabel(, labsize(vsmall) angle(0)) xlabel(, labsize(vsmall) angle(45)) ///
    graphregion(color(white)) plotregion(margin(small)) scheme(s2color) ///
    name(g_inv, replace)
graph export "${graphs}\Inventories_ts.png", replace

tsline ppi_farm, ///
    lcolor(emerald) ///
    tline(2008m9, lcolor(green) lpattern(dash)) ///
    tline(2020m3, lcolor(orange) lpattern(dash)) ///
    title("PPI — productos agrícolas", size(small)) ///
    ytitle("Índice (1982=100)", size(vsmall)) xtitle("") ///
    ylabel(, labsize(vsmall) angle(0)) xlabel(, labsize(vsmall) angle(45)) ///
    graphregion(color(white)) plotregion(margin(small)) scheme(s2color) ///
    name(g_ppi, replace)
graph export "${graphs}\PPI_Farm_ts.png", replace

twoway (tsline salario_min, lcolor(purple)), ///
    tline(2008m9, lcolor(green) lpattern(dash)) ///
    tline(2020m3, lcolor(orange) lpattern(dash)) ///
    title("Salario mínimo agrícola", size(small)) ///
    ytitle("USD por hora", size(vsmall)) xtitle("") ///
    ylabel(, labsize(vsmall) angle(0)) xlabel(, labsize(vsmall) angle(45)) ///
    graphregion(color(white)) plotregion(margin(small)) scheme(s2color) ///
    name(g_sal, replace)
graph export "${graphs}\Salario_Min_ts.png", replace

graph combine g_emp g_inv g_ppi g_sal, ///
    cols(2) rows(2) ///
    title("Series de tiempo — variables del modelo", size(medsmall)) ///
    note("Nota: línea verde = crisis financiera 2008; línea naranja = inicio COVID-19", size(vsmall)) ///
    graphregion(color(white)) ysize(7) xsize(10)
graph export "${graphs}\Series_Combinadas.png", replace width(1800)

*---------------------------------------------------------------------------
* 2.2 Co-movimiento: empleo vs inventarios
*---------------------------------------------------------------------------

twoway ///
    (tsline emp_agr,   yaxis(1) lcolor(blue)     lwidth(thin)) ///
    (tsline inv_manuf, yaxis(2) lcolor(cranberry) lwidth(thin)), ///
    title("Empleo agrícola vs. inventarios de maquinaria", size(medsmall)) ///
    ytitle("Empleo (miles de personas)", axis(1) size(small)) ///
    ytitle("Inventarios (millones USD)", axis(2) size(small)) ///
    xtitle("Fecha", size(small)) ///
    xlabel(, angle(45) labsize(small)) ///
    ylabel(, axis(1) labsize(small) angle(0)) ///
    ylabel(, axis(2) labsize(small) angle(0)) ///
    legend(order(1 "Empleo agrícola" 2 "Inventarios maquinaria") ///
           position(6) rows(1) size(small) region(lstyle(none))) ///
    tline(2008m9, lcolor(green) lpattern(dash)) ///
    tline(2020m3, lcolor(orange) lpattern(dash)) ///
    note("Nota: verde = crisis 2008; naranja = COVID-19", size(vsmall)) ///
    graphregion(color(white)) plotregion(margin(medsmall)) scheme(s2color)
graph export "${graphs}\Employment_Inventories_ts.png", replace

*---------------------------------------------------------------------------
* 2.3 Variables en logaritmos
*---------------------------------------------------------------------------

twoway ///
    (tsline ln_emp_agr,     yaxis(1) lcolor(blue)       lwidth(medthin)) ///
    (tsline ln_inv_manuf,   yaxis(1) lcolor(cranberry)  lwidth(medthin)) ///
    (tsline ln_ppi_farm,    yaxis(1) lcolor(emerald%45) lwidth(thin)) ///
    (tsline ln_salario_min, yaxis(1) lcolor(purple%45)  lwidth(thin)), ///
    title("Variables en logaritmos", size(medsmall)) ///
    ytitle("Escala logarítmica", axis(1) size(small)) xtitle("Fecha", size(small)) ///
    xlabel(, angle(45) labsize(small)) ylabel(, axis(1) labsize(small) angle(0)) ///
    legend(order(1 "ln empleo" 2 "ln inventarios" 3 "ln PPI agr." 4 "ln salario mín.") ///
           position(6) rows(2) size(small) region(lstyle(none))) ///
    tline(2008m9, lcolor(green) lpattern(dash)) ///
    tline(2020m3, lcolor(orange) lpattern(dash)) ///
    note("Nota: verde = crisis 2008; naranja = COVID-19. Controles en menor opacidad.", size(vsmall)) ///
    graphregion(color(white)) plotregion(margin(medsmall)) scheme(s2color)
graph export "${graphs}\Log_Variables_ts.png", replace

*---------------------------------------------------------------------------
* 2.4 Descomposición estacional del empleo agrícola
*---------------------------------------------------------------------------

tssmooth ma tendencia = emp_agr, window(12)
gen est_bruto = emp_agr - tendencia
gen mes  = month(dofm(date))
gen anio = year(dofm(date))

bysort mes: egen patron_estacional = mean(est_bruto)
gen residuo = emp_agr - tendencia - patron_estacional

twoway ///
    (tsline emp_agr,   lcolor(blue%50) lwidth(thin)) ///
    (tsline tendencia, lcolor(red)     lwidth(medthick)), ///
    title("Empleo agrícola: serie y tendencia", size(medsmall)) ///
    ytitle("Miles de personas", size(small)) xtitle("Fecha", size(small)) ///
    legend(order(1 "Serie original" 2 "Tendencia (MM 12)") ///
           position(6) rows(1) size(small) region(lstyle(none))) ///
    yline(0) graphregion(color(white)) scheme(s2color)
graph export "${graphs}\Tendencia_ts.png", replace

preserve
    collapse (mean) patron_estacional, by(mes)
    twoway ///
        (bar  patron_estacional mes, barwidth(0.7) color(blue%70)) ///
        (line patron_estacional mes, lcolor(red) lwidth(thin)), ///
        title("Patrón estacional mensual — empleo agrícola", size(medsmall)) ///
        ytitle("Desviación respecto a tendencia (miles)", size(small)) ///
        xtitle("Mes", size(small)) ///
        xlabel(1 "Ene" 2 "Feb" 3 "Mar" 4 "Abr" 5 "May" 6 "Jun" ///
               7 "Jul" 8 "Ago" 9 "Sep" 10 "Oct" 11 "Nov" 12 "Dic", labsize(small)) ///
        yline(0, lcolor(black) lwidth(thin)) ///
        graphregion(color(white)) scheme(s2color)
    graph export "${graphs}\Patron_Estacional.png", replace
restore

*---------------------------------------------------------------------------
* 2.5 Definición de muestras: entrenamiento y evaluación
*---------------------------------------------------------------------------

* Train: 2000m1 – 2022m9 (273 obs.) | Test: 2022m10 – 2025m9 (36 obs.)
gen train = (date <= tm(2022m9))
gen test  = (date >  tm(2022m9))
tab test

*===========================================================================
**# 3. PRUEBAS DE RAÍZ UNITARIA (ADF)
*===========================================================================

foreach v in emp inv ppi sal {
    if "`v'" == "emp" local vname "ln_emp_agr"
    if "`v'" == "inv" local vname "ln_inv_manuf"
    if "`v'" == "ppi" local vname "ln_ppi_farm"
    if "`v'" == "sal" local vname "ln_salario_min"

    dfuller `vname', lags(12) trend
    scalar adf_`v'_niv  = r(Zt)
    scalar adfp_`v'_niv = r(p)

    dfuller D.`vname', lags(12) trend
    scalar adf_`v'_d1  = r(Zt)
    scalar adfp_`v'_d1 = r(p)

    dfuller DS12.`vname', lags(12) trend
    scalar adf_`v'_ds  = r(Zt)
    scalar adfp_`v'_ds = r(p)
}

foreach v in emp inv ppi sal {
    foreach s in niv d1 ds {
        local p = scalar(adfp_`v'_`s')
        if      `p' < 0.01  local sig_`v'_`s' "***"
        else if `p' < 0.05  local sig_`v'_`s' "**"
        else if `p' < 0.10  local sig_`v'_`s' "*"
        else                 local sig_`v'_`s' ""
    }
}

di _newline(2)
di "══════════════════════════════════════════════════════════════════════════════"
di "              PRUEBAS ADF — ORDEN DE INTEGRACIÓN"
di "══════════════════════════════════════════════════════════════════════════════"
di "  Variable          Niveles              Δ regular            Δ estacional"
di "                  Stat     p-val       Stat     p-val       Stat     p-val"
di "──────────────────────────────────────────────────────────────────────────────"
foreach v in emp inv ppi sal {
    if "`v'" == "emp" local vlab "ln_emp_agr    "
    if "`v'" == "inv" local vlab "ln_inv_manuf  "
    if "`v'" == "ppi" local vlab "ln_ppi_farm   "
    if "`v'" == "sal" local vlab "ln_salario_min"
    di "  `vlab' " ///
       %7.3f scalar(adf_`v'_niv) "`sig_`v'_niv'"  "  " %6.4f scalar(adfp_`v'_niv) ///
       "    " %7.3f scalar(adf_`v'_d1) "`sig_`v'_d1'"  "  " %6.4f scalar(adfp_`v'_d1) ///
       "    " %7.3f scalar(adf_`v'_ds) "`sig_`v'_ds'"  "  " %6.4f scalar(adfp_`v'_ds)
}
di "──────────────────────────────────────────────────────────────────────────────"
di "  VC con tendencia: 1% = -3.99   5% = -3.43   10% = -3.13"
di "  *** p<0.01  ** p<0.05  * p<0.10. H0: raíz unitaria."
di "══════════════════════════════════════════════════════════════════════════════"

* Exportar tabla ADF
foreach v in emp inv ppi sal {
    foreach s in niv d1 ds {
        local x_`v'_`s'  = scalar(adf_`v'_`s')
        local xp_`v'_`s' = scalar(adfp_`v'_`s')
    }
}

putexcel set "${tables}\UnitRoot_ADF.xlsx", replace sheet("ADF")
putexcel A1 = "Pruebas ADF — Orden de integración"
putexcel A2 = "Variable"
putexcel B2 = "Niveles — Estadístico"   C2 = "Niveles — p-valor"   D2 = "Niveles — Decisión"
putexcel E2 = "Δ regular — Estadístico" F2 = "Δ regular — p-valor" G2 = "Δ regular — Decisión"
putexcel H2 = "Δ estacional — Estadístico" I2 = "Δ estacional — p-valor" J2 = "Conclusión"

local row = 3
foreach v in emp inv ppi sal {
    if "`v'" == "emp" local vlab "ln_emp_agr"
    if "`v'" == "inv" local vlab "ln_inv_manuf"
    if "`v'" == "ppi" local vlab "ln_ppi_farm"
    if "`v'" == "sal" local vlab "ln_salario_min"
    if `xp_`v'_niv' < 0.05  local dec_niv "Rechaza H0 `sig_`v'_niv''"
    else                      local dec_niv "No rechaza H0"
    if `xp_`v'_d1'  < 0.05  local dec_d1  "Rechaza H0 `sig_`v'_d1''"
    else                      local dec_d1  "No rechaza H0"
    putexcel A`row' = "`vlab'"
    putexcel B`row' = `x_`v'_niv',  nformat("0.000")
    putexcel C`row' = `xp_`v'_niv', nformat("0.0000")
    putexcel D`row' = "`dec_niv'"
    putexcel E`row' = `x_`v'_d1',   nformat("0.000")
    putexcel F`row' = `xp_`v'_d1',  nformat("0.0000")
    putexcel G`row' = "`dec_d1'"
    putexcel H`row' = `x_`v'_ds',   nformat("0.000")
    putexcel I`row' = `xp_`v'_ds',  nformat("0.0000")
    putexcel J`row' = "I(1)"
    local row = `row' + 1
}
local nf = `row' + 1
putexcel A`nf' = "VC con tendencia: 1% = -3.99   5% = -3.43   10% = -3.13"
local nf2 = `nf' + 1
putexcel A`nf2' = "*** p<0.01  ** p<0.05  * p<0.10. H0: raíz unitaria."
di "Tabla ADF exportada."

*===========================================================================
**# 4. IDENTIFICACIÓN SARIMA — ACF / PACF Y SELECCIÓN DE ÓRDENES
*===========================================================================

gen d_ln_emp    = D.ln_emp_agr
gen ds_d_ln_emp = DS12.d_ln_emp
label var d_ln_emp    "Δ ln(empleo agrícola)"
label var ds_d_ln_emp "Δ ΔS12 ln(empleo agrícola)"

ac  d_ln_emp, lags(36) title("ACF — Δ ln(empleo)", size(small))       graphregion(color(white)) name(g1, replace)
graph export "${graphs}\ACF_d1.png", replace
pac d_ln_emp, lags(36) title("PACF — Δ ln(empleo)", size(small))      graphregion(color(white)) name(g2, replace)
graph export "${graphs}\PACF_d1.png", replace
ac  ds_d_ln_emp, lags(36) title("ACF — Δ ΔS12 ln(empleo)", size(small))  graphregion(color(white)) name(g3, replace)
graph export "${graphs}\ACF_d1D1.png", replace
pac ds_d_ln_emp, lags(36) title("PACF — Δ ΔS12 ln(empleo)", size(small)) graphregion(color(white)) name(g4, replace)
graph export "${graphs}\PACF_d1D1.png", replace

graph combine g1 g2 g3 g4, cols(2) rows(2) ///
    title("Funciones de autocorrelación — identificación SARIMA", size(medsmall)) ///
    graphregion(color(white)) ysize(6) xsize(8)
graph export "${graphs}\ACF_PACF_combinado.png", replace width(1600)

* Grid search AIC/BIC
matrix IC = J(1, 6, .)
local row = 0
qui foreach p in 0 1 2 {
  foreach q in 0 1 2 {
    foreach P in 0 1 {
      foreach Q in 0 1 {
        capture arima ln_emp_agr if train==1, arima(`p',1,`q') sarima(`P',1,`Q',12) nolog
        if _rc == 0 {
            local row = `row' + 1
            estat ic
            matrix tmp = r(S)
            matrix IC  = IC \ (`p', `q', `P', `Q', tmp[1,5], tmp[1,6])
        }
      }
    }
  }
}
matrix IC = IC[2..rowsof(IC), 1..6]
matrix colnames IC = p q P Q AIC BIC

mata:
    IC = st_matrix("IC")
    ord = order(IC[,5], 1)
    IC_sorted = IC[ord, .]
    st_matrix("IC_sorted", IC_sorted)
    st_numscalar("minAIC", IC_sorted[1,5])
    st_numscalar("minBIC", IC_sorted[1,6])
end
matrix colnames IC_sorted = p q P Q AIC BIC

di _newline "Modelos ordenados de menor a mayor AIC:"
matrix list IC_sorted
di "SARIMA(1,1,1)(1,1,1)₁₂ seleccionado por parsimonia (BIC)."

local p_opt = 1
local q_opt = 1
local P_opt = 1
local Q_opt = 1

*===========================================================================
**# 5. MODELO 1 — NAÏVE ESTACIONAL
*===========================================================================

/*
  El naïve estacional asigna como pronóstico el valor del mismo mes del
  año anterior: ŷ_t = y_{t-12}. Opera directamente en niveles (miles de
  personas) sin ninguna transformación logarítmica, por lo que no existe
  sesgo de retransformación. La corrección B-O no aplica (σ̂² = 0).
*/

gen yhat_naive = L12.emp_agr
label var yhat_naive "Naïve estacional — pronóstico en niveles"

* Para homogeneidad con los demás modelos, se define yhat_naive_BO = yhat_naive
gen yhat_naive_BO = yhat_naive
label var yhat_naive_BO "Naïve estacional — B-O (sin cambio, ya en niveles)"

twoway ///
    (tsline emp_agr          if test==1, lcolor(black) lwidth(medthin)) ///
    (tsline yhat_naive_BO    if test==1, lcolor(gray)  lwidth(medthin) lpattern(dash)), ///
    title("Naïve estacional — período test", size(medsmall)) ///
    ytitle("Miles de personas", size(small)) xtitle("") ///
    legend(order(1 "Observado" 2 "Naïve") position(6) rows(1) size(small)) ///
    graphregion(color(white))
graph export "${graphs}\Forecast_Naive.png", replace

*===========================================================================
**# 6. MODELO 2 — HOLT-WINTERS (MULTIPLICATIVO VÍA LOGARITMOS)
*===========================================================================

/*
  tssmooth shwinters implementa Holt-Winters aditivo sobre logaritmos,
  equivalente a Holt-Winters multiplicativo en niveles.

  La condición "if train==1" restringe la estimación de los parámetros
  de suavizamiento (α, β, γ) exclusivamente a la muestra de entrenamiento
  (2000m1 – 2022m9). La opción forecast(36) genera 36 períodos adicionales
  a partir del último valor de entrenamiento (2022m9), proyectando
  exactamente las observaciones del período test (2022m10 – 2025m9).
  Stata coloca automáticamente los valores pronosticados en las filas
  siguientes al último período train, que corresponden al período test.

  Corrección B-O (Beauchamp y Olson 1973):
    σ̂²_HW = Var(ln y_t − ŷ_hw_ln) sobre el período de entrenamiento
    ŷ_hw_BO = exp(ŷ_hw_ln) × exp(σ̂²_HW / 2)
*/

* Estimación restringida al período train + pronóstico 36 períodos adelante
tssmooth shwinters yhat_hw_ln = ln_emp_agr if train==1, forecast(36)
label var yhat_hw_ln "HW — suavizado (train) + pronóstico (test) en ln"

* Verificar cobertura: deben existir exactamente 36 valores en test
count if !missing(yhat_hw_ln) & test==1
if r(N) != 36 {
    di as error "ADVERTENCIA: HW generó `r(N)' valores en test (se esperan 36). Revisar."
}

* Cálculo de sigma2 HW: varianza de residuos in-sample en escala logarítmica
* Solo sobre train (parámetros estimados con esa muestra)
gen resid_hw_ln = ln_emp_agr - yhat_hw_ln if train==1
qui summarize resid_hw_ln if train==1
scalar sigma2_hw = r(Var)
drop resid_hw_ln

di _newline "─── Holt-Winters ───"
di "  σ̂²_HW = " %10.8f scalar(sigma2_hw)
di "  Factor B-O = exp(σ̂²/2) = " %8.6f exp(scalar(sigma2_hw)/2)

* Pronóstico con corrección B-O
gen yhat_hw_BO = exp(yhat_hw_ln) * exp(scalar(sigma2_hw) / 2)
label var yhat_hw_BO "HW — pronóstico B-O (miles de personas)"

twoway ///
    (tsline emp_agr    if test==1, lcolor(black)  lwidth(medthin)) ///
    (tsline yhat_hw_BO if test==1, lcolor(orange) lwidth(medthin) lpattern(dash)), ///
    title("Holt-Winters — período test (B-O)", size(medsmall)) ///
    ytitle("Miles de personas", size(small)) xtitle("") ///
    legend(order(1 "Observado" 2 "Holt-Winters (B-O)") ///
           position(6) rows(1) size(small)) ///
    graphregion(color(white))
graph export "${graphs}\Forecast_HW.png", replace

*===========================================================================
**# 7. MODELO 3 — SARIMA BASE
*===========================================================================

/*
  SARIMA(1,1,1)(1,1,1)₁₂ estimado sobre ln(empleo agrícola) sin regresores.

  Corrección B-O (Beauchamp y Olson 1973):
    σ̂²_base = e(sigma)²  ← desviación estándar MLE del término de innovación
    ŷ_base_BO = exp(ŷ_base_ln) × exp(σ̂²_base / 2)

  IMPORTANTE: e(sigma) debe capturarse antes de cualquier estimates restore.
*/

local p_opt = 1
local q_opt = 1
local P_opt = 1
local Q_opt = 1

arima ln_emp_agr if train==1, ///
    arima(`p_opt',1,`q_opt') sarima(`P_opt',1,`Q_opt',12) nolog
estat ic
estimates store sarima_base

* Capturar sigma2 desde e(sigma) — único escalar de dispersión en arima
scalar sigma2_base = e(sigma)^2
di _newline "─── SARIMA base ───"
di "  e(sigma) = " %10.8f e(sigma)
di "  σ̂²_base  = " %10.8f scalar(sigma2_base)
di "  Factor B-O = exp(σ̂²/2) = " %8.6f exp(scalar(sigma2_base)/2)

predict yhat_base_ln, y
label var yhat_base_ln "SARIMA base — pronóstico en ln"

gen yhat_base_BO = exp(yhat_base_ln) * exp(scalar(sigma2_base) / 2)
label var yhat_base_BO "SARIMA base — pronóstico B-O (miles de personas)"

twoway ///
    (tsline emp_agr      if test==1, lcolor(black) lwidth(medthin)) ///
    (tsline yhat_base_BO if test==1, lcolor(green) lwidth(medthin) lpattern(dash)), ///
    title("SARIMA base — período test (B-O)", size(medsmall)) ///
    ytitle("Miles de personas", size(small)) xtitle("") ///
    legend(order(1 "Observado" 2 "SARIMA base (B-O)") position(6) rows(1) size(small)) ///
    graphregion(color(white))
graph export "${graphs}\Forecast_SARIMA_base.png", replace

*===========================================================================
**# 8. MODELO 4 — SARIMA CON CONTROLES (PPI Y SALARIO MÍNIMO)
*===========================================================================

/*
  Regresores exógenos: ln(PPI agrícola) y ln(salario mínimo agrícola).

  Corrección B-O:
    σ̂²_ctrl = e(sigma)²
    ŷ_ctrl_BO = exp(ŷ_ctrl_ln) × exp(σ̂²_ctrl / 2)
*/

local p_opt = 1
local q_opt = 1
local P_opt = 1
local Q_opt = 1

arima ln_emp_agr ln_ppi_farm ln_salario_min if train==1, ///
    arima(`p_opt',1,`q_opt') sarima(`P_opt',1,`Q_opt',12) nolog
estat ic
estimates store sarima_controles

scalar sigma2_ctrl = e(sigma)^2
di _newline "─── SARIMA + controles ───"
di "  e(sigma) = " %10.8f e(sigma)
di "  σ̂²_ctrl  = " %10.8f scalar(sigma2_ctrl)
di "  Factor B-O = exp(σ̂²/2) = " %8.6f exp(scalar(sigma2_ctrl)/2)

predict yhat_ctrl_ln, y
label var yhat_ctrl_ln "SARIMA + controles — pronóstico en ln"

gen yhat_ctrl_BO = exp(yhat_ctrl_ln) * exp(scalar(sigma2_ctrl) / 2)
label var yhat_ctrl_BO "SARIMA + controles — pronóstico B-O"

twoway ///
    (tsline emp_agr      if test==1, lcolor(black)  lwidth(medthin)) ///
    (tsline yhat_ctrl_BO if test==1, lcolor(purple) lwidth(medthin) lpattern(dash)), ///
    title("SARIMA + controles — período test (B-O)", size(medsmall)) ///
    ytitle("Miles de personas", size(small)) xtitle("") ///
    legend(order(1 "Observado" 2 "SARIMA + ctrl (B-O)") position(6) rows(1) size(small)) ///
    graphregion(color(white))
graph export "${graphs}\Forecast_SARIMA_ctrl.png", replace

*===========================================================================
**# 9. MODELO 5 — SARIMA COMPLETO (CON CAPITAL FÍSICO)
*===========================================================================

/*
  Regresores exógenos: PPI, salario mínimo e inventarios de maquinaria
  agrícola (contemporáneo y dos rezagos).

  Corrección B-O:
    σ̂²_comp = e(sigma)²
    ŷ_comp_BO = exp(ŷ_comp_ln) × exp(σ̂²_comp / 2)
*/

local p_opt = 1
local q_opt = 1
local P_opt = 1
local Q_opt = 1

gen L1_ln_inv = L1.ln_inv_manuf
gen L2_ln_inv = L2.ln_inv_manuf
label var L1_ln_inv "ln inventarios (rezago 1)"
label var L2_ln_inv "ln inventarios (rezago 2)"

arima ln_emp_agr ln_ppi_farm ln_salario_min ln_inv_manuf L1_ln_inv L2_ln_inv ///
    if train==1, ///
    arima(`p_opt',1,`q_opt') sarima(`P_opt',1,`Q_opt',12) nolog
estat ic
estimates store sarima_completo

scalar sigma2_comp = e(sigma)^2
di _newline "─── SARIMA completo ───"
di "  e(sigma) = " %10.8f e(sigma)
di "  σ̂²_comp  = " %10.8f scalar(sigma2_comp)
di "  Factor B-O = exp(σ̂²/2) = " %8.6f exp(scalar(sigma2_comp)/2)

predict yhat_comp_ln, y
label var yhat_comp_ln "SARIMA completo — pronóstico en ln"

gen yhat_comp_BO = exp(yhat_comp_ln) * exp(scalar(sigma2_comp) / 2)
label var yhat_comp_BO "SARIMA completo — pronóstico B-O"

twoway ///
    (tsline emp_agr      if test==1, lcolor(black)     lwidth(medthin)) ///
    (tsline yhat_comp_BO if test==1, lcolor(cranberry) lwidth(medthin) lpattern(dash)), ///
    title("SARIMA completo — período test (B-O)", size(medsmall)) ///
    ytitle("Miles de personas", size(small)) xtitle("") ///
    legend(order(1 "Observado" 2 "SARIMA completo (B-O)") position(6) rows(1) size(small)) ///
    graphregion(color(white))
graph export "${graphs}\Forecast_SARIMA_comp.png", replace

*---------------------------------------------------------------------------
* Resumen de factores de corrección B-O
*---------------------------------------------------------------------------

di _newline(2)
di "══════════════════════════════════════════════════════════════════"
di "    RESUMEN — CORRECCIÓN BEAUCHAMP Y OLSON (1973)"
di "══════════════════════════════════════════════════════════════════"
di "  Modelo               σ̂²          Factor exp(σ̂²/2)"
di "──────────────────────────────────────────────────────────────────"
di "  Naïve estacional   (sin log)   (no aplica)"
di "  Holt-Winters     " %10.8f scalar(sigma2_hw)   "   " %8.6f exp(scalar(sigma2_hw)/2)
di "  SARIMA base      " %10.8f scalar(sigma2_base) "   " %8.6f exp(scalar(sigma2_base)/2)
di "  SARIMA+ctrl      " %10.8f scalar(sigma2_ctrl) "   " %8.6f exp(scalar(sigma2_ctrl)/2)
di "  SARIMA completo  " %10.8f scalar(sigma2_comp) "   " %8.6f exp(scalar(sigma2_comp)/2)
di "──────────────────────────────────────────────────────────────────"
di "  ŷ_BO = exp(ŷ_ln) × exp(σ̂²/2)"
di "══════════════════════════════════════════════════════════════════"

*===========================================================================
**# 10. GRÁFICO COMPARATIVO — TODOS LOS MODELOS (PERÍODO TEST, B-O)
*===========================================================================

twoway ///
    (tsline emp_agr      if test==1, lcolor(black)     lwidth(medthick)) ///
    (tsline yhat_naive_BO if test==1, lcolor(gs10)     lwidth(thin) lpattern(dash)) ///
    (tsline yhat_hw_BO   if test==1, lcolor(orange)    lwidth(thin) lpattern(dash)) ///
    (tsline yhat_base_BO if test==1, lcolor(green)     lwidth(thin) lpattern(dash)) ///
    (tsline yhat_ctrl_BO if test==1, lcolor(purple)    lwidth(thin) lpattern(dash)) ///
    (tsline yhat_comp_BO if test==1, lcolor(cranberry) lwidth(thin) lpattern(dash)), ///
    title("Comparación de pronósticos — período test (B-O corregido)", size(medsmall)) ///
    ytitle("Miles de personas", size(small)) xtitle("") ///
    legend(order(1 "Observado" 2 "Naïve" 3 "Holt-Winters" ///
                 4 "SARIMA base" 5 "SARIMA + ctrl" 6 "SARIMA completo") ///
           position(6) rows(2) size(small)) ///
    graphregion(color(white))
graph export "${graphs}\Forecast_Comparativo_BO.png", replace width(1800)

*===========================================================================
**# 11. MÉTRICAS DE EVALUACIÓN — 5 MODELOS (PRONÓSTICOS B-O CORREGIDOS)
*===========================================================================

gen e_naive = emp_agr - yhat_naive_BO  if test==1
gen e_hw    = emp_agr - yhat_hw_BO     if test==1
gen e_base  = emp_agr - yhat_base_BO   if test==1
gen e_ctrl  = emp_agr - yhat_ctrl_BO   if test==1
gen e_comp  = emp_agr - yhat_comp_BO   if test==1

foreach m in naive hw base ctrl comp {
    gen e2_`m'  = e_`m'^2
    gen ape_`m' = abs(e_`m' / emp_agr) * 100 if test==1
}

foreach m in naive hw base ctrl comp {
    qui summarize e2_`m'  if test==1
    scalar RMSE_`m' = sqrt(r(mean))
    qui summarize ape_`m' if test==1
    scalar MAPE_`m' = r(mean)
}

foreach m in hw base ctrl comp {
    scalar U_`m' = RMSE_`m' / RMSE_naive
}

di _newline(2)
di "═══════════════════════════════════════════════════════════════════"
di "   MÉTRICAS DE EVALUACIÓN — PERÍODO TEST (pronósticos B-O)"
di "═══════════════════════════════════════════════════════════════════"
di "  Modelo                 RMSE       MAPE (%)    Theil U"
di "───────────────────────────────────────────────────────────────────"
di "  Naïve estacional    " %8.3f RMSE_naive "   " %8.3f MAPE_naive "     1.000"
di "  Holt-Winters        " %8.3f RMSE_hw    "   " %8.3f MAPE_hw    "   " %8.3f U_hw
di "  SARIMA base         " %8.3f RMSE_base  "   " %8.3f MAPE_base  "   " %8.3f U_base
di "  SARIMA + controles  " %8.3f RMSE_ctrl  "   " %8.3f MAPE_ctrl  "   " %8.3f U_ctrl
di "  SARIMA completo     " %8.3f RMSE_comp  "   " %8.3f MAPE_comp  "   " %8.3f U_comp
di "───────────────────────────────────────────────────────────────────"
di "  RMSE en miles de personas. U = RMSE_modelo / RMSE_naïve."
di "  Corrección B-O: ŷ_BO = exp(ŷ_ln) × exp(σ̂²/2)."
di "═══════════════════════════════════════════════════════════════════"

* Pasar escalares a locales para uso en putexcel
local rmse_naive = RMSE_naive
local rmse_hw    = RMSE_hw
local rmse_base  = RMSE_base
local rmse_ctrl  = RMSE_ctrl
local rmse_comp  = RMSE_comp

local mape_naive = MAPE_naive
local mape_hw    = MAPE_hw
local mape_base  = MAPE_base
local mape_ctrl  = MAPE_ctrl
local mape_comp  = MAPE_comp

local u_hw   = U_hw
local u_base = U_base
local u_ctrl = U_ctrl
local u_comp = U_comp

* Exportar métricas — Excel
putexcel set "${tables}\Metricas_5Modelos.xlsx", replace sheet("Metricas_BO")
putexcel A1 = "Métricas de evaluación — 5 modelos (corrección Beauchamp-Olson)"
putexcel A2 = "Modelo"
putexcel B2 = "RMSE"
putexcel C2 = "MAPE (%)"
putexcel D2 = "Theil U"
putexcel A3 = "Naïve estacional"
putexcel B3 = `rmse_naive'
putexcel C3 = `mape_naive'
putexcel D3 = 1
putexcel A4 = "Holt-Winters"
putexcel B4 = `rmse_hw'
putexcel C4 = `mape_hw'
putexcel D4 = `u_hw'
putexcel A5 = "SARIMA base"
putexcel B5 = `rmse_base'
putexcel C5 = `mape_base'
putexcel D5 = `u_base'
putexcel A6 = "SARIMA + controles"
putexcel B6 = `rmse_ctrl'
putexcel C6 = `mape_ctrl'
putexcel D6 = `u_ctrl'
putexcel A7 = "SARIMA completo"
putexcel B7 = `rmse_comp'
putexcel C7 = `mape_comp'
putexcel D7 = `u_comp'
putexcel A9  = "RMSE en miles de personas."
putexcel A10 = "U = RMSE_modelo / RMSE_naïve."
putexcel A11 = "Pronósticos con corrección B-O: ŷ_BO = exp(ŷ_ln) × exp(σ̂²/2)."
di "Tabla de métricas exportada."

* Formatear todos los valores numéricos como strings antes de escribir
local s_rmse_naive : display %6.3f `rmse_naive'
local s_rmse_hw    : display %6.3f `rmse_hw'
local s_rmse_base  : display %6.3f `rmse_base'
local s_rmse_ctrl  : display %6.3f `rmse_ctrl'
local s_rmse_comp  : display %6.3f `rmse_comp'

local s_mape_naive : display %5.3f `mape_naive'
local s_mape_hw    : display %5.3f `mape_hw'
local s_mape_base  : display %5.3f `mape_base'
local s_mape_ctrl  : display %5.3f `mape_ctrl'
local s_mape_comp  : display %5.3f `mape_comp'

local s_u_hw   : display %5.3f `u_hw'
local s_u_base : display %5.3f `u_base'
local s_u_ctrl : display %5.3f `u_ctrl'
local s_u_comp : display %5.3f `u_comp'

* Exportar métricas — LaTeX
file open mtex using "${tables}\Metricas_5Modelos.tex", write replace
file write mtex "\begin{table}[htbp]" _n
file write mtex "\centering" _n
file write mtex "\caption{M\'{e}tricas de precisi\'{o}n predictiva --- per\'{i}odo fuera de muestra (B-O corregido)}" _n
file write mtex "\label{tab:metricas_5modelos}" _n
file write mtex "\begin{tabular}{lccc}" _n
file write mtex "\toprule" _n
file write mtex "Modelo & RMSE & MAPE (\%) & Theil \$U\$ \\" _n
file write mtex "\midrule" _n
file write mtex "Na\`{i}ve estacional  & `s_rmse_naive' & `s_mape_naive' & 1.000 \\" _n
file write mtex "Holt-Winters         & `s_rmse_hw'    & `s_mape_hw'    & `s_u_hw'    \\" _n
file write mtex "\textbf{SARIMA base} & \textbf{`s_rmse_base'} & \textbf{`s_mape_base'} & \textbf{`s_u_base'} \\" _n
file write mtex "SARIMA + controles   & `s_rmse_ctrl'  & `s_mape_ctrl'  & `s_u_ctrl'  \\" _n
file write mtex "SARIMA completo      & `s_rmse_comp'  & `s_mape_comp'  & `s_u_comp'  \\" _n
file write mtex "\bottomrule" _n
file write mtex "\multicolumn{4}{p{0.72\textwidth}}{\footnotesize RMSE en miles de personas. \$U = \text{RMSE}_m / \text{RMSE}_{\text{na\`{i}ve}}\$. Correcci\'{o}n B-O: \$\hat{y}^{\text{BO}} = \exp(\hat{y}^{\ln}) \times \exp(\hat{\sigma}^2/2)\$. En negrita el mejor modelo.}" _n
file write mtex "\end{tabular}" _n
file write mtex "\end{table}" _n
file close mtex
di "Tabla LaTeX de métricas exportada."

*===========================================================================
**# 12. TEST DE DIEBOLD-MARIANO (sobre errores B-O)
*===========================================================================

qui count if test==1
local T_test   = r(N)
local lags_hac = floor(`T_test'^(1/3))
di _newline "Observaciones test: `T_test'   Lags HAC: `lags_hac'"

gen dm_A = e2_base - e2_ctrl
gen dm_B = e2_base - e2_comp
gen dm_C = e2_ctrl - e2_comp

label var dm_A "DM: base vs +controles (B-O)"
label var dm_B "DM: base vs completo (B-O)"
label var dm_C "DM: +controles vs completo (B-O)"

foreach c in A B C {
    qui summarize dm_`c' if test==1
    scalar dm_`c'_mean = r(mean)
    newey dm_`c' if test==1, lag(`lags_hac')
    scalar dm_`c'_stat = _b[_cons] / _se[_cons]
    scalar dm_`c'_se   = _se[_cons]
    test _cons
    scalar dm_`c'_pval = r(p)
    local p = scalar(dm_`c'_pval)
    if      `p' < 0.01  local sig_`c' "***"
    else if `p' < 0.05  local sig_`c' "**"
    else if `p' < 0.10  local sig_`c' "*"
    else                 local sig_`c' ""
    if      `p' < 0.05 & scalar(dm_`c'_mean) < 0  local concl_`c' "Modelo 1 mejor"
    else if `p' < 0.05 & scalar(dm_`c'_mean) > 0  local concl_`c' "Modelo 2 mejor"
    else                                            local concl_`c' "Sin diferencia sig."
}

di _newline(2)
di "═══════════════════════════════════════════════════════════════════"
di "         TEST DE DIEBOLD-MARIANO (errores B-O corregidos)"
di "═══════════════════════════════════════════════════════════════════"
di "  Comp.   Media d_t    DM stat    p-valor    Conclusión"
di "───────────────────────────────────────────────────────────────────"
foreach c in A B C {
    di "  `c'    " %9.2f scalar(dm_`c'_mean) "   " ///
       %7.3f scalar(dm_`c'_stat) "`sig_`c'" "   " ///
       %7.4f scalar(dm_`c'_pval) "   `concl_`c''"
}
di "───────────────────────────────────────────────────────────────────"
di "  Lags Newey-West: `lags_hac' | Obs. test: `T_test'"
di "  d_t = e²_BO(M1) - e²_BO(M2). *** p<0.01  ** p<0.05  * p<0.10"
di "═══════════════════════════════════════════════════════════════════"

* Pasar escalares DM a locales para putexcel
local dm_A_mean = dm_A_mean
local dm_A_stat = dm_A_stat
local dm_A_pval = dm_A_pval
local dm_B_mean = dm_B_mean
local dm_B_stat = dm_B_stat
local dm_B_pval = dm_B_pval
local dm_C_mean = dm_C_mean
local dm_C_stat = dm_C_stat
local dm_C_pval = dm_C_pval

* Exportar DM — Excel
putexcel set "${tables}\DieboldMariano.xlsx", replace sheet("DM_BO")
putexcel A1 = "Test de Diebold-Mariano — pronósticos B-O corregidos"
putexcel A2 = "Comp."
putexcel B2 = "Modelo 1"
putexcel C2 = "Modelo 2"
putexcel D2 = "Media d_t"
putexcel E2 = "DM stat"
putexcel F2 = "p-valor"
putexcel G2 = "Sig."
putexcel H2 = "Conclusión"
putexcel A3 = "A"
putexcel B3 = "SARIMA base"
putexcel C3 = "SARIMA + controles"
putexcel D3 = `dm_A_mean'
putexcel E3 = `dm_A_stat'
putexcel F3 = `dm_A_pval'
putexcel G3 = "`sig_A'"
putexcel H3 = "`concl_A'"
putexcel A4 = "B"
putexcel B4 = "SARIMA base"
putexcel C4 = "SARIMA completo"
putexcel D4 = `dm_B_mean'
putexcel E4 = `dm_B_stat'
putexcel F4 = `dm_B_pval'
putexcel G4 = "`sig_B'"
putexcel H4 = "`concl_B'"
putexcel A5 = "C"
putexcel B5 = "SARIMA + controles"
putexcel C5 = "SARIMA completo"
putexcel D5 = `dm_C_mean'
putexcel E5 = `dm_C_stat'
putexcel F5 = `dm_C_pval'
putexcel G5 = "`sig_C'"
putexcel H5 = "`concl_C'"
putexcel A7 = "Newey-West (`lags_hac' lags) | Obs. test: `T_test'"
putexcel A8 = "d_t = e²_BO(M1) - e²_BO(M2). *** p<0.01  ** p<0.05  * p<0.10"
di "Tabla DM exportada."

* Formatear valores DM como strings
local s_dmA_mean : display %8.2f `dm_A_mean'
local s_dmA_stat : display %6.3f `dm_A_stat'
local s_dmA_pval : display %6.4f `dm_A_pval'

local s_dmB_mean : display %8.2f `dm_B_mean'
local s_dmB_stat : display %6.3f `dm_B_stat'
local s_dmB_pval : display %6.4f `dm_B_pval'

local s_dmC_mean : display %8.2f `dm_C_mean'
local s_dmC_stat : display %6.3f `dm_C_stat'
local s_dmC_pval : display %6.4f `dm_C_pval'

* Exportar DM — LaTeX
file open dtex using "${tables}\DieboldMariano.tex", write replace
file write dtex "\begin{table}[htbp]" _n
file write dtex "\centering" _n
file write dtex "\caption{Test de Diebold-Mariano --- pron\'{o}sticos con correcci\'{o}n B-O}" _n
file write dtex "\label{tab:dm_base}" _n
file write dtex "\begin{tabular}{clcrrcc}" _n
file write dtex "\toprule" _n
file write dtex "Comp. & Modelo 1 & vs & Modelo 2 & Media \$d_t\$ & DM stat & \$p\$-valor \\" _n
file write dtex "\midrule" _n
file write dtex "A & SARIMA base & vs & SARIMA + controles & `s_dmA_mean' & `s_dmA_stat'`sig_A' & `s_dmA_pval' \\" _n
file write dtex "B & SARIMA base & vs & SARIMA completo    & `s_dmB_mean' & `s_dmB_stat'`sig_B' & `s_dmB_pval' \\" _n
file write dtex "C & SARIMA + ctrl & vs & SARIMA completo  & `s_dmC_mean' & `s_dmC_stat'`sig_C' & `s_dmC_pval' \\" _n
file write dtex "\bottomrule" _n
file write dtex "\multicolumn{7}{p{0.88\textwidth}}{\footnotesize \$d_t = e^2_{\text{BO},M1} - e^2_{\text{BO},M2}\$. Errores Newey-West (`lags_hac' rezagos). \$H_0\$: igual precisi\'{o}n predictiva. *** \$p<0{,}01\$, ** \$p<0{,}05\$, * \$p<0{,}10\$.}" _n
file write dtex "\end{tabular}" _n
file write dtex "\end{table}" _n
file close dtex
di "Tabla DM LaTeX exportada."

*===========================================================================
**# 13. DIAGNÓSTICO DE RESIDUOS — SARIMA COMPLETO
*===========================================================================

estimates restore sarima_completo
predict resid_comp, resid
label var resid_comp "Residuos SARIMA completo"

tsline resid_comp, ///
    title("Residuos — SARIMA completo", size(medsmall)) ///
    yline(0, lcolor(red) lwidth(thin)) ///
    ytitle("Residuo", size(small)) xtitle("") ///
    graphregion(color(white))
graph export "${graphs}\Residuos_SARIMA_comp.png", replace

ac resid_comp, lags(36) ///
    title("ACF residuos — SARIMA completo") graphregion(color(white))
graph export "${graphs}\ACF_Residuos.png", replace

wntestq resid_comp, lags(24)

*===========================================================================
**# 14. TABLA DE COEFICIENTES SARIMA
*===========================================================================

estimates dir

esttab sarima_base sarima_controles sarima_completo, ///
    title("Comparación SARIMA — Variable dependiente: ln(empleo agrícola)") ///
    mtitles("SARIMA base" "SARIMA + controles" "SARIMA completo") ///
    label b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N aic bic ll, labels("Observaciones" "AIC" "BIC" "Log-likelihood") ///
          fmt(%9.0f %9.2f %9.2f %9.2f)) ///
    note("Errores estándar entre paréntesis. *** p<0.01 ** p<0.05 * p<0.10") ///
    nogaps compress

esttab sarima_base sarima_controles sarima_completo ///
    using "${tables}\Coeficientes_SARIMA.xlsx", replace ///
    title("Comparación SARIMA") ///
    mtitles("SARIMA base" "SARIMA + controles" "SARIMA completo") ///
    label b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N aic bic ll, labels("Obs." "AIC" "BIC" "Log-likelihood") ///
          fmt(%9.0f %9.2f %9.2f %9.2f)) ///
    note("Errores estándar entre paréntesis. *** p<0.01 ** p<0.05 * p<0.10") ///
    nogaps compress
di "Tabla Excel de coeficientes exportada."

esttab sarima_base sarima_controles sarima_completo ///
    using "${tables}\Coeficientes_SARIMA.tex", replace ///
    title("Comparación SARIMA --- Variable dependiente: $\ln$(empleo agr\'{i}cola)") ///
    mtitles("SARIMA base" "SARIMA + controles" "SARIMA completo") ///
    label b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N aic bic ll, labels("Observaciones" "AIC" "BIC" "Log-likelihood") ///
          fmt(%9.0f %9.2f %9.2f %9.2f)) ///
    note("Errores estandar entre parentesis. *** p<0.01 ** p<0.05 * p<0.10") ///
    nogaps compress booktabs alignment(D{.}{.}{-1}) fragment
di "Tabla LaTeX de coeficientes exportada."

*===========================================================================
**# 15. GUARDAR BASE FINAL (project_forecasts.dta)
*===========================================================================

/*
  La base guardada incluye:
    · Series originales en niveles y logaritmos
    · Indicadores train/test
    · Pronósticos en ln (yhat_*_ln) y B-O corregidos (yhat_*_BO)
    · Errores y métricas en nivel para los 5 modelos
  
  Esta base es el input directo del Script 02 (VAR/VECM, OCMT, Ensemble).
*/

save "${clean}\project_forecasts.dta", replace
di _newline "Base project_forecasts.dta guardada."
di "====== SCRIPT 01 COMPLETADO ======"
