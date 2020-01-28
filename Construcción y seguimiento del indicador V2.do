/*------------------------------------------------------------------------------

Proyecto: 									Construccion del indicador para el 
											compromiso de desempeño de raciona-
											lizacion
Autor: 										Hugo Fernandez-Racionalización-UPP
Ultima fecha de modificación:				28/01/2020
Outputs:									Excel con el indicador a nivel de 
											UGEL-Region
											
------------------------------------------------------------------------------*/

clear all
set more off, perm
set excelxlsxlargefile on
*ssc install blindschemes, replace all
set scheme plottig 
cap mkdir "D:\Proyectos\12. Seguimiento del compromiso por desempeño\temp" 
cd "D:\Proyectos\12. Seguimiento del compromiso por desempeño\temp"

global inputs "D:\Proyectos\12. Seguimiento del compromiso por desempeño\Insumos"
global resultados "D:\Proyectos\12. Seguimiento del compromiso por desempeño\Resultados"
global nexus "D:\Base de datos\Nexus\Clean\2019"
global padron "D:\Base de datos\Padron web\Clean"

program plazaunica
*Identifico al personal de interes:
drop if mi(numdocum) //Personal en el aula

 ** Identificación de la plaza original y sus espejo **
 	
	*Plazas únicas
		
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

program define nexuspliego
	collapse (rawsum) bloq_plaza, by(d_dpto d_dreugel)
	hashsort d_dpto d_dreugel
	g idm=_n
	reclink2 d_dpto d_dreugel using "$inputs\nexuspliego_limpio", idmaster(idm) idusing(idu) gen(prob_match) minscore(0.95) 
	keep U* ejecutora secejec cod_pliego cod_ue cod_ugel bloq_plaza
	ren U* * 
	order d_dpto ejecutora d_dreugel 
	order bloq_plaza, last
	compress
	hashsort d_dpto d_dreugel
end 

program define actualizacion_mov

	foreach x in origen destino {
		
		replace cod_mod_`x'=subinstr(cod_mod_`x'," ","",.)
		replace cod_mod_`x'="0"*(7-length(cod_mod_`x'))+cod_mod_`x'
		g anexo_`x'="0"
		order anexo_`x', after(cod_mod_`x')
		
		*Datos del padron
		preserve
			use "$padron\Padron_2020", clear
			keep cod_mod anexo d_ges_dep d_niv_mod d_region d_dreugel d_estado
			ren * *_`x'
			tempfile padron`x'
			save `padron`x'', replace
		restore
		
		merge m:1 cod_mod_`x' anexo_`x' using `padron`x'', gen(escale_`x') keep(1 3)
		
		*Datos del sira
		preserve
			use "$inputs\Base lite", clear
			keep cod_mod doc_e doc_e_n doc_e_c doc_req
			ren * *_`x'
			g anexo_`x'="0"
			order anexo_`x', after(cod_mod_`x')
			tempfile sira`x'
			save `sira`x'', replace
		restore
		
		merge m:1 cod_mod_`x' anexo_`x' using `sira`x'', gen(sira_`x') keep(1 3)
		
	}	


end 

program define collapsemov 
	
	gen movimiento=1
	gen movimiento_oportuno=1 if d_dreugel_origen==d_dreugel_destino & (doc_e_origen!=0 & !mi(doc_e_origen)) & (doc_req_destino!=0 & !mi(doc_req_destino)) 
	 
	collapse (rawsum) movimiento movimiento_oportuno, by(d_region_origen d_dreugel_origen)

	drop if mi(d_dreugel_origen)

	split d_region_origen, p("DRE ")
	replace d_region_origen2="MADRE DE DIOS" if strpos(d_region_origen,"MADRE DE DIOS")
	ren (d_region_origen2 d_dreugel_origen) (d_region d_dreugel)
	order d_region d_dreugel movimiento movimiento_oportuno
	keep d_region d_dreugel movimiento movimiento_oportuno

end

program define padronnexuspliego
	ren (d_region d_dreugel) (d_dpto d_dreugel)
	hashsort d_dpto d_dreugel
	g idm=_n
	reclink2 d_dpto d_dreugel using "$inputs\nexuspliego_limpio", idmaster(idm) idusing(idu) gen(prob_match) minscore(0.95) 
	keep U* ejecutora secejec cod_pliego cod_ue cod_ugel movimiento movimiento_oportuno
	ren U* * 
	order d_dpto ejecutora d_dreugel 
	order movimiento movimiento_oportuno, last
	compress
	hashsort d_dpto d_dreugel
end 

program define construccion_meta 

	g brecha_cdd=nueva_brecha-bloq_plaza+plazas_creacion
	order nueva_brecha, after(nom_exd_mov1_esc1)

	egen movimiento=rowtotal(movimiento1 movimiento2 movimiento3)
	order movimiento, after(movimiento3)
	egen movimiento_oportuno=rowtotal(movimiento_oportuno1 movimiento_oportuno2 movimiento_oportuno3)
	order movimiento_oportuno, after(movimiento_oportuno3)

	*Determinacion de la meta
	egen meta=rowmin(doc_e doc_req)

	*Definicion de participacion
	g estado=0
	replace estado=1 if meta==0 //Esto fue el acuerdo original

	label define estado 0 "Participa" 1 "No participa"
	label val estado estado

	*Definicion del indicador
	g por_meta_pea=meta*100/plaza_doc

	g indicador=.
	replace indicador=1 if meta==doc_e 
	replace indicador=2 if meta==doc_req 

	label define indicador 1 "Indicador 1 (Meta: excedente)" 2 "Indicador 2(Meta: requerimiento)" 
	label val indicador indicador 

	*Porcentaje de avance
	g avance_preliminar=movimiento*100/meta
	g avance_preliminar_oportuno=movimiento_oportuno*100/meta

	*Indicador opcional
	g estado_1=0
	replace estado_1=1 if meta==0 //Esto fue el acuerdo original
	replace estado_1=1 if meta<=5 & por_meta_pea<=2 & nom_exd_mov1_esc1==0 //Q1=5 & <2%

	label define estado_1 0 "Participa" 1 "No participa"
	label val estado_1 estado_1

	hashsort d_dpto ejecutora 
	
end 

/*----------------------------------------------------------------------------*/

/*========================
I) Limpieza y consolidación
========================*/

*1.1) Brecha
use "$inputs\Brecha con horas remanentes", clear
collapse (rawsum) doc_e doc_req nom_exd_mov1_esc1 nueva_brecha, by(d_dpto d_dreugel pliego ejecutora codpliego secejec cod_ue cod_ugel)
tempfile brecha
save `brecha', replace

*1.2) Bloqueo
use "$inputs\Bloqueo nominal", clear
keep if bloq_plaza==1
collapse (rawsum) bloq_plaza (firstnm) region ugel, by(cod_mod)
g anexo="0"

ren (ugel region) (d_dreugel d_dpto) 

nexuspliego

tempfile bloqueo
save `bloqueo', replace

*1.3) Creacion
use "$inputs\creacion de plazas por codmod", clear
keep if creacion==1

collapse (rawsum) plazas_creacion=doc_req_adj,by(d_dpto d_dreugel pliego ejecutora codpliego secejec cod_ue cod_ugel)
tempfile creacion
save `creacion', replace

*1.4) Total de plazas docentes de aula

use "$nexus\nexus_51sira", clear

keep if real(codtipotrab)==10 & strpos(nivel,"E.B.R.")
plazaunica //Correr el do de "Plaza con personal"
keep if tipo_fin==1 //Me quedo con las plazas únicas

*Docente de aula
	gen plaza_doc=1 if tiporegistro!="CUADRO DE HORAS" & real(codsubtipt)==13 & (codcargo=="13007" | codcargo=="13012" | codcargo=="13013" | codcargo=="13048" | codcargo=="13042" | codcargo=="13055" | codcargo=="13032" | codcargo=="13035")
	replace plaza_doc = 0 if mi(plaza_doc)
	
drop if codmod=="0000000" | codmod=="0000001" | codmod=="0000002" | codmod=="0000003" | codmod=="0000006" | strpos(codmod,"P") | strpos(codmod,"O") | strpos(codmod,"I")

replace nombreooii="UGEL MOYOBAMBA" if nombreooii=="DRE SAN MARTIN" //La DRE San Martin tiene la PEA de la UGEL Moyobamba

collapse (sum) plaza_* (firstnm) descreg nombreooii, by(codmod)
ren codmod cod_mod  
g anexo="0"

merge 1:1 cod_mod anexo using "$padron\Padron_2020",keepusing(d_ges_dep) keep(3) nogen
keep if d_ges_dep=="Sector Educación"

collapse (sum) plaza_* , by(descreg nombreooii)
ren (descreg nombreooii) (d_dpto d_dreugel)

hashsort d_dpto d_dreugel
g idm=_n
reclink2 d_dpto d_dreugel using "$inputs\nexuspliego_limpio", idmaster(idm) idusing(idu) gen(prob_match) minscore(0.95) 
keep U* ejecutora secejec cod_pliego cod_ue cod_ugel plaza_doc
ren U* * 
order d_dpto ejecutora d_dreugel 
order plaza_doc, last
compress
tempfile peas
save `peas', replace


*1.4) Movimiento de plazas enviados a DITEN el 09/12/2019
import excel using "$inputs\Moviento de plazas 09122019.xlsx", clear cellrange("A4:K26") sheet("Hoja1")

keep E J K 
ren(E J K) (cod_mod_origen cod_mod_destino rd_reubicacion)

actualizacion_mov
save "$inputs\Aprobado por UPP 09122019", replace
collapsemov
padronnexuspliego

ren (movimiento movimiento_oportuno) (movimiento1 movimiento_oportuno1)
label var movimiento1 "N° de movimientos enviados al 09/12/2019"
label var movimiento_oportuno1 "N° de movimientos oportunos enviados al 09/12/2019"
	
tempfile mov1
save `mov1', replace

*1.5) Movimiento de plazas enviados a DITEN el 10/12/2019
import excel using "$inputs\Moviento de plazas 10122019.xlsx", clear cellrange("A4:N129") sheet("nominal")

keep E L N 
ren(E L N) (cod_mod_origen cod_mod_destino rd_reubicacion)

actualizacion_mov
save "$inputs\Aprobado por UPP 10122019", replace
collapsemov
padronnexuspliego

ren (movimiento movimiento_oportuno) (movimiento2 movimiento_oportuno2)
label var movimiento2 "N° de movimientos enviados al 10/12/2019"
label var movimiento_oportuno2 "N° de movimientos oportunos enviados al 10/12/2019"
	
tempfile mov2
save `mov2', replace

*1.6) Movimiento de plazas enviados a DITEN el 23/01/2020
import excel using "$inputs\Moviento de plazas 23012020.xlsx", clear cellrange("A3:O412") sheet("BD Definit") first

keep F M O 
ren(F M O) (cod_mod_origen cod_mod_destino rd_reubicacion)

actualizacion_mov
save "$inputs\Aprobado por UPP 23012020", replace
collapsemov
padronnexuspliego

ren (movimiento movimiento_oportuno) (movimiento3 movimiento_oportuno3)
label var movimiento3 "N° de movimientos enviados al 23/01/2020"
label var movimiento_oportuno3 "N° de movimientos oportunos enviados al 23/01/2020"
	
tempfile mov3
save `mov3', replace

/*========================
II) Construccion del 
indicador - Nivel UGEL
========================*/

use `brecha', clear
merge 1:1 cod_ugel using `bloqueo', nogen
merge 1:1 cod_ugel using `creacion', nogen
merge 1:1 cod_ugel using `peas', nogen keep(1 3)
merge 1:1 cod_ugel using `mov1', nogen keep(1 3)
merge 1:1 cod_ugel using `mov2', nogen keep(1 3)
merge 1:1 cod_ugel using `mov3', nogen keep(1 3)
order d_dreugel, a(ejecutora)
drop cod_pliego

mvencode bloq_plaza plazas_creacion, mv(0)

construccion_meta

save "$resultados\Metas Racionalización CdD-UGEL", replace
export excel using "$resultados\Metas Racionalización CdD-UGEL.xlsx", sheet("CdD") sheetreplace first(variable)

/*========================
III) Construccion del 
indicador - Nivel Ejecutora
========================*/

use `brecha', clear
merge 1:1 cod_ugel using `bloqueo', nogen
merge 1:1 cod_ugel using `creacion', nogen
merge 1:1 cod_ugel using `peas', nogen keep(1 3)
merge 1:1 cod_ugel using `mov1', nogen keep(1 3)
merge 1:1 cod_ugel using `mov2', nogen keep(1 3)
merge 1:1 cod_ugel using `mov3', nogen keep(1 3)
order d_dreugel, a(ejecutora)
drop cod_pliego

collapse (rawsum) doc_e doc_req nom_exd_mov1_esc1 nueva_brecha bloq_plaza plazas_creacion plaza_doc movimiento*, by(d_dpto pliego ejecutora codpliego secejec cod_ue)

construccion_meta

save "$resultados\Metas Racionalización CdD-Ejecutora", replace
export excel using "$resultados\Metas Racionalización CdD-Ejecutora.xlsx", sheet("CdD") sheetreplace first(variable)
/*=============================== END PROGRAM ================================*/