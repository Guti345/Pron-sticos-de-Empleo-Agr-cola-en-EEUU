/*===========================================================================
  PROYECTO FINAL: Pronósticos Prácticos — Series de Tiempo
  Título:  Capital físico y empleo agrícola en EE.UU.
  Autor:   Antonio Gutiérrez Arango
  Fecha:   Abril 2026
  Desc.:   Evaluación del poder predictivo de cinco modelos de pronóstico
           para el empleo agrícola, con y sin capital físico como regresor.
===========================================================================*/

clear all
set more off

*===========================================================================
**# 0. ESTRUCTURA DEL PROYECTO
*===========================================================================

cd "C:\Users\anton\OneDrive\Documentos\GitHub\Pronósticos de Empleo Agrícola en EEUU\Scripts"

* Definir rutas globales
global main    "C:\Users\anton\OneDrive\Documentos\GitHub\Pronósticos de Empleo Agrícola en EEUU"
global graphs  "${main}\Outputs\Graphs"
global tables  "${main}\Outputs\Tables"
global raw     "${main}\Data\Raw"
global clean   "${main}\Data\Clean"

*===========================================================================
**# 1. IMPORTACIÓN Y PREPARACIÓN DE DATOS
*===========================================================================

* Importar series desde FRED en frecuencia mensual (2000m1 – 2025m9)
import fred LNU02034560 A33ATI WPU01 FEDMINFRMWG, ///
    daterange(2000-01-01 2025-09-30) aggregate(monthly) nosummary clear

* Guardar datos crudos
export excel "${raw}\FRED_data.xlsx", replace firstrow(varlabels)
save "${raw}\FRED_Data.dta", replace

* Renombrar variables para mayor claridad
rename LNU02034560 emp_agr
rename A33ATI       inv_manuf
rename WPU01        ppi_farm
rename FEDMINFRMWG  salario_min

* Declarar como serie de tiempo mensual
gen date = mofd(daten)
format date %tm
tsset date, monthly
order datestr daten date

* Transformar a logaritmos para linealizar y estabilizar varianza
foreach var in emp_agr inv_manuf ppi_farm salario_min {
    gen ln_`var' = ln(`var')
}

* Guardar datos limpios
save "${clean}\project_clean_data.dta", replace

* Estadísticas descriptivas
summarize emp_agr inv_manuf ppi_farm salario_min
summarize ln_emp_agr ln_inv_manuf ln_ppi_farm ln_salario_min

*===========================================================================
**# 2. ANÁLISIS EXPLORATORIO
*===========================================================================

*---------------------------------------------------------------------------
* 2.1 Series de tiempo — gráfico combinado 2×2
*---------------------------------------------------------------------------

* Las líneas verticales marcan la crisis financiera de 2008 y el COVID-19.

* Panel 1: Empleo agrícola
tsline emp_agr, ///
    lcolor(blue) ///
    tline(2008m9, lcolor(green) lpattern(dash)) ///
    tline(2020m3, lcolor(orange) lpattern(dash)) ///
    title("Empleo agrícola", size(small)) ///
    ytitle("Miles de personas", size(vsmall)) xtitle("") ///
    ylabel(, labsize(vsmall) angle(0)) ///
    xlabel(, labsize(vsmall) angle(45)) ///
    graphregion(color(white)) plotregion(margin(small)) ///
    scheme(s2color) ///
    name(g_emp, replace)

graph export "${graphs}\Employment_ts.png", replace

* Panel 2: Inventarios de maquinaria agrícola (proxy de capital físico)
tsline inv_manuf, ///
    lcolor(red) ///
    tline(2008m9, lcolor(green) lpattern(dash)) ///
    tline(2020m3, lcolor(orange) lpattern(dash)) ///
    title("Capital físico agrícola", size(small)) ///
    ytitle("Millones USD", size(vsmall)) xtitle("") ///
    ylabel(, labsize(vsmall) angle(0)) ///
    xlabel(, labsize(vsmall) angle(45)) ///
    graphregion(color(white)) plotregion(margin(small)) ///
    scheme(s2color) ///
    name(g_inv, replace)

graph export "${graphs}\Inventories_ts.png", replace

* Panel 3: Índice de precios al productor agrícola
tsline ppi_farm, ///
    lcolor(emerald) ///
    tline(2008m9, lcolor(green) lpattern(dash)) ///
    tline(2020m3, lcolor(orange) lpattern(dash)) ///
    title("PPI — productos agrícolas", size(small)) ///
    ytitle("Índice (1982=100)", size(vsmall)) xtitle("") ///
    ylabel(, labsize(vsmall) angle(0)) ///
    xlabel(, labsize(vsmall) angle(45)) ///
    graphregion(color(white)) plotregion(margin(small)) ///
    scheme(s2color) ///
    name(g_ppi, replace)

graph export "${graphs}\PPI_Farm_ts.png", replace

