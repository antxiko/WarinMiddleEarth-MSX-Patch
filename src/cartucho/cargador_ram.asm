; ==========================================================================
; WAR IN MIDDLE EARTH - de cinta a cartucho: EL STUB QUE CORRE EN RAM
; ==========================================================================
; El juego no corre desde ROM (es automodificable por todas partes y quiere
; las cuatro paginas en RAM, como en la cinta), asi que el cartucho es un
; CARGADOR: deja la RAM exactamente como la deja el cargador de la cinta
; (0xD6D8) justo antes de saltar a 0x0190, y salta a 0x0190. Lo que hace el
; juego a partir de ahi es lo mismo con cinta que con cartucho.
;
; Este trozo lo copia a 0xD800 el arranque del cartucho (cargador_ram.asm
; corre desde la RAM porque tiene que quitar el cartucho de la pagina 1 para
; poder escribir 0x4000-0x783F). Lo que hace, por orden:
;
;   1. Busca RAM en las paginas 2, 1 y 0 (en ese orden), ranura a ranura,
;      escribiendo y releyendo, como hace el cargador de la cinta. Mientras
;      la pagina 0 es la BIOS usa su ENASLT; para la pagina 0 y todo lo que
;      viene detras usa el clon de abajo, que no vuelve a necesitar la BIOS.
;   2. Ejecuta el PLAN: una lista de operaciones de 8 bytes que genera
;      tools/haz_rom.py -copiar de ROM a RAM, de ROM a VRAM, de VRAM a RAM,
;      cambiar la pagina 1, escribir registros, esperar- y que acaba con el
;      salto a 0x0190. El plan es el que sabe donde esta cada bloque en la ROM
;      y en que orden hay que moverlo; este fichero solo sabe hacer cada cosa.
;
; El tramo del bloque medio que cae en la pagina 1 (0x4000-0x783F, 14.400 B)
; no se puede escribir mientras la ROM esta en esa pagina: el plan lo deja
; primero en la VRAM (16 KB, libre durante la carga), quita el cartucho de la
; pagina 1, y lo trae de vuelta de la VRAM. La imagen de carga se vuelve a
; pintar despues, con el cartucho otra vez en la pagina 1.
; ==========================================================================

        include "direcciones.inc"
        org     STUB

        jp      INICIO
V_ID_CART:      defb    0       ; STUB+3: lo escribe el arranque desde la ROM
V_ID_RAM0:      defb    0       ; STUB+4
V_ID_RAM1:      defb    0       ; STUB+5
V_ID_RAM2:      defb    0       ; STUB+6
V_BIOS_OK:      defb    1       ; STUB+7: 1 mientras la pagina 0 sea la BIOS

; --------------------------------------------------------------------------
INICIO:
        di
        ld      sp,PILA

        ; Pagina 2: hasta aqui es la segunda ventana del cartucho. Queda RAM.
        ld      hl,08000h
        call    BUSCA_RAM
        jp      c,SIN_RAM
        ld      (V_ID_RAM2),a

        ; Pagina 1: la prueba quita el cartucho, por eso este codigo esta en RAM.
        ld      hl,04000h
        call    BUSCA_RAM
        jp      c,SIN_RAM
        ld      (V_ID_RAM1),a

        ; Y el cartucho vuelve a la pagina 1: el plan lee la ROM por ahi.
        ld      a,(V_ID_CART)
        ld      hl,04000h
        call    SELECCIONA

        ; Pagina 0: a partir de aqui la BIOS no esta. Primero se prueba la
        ; ranura que valio para la pagina 1, que es la de siempre; si no, todas.
        xor     a
        ld      (V_BIOS_OK),a
        ld      a,(V_ID_RAM1)
        ld      hl,00000h
        call    PRUEBA_RANURA
        jr      nc,PAGINA0_LISTA
        ld      hl,00000h
        call    BUSCA_RAM
        jp      c,SIN_RAM
