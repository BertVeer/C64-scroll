;-----------------------------------------------------------------------------
;  C64 SIDE SCROLLER
;  MIT licensed 2019 Bert vt Veer
;  Compiled with 64TASS
;-----------------------------------------------------------------------------

; Start with BASIC line "2019 SYS2063"
*=$0801
	.word (+), 2019
	.null $9e, "2063"
+	.word 0

*=$080f
	jmp Main


; Constants
SCREEN_BASE		= $3000
COLMEM_BASE		= $D800
RAS_BEGIN_LINE		= 44
RAS_COPY_LINE		= 59
TRIGGER_SCREEN		= 1
TRIGGER_COLORS		= 2

; Variables
buffer_front		.word SCREEN_BASE
buffer_back		.word SCREEN_BASE+1024
trigger			.byte 0
scroll_x		.byte 0
scroll_speed		.byte 1					; 1, 2, 4
char_index		.byte 0


;-----------------------------------------------------------------------------
; Main procedure
;-----------------------------------------------------------------------------

Main
.proc
	lda $d016
	and #%11110111
	sta $d016						; Set 38 columns

	lda $d018
	and #%00001111
	ora #%11000000
	sta $d018						; set VIC screen location to $3000
	jsr ClearBuffers					; clear front/back screen

	lda #$7f
	sta $dc0d						; enable interrupts
	and $d011
	sta $d011						; clear raster MSB
	lda #RAS_BEGIN_LINE
	sta $d012						; set initial raster line
	lda #<RasterProc_Begin
	sta $0314						; set raster interrupt lo address
	lda #>RasterProc_Begin
	sta $0315						; set raster interrupt hi address
	lda #$01
	sta $d01a						; enable raster interrupt
	lda #54
	sta $01							; disable BASIC

; Start main loop
_forever
	lda trigger
	beq _forever						; do nothing if no triggers

	cmp #TRIGGER_SCREEN
	bne +
	jsr ScrollScreen					; scroll the screen
	jsr FillEdge						; fill right edge of screen
	jmp _done

+	cmp #TRIGGER_COLORS
	bne _done
	jsr ScrollColors					; scroll the colors	
	jsr SwapScreens						; Next retrace has already happened by now, quickly
								; swap now before first visible scanline is reached
_done
	lda #0
	sta trigger						; events handled, reset trigger
	jmp _forever
.pend


;-----------------------------------------------------------------------------
; Peform soft scroll
;-----------------------------------------------------------------------------

RasterProc_Begin
.proc
	lda scroll_x
	sec
	sbc scroll_speed					; scroll_x -= scroll_speed
	bcs +							; reset scroll_x on underflow?
	lda #8
	sec
	sbc scroll_speed					; scroll init = 8 - scroll_speed
+	sta scroll_x	
	lda $d016
	and #%11111000
	ora scroll_x
	sta $d016						; update soft scroll register

	; Update raster interrupt vector
	lda #RAS_COPY_LINE
	sta $d012						; set next raster line
	lda #<RasterProc_Copy
	sta $0314
	lda #>RasterProc_Copy
	sta $0315
	asl $d019						; ack interrupt
	jmp $ea81						; rti
.pend


;-----------------------------------------------------------------------------
; Set trigger depending on soft scroll value
;-----------------------------------------------------------------------------

RasterProc_Copy
.proc
	lda scroll_x						
	cmp #4
	bne +
	lda #TRIGGER_SCREEN
	sta trigger						; trigger = screen
	jmp _done
+	cmp #0
	bne _done
	lda #TRIGGER_COLORS
	sta trigger						; trigger = colors

_done
	; Update raster interrupt vector
	lda #RAS_BEGIN_LINE
	sta $d012
	lda #<RasterProc_Begin
	sta $0314
	lda #>RasterProc_Begin
	sta $0315							
	asl $d019						; ack interrupt
	jmp $ea81						; rti
.pend


;-----------------------------------------------------------------------------
; Swap front/back buffers and update addresses
;-----------------------------------------------------------------------------

SwapScreens
.proc
	lda #0
	sta buffer_front					; update screen pointer lo
	sta buffer_back

	lda $d018
	eor #%00010000
	sta $d018						; toggle screen pointer LSB
	and #%00010000						; current screen = base?
	beq +

	lda #>SCREEN_BASE					; no, use base address
	sta buffer_front+1
	clc
	adc #$04
	sta buffer_back+1
	rts

+	lda #>SCREEN_BASE					; yes, use base address + $0400
	sta buffer_back+1
	clc
	adc #$04
	sta buffer_front+1
	rts
.pend


;-----------------------------------------------------------------------------
; Clear front and back buffer
;-----------------------------------------------------------------------------

ClearBuffers
.proc
	lda #<SCREEN_BASE
	sta $fb
	lda #>SCREEN_BASE
	sta $fc
	ldx #8							; 8 x 256b blocks, 2 screens
	ldy #0
	lda #32
-	sta ($fb),y
	dey
	bne -
	inc $fc
	dex
	bne -
	rts
.pend


;-----------------------------------------------------------------------------
; Scroll color memory left
;-----------------------------------------------------------------------------

ScrollColors
.proc
	lda #>COLMEM_BASE
	sta _copy+2						; init pointer copy-from
	sta _copy+5						; init pointer copy-to
	ldx #4							; 4 x 256b blocks
	ldy #0
_copy
	lda COLMEM_BASE+1,y
	sta COLMEM_BASE,y
	iny
	bne _copy
	inc _copy+2
	inc _copy+5
	dex
	bne _copy
	rts
.pend


;-----------------------------------------------------------------------------
; Scroll character memory left
;-----------------------------------------------------------------------------

ScrollScreen
.proc
	lda buffer_back+1
	sta _copy+2
	lda buffer_front+1
	sta _copy+5
_start
	ldx #4							; 4 blocks of 256 bytes
	ldy #0
_copy
	lda SCREEN_BASE+1,y
	sta SCREEN_BASE,y
	iny
	bne _copy
	inc _copy+2
	inc _copy+5
	dex
	bne _copy
	rts
.pend


;-----------------------------------------------------------------------------
; Fill right edge of screen
;-----------------------------------------------------------------------------

FillEdge
.proc
	lda buffer_front+1
	sta _fill+2						; screen hi
	lda #>COLMEM_BASE
	sta _fill+5						; colors hi
	lda #39
	sta _fill+1						; screen lo
	sta _fill+4						; colors lo

	inc char_index						; increase character counter
	ldx #25							; count 25 lines

_loop
	lda char_index						; a = character
	tay							; y = color
_fill
	sta SCREEN_BASE						; draw character
	sty COLMEM_BASE						; draw color

	lda _fill+1
	clc
	adc #40
	sta _fill+1						; increase screen lo

	lda _fill+4
	clc
	adc #40
	sta _fill+4						; increase colors lo

	bcc +
	inc _fill+5						; increase colors hi
	inc _fill+2						; increase screen hi
+	dex
	bne _loop

_done
	rts
.pend	