* Panel 4: Salario mínimo federal agrícola
twoway (tsline salario_min, lcolor(purple)), ///
    tline(2008m9, lcolor(green) lpattern(dash)) ///
    tline(2020m3, lcolor(orange) lpattern(dash)) ///
    title("Salario mínimo agrícola", size(small)) ///
    ytitle("USD por hora", size(vsmall)) xtitle("") ///
    ylabel(, labsize(vsmall) angle(0)) ///
    xlabel(, labsize(vsmall) angle(45)) ///
    graphregion(color(white)) plotregion(margin(small)) ///
    scheme(s2color) ///
    name(g_sal, replace)

graph export "${graphs}\Salario_Min_ts.png", replace

* Combinar los cuatro paneles en una sola figura
graph combine g_emp g_inv g_ppi g_sal, ///
    cols(2) rows(2) ///
    title("Series de tiempo — variables del modelo", size(medsmall)) ///
    note("Nota: línea verde = crisis financiera 2008; línea naranja = inicio COVID-19", ///
         size(vsmall)) ///
    graphregion(color(white)) ///
    ysize(7) xsize(10)

graph export "${graphs}\Series_Combinadas.png", replace width(1800)

*---------------------------------------------------------------------------
* 2.2 Co-movimiento entre empleo e inventarios
*---------------------------------------------------------------------------

* Eje dual para comparar visualmente empleo agrícola e inventarios
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
* 2.3 Variables en logaritmos — co-movimiento conjunto
*---------------------------------------------------------------------------

twoway ///
    (tsline ln_emp_agr,     yaxis(1) lcolor(blue)       lwidth(medthin)) ///
    (tsline ln_inv_manuf,   yaxis(1) lcolor(cranberry)  lwidth(medthin)) ///
    (tsline ln_ppi_farm,    yaxis(1) lcolor(emerald%45) lwidth(thin)) ///
    (tsline ln_salario_min, yaxis(1) lcolor(purple%45)  lwidth(thin)), ///
    title("Variables en logaritmos", size(medsmall)) ///
    ytitle("Escala logarítmica", axis(1) size(small)) ///
    xtitle("Fecha", size(small)) ///
    xlabel(, angle(45) labsize(small)) ///
    ylabel(, axis(1) labsize(small) angle(0)) ///
    legend(order(1 "ln empleo" 2 "ln inventarios" ///
                 3 "ln PPI agr." 4 "ln salario mín.") ///
           position(6) rows(2) size(small) region(lstyle(none))) ///
    tline(2008m9, lcolor(green) lpattern(dash)) ///
    tline(2020m3, lcolor(orange) lpattern(dash)) ///
    note("Nota: verde = crisis 2008; naranja = COVID-19. Controles en menor opacidad.", ///
         size(vsmall)) ///
    graphregion(color(white)) plotregion(margin(medsmall)) scheme(s2color)

graph export "${graphs}\Log_Variables_ts.png", replace

*---------------------------------------------------------------------------
* 2.4 Descomposición del empleo agrícola (tendencia + estacionalidad)
*---------------------------------------------------------------------------

* Tendencia mediante media móvil centrada de 12 términos
tssmooth ma tendencia = emp_agr, window(12)

* Componente estacional bruto: desviación de la serie respecto a la tendencia
gen est_bruto = emp_agr - tendencia

* Variables auxiliares de mes y año para calcular el patrón estacional
gen mes  = month(dofm(date))
gen anio = year(dofm(date))

* Patrón estacional promedio por mes
bysort mes: egen patron_estacional = mean(est_bruto)

* Componente residual: lo que queda tras remover tendencia y estacionalidad
gen residuo = emp_agr - tendencia - patron_estacional

* Verificar que los factores estacionales suman aproximadamente cero
tabstat patron_estacional, by(mes) stats(mean)

* Serie original con tendencia superpuesta
twoway ///
    (tsline emp_agr,   lcolor(blue%50) lwidth(thin)) ///
    (tsline tendencia, lcolor(red)     lwidth(medthick)), ///
    title("Empleo agrícola: serie y tendencia", size(medsmall)) ///
    ytitle("Miles de personas", size(small)) ///
    xtitle("Fecha", size(small)) ///
    legend(order(1 "Serie original" 2 "Tendencia (MM 12)") ///
           position(6) rows(1) size(small) region(lstyle(none))) ///
    yline(0) graphregion(color(white)) scheme(s2color)

graph export "${graphs}\Tendencia_ts.png", replace

* Patrón estacional mensual (barras por mes)
preserve
    collapse (mean) patron_estacional, by(mes)

    twoway ///
        (bar  patron_estacional mes, barwidth(0.7) color(blue%70)) ///
        (line patron_estacional mes, lcolor(red) lwidth(thin)), ///
        title("Patrón estacional mensual — empleo agrícola", size(medsmall)) ///
        ytitle("Desviación respecto a tendencia (miles)", size(small)) ///
        xtitle("Mes", size(small)) ///
        xlabel(1 "Ene" 2 "Feb" 3 "Mar" 4 "Abr" 5 "May" ///
               6 "Jun" 7 "Jul" 8 "Ago" 9 "Sep" 10 "Oct" ///
               11 "Nov" 12 "Dic", labsize(small)) ///
        yline(0, lcolor(black) lwidth(thin)) ///
        graphregion(color(white)) scheme(s2color)

    graph export "${graphs}\Patron_Estacional.png", replace
restore

*---------------------------------------------------------------------------
* 2.5 Definición de la muestra: entrenamiento y evaluación
*---------------------------------------------------------------------------

* Train: 2000m1 – 2022m9 | Test: 2022m10 – 2025m9
gen train = (date <= tm(2022m9))
gen test  = (date >  tm(2022m9))

tab test

*===========================================================================
**# 3. PRUEBAS DE RAÍZ UNITARIA (ADF)
*===========================================================================

/*
  Se aplica la prueba ADF con tendencia en tres formas para cada variable:
  niveles, primera diferencia regular y primera diferencia estacional.
  H0: la serie tiene raíz unitaria. Rechazar H0 → estacionaria.
*/

*---------------------------------------------------------------------------
* 3.1 Capturar estadísticos ADF
*---------------------------------------------------------------------------

* ln_emp_agr
dfuller ln_emp_agr, lags(12) trend
scalar adf_emp_niv  = r(Zt)
scalar adfp_emp_niv = r(p)

dfuller D.ln_emp_agr, lags(12) trend
scalar adf_emp_d1  = r(Zt)
scalar adfp_emp_d1 = r(p)

dfuller DS12.ln_emp_agr, lags(12) trend
scalar adf_emp_ds  = r(Zt)
scalar adfp_emp_ds = r(p)

* ln_inv_manuf
dfuller ln_inv_manuf, lags(12) trend
scalar adf_inv_niv  = r(Zt)
scalar adfp_inv_niv = r(p)

dfuller D.ln_inv_manuf, lags(12) trend
scalar adf_inv_d1  = r(Zt)
scalar adfp_inv_d1 = r(p)

dfuller DS12.ln_inv_manuf, lags(12) trend
scalar adf_inv_ds  = r(Zt)
scalar adfp_inv_ds = r(p)

* ln_ppi_farm
dfuller ln_ppi_farm, lags(12) trend
scalar adf_ppi_niv  = r(Zt)
scalar adfp_ppi_niv = r(p)

dfuller D.ln_ppi_farm, lags(12) trend
scalar adf_ppi_d1  = r(Zt)
scalar adfp_ppi_d1 = r(p)

dfuller DS12.ln_ppi_farm, lags(12) trend
scalar adf_ppi_ds  = r(Zt)
scalar adfp_ppi_ds = r(p)

* ln_salario_min
dfuller ln_salario_min, lags(12) trend
scalar adf_sal_niv  = r(Zt)
scalar adfp_sal_niv = r(p)

dfuller D.ln_salario_min, lags(12) trend
scalar adf_sal_d1  = r(Zt)
scalar adfp_sal_d1 = r(p)

dfuller DS12.ln_salario_min, lags(12) trend
scalar adf_sal_ds  = r(Zt)
scalar adfp_sal_ds = r(p)

*---------------------------------------------------------------------------
* 3.2 Etiquetas de significancia
*---------------------------------------------------------------------------

foreach v in emp inv ppi sal {
    foreach s in niv d1 ds {
        local p = scalar(adfp_`v'_`s')
        if      `p' < 0.01  local sig_`v'_`s' "***"
        else if `p' < 0.05  local sig_`v'_`s' "**"
        else if `p' < 0.10  local sig_`v'_`s' "*"
        else                 local sig_`v'_`s' ""
    }
}

*---------------------------------------------------------------------------
* 3.3 Tabla en consola
*---------------------------------------------------------------------------

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
       "    " %7.3f scalar(adf_`v'_d1)  "`sig_`v'_d1'"  "  " %6.4f scalar(adfp_`v'_d1)  ///
       "    " %7.3f scalar(adf_`v'_ds)  "`sig_`v'_ds'"  "  " %6.4f scalar(adfp_`v'_ds)
}

di "──────────────────────────────────────────────────────────────────────────────"
di "  VC con tendencia: 1% = -3.99   5% = -3.43   10% = -3.13"
di "  *** p<0.01  ** p<0.05  * p<0.10. H0: raíz unitaria."
di "══════════════════════════════════════════════════════════════════════════════"

*---------------------------------------------------------------------------
* 3.4 Exportar tabla ADF a Excel
*---------------------------------------------------------------------------

foreach v in emp inv ppi sal {
    foreach s in niv d1 ds {
        local x_`v'_`s'  = scalar(adf_`v'_`s')
        local xp_`v'_`s' = scalar(adfp_`v'_`s')
    }
}

putexcel set "${tables}\UnitRoot_ADF.xlsx", replace sheet("ADF")

putexcel A1 = "Pruebas ADF — Orden de integración de las variables"
putexcel A2 = "Variable"
putexcel B2 = "Niveles — Estadístico"   
putexcel C2 = "Niveles — p-valor"
putexcel D2 = "Niveles — Decisión"
putexcel E2 = "Δ regular — Estadístico" 
putexcel F2 = "Δ regular — p-valor"
putexcel G2 = "Δ regular — Decisión"
putexcel H2 = "Δ estacional — Estadístico" 
putexcel I2 = "Δ estacional — p-valor"
putexcel J2 = "Conclusión"

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
putexcel A`nf2' = "*** p<0.01  ** p<0.05  * p<0.10. H0: la serie tiene raíz unitaria."

di "Tabla ADF exportada a: ${tables}\UnitRoot_ADF.xlsx"

*===========================================================================
**# 4. IDENTIFICACIÓN SARIMA — ACF / PACF Y SELECCIÓN DE ÓRDENES
*===========================================================================

*---------------------------------------------------------------------------
* 4.1 ACF y PACF para identificar órdenes p, q, P, Q
*---------------------------------------------------------------------------

* Generar diferencias para los correlogramas
gen d_ln_emp    = D.ln_emp_agr
gen ds_d_ln_emp = DS12.d_ln_emp

label var d_ln_emp    "Δ ln(empleo agrícola)"
label var ds_d_ln_emp "Δ ΔS12 ln(empleo agrícola)"

* ACF y PACF — primera diferencia regular (d=1)
ac d_ln_emp, lags(36) title("ACF — Δ ln(empleo)", size(small)) ///
    ytitle("") graphregion(color(white)) name(g1, replace) 
graph export "${graphs}\ACF_d1.png", replace

pac d_ln_emp, lags(36) title("PACF — Δ ln(empleo)", size(small)) ///
    ytitle("") graphregion(color(white)) name(g2, replace) 
graph export "${graphs}\PACF_d1.png", replace

* ACF y PACF — doble diferencia (d=1, D=1): serie estacionaria
ac ds_d_ln_emp, lags(36) title("ACF — Δ ΔS12 ln(empleo)", size(small)) ///
    ytitle("") graphregion(color(white)) name(g3, replace) 
graph export "${graphs}\ACF_d1D1.png", replace

pac ds_d_ln_emp, lags(36) title("PACF — Δ ΔS12 ln(empleo)", size(small)) ///
    ytitle("") graphregion(color(white)) name(g4, replace) 
graph export "${graphs}\PACF_d1D1.png", replace

* Combinar los cuatro correlogramas en una sola figura
graph combine g1 g2 g3 g4, ///
    cols(2) rows(2) ///
    title("Funciones de autocorrelación — identificación SARIMA", size(medsmall)) ///
    graphregion(color(white)) ysize(6) xsize(8)

graph export "${graphs}\ACF_PACF_combinado.png", replace width(1600)

*---------------------------------------------------------------------------
* 4.2 Selección de órdenes por AIC/BIC — grid search
*---------------------------------------------------------------------------

* Evaluar todas las combinaciones p,q ∈ {0,1,2} y P,Q ∈ {0,1} con d=1, D=1
matrix IC  = J(1, 6, .)
local row  = 0

qui foreach p in 0 1 2 {
  foreach q in 0 1 2 {
    foreach P in 0 1 {
      foreach Q in 0 1 {
        capture arima ln_emp_agr if train==1, ///
            arima(`p',1,`q') sarima(`P',1,`Q',12) nolog
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

* Eliminar primera fila de missing y nombrar columnas
matrix IC = IC[2..rowsof(IC), 1..6]
matrix colnames IC = p q P Q AIC BIC

* Ordenar de menor a mayor AIC con Mata
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

di _newline "══════════════════════════════════════════"
di "  MODELO CON MENOR AIC"
di "══════════════════════════════════════════"
di "  p = " IC_sorted[1,1] "  q = " IC_sorted[1,2]
di "  P = " IC_sorted[1,3] "  Q = " IC_sorted[1,4]
di "  AIC = " %8.4f minAIC "  BIC = " %8.4f minBIC
di "══════════════════════════════════════════"

* Órdenes finales: SARIMA(1,1,1)(1,1,1)12 por parsimonia (BIC favorece este modelo)
local p_opt = 1
local q_opt = 1
local P_opt = 1
local Q_opt = 1

*===========================================================================
**# 5. MODELO 1 — NAÏVE ESTACIONAL
*===========================================================================

* El pronóstico naïve asigna el valor del mismo mes del año anterior
gen yhat_naive = L12.emp_agr
label var yhat_naive "Pronóstico naïve estacional (L12)"

twoway ///
    (tsline emp_agr    if test==1, lcolor(blue) lwidth(medthin)) ///
    (tsline yhat_naive if test==1, lcolor(red)  lwidth(medthin) lpattern(dash)), ///
    title("Naïve estacional — período test", size(medsmall)) ///
    ytitle("Miles de personas", size(small)) xtitle("") ///
    legend(order(1 "Observado" 2 "Naïve S12") position(6) rows(1) size(small)) ///
    graphregion(color(white))

graph export "${graphs}\Forecast_Naive.png", replace

*===========================================================================
**# 6. MODELO 2 — HOLT-WINTERS (MULTIPLICATIVO VÍA LOGARITMOS)
*===========================================================================

/*
  tssmooth shwinters implementa el modelo aditivo sobre logaritmos,
  equivalente al modelo multiplicativo en niveles. Los parámetros
  alpha (nivel), beta (tendencia) y gamma (estacionalidad) se optimizan
  automáticamente minimizando el SSE sobre la muestra de entrenamiento.
  forecast(36) proyecta el período de evaluación completo.
*/

tssmooth shwinters yhat_hw_ln = ln_emp_agr, forecast(36)

* Revertir logaritmo para obtener el pronóstico en niveles originales
gen yhat_hw = exp(yhat_hw_ln)
label var yhat_hw_ln "HW — pronóstico en ln"
label var yhat_hw    "HW — pronóstico en niveles (miles personas)"

* Verificar que el forecast alcanzó todo el período test
count if missing(yhat_hw) & test==1

twoway ///
    (tsline emp_agr if test==1, lcolor(blue)   lwidth(medthin)) ///
    (tsline yhat_hw if test==1, lcolor(orange) lwidth(medthin) lpattern(dash)), ///
    title("Holt-Winters — período test", size(medsmall)) ///
    ytitle("Miles de personas", size(small)) xtitle("") ///
    legend(order(1 "Observado" 2 "Holt-Winters") position(6) rows(1) size(small)) ///
    graphregion(color(white))

graph export "${graphs}\Forecast_HW.png", replace

*===========================================================================
**# 7. MODELO 3 — SARIMA BASE (SIN REGRESORES)
*===========================================================================

* SARIMA(1,1,1)(1,1,1)12 estimado solo sobre ln_emp_agr en el período train
arima ln_emp_agr if train==1, ///
    arima(`p_opt',1,`q_opt') sarima(`P_opt',1,`Q_opt',12) nolog

estat ic
estimates store sarima_base
scalar N_train = e(N)

* Pronóstico sobre la muestra completa (fitted en train + forecast en test)
predict yhat_sarima_base_ln, y
gen yhat_sarima_base = exp(yhat_sarima_base_ln)
label var yhat_sarima_base "SARIMA base — pronóstico"

twoway ///
    (tsline emp_agr          if test==1, lcolor(blue)  lwidth(medthin)) ///
    (tsline yhat_sarima_base if test==1, lcolor(green) lwidth(medthin) lpattern(dash)), ///
    title("SARIMA base — período test", size(medsmall)) ///
    ytitle("Miles de personas", size(small)) xtitle("") ///
    legend(order(1 "Observado" 2 "SARIMA base") position(6) rows(1) size(small)) ///
    graphregion(color(white))

graph export "${graphs}\Forecast_SARIMA_base.png", replace

*===========================================================================
**# 8. MODELO 4 — SARIMA CON CONTROLES (SIN CAPITAL FÍSICO)
*===========================================================================

* Se incorporan PPI agrícola y salario mínimo como regresores exógenos
arima ln_emp_agr ln_ppi_farm ln_salario_min if train==1, ///
    arima(`p_opt',1,`q_opt') sarima(`P_opt',1,`Q_opt',12) nolog

estat ic
estimates store sarima_controles

predict yhat_sarima_ctrl_ln, y
gen yhat_sarima_ctrl = exp(yhat_sarima_ctrl_ln)
label var yhat_sarima_ctrl "SARIMA + controles — pronóstico"

twoway ///
    (tsline emp_agr          if test==1, lcolor(blue)   lwidth(medthin)) ///
    (tsline yhat_sarima_ctrl if test==1, lcolor(purple) lwidth(medthin) lpattern(dash)), ///
    title("SARIMA + controles — período test", size(medsmall)) ///
    ytitle("Miles de personas", size(small)) xtitle("") ///
    legend(order(1 "Observado" 2 "SARIMA + controles") position(6) rows(1) size(small)) ///
    graphregion(color(white))

graph export "${graphs}\Forecast_SARIMA_ctrl.png", replace

*===========================================================================
**# 9. MODELO 5 — SARIMA COMPLETO (CON CAPITAL FÍSICO)
*===========================================================================

/*
  Se agrega el inventario de maquinaria agrícola y dos rezagos para
  capturar el efecto diferido de la acumulación de capital sobre el empleo.
*/

gen L1_ln_inv = L1.ln_inv_manuf
gen L2_ln_inv = L2.ln_inv_manuf
label var L1_ln_inv "ln inventarios (rezago 1)"
label var L2_ln_inv "ln inventarios (rezago 2)"

arima ln_emp_agr ln_ppi_farm ln_salario_min ln_inv_manuf L1_ln_inv L2_ln_inv ///
    if train==1, ///
    arima(`p_opt',1,`q_opt') sarima(`P_opt',1,`Q_opt',12) nolog

estat ic
estimates store sarima_completo

predict yhat_sarima_comp_ln, y
gen yhat_sarima_comp = exp(yhat_sarima_comp_ln)
label var yhat_sarima_comp "SARIMA completo — pronóstico"

twoway ///
    (tsline emp_agr          if test==1, lcolor(blue)      lwidth(medthin)) ///
    (tsline yhat_sarima_comp if test==1, lcolor(cranberry) lwidth(medthin) lpattern(dash)), ///
    title("SARIMA completo — período test", size(medsmall)) ///
    ytitle("Miles de personas", size(small)) xtitle("") ///
    legend(order(1 "Observado" 2 "SARIMA + capital físico") position(6) rows(1) size(small)) ///
    graphregion(color(white))

graph export "${graphs}\Forecast_SARIMA_comp.png", replace

* Gráfico comparativo de todos los modelos en el período test
twoway ///
    (tsline emp_agr if test==1, lcolor(black) lwidth(medthick)) ///
    (tsline yhat_naive if test==1, lcolor(gray) lwidth(thin) lpattern(dash)) ///
    (tsline yhat_hw if test==1, lcolor(orange) lwidth(thin) lpattern(dash)) ///
    (tsline yhat_sarima_base if test==1, lcolor(green) lwidth(thin) lpattern(dash)) ///
    (tsline yhat_sarima_ctrl if test==1, lcolor(purple) lwidth(thin) lpattern(dash)) ///
    (tsline yhat_sarima_comp if test==1, lcolor(cranberry) lwidth(thin) lpattern(dash)), ///
    title("Comparación de pronósticos — período test", size(medsmall)) ///
    ytitle("Miles de personas", size(small)) xtitle("") ///
    legend(order(1 "Observado" 2 "Naïve" 3 "Holt-Winters" ///
                 4 "SARIMA base" 5 "SARIMA + ctrl" 6 "SARIMA completo") ///
           position(6) rows(2) size(small)) ///
    graphregion(color(white))

graph export "${graphs}\Forecast_Comparativo.png", replace

*===========================================================================
**# 10. MÉTRICAS DE EVALUACIÓN — RMSE, MAPE Y THEIL U
*===========================================================================

* Todas las métricas se calculan sobre el período test en niveles originales

* Errores de pronóstico por modelo
gen e_naive = emp_agr - yhat_naive       if test==1
gen e_hw    = emp_agr - yhat_hw          if test==1
gen e_base  = emp_agr - yhat_sarima_base if test==1
gen e_ctrl  = emp_agr - yhat_sarima_ctrl if test==1
gen e_comp  = emp_agr - yhat_sarima_comp if test==1

* Errores al cuadrado y errores porcentuales absolutos
foreach m in naive hw base ctrl comp {
    gen e2_`m'  = e_`m'^2
    gen ape_`m' = abs(e_`m' / emp_agr) * 100 if test==1
}

* RMSE y MAPE
foreach m in naive hw base ctrl comp {
    qui summarize e2_`m'  if test==1
    scalar RMSE_`m' = sqrt(r(mean))
    qui summarize ape_`m' if test==1
    scalar MAPE_`m' = r(mean)
}

* Theil U: RMSE del modelo relativo al RMSE del naïve
foreach m in hw base ctrl comp {
    scalar U_`m' = RMSE_`m' / RMSE_naive
}

* Tabla en consola
di _newline(2)
di "==========================================================="
di "          MÉTRICAS DE EVALUACIÓN — PERÍODO TEST"
di "==========================================================="
di "  Modelo              RMSE       MAPE (%)    Theil U"
di "-----------------------------------------------------------"
di "  Naïve           " %8.3f RMSE_naive "   " %8.3f MAPE_naive "     (1.000)"
di "  Holt-Winters    " %8.3f RMSE_hw    "   " %8.3f MAPE_hw    "   " %8.3f U_hw
di "  SARIMA base     " %8.3f RMSE_base  "   " %8.3f MAPE_base  "   " %8.3f U_base
di "  SARIMA+ctrl     " %8.3f RMSE_ctrl  "   " %8.3f MAPE_ctrl  "   " %8.3f U_ctrl
di "  SARIMA completo " %8.3f RMSE_comp  "   " %8.3f MAPE_comp  "   " %8.3f U_comp
di "==========================================================="

* Exportar a Excel
putexcel set "${tables}\Metricas_Modelos.xlsx", replace sheet("Metricas")

putexcel A1 = "Modelo" 
putexcel B1 = "RMSE"
putexcel C1 = "MAPE (%)" 
putexcel D1 = "Theil U"

putexcel A2 = "Naïve"            
putexcel A3 = "Holt-Winters"
putexcel A4 = "SARIMA base"       
putexcel A5 = "SARIMA + controles"
putexcel A6 = "SARIMA completo"

foreach m in naive hw base ctrl comp {
    local r = cond("`m'"=="naive",2, cond("`m'"=="hw",3, cond("`m'"=="base",4, cond("`m'"=="ctrl",5,6))))
    local rmse_v = scalar(RMSE_`m')
    local mape_v = scalar(MAPE_`m')
    putexcel B`r' = `rmse_v'
    putexcel C`r' = `mape_v'
}

putexcel D2 = 1
foreach m in hw base ctrl comp {
    local r = cond("`m'"=="hw",3, cond("`m'"=="base",4, cond("`m'"=="ctrl",5,6)))
    local u_v = scalar(U_`m')
    putexcel D`r' = `u_v'
}

di "Tabla de métricas exportada a: ${tables}\Metricas_Modelos.xlsx"

*===========================================================================
**# 11. TEST DE DIEBOLD-MARIANO
*===========================================================================

/*
  Compara la precisión de pares de modelos mediante la regresión de la
  diferencia de pérdidas cuadráticas d_t = e1t² - e2t² sobre una constante
  con errores Newey-West (HAC). Un estadístico negativo y significativo
  indica que el modelo 1 genera menores errores que el modelo 2.

  Comparaciones:
    A) SARIMA base vs SARIMA + controles
    B) SARIMA base vs SARIMA completo         ← comparación principal
    C) SARIMA + controles vs SARIMA completo
*/

qui count if test==1
local T_test   = r(N)
local lags_hac = floor(`T_test'^(1/3))

di _newline "Observaciones test: `T_test'   Lags HAC: `lags_hac'"

* Diferencias de pérdida cuadrática
gen dm_A = e2_base - e2_ctrl
gen dm_B = e2_base - e2_comp
gen dm_C = e2_ctrl - e2_comp

label var dm_A "DM: base vs +controles"
label var dm_B "DM: base vs completo"
label var dm_C "DM: +controles vs completo"

* Correr tests y capturar estadísticos
foreach c in A B C {
    qui summarize dm_`c' if test==1
    scalar dm_`c'_mean = r(mean)

    newey dm_`c' if test==1, lag(`lags_hac')
    scalar dm_`c'_stat = _b[_cons] / _se[_cons]
    scalar dm_`c'_se   = _se[_cons]

    test _cons
    scalar dm_`c'_pval = r(p)
}

* Etiquetas de significancia y conclusión
foreach c in A B C {
    local p = scalar(dm_`c'_pval)
    local m = scalar(dm_`c'_mean)

    if      `p' < 0.01              local sig_`c'   "***"
    else if `p' < 0.05              local sig_`c'   "**"
    else if `p' < 0.10              local sig_`c'   "*"
    else                             local sig_`c'   ""

    if      `p' < 0.05 & `m' > 0   local concl_`c' "Modelo 2 mejor"
    else if `p' < 0.05 & `m' < 0   local concl_`c' "Modelo 1 mejor"
    else                             local concl_`c' "Sin diferencia sig."
}

* Tabla en consola
di _newline(2)
di "═══════════════════════════════════════════════════════════════════════"
di "                   TEST DE DIEBOLD-MARIANO"
di "═══════════════════════════════════════════════════════════════════════"
di "  Comp.   Media d_t    DM stat    p-valor    Conclusión"
di "───────────────────────────────────────────────────────────────────────"
foreach c in A B C {
    di "  `c'    " %9.2f scalar(dm_`c'_mean) "   " ///
       %7.3f scalar(dm_`c'_stat) "`sig_`c'" "   " ///
       %7.4f scalar(dm_`c'_pval) "   `concl_`c''"
}
di "───────────────────────────────────────────────────────────────────────"
di "  Lags Newey-West: `lags_hac' | Obs. test: `T_test'"
di "  d_t = MSE(modelo 1) - MSE(modelo 2)"
di "  *** p<0.01  ** p<0.05  * p<0.10"
di "═══════════════════════════════════════════════════════════════════════"

* Exportar a Excel
foreach c in A B C {
    local mean_`c' = scalar(dm_`c'_mean)
    local stat_`c' = scalar(dm_`c'_stat)
    local pval_`c' = scalar(dm_`c'_pval)
}

putexcel set "${tables}\DieboldMariano.xlsx", replace sheet("DM_Test")

putexcel A1 = "Test de Diebold-Mariano — Comparación de poder predictivo"
putexcel A2 = "Comp."
putexcel B2 = "Modelo 1"
putexcel C2 = "Modelo 2"
putexcel D2 = "Media d_t"
putexcel E2 = "Estadístico DM"
putexcel F2 = "p-valor"
putexcel G2 = "Significancia"
putexcel H2 = "Conclusión"

putexcel A3 = "A" 
putexcel B3 = "SARIMA base"
putexcel C3 = "SARIMA + controles"
putexcel D3 = `mean_A', nformat("0.0000")
putexcel E3 = `stat_A', nformat("0.000")
putexcel F3 = `pval_A', nformat("0.0000")
putexcel G3 = "`sig_A'"
putexcel H3 = "`concl_A'"

putexcel A4 = "B" 
putexcel B4 = "SARIMA base"
putexcel C4 = "SARIMA completo"
putexcel D4 = `mean_B', nformat("0.0000") 
putexcel E4 = `stat_B', nformat("0.000")
putexcel F4 = `pval_B', nformat("0.0000")
putexcel G4 = "`sig_B'"
putexcel H4 = "`concl_B'"

putexcel A5 = "C"
putexcel B5 = "SARIMA + controles"
putexcel C5 = "SARIMA completo"
putexcel D5 = `mean_C', nformat("0.0000")
putexcel E5 = `stat_C', nformat("0.000")
putexcel F5 = `pval_C', nformat("0.0000")
putexcel G5 = "`sig_C'"
putexcel H5 = "`concl_C'"

putexcel A7  = "Lags Newey-West: `lags_hac' | Obs. test: `T_test'"
putexcel A8  = "H0: igual precisión predictiva. d_t = MSE(modelo 1) - MSE(modelo 2)."
putexcel A9  = "*** p<0.01  ** p<0.05  * p<0.10"

di "Tabla Diebold-Mariano exportada a: ${tables}\DieboldMariano.xlsx"

*===========================================================================
**# 12. DIAGNÓSTICO DE RESIDUOS — SARIMA COMPLETO
*===========================================================================

* Recuperar residuos del modelo completo para validar la especificación
estimates restore sarima_completo
predict resid_comp, resid
label var resid_comp "Residuos SARIMA completo"

* Gráfico de residuos en el tiempo
tsline resid_comp, ///
    title("Residuos — SARIMA completo", size(medsmall)) ///
    yline(0, lcolor(red) lwidth(thin)) ///
    ytitle("Residuo", size(small)) xtitle("") ///
    graphregion(color(white))

graph export "${graphs}\Residuos_SARIMA_comp.png", replace

* ACF de residuos: verificar ausencia de autocorrelación
ac resid_comp, lags(36) ///
    title("ACF residuos — SARIMA completo") graphregion(color(white))

graph export "${graphs}\ACF_Residuos.png", replace

* Test de Ljung-Box: H0 = residuos son ruido blanco
wntestq resid_comp, lags(24)

*===========================================================================
**# 13. TABLA DE COEFICIENTES SARIMA — EXPORTACIÓN
*===========================================================================

* Verificar que los tres modelos están en memoria
estimates dir

* Tabla en consola
esttab sarima_base sarima_controles sarima_completo, ///
    title("Comparación SARIMA — Variable dependiente: ln(empleo agrícola)") ///
    mtitles("SARIMA base" "SARIMA + controles" "SARIMA completo") ///
    label b(3) se(3) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N aic bic ll, ///
          labels("Observaciones" "AIC" "BIC" "Log-likelihood") ///
          fmt(%9.0f %9.2f %9.2f %9.2f)) ///
    note("Errores estándar entre paréntesis. *** p<0.01 ** p<0.05 * p<0.10") ///
    nogaps compress

* Exportar a Excel
esttab sarima_base sarima_controles sarima_completo ///
    using "${tables}\Coeficientes_SARIMA.xlsx", replace ///
    title("Comparación SARIMA — Variable dependiente: ln(empleo agrícola)") ///
    mtitles("SARIMA base" "SARIMA + controles" "SARIMA completo") ///
    label b(3) se(3) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N aic bic ll, ///
          labels("Observaciones" "AIC" "BIC" "Log-likelihood") ///
          fmt(%9.0f %9.2f %9.2f %9.2f)) ///
    note("Errores estándar entre paréntesis. *** p<0.01 ** p<0.05 * p<0.10") ///
    nogaps compress

di "Tabla Excel exportada a: ${tables}\Coeficientes_SARIMA.xlsx"

* Exportar a LaTeX (fragment para usar con \input{} en Overleaf)
esttab sarima_base sarima_controles sarima_completo ///
    using "${tables}\Coeficientes_SARIMA.tex", replace ///
    title("Comparación SARIMA — Variable dependiente: ln(empleo agricola)") ///
    mtitles("SARIMA base" "SARIMA + controles" "SARIMA completo") ///
    label b(3) se(3) ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N aic bic ll, ///
          labels("Observaciones" "AIC" "BIC" "Log-likelihood") ///
          fmt(%9.0f %9.2f %9.2f %9.2f)) ///
    note("Errores estandar entre parentesis. *** p<0.01 ** p<0.05 * p<0.10") ///
    nogaps compress booktabs alignment(D{.}{.}{-1}) fragment

di "Tabla LaTeX exportada a: ${tables}\Coeficientes_SARIMA.tex"

*===========================================================================
**# 14. GUARDAR BASE FINAL
*===========================================================================

save "${clean}\project_forecasts.dta", replace
di "Base con pronósticos guardada en: ${clean}\project_forecasts.dta"

di _newline "====== SCRIPT COMPLETADO ======"