PAGINA0_LISTA:
        ld      (V_ID_RAM0),a

        ; ------------------------------------------------------------------
        ; El plan
        ; ------------------------------------------------------------------
        ld      ix,PLAN
PLAN_BUCLE:
        ld      a,(ix+0)
        cp      OP_SALTA+1
        jr      nc,SIN_RAM              ; un op que no existe: parar
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,TABLA_OPS
        add     hl,de
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        ld      de,PLAN_SIGUIENTE
        push    de
        jp      (hl)
PLAN_SIGUIENTE:
        ld      de,8
        add     ix,de
        jr      PLAN_BUCLE

TABLA_OPS:
        defw    OP_FIN_,OP_ROM_RAM_,OP_ROM_VRAM_,OP_VRAM_RAM_
        defw    OP_LLENA_RAM_,OP_LLENA_VRAM_,OP_IDENT_VRAM_,OP_SPRITES_VRAM_
        defw    OP_PAG1_RAM_,OP_PAG1_CART_,OP_VDP_REG_,OP_PSG_REG_
        defw    OP_ESPERA_,OP_SALTA_

; --------------------------------------------------------------------------
; Sin RAM en alguna pagina, o un plan roto: borde rojo y a esperar.
; --------------------------------------------------------------------------
SIN_RAM:
OP_FIN_:
        ld      a,006h                  ; rojo
        out     (099h),a
        ld      a,087h
        out     (099h),a
        jr      $

; --------------------------------------------------------------------------
; Las operaciones. Entran con IX apuntando a la entrada del plan.
; --------------------------------------------------------------------------
OP_ROM_RAM_:
        call    BANCO_Y_REGISTROS       ; banco puesto; HL=src DE=dst BC=len
        ldir
        ret

OP_ROM_VRAM_:
        call    BANCO_Y_REGISTROS
        ex      de,hl                   ; HL=dst (VRAM), DE=src
        call    VRAM_ESCRIBIR_EN
        ex      de,hl
VRAM_BUCLE_ESCRIBE:                     ; HL=origen en RAM/ROM, BC=cuantos
        ld      a,(hl)
        out     (098h),a
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,VRAM_BUCLE_ESCRIBE
        ret

OP_VRAM_RAM_:
        call    REGISTROS               ; HL=src (VRAM) DE=dst BC=len
        call    VRAM_LEER_EN
        ex      de,hl                   ; HL=destino en RAM
VRAM_BUCLE_LEE:
        in      a,(098h)
        ld      (hl),a
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,VRAM_BUCLE_LEE
        ret

OP_LLENA_RAM_:
        call    REGISTROS               ; DE=dst BC=len, b=valor
        ld      a,(ix+1)
        ld      h,d
        ld      l,e
        ld      (hl),a
        dec     bc
        ld      a,b
        or      c
        ret     z
        inc     de
        ldir
        ret

OP_LLENA_VRAM_:
        call    REGISTROS
        ex      de,hl
        call    VRAM_ESCRIBIR_EN
        ld      a,(ix+1)
VRAM_BUCLE_LLENA:
        out     (098h),a
        dec     bc
        ld      d,a
        ld      a,b
        or      c
        ld      a,d
        jr      nz,VRAM_BUCLE_LLENA
        ret

OP_IDENT_VRAM_:                         ; 0,1,2..255,0,1.. : la tabla de nombres del SCREEN 2
        call    REGISTROS
        ex      de,hl
        call    VRAM_ESCRIBIR_EN
        xor     a
VRAM_BUCLE_IDENT:
        out     (098h),a
        inc     a
        dec     bc
        ld      d,a
        ld      a,b
        or      c
        ld      a,d
        jr      nz,VRAM_BUCLE_IDENT
        ret

OP_SPRITES_VRAM_:                       ; lo que deja el SCREEN 2 del BASIC: 32 sprites fuera de pantalla
        call    REGISTROS
        ex      de,hl
        call    VRAM_ESCRIBIR_EN
        ld      b,32
        ld      c,0                     ; numero de patron
SPRITES_BUCLE:
        ld      a,209                   ; Y=209: el sprite no se pinta
        out     (098h),a
        xor     a                       ; X=0
        out     (098h),a
        ld      a,c                     ; patron n
        out     (098h),a
        ld      a,1                     ; color 1
        out     (098h),a
        inc     c
        djnz    SPRITES_BUCLE
        ret

OP_PAG1_RAM_:
        ld      a,(V_ID_RAM1)
        ld      hl,04000h
        jp      SELECCIONA

OP_PAG1_CART_:
        ld      a,(V_ID_CART)
        ld      hl,04000h
        jp      SELECCIONA

OP_VDP_REG_:
        ld      a,(ix+2)                ; el valor
        out     (099h),a
        ld      a,(ix+1)                ; el registro
        or      080h
        out     (099h),a
        ret

OP_PSG_REG_:
        ld      a,(ix+1)
        out     (0A0h),a
        ld      a,(ix+2)
        out     (0A1h),a
        ret

OP_ESPERA_:                             ; b cuadros: el bit 7 del estado del VDP se pone en cada barrido
        ld      b,(ix+1)
ESPERA_CUADRO:
        in      a,(099h)                ; leerlo lo baja
        rlca
        jr      nc,ESPERA_CUADRO
        djnz    ESPERA_CUADRO
        ret

OP_SALTA_:
        ld      l,(ix+2)
        ld      h,(ix+3)
        ld      sp,hl
        ld      l,(ix+4)
        ld      h,(ix+5)
        jp      (hl)

; --------------------------------------------------------------------------
; Auxiliares de las operaciones
; --------------------------------------------------------------------------
BANCO_Y_REGISTROS:                      ; pone el banco de la entrada en la ventana de 0x4000
        ld      a,(ix+1)
        ld      (BANCO_VENTANA),a
REGISTROS:                              ; HL=src DE=dst BC=len
        ld      l,(ix+2)
        ld      h,(ix+3)
        ld      e,(ix+4)
        ld      d,(ix+5)
        ld      c,(ix+6)
        ld      b,(ix+7)
        ret

VRAM_ESCRIBIR_EN:                       ; HL = direccion de VRAM para escribir
        ld      a,l
        out     (099h),a
        ld      a,h
        and     03Fh
        or      040h
        out     (099h),a
        ret

VRAM_LEER_EN:                           ; HL = direccion de VRAM para leer
        ld      a,l
        out     (099h),a
        ld      a,h
        and     03Fh
        out     (099h),a
        ret

; --------------------------------------------------------------------------
; Las ranuras
; --------------------------------------------------------------------------
; BUSCA_RAM: HL = direccion de la pagina (0x0000, 0x4000 o 0x8000). Recorre
; las ranuras primarias y, en las expandidas segun EXPTBL, sus secundarias,
; hasta encontrar una en la que se pueda escribir y releer. Sale con esa
; ranura puesta, su identificador en A y el acarreo a cero; con acarreo si no
; hay ninguna.
BUSCA_RAM:
        ld      c,0                     ; primaria
BR_PRIMARIA:
        push    hl
        ld      hl,EXPTBL
        ld      b,0
        add     hl,bc
        ld      a,(hl)
        pop     hl
        bit     7,a
        jr      z,BR_NO_EXPANDIDA
        ld      d,0                     ; secundaria
BR_SECUNDARIA:
        ld      a,d
        rlca
        rlca
        or      c
        or      080h
        call    PRUEBA_RANURA
        ret     nc
        inc     d
        ld      a,d
        cp      4
        jr      nz,BR_SECUNDARIA
        jr      BR_SIGUIENTE
BR_NO_EXPANDIDA:
        ld      a,c
        call    PRUEBA_RANURA
        ret     nc
BR_SIGUIENTE:
        inc     c
        ld      a,c
        cp      4
        jr      nz,BR_PRIMARIA
        scf
        ret

; PRUEBA_RANURA: A = identificador, HL = direccion. Pone la ranura y escribe
; dos valores distintos para ver si vuelven. Conserva BC, DE y HL. Acarreo a
; cero si hay RAM (y se queda puesta), a uno si no.
PRUEBA_RANURA:
        push    bc
        push    de
        push    hl
        push    af
        call    SELECCIONA
        pop     af
        pop     hl
        push    hl
        push    af
        ld      (hl),020h
        ld      a,(hl)
        cp      020h
        jr      nz,PR_NO
        ld      (hl),0FAh
        ld      a,(hl)
        cp      0FAh
        jr      nz,PR_NO
        pop     af
        or      a                       ; acarreo a cero: hay RAM
        jr      PR_FIN
PR_NO:
        pop     af
        scf
PR_FIN:
        pop     hl
        pop     de
        pop     bc
        ret

; SELECCIONA: A = identificador (formato de ENASLT: bit 7 = expandida, bits
; 3-2 = secundaria, bits 1-0 = primaria), HL = direccion de la pagina.
;
; Mientras la pagina 0 es la BIOS, es ENASLT tal cual: sabe cambiar la
; secundaria de cualquier ranura porque para eso pasa un momento la pagina 3
; a esa primaria, y ella corre en la pagina 0. Este stub corre en la pagina 3
; y no puede hacer eso: el clon escribe el registro de secundarias (0xFFFF)
; solo cuando la primaria de destino es la que ya esta en la pagina 3 -la de
; la RAM, que es el caso de la RAM en cualquier maquina normal- y, si no, se
; fia de que el registro ya este bien: para el cartucho lo dejo la BIOS al
; arrancar, y para la RAM lo dejo ENASLT al buscarla.
SELECCIONA:
        push    af
        ld      a,(V_BIOS_OK)
        or      a
        jr      z,SEL_CLON
        pop     af
        jp      ENASLT
SEL_CLON:
        pop     af
        push    af
        ; C = mascara de lo que se conserva, B = cuantos bits hay que
        ; desplazar (el numero de pagina por dos)
        ld      a,h
        rlca
        rlca
        and     003h
        add     a,a
        ld      b,a
        ld      a,003h
        ld      c,a
        inc     b
        dec     b
        jr      z,SEL_MASCARA_LISTA
        push    bc
SEL_ROTA:
        rlca
        djnz    SEL_ROTA
        pop     bc
SEL_MASCARA_LISTA:
        cpl
        ld      c,a                     ; C = ~(3 << 2*pagina)
        pop     af
        push    af
        bit     7,a
        jr      z,SEL_PRIMARIA
        ; expandida: solo se puede tocar 0xFFFF si su primaria es la de la pagina 3
        and     003h
        ld      e,a
        in      a,(0A8h)
        rlca
        rlca
        and     003h
        cp      e
        jr      nz,SEL_PRIMARIA         ; no se llega al registro: se da por bien puesto
        pop     af
        push    af
        rrca
        rrca
        and     003h                    ; la secundaria
        call    SEL_DESPLAZA            ; a su sitio segun la pagina
        ld      e,a
        ld      a,(0FFFFh)
        cpl                             ; el registro se lee invertido
        and     c
        or      e
        ld      (0FFFFh),a
SEL_PRIMARIA:
        pop     af
        and     003h
        call    SEL_DESPLAZA
        ld      e,a
        in      a,(0A8h)
        and     c
        or      e
        out     (0A8h),a
        ret

SEL_DESPLAZA:                           ; A <<= B (B = 2*pagina), sin tocar B ni C
        push    bc
        inc     b
        dec     b
        jr      z,SD_FIN
SD_BUCLE:
        add     a,a
        djnz    SD_BUCLE
SD_FIN:
        pop     bc
        ret

; --------------------------------------------------------------------------
; El plan, generado por tools/haz_rom.py con la disposicion de la ROM
; --------------------------------------------------------------------------
PLAN:
        include "plan.inc"
FIN_STUB:
