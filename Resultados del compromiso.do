/*------------------------------------------------------------------------------

Proyecto: 								 Compromiso de Desempeño-Racionalización 
										 2020 
Autor: 									 Hugo Fernandez-Racionalización-UPP
Ultima fecha de modificación:			 05/03/2020
Outputs:								 Excel con los resultados del indicador
											
------------------------------------------------------------------------------*/

clear all
set more off, perm
set excelxlsxlargefile on
*ssc install blindschemes, replace all //Graficos formato R
*ssc install hashsort //Es para un sort rápido, estable y replicable
set scheme plottig 

*Set global
global work "D:\Proyectos\12. Seguimiento del compromiso por desempeño"
cd "$work\temp" 
global inputs "$work\Insumos"
global resultados "$work\Resultados"

*Set directories
cap mkdir "$work\temp"
cap mkdir "$resultados\Oficios-UPP"

/*----------------------------------------------------------------------------*/

*Programa para identificar a la plaza original en Nexus 
program plazaunica	
 	
		gen prior_tipo = 1
		replace prior_tipo = 2 if tiporegistro == "EVENTUAL"
		replace prior_tipo = 3 if tiporegistro == "PROYECTO"
		replace prior_tipo = 4 if tiporegistro == "CUADRO DE HORAS"
		replace prior_tipo = 5 if tiporegistro == "REEMPLAZO"
		
	 	gen prior_sitlab = 1
		replace prior_sitlab = 2 if sitlab == "F" | sitlab == "D" | sitlab == "E"  | sitlab == "T"
		replace prior_sitlab = 3 if sitlab == "C" | sitlab == "V"
		
		gen soplaza = !strpos(estplaza,"SG") & !strpos(estplaza,"CG") & !strpos(estplaza,"ABAND") //toma valor 1 si la plaza no tiene licencia sin goce, con goce o es una plaza abandonada 
		gen sestpla = estplaza == "ACTIV" //toma valor 1 si es activo
		gsort -jornlab, gen(sjornlb) //ordenamiento ascendente
		gen socupp = mi(numdocum) //toma valor 1 si tiene dni 
		
		*Priorización de plazas activas con personal
		
		duplicates tag descreg nombreooii codmod codplaza, g(dupli)
		
		bys descreg nombreooii codmod codplaza (prior_tipo - socupp): gen tipo_fin = _n  
       
		  label define tipo_fin 1"Plaza original" 2"Plaza espejo 1" 3"Plaza espejo 2" 4"Plaza espejo 3" 5"Plaza espejo 4"
		  label values tipo_fin tipo_fin		
		
	tab tipo_fin dupli
	keep if tipo_fin==1
	
end

*Programa para limpiar los oficios enviados por el equipo de Racionalizacion a DITEN
program define limpia_oficios
	
	*Reparo los problemas de importacion
	drop if mi(codplaza)
	replace codplaza="0"*(12-length(codplaza))+codplaza
	
	*Validacion del identificador: Una plaza solo puede tener un destino
	duplicates tag codplaza, gen(ducodplaza)
	
	*Validacion de los movimientos 	
	
		*Error en el Oficio 810-2019
		drop if codplaza == "25EV01907569" & cod_mod_destino == "1673011" 
		drop if ducodplaza==1 & strpos(rddereubicacion, "RDL")
		
		*Error en el Oficio 47-2020
		drop if ducodplaza==1 & strpos(rddereubicacion, "R.D. N")
		
	foreach x in origen destino {
		replace cod_mod_`x'=subinstr(cod_mod_`x'," ","",.)
		replace cod_mod_`x'="0"*(7-length(cod_mod_`x'))+cod_mod_`x'
		gen anexo_`x'="0"
		
		*Datos del padron
		preserve
			use "$inputs\Padron\Padron_2020", clear //20/02/2020
			g nivel="Inicial" if niv_mod== "A1" | niv_mod== "A2" | niv_mod== "A3"  | niv_mod== "A5"
			replace nivel="Primaria" if niv_mod== "B0"
			replace nivel="Secundaria" if niv_mod== "F0"
			
			keep cod_mod anexo cen_edu d_gestion nivel d_region d_dreugel d_estado
			ren * *_`x'
			tempfile padron`x'
			save `padron`x'', replace
		restore
		
		merge m:1 cod_mod_`x' anexo_`x' using `padron`x'', gen(escale_`x') keep(1 3)
	}
	
	hashsort cod_mod_origen codplaza cod_mod_destino

end

*Programa que pega la ejecutora a los oficios del equipo de Racionalizacion
program define nexuspliego

	*A) Ajustes para el fuzze merge
	
	ren (d_region_origen d_dreugel_origen) (d_dpto d_dreugel)
	
	replace d_dreugel="UGEL DATEM DEL MARAÑON" if d_dreugel=="UGEL ALTO AMAZONAS-SAN LORENZO" //Son la misma UGEL pero con diferentes nombres en ESCALE y NEXUS
	
	replace d_dreugel="UGEL OXAPAMPA" if d_dreugel=="UGEL PUERTO BERMUDEZ" //Aun no se oficializa la ejecutora y su personar sigue a cargo de la UGEL OXAPAMPA
	
	replace d_dreugel="UGEL NAZCA" if d_dreugel=="UGEL NASCA" //Ajuste para que crucen las padrones
	
	*B) Fuzzy merge
	
	collapse (rawsum) movimiento*, by(d_dpto d_dreugel)
	hashsort d_dpto d_dreugel
	g idm=_n
	reclink2 d_dpto d_dreugel using "$inputs\nexuspliego_limpio", idmaster(idm) idusing(idu) gen(prob_match) minscore(0.60) //Punto de corte establecido para que crucen todas las UGEL (se verifico de forma visual que el fuzzy merge sea correcto)
	
	*C) Estandarizacion de variables
	
	keep U* ejecutora secejec cod_pliego cod_ue cod_ugel movimiento*
	ren U* * 
	order d_dpto ejecutora d_dreugel 
	order movimiento*, last
	compress
	hashsort d_dpto d_dreugel

end 

*Programa que consolida todos los movimientos limpios 
program define merge_oficios

	*Movimientos 2019
	foreach oficio in 810 869 1014 998 {
		
		use "$resultados\Oficios-UPP\Oficio `oficio'-2019", clear
		g movimiento_oficio_`oficio' =1
		
		nexuspliego
		
		tempfile oficio`oficio'
		save `oficio`oficio'', replace
	}

	*Movimientos 2020
	foreach oficio in 47 89 143 {

		use "$resultados\Oficios-UPP\Oficio `oficio'-2020", clear 
		g movimiento_oficio_`oficio' =1
		
		nexuspliego
		
		tempfile oficio`oficio'
		save `oficio`oficio'', replace
	}

	use `oficio810', clear 
	foreach oficio in 869 1014 998 47 89 143 {
		di "----------------  Oficio `oficio' ----------------"
		merge 1:1 cod_ugel using `oficio`oficio'', nogen
	}
		
end

*Programa que construye las metas
program define resultado_meta 
	
	cap mvencode movimiento*, mv(0)
	egen total_movimientos=rowtotal(movimiento_oficio_810 - movimiento_oficio_143) 
	
	gen avance_meta=total_movimientos*100/meta if estado==0

	gen resultado=1==avance_meta>=80
	replace resultado=. if estado==1
	
	label define resultado 1 "Alcanzó la meta" 0 "No alcanzó la meta"
	label val resultado resultado
	
end 

/*----------------------------------------------------------------------------*/

							/*---------------------------
							|I) Limpieza y consolidación|
							---------------------------*/

*1.1) Oficio 810-2019 (11/11/2019)

import excel using "$inputs\Movimientos\Oficio8102019.xlsx", clear first sheet("BD") cellrange("A3:M203")
ren *, l
ren (codmod l) (cod_mod_origen cod_mod_destino) 
	
limpia_oficios
	
preserve
	use "$inputs\Nexus\nexus_45sira", clear // 04/11/2019
	plazaunica
	keep if real(codtipotrab)==10 & real(codsubtipt)==13 //Plazas docentes
	contract codplaza descargo
	tempfile nexus
	save `nexus', replace
restore

merge 1:m codplaza using `nexus', keepusing(descargo) keep(3) nogen

keep if !mi(cod_mod_origen) & !mi(cod_mod_destino) //Verifico que existan los servicios
keep if strpos(d_gestion_destino, "Pública")

save "$resultados\Oficios-UPP\Oficio 810-2019", replace

*1.2) Oficio 869-2019 (05/12/2019)

import excel using "$inputs\Movimientos\Oficio8692019.xlsx", clear first sheet("BD") cellrange("A3:K181")
ren *, l
ren (codmod j) (cod_mod_origen cod_mod_destino)

limpia_oficios

*Validacion de los movimientos 
preserve
	use "$inputs\Nexus\nexus_49sira", clear // 02/12/2019
	plazaunica
	keep if real(codtipotrab)==10 & real(codsubtipt)==13
	contract codplaza descargo
	tempfile nexus
	save `nexus', replace
restore

merge 1:m codplaza using `nexus', keepusing(descargo) keep(3) nogen

keep if !mi(cod_mod_origen) & !mi(cod_mod_destino)
keep if strpos(d_gestion_destino, "Pública") 

save "$resultados\Oficios-UPP\Oficio 869-2019", replace

*1.3) Oficios 1014-2019, 998-2019 y 47-2019  
foreach noficio in 1014 998 47 {

	*Oficio `noficio'-2019 (30/01/2020)

	import excel using "$inputs\Movimientos\Oficio472020-9982019 -10142019.xlsx", clear first sheet("ANEXO 2") cellrange("A3:Z561")
	ren *, l
	keep if strpos(oficio,"`noficio'")
	ren (codmod s) (cod_mod_origen cod_mod_destino)
	
	limpia_oficios
	
	preserve
		use "$inputs\Nexus\nexus_51sira", clear //19/12/2019
		plazaunica
		keep if real(codtipotrab)==10 & real(codsubtipt)==13
		contract codplaza descargo
		tempfile nexus
		save `nexus', replace
	restore

	merge 1:m codplaza using `nexus', keepusing(descargo) keep(3)
	
	keep if !mi(cod_mod_origen) & !mi(cod_mod_destino)
	keep if strpos(d_gestion_destino, "Pública") 

	save "$resultados\Oficios-UPP\Oficio `noficio'-2019", replace	
	
}

*Ajustes adicionales
cd "$resultados\Oficios-UPP"
shell !ren "Oficio 47-2019.dta" "Oficio 47-2020.dta"
cd "$work\temp" 

*1.4) Complementaria al Oficio9982019

import excel using "$inputs\Movimientos\Complementaria Oficio9982019.xlsx", clear first sheet("Sheet1") cellrange("A3:P229")
ren *, l
ren (codmod l) (cod_mod_origen cod_mod_destino) 

limpia_oficios

*Validacion de los movimientos 

preserve
	use "$inputs\Nexus\nexus_51sira", clear 
	plazaunica
	keep if real(codtipotrab)==10 & real(codsubtipt)==13
	contract codplaza descargo
	tempfile nexus
	save `nexus', replace
restore

merge 1:m codplaza using `nexus', keepusing(descargo) keep(3)

keep if !mi(cod_mod_origen) & !mi(cod_mod_destino)
keep if strpos(d_gestion_destino, "Pública")

append using "$resultados\Oficios-UPP\Oficio 998-2019"
save "$resultados\Oficios-UPP\Oficio 998-2019", replace

*1.5) Oficio 89-2020 (14/02/2020) 

import excel using "$inputs\Movimientos\Oficio892020.xlsx", clear first sheet("nominal1") cellrange("A3:O104")
ren *, l
ren (codmod m) (cod_mod_origen cod_mod_destino)

limpia_oficios
	
*Validacion de los movimientos 

preserve
	use "$inputs\Nexus\nexus_4sira", clear // 14/02/2020
	plazaunica
	keep if real(codtipotrab)==10 & real(codsubtipt)==13
	contract codplaza descargo
	tempfile nexus
	save `nexus', replace
restore

merge 1:m codplaza using `nexus', keepusing(descargo) keep(3)

keep if !mi(cod_mod_origen) & !mi(cod_mod_destino)
keep if strpos(d_gestion_destino, "Pública")

save "$resultados\Oficios-UPP\Oficio 89-2020", replace

*1.6) Oficio 143-2020 // 02/03/2020 

import excel using "$inputs\Movimientos\Oficio1432020.xlsx", clear first sheet("nominal2") cellrange("A3:N926")
ren *, l
ren (codmod l) (cod_mod_origen cod_mod_destino)

limpia_oficios
	
*Validacion de los movimientos 

preserve
	use "$inputs\Nexus\nexus_8sira", clear // 21/02/2020
	plazaunica
	keep if real(codtipotrab)==10 & real(codsubtipt)==13
	contract codplaza descargo
	tempfile nexus
	save `nexus', replace
restore

merge 1:m codplaza using `nexus', keepusing(descargo) keep(3)

keep if !mi(cod_mod_origen) & !mi(cod_mod_destino)
keep if strpos(d_gestion_destino, "Pública")

merge 1:1 codplaza using "$inputs\Plazas creadas\plazas creadas", keep(1) nogen

save "$resultados\Oficios-UPP\Oficio 143-2020", replace
 
							/*------------------------------
							|II) Construccion del indicador|
							------------------------------*/
							
*2.1) Resultados a nivel de UGEL

merge_oficios

merge 1:1 cod_ugel using "$resultados\Metas Racionalización CdD-UGEL", keepusing(d_dpto - cod_ue doc_e - plaza_doc brecha_cdd - indicador) nogen update

resultado_meta

hashsort d_dpto ejecutora d_dreugel

drop cod_pliego

order d_dpto pliego ejecutora codpliego secejec cod_ue cod_ugel  
order meta total_movimientos avance_meta, before(resultado)
	
export excel using "$resultados\Resultados CdD.xlsx", sheet("UGEL") first(variable) sheetreplace
save "$resultados\Resultados CdD-UGEL", replace

*2.2) Resultados a nivel de ejecutora

merge_oficios

collapse (rawsum)  movimiento_oficio_* , by(d_dpto ejecutora cod_pliego secejec cod_ue)
ren cod_pliego codpliego

merge 1:1 codpliego secejec cod_ue using "$resultados\Metas Racionalización CdD-Ejecutora", keepusing(d_dpto - cod_ue doc_e - plaza_doc brecha_cdd - indicador) nogen update

resultado_meta

order d_dpto pliego ejecutora codpliego secejec cod_ue  
order meta total_movimientos avance_meta, before(resultado)

export excel using "$resultados\Resultados CdD.xlsx", sheet("Ejecutora") first(variable) sheetreplace
save "$resultados\Resultados CdD-Ejecutora", replace

/*=============================== END PROGRAM ================================*/