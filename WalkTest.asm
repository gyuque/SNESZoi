;----------------------------------------------------------------------------
;			SNES Walking Demo by S.Ueyama, 2015
;					Based on SNES lab. by Tekepen
;----------------------------------------------------------------------------
.setcpu		"65816"
.autoimport	on

; Global Variables

.define gBitOpTemp   $0006
.define gTriggerWait $0008
.define gPlayerX     $0010
.define gPlayerY     $0012
.define gWalkAnimationCount $0016
.define gPlayerTileBase $0018
.define gPlayerDirFlag  $001a
.define gTalkingFlag    $001c
.define gTalkingCount   $001e
.define gTalkingAnimationCount $0020
.define gSpritePosTemp $0022
.define gSpriteNegTemp $0024
.define gEffectAnimationCount $0026
.define gRandomReg     $0028

.define gPadCountL $002a
.define gPadCountR $002c
.define gPadCountB $002e
.define gPadState  $0030

.define gWorkArea      $0040

.define kPlayerSpriteIndex1 #$08
.define kPlayerSpriteIndex2 #$09
.define kShadowSpriteIndex  #$0a
.define kFxSpriteIndex      #$00

.import	InitRegs
.segment "STARTUP"

; パレットテーブル
PaletteBase:
	.incbin	"bg-palette.bin"
	.incbin	"sp-palette.bin"

; パターンテーブル
PatternBase:
	.incbin	"bg-ptn.bin"
	.incbin	"sprite-ptn.bin"

WalkAnimationTable:
	.byte $01
	.byte $02
	.byte $03
	.byte $02

; リセット割り込み
.proc	Reset
	sei
	clc
	xce	; Native Mode
	phk
	plb	; DB = 0

	rep	#$30	; A,I 16bit
.a16
.i16
	ldx	#$1fff
	txs
	
	jsr	InitRegs

	; BG configuration
	sep	#$20
.a8
	; Specify BGMode (16/16/4/0)
	lda #$01
	sta $2105

	; BG1
	; Map address and size
	lda	#$40
	sta	$2107
	; Pattern address
	stz	$210b

	; BG2
	; Map address and size
	lda	#$50
	sta	$2108
	; Pattern address
	;  -> share with BG1

	rep	#$20
.a16

	; BG Palette
	ldx	#$0000 ; src start
	ldy #$0000 ; dest start in words
	jsr transferPaletteData

	; Sprite Palette
	ldx	#$0020 ; src start
	ldy #$0080 ; dest start in words
	jsr transferPaletteData


	; BG Pattern
	lda	#$0000 ; dest start
	ldx #$0000 ; src start
	ldy	#$0800 ; size in words
	jsr transferPatternData

	; Sprite Pattern
	lda	#$2000 ; dest start
	ldx #$1000 ; src start
	ldy	#$1000 ; size in words
	jsr transferPatternData


	jsr fillBGWall
	jsr fillBGFloor

	ldx #$4000
	jsr zeroFillBG

	ldx #$01
	jsr enableScreen

	; Initialize sprites
	jsr clearSpriteSecondTable
	jsr outAllSprites

	; Use sprites for characters

	ldx kPlayerSpriteIndex1
	ldy #$0000
	jsr enableSprite

	ldx kPlayerSpriteIndex2
	ldy #$0000
	jsr enableSprite

	ldx kShadowSpriteIndex
	ldy #$0000
	jsr enableSprite

	; Enable effect sprite (and go out)
	ldx kFxSpriteIndex
	ldy #$00
	jsr enableSprite

	lda kFxSpriteIndex
	ldx #$00
	ldy #$e0
	jsr setSpritePosition

	jsr initGameStates
	jsr initSystemStates

	jsr enterMainLoop

	rti
.endproc

.include "snippets.asm"

; ================= main procs =================

.proc enterMainLoop

mainloop_start:

;	mWaitVBlankStart
;	mWaitVBlankEnd

	jmp	mainloop_start

	rts
.endproc

.proc mainUpdate
	php
	pha
	phx

	jsr applyPadState
	jsr calcPlayerTileBase
	jsr placePlayerSprites

	jsr updateEffectSprite
	jsr updateEffectAnimationStatus

	jsr scrollHalfPlayerX

	; If talking window is enabled
	lda gTalkingFlag
	and #$01
	beq no_talk_proc
	jsr advanceTalkingAnimation
	no_talk_proc:

	plx
	pla
	plp
	rts
.endproc

.proc scrollHalfPlayerX
	pha
	phx

	lda gPlayerX
	lsr
	tax
	jsr scrollBG2
	
	plx
	pla
	rts
.endproc


.proc applyPadState
	php
	pha
	phx

	; Don't move while talking
	lda gTalkingFlag
	and #$0f
	bne end_anim

	; Right ON
	lda gPadState
	and #$01
	beq ifleft

	; Check maximum value
	lda gPlayerX
	eor #$ff
	beq endmoveif

	inc gPlayerX
	stz gPlayerDirFlag ; Update direction flag

	jmp endmoveif

	ifleft:
	; Left ON
	lda gPadState
	and #$02
	beq endmoveif

	; Check minumum value
	lda gPlayerX
	dec
	beq endmoveif

	dec gPlayerX

	lda #$01
	sta gPlayerDirFlag ; Update direction flag

	endmoveif:


	; Advance animation (if needed)
	lda gPadState
	and #$03
	beq no_anim
	jsr advanceAnimationCount
	jmp end_anim

	no_anim:
	stz gWalkAnimationCount

	end_anim:

	; Check trigger
	lda gPadState
	and #$10
	beq notrgset
		jsr onTriggerPushed
		jmp trgend

	notrgset:
		stz gTriggerWait

	trgend:

	plx
	pla
	plp
	rts
.endproc

.proc onTriggerPushed
	php
	pha
	phx

	; Suppress repeating
	lda gTriggerWait
	and #$01
	bne trgp_end ; Wait for release...
	; else
		; Set flag
		lda #$01
		sta gTriggerWait

	lda gTalkingFlag
	and #$01
	bne tk_toggle_close

		; Open talking window
		ldx #$01
		jsr fillMessageWindowArea

		lda #$01
		sta gTalkingFlag

		stz gEffectAnimationCount
		stz gTalkingCount
		stz gTalkingAnimationCount
		jmp tk_toggle_end

	tk_toggle_close:

		; Close talking window
		ldx #$00
		jsr fillMessageWindowArea

		stz gTalkingFlag
		stz gEffectAnimationCount

	tk_toggle_end:


	trgp_end:
	plx
	pla
	plp
	rts
.endproc


.proc advanceAnimationCount
	pha

	lda gWalkAnimationCount
	inc
	and #$1f
	ora #$80
	sta gWalkAnimationCount

	pla
	rts
.endproc


.proc VBlank
	pha
	phx
	php

	sep	#$20
.a8    

	; * Only one waiting causes chattering.
	;   I wait three times and got good result...
	;   Does anyone know better way?
	; S.Ueyama

	; Wait Joypad
	padwait:
		lda $4212
		and #$01
		bne padwait

	lda $4212
	ora #$01
	sta $4212

	; Wait Joypad
	padwait2:
		lda $4212
		and #$01
		bne padwait2

	lda $4212
	ora #$01
	sta $4212

	; Wait Joypad
	padwait3:
		lda $4212
		and #$01
		bne padwait3


	rep	#$20
.a16

	lda $4218
	tay

	; * I put filter routine here to suppress input chattering.
	;   However, this may not be needed after I wrote (ugly) "3-time-waiting" above.

	; X <- pad input
	jsr updatePadInputCount

	txa ; filtered val
	and #$03  ; Left, Right bits
	sta gPadState

	txa ; filtered val
	and #$c0
	beq notrig

	lda #$10
	ora gPadState
	sta gPadState

	notrig:

	jsr mainUpdate

	; Show screen with full brightness
	ldx #$0f
	jsr enableScreen

	plp
	plx
	pla
	rti
.endproc


; == Sub
; MUST UNDER: A16, I16
.proc updatePadInputCount
	pha
	phy

	; Update count
	ldx gPadCountR
	tya ; in Y = raw
	and #$0100
	jsr calcNextPadInCount
	stx gPadCountR

	ldx gPadCountL
	tya
	and #$0200
	jsr calcNextPadInCount
	stx gPadCountL

	ldx gPadCountB
	tya
	and #$c000
	jsr calcNextPadInCount
	stx gPadCountB


	; Update bits
	ldx #$00

	lda gPadCountR
	ldy #$01
	jsr calcNextPadBits

	lda gPadCountL
	ldy #$02
	jsr calcNextPadBits

	lda gPadCountB
	ldy #$80
	jsr calcNextPadBits

	ply
	pla
	rts
.endproc

; in X: prev val
.proc calcNextPadInCount

	bne held
		; released: -1

		txa
		beq endb ; already zero

		dex

	jmp endb
	held:
		; held: +1
		txa
		and #$fc
		bne endb ; already max

		inx

	endb:

	rts
.endproc


; in A: count
; in X: old pad bits
; in Y: mask
; out X: new pad bits
.proc calcNextPadBits
	clc
	cmp #$02
	bcc noset

	; SET
	sty gBitOpTemp
	txa
	ora gBitOpTemp

	jmp endb
	noset:

	; DEL
	tya
	eor #$ffff
	sta gBitOpTemp
	txa
	and gBitOpTemp

	endb:

	tax
	rts
.endproc


; ================= generic graphics routines =================

; == Sub
; MUST UNDER: A16, I16
; in X: Source offset
; in Y: Dest offset (in words)
.proc transferPaletteData
	pha
	phx
	phy

	sep #$20
.a8

	tya
	sta	$2121

	ldy	#$0020 ; N=16 entries
copypal:
	lda	PaletteBase, x
	sta	$2122
	inx
	dey
	bne	copypal

	rep	#$20
.a16

	ply
	plx
	pla
	rts
.endproc


; == Sub
; MUST UNDER: A16, I16
; in A: Dest address
; in X: Start offset
; in Y: Size (in words)
.proc transferPatternData
	sta	$2116

	pha
	phx
	phy

copyptn:
	lda	PatternBase, x
	sta	$2118
	inx
	inx
	dey
	bne	copyptn

	ply
	plx
	pla
	rts
.endproc


; == Sub
; MUST UNDER: A16, I16
.proc outAllSprites
	pha
	phx

	sep	#$20
.a8

	mWaitVBlankEnd

	ldx #$80
	spcloop:

	rep	#$20
.a16

	txa
	dec
	asl
	sta $2102

	sep	#$20
.a8
	

	stz $2104 ; x
	lda #$e0
	sta $2104 ; y
	stz $2104 ; tile
	stz $2104 ; others

	dex
	bne spcloop

	rep	#$20
.a16

	plx
	pla
	rts
.endproc


; == Sub
; MUST UNDER: A16, I16
.proc clearSpriteSecondTable
	php
	pha
	phx

	mWaitVBlankEnd

	sep	#$20
.a8

	; Access second table
	stz $2102
	lda #$01
	sta $2103

	ldx #$20
	clearloop:
		stz $2104

	dex
	bne clearloop

	rep	#$20
.a16

	plx
	pla
	plp
	rts
.endproc

; == Sub
; MUST UNDER: A16, I16
; in X: sprite index
; in Y: chip index
.proc enableSprite
	pha
	phx
	phy

	sep	#$20
.a8
	; Set Pattern Area Base
	lda #%10100001 ; start=$2000
	sta $2101

	txa
	asl ; Select sprite (start = x*2 words)
	sta $2102
	stz $2103
	
	lda #$00
	sta $2104 ; x = 0

	lda #$00
	sta $2104 ; y = 0

	tya
	sta $2104 ; tile

	lda #$20  ; Display order = high
	sta $2104 ; other flags


	rep	#$20
.a16

	ply
	plx
	pla
	rts
.endproc


; == Sub
; MUST UNDER: A16, I16
; in A: sprite index
; in X: start tile index
; in Y: high priority bit
.proc changeSpriteTile
	pha
	phx
	phy

	asl
	inc
	sta $2102 ; Select sprite + 1w

	sep	#$20
.a8
	txa
	sta $2104 ; Base tile index

	; Update other flags
	lda #$00
	ldx gPlayerDirFlag
	beq noflip
	ora #$40  ; Flip X

	noflip:
	ora #$20

	tyx
	beq no_highest
	ora #$10
	no_highest:

	sta $2104 ; store


	rep	#$20
.a16

	ply
	plx
	pla
	rts
.endproc


; == Sub
; MUST UNDER: A16, I16
; in A: sprite index
; in X: x position
; in Y: y position
.proc setSpritePosition
	pha
	phx
	phy

	asl
	sta $2102 ; Select sprite

	; Check max X
	txa
	and #$ff00
	beq no_cap_x
		bmi no_cap_x ; negative

		ldx #$ff ; Cap to 255
	no_cap_x:

	sep	#$20
.a8

	txa
	sta $2104 ; x

	tya
	sta $2104 ; y

	rep	#$20
.a16

	ply
	plx
	pla
	rts
.endproc

; == Sub
; MUST UNDER: A16, I16
; in X: brightness(1-15)
.proc enableScreen
	php
	pha


	sep	#$20
.a8
	lda	#$13 ; Sprite and BG1,2 ON
	sta	$212c
	stz	$212d

	; brightness
	txa
	and #$0f
	sta $2100

	rep	#$20
.a16

	pla
	plp
	rts
.endproc

; ================= specific routines =================

; == Sub
; MUST UNDER: A16, I16
.proc disableInts
	sep	#$20
.a8

	stz $4200

	rep	#$20
.a16	

	rts
.endproc

; == Sub
; MUST UNDER: A16, I16
.proc initSystemStates
	pha

	; VSync and Joypad
	sep	#$20
.a8

	stz $4016

	lda #$81
	sta $4200

	rep	#$20
.a16	

	pla
	rts
.endproc


; == Sub
; MUST UNDER: A16, I16
.proc initGameStates
	pha

	sep	#$20
.a8

	stz gPadState
	stz gWalkAnimationCount

	rep	#$20
.a16	

	lda #$20
	sta gPlayerX

	lda #$6e
	sta gPlayerY

	stz gPlayerTileBase
	stz gPlayerDirFlag
	stz gTriggerWait
	stz gTalkingFlag
	stz gTalkingCount
	stz gTalkingAnimationCount
	stz gEffectAnimationCount

	lda #$1234
	sta gRandomReg

	stz gPadCountL
	stz gPadCountR
	stz gPadCountB

	pla
	rts
.endproc


; == Sub
; MUST UNDER: A16, I16
; in X: amount
.proc scrollBG2
	php
	pha

	sep	#$20
.a8

	txa
	sta $210f
	lda #$00
	sta $210f

	rep	#$20
.a16

	pla
	plp
	rts
.endproc


; == Sub
; MUST UNDER: A16, I16
.proc calcPlayerTileBase
	php
	pha
	phx
	phy

	lda gWalkAnimationCount
	and #$80
	beq tilecalc_stopped

	; Walking frames - - - - -
	lda gWalkAnimationCount
	and #$1f
	lsr
	lsr
	lsr
	tax
	lda WalkAnimationTable, x
	and #$00ff
	asl
	asl
	sta gPlayerTileBase
	jmp tilecalc_end

	; Stopped frame - - - - -
	tilecalc_stopped:
	stz gPlayerTileBase

	tilecalc_end:


	; If talking
	lda gTalkingFlag
	and #$0f
	beq calc_talk_tile_end

	; Don't animate if count is max
	clc
	lda gTalkingCount
	cmp #$60
	bcs skip_inc
		inc gTalkingAnimationCount
	skip_inc:

	lda gTalkingAnimationCount
	clc
	and #$08
	lsr
	adc #$80
	sta gPlayerTileBase ; 0x80 + 0 or 4

	calc_talk_tile_end:

	ply
	plx
	pla
	plp
	rts
.endproc


.define kPlayerXOffset #$10
.define kPlayerEffectSpriteOffset #$10

; == Sub
; MUST UNDER: A16, I16
.proc placePlayerSprites
	php
	pha
	phx
	phy

	; Position

	lda gPlayerX
	sta gSpritePosTemp

	ldx kPlayerXOffset
	jsr calcOffsetPosition
	stx gSpriteNegTemp

	; Top sprite
	ldx gSpritePosTemp ; X=x position
	ldy gPlayerY       ; Y=y position
	lda kPlayerSpriteIndex1 ; A=Sprite Index
	jsr setSpritePosition

	; Bottom sprite
	clc
	lda gPlayerY
	adc #$20
	tay                ; a-> y
	ldx gSpritePosTemp ; X=x position
	lda kPlayerSpriteIndex2
	jsr setSpritePosition

	lda kShadowSpriteIndex
	jsr setSpritePosition


	ldx gSpriteNegTemp
	ldy #$01
	jsr setSpriteNrgativeXFlag

	; Animation

	; Top sprite
	ldx gPlayerTileBase
	ldy gPlayerDirFlag
	lda kPlayerSpriteIndex1 ; A=Sprite Index
	jsr changeSpriteTile

	
	; Bottom sprite
	clc
	lda gPlayerTileBase
	adc #$40
	tax

	; Special case (Chip 2 of talking)
	lda gPlayerTileBase
	eor #$84
	bne no_tile_tweak ; gPlayerTileBase != 0x84
		dex
		dex
		dex
		dex
	no_tile_tweak:

	ldy gPlayerDirFlag
	lda kPlayerSpriteIndex2 ; A=Sprite Index
	jsr changeSpriteTile

	ldx #$8c
	ldy #$00
	lda kShadowSpriteIndex ; A=Sprite Index
	jsr changeSpriteTile

	ply
	plx
	pla
	plp
	rts
.endproc

; == Sub
; MUST UNDER: A16, I16
; in X: minus?
; in Y: group
.proc setSpriteNrgativeXFlag
	php
	pha
	phx
	phy

	sep	#$20
.a8

	; Access second table
	stz $2102
	lda #$01
	sta $2103

	; Save group index
	tya
	pha ; A -->

	lda $2138
	and #$aa
	tay
	lda $2138 ; ignore

	txa
	and #$01
	beq no_setneg ; Add negative bits
		tya
		ora #$55
		tay

	no_setneg:

	; Access second table
	pla ; A <--
	sta $2102
	lda #$01
	sta $2103

	tya
	sta $2104
	stz $2104

	rep	#$20
.a16	

	ply
	plx
	pla
	plp
	rts
.endproc

; == Sub
; MUST UNDER: A16, I16
; in X: amount
; out X: minus?
.proc calcOffsetPosition
	php
	pha

	clc
	; A <- gSpritePosTemp - X
	lda gSpritePosTemp
	stx gSpritePosTemp
	sbc gSpritePosTemp
	sta gSpritePosTemp

	; Update minus flag
	ldx #$00
	eor #$0 ; see A
	bpl decpos_noneg

	; minus
	ldx #$01

	decpos_noneg:

	pla
	plp
	rts
.endproc


; == Sub
; MUST UNDER: A16, I16
; in X: base address
.proc zeroFillBG
	php
	pha

	mWaitVBlankEnd

	; Set base address
	txa
	sta	$2116

	lda #$400
	fillloop:
	stz	$2118
	dec
	bne fillloop

	pla
	plp
	rts
.endproc


; == Sub
; MUST UNDER: A16, I16
.proc fillBGFloor
	pha
	phx
	phy

	mWaitVBlankEnd

	; base address = $5000

	lda	#$5280
	sta	$2116

	ldx #$0008
	fill_outer_loop:

		ldy	#$0020
		fill_loop:

			txa
			cmp #$07
			bcc fill_later_line

			and #$01
			ora	#$04
			jmp fill_one_end

			fill_later_line:

				tya
				and #$1
				bne fillcol_2

				; pattern = !(x & 1)
				txa
				and #$1
				eor #$1
				jmp fillcol_add_base

				; pattern = (x & 1)
				fillcol_2:
				txa
				and #$1

				fillcol_add_base:
				ora #$02

			fill_one_end:

			sta	$2118
		dey
		bne	fill_loop

	dex
	bne fill_outer_loop

	ply
	plx
	pla
	rts
.endproc

; == Sub
; MUST UNDER: A16, I16
.proc fillBGWall
	pha
	phx
	phy

	; Init random
	lda #$2345
	sta gRandomReg

	; Make image on the work area
	ldy #$00
	ldx #$2a0
	fillloop:

	jsr advanceRandomRegister
	lda gRandomReg
	and #$03
	ora #$08

	sta gWorkArea, y

	iny
	iny
	dex
	bne fillloop


	; Transfer
	mWaitVBlankEnd

	ldx #$2a0
	ldy #$00

	lda	#$5000
	sta	$2116

	transloop:
	lda gWorkArea, y
	sta	$2118

	iny
	iny
	dex
	bne transloop


	ply
	plx
	pla
	rts
.endproc



; == Sub
; MUST UNDER: A16, I16
; in X: 0=Close, 1=Open
.proc fillMessageWindowArea
	php
	pha
	phx
	phy

	; base address = $4000

	txa
	tay
	; Y = Open/Close

	; Row 1
	lda	#$4102
	sta	$2116

	ldx #$10
	jsr fillWindowRow


	; Row 2
	lda	#$4122
	sta	$2116

	ldx #$14
	jsr fillWindowRow


	; Row 3
	lda	#$4142
	sta	$2116

	ldx #$14
	jsr fillWindowRow


	; Row 4
	lda	#$4162
	sta	$2116

	ldx #$18
	jsr fillWindowRow


	ply
	plx
	pla
	plp
	rts
.endproc


; == Sub
; MUST UNDER: A16, I16
; in X: Tile base
; in Y: 0=Close, 1=Open
.proc fillWindowRow
	php
	pha
	phx
	phy

	tya
	bne use_open_ptn

	; when closed
	ldx #$1c

	use_open_ptn:

	; Left end
	txa
	sta	$2118
	inx


	; Middle
	ldy #$1a ; 26 columns
	fillwnd_start:

	txa
	sta	$2118

	dey
	bne fillwnd_start


	; Right end
	inx
	txa
	sta	$2118

	ply
	plx
	pla
	plp
	rts
.endproc

; == Sub
; MUST UNDER: A16, I16
.proc advanceTalkingAnimation
	php
	pha
	phx

	lda gTalkingCount
	cmp #$60 ; 12*8
	bcs tk_max

	lda gTalkingCount
	and #$07
	bne no_put_letter ; (gTalkingCount % 8) != 0

	; Put a letter
	lda gTalkingCount
	lsr
	lsr
	lsr
	; Letter index = gTalkingCount / 8
	tax
	jsr putTalkingWindowChar

	no_put_letter:

	inc gTalkingCount
	tk_max:


	; Show effect when the talk has finished
	lda gTalkingCount
	eor #$5f
	bne no_fxstart
	lda #$01
	sta gEffectAnimationCount

	no_fxstart:

	plx
	pla
	plp
	rts
.endproc

; == Sub
; MUST UNDER: A16, I16
; in X: char index
.proc putTalkingWindowChar
	php
	pha
	phx

	txa
	asl
	tax

	; Row1 base address
	clc
	txa
	adc #$4123 ; 4123 + x*2
	sta	$2116

	clc
	txa
	adc #$20
	sta	$2118

	inc
	sta	$2118

	; Row2 base address
	clc
	txa
	adc #$4143 ; 4143 + x*2
	sta	$2116

	clc
	txa
	adc #$40
	sta	$2118

	inc
	sta	$2118

	plx
	pla
	plp
	rts
.endproc

.proc updateEffectAnimationStatus
	php
	pha
	phx

	lda gEffectAnimationCount
	beq fxup_end

	inc gEffectAnimationCount

	; 24 -> reset count
	lda gEffectAnimationCount
	eor #$18
	bne fxup_end
	lda #$01
	sta gEffectAnimationCount


	fxup_end:

	plx
	pla
	plp
	rts
.endproc

.proc updateEffectSprite
	php
	pha
	phx
	phy

	lda gEffectAnimationCount

	clc
	lsr
	lsr
	beq fxsp_hide

	cmp #$04
	bcs fxsp_hide
	; (count/2) >= 4 || (count/2) == 0 -> hide

	clc
	asl
	asl
	adc #$c0
	tax ; Tile Index: X <- (A * 4) + 0xc0

	; Update sprite
	;   Tile
	lda kFxSpriteIndex
	ldy #$01
	jsr changeSpriteTile

	;   Position

	;   y + rand
	clc
	lda gRandomReg
	lsr
	lsr
	lsr
	and #$0f
	adc gPlayerY
	sbc #$0f
	tay

	lda kFxSpriteIndex
	jsr calcEffectSpritePosition ; x will be set
	jsr setSpritePosition

	jsr isEffectPositionNegative ; x will be set
	ldy #$00
	jsr setSpriteNrgativeXFlag

	jmp fxsp_end
	fxsp_hide:

	; Update random register (only when talking)
	lda gTalkingFlag
	and #$01
	beq nouprand
	jsr advanceRandomRegister
	nouprand:

	; Hide (go out) the sprite
	lda kFxSpriteIndex
	ldx #$00
	ldy #$e0
	jsr setSpritePosition

	fxsp_end:

	ply
	plx
	pla
	plp
	rts
.endproc

; in X: x coordinate
; out X: negative?
.proc isEffectPositionNegative
	pha

	txa
	bpl noneg

	ldx #$01

	jmp endif
	noneg:

	ldx #$00

	endif:

	pla
	rts
.endproc

; out X: result x coordinate
.proc calcEffectSpritePosition
	php
	pha

	; Set on the center
	clc
	lda gPlayerX
	sbc kPlayerXOffset
	sbc kPlayerXOffset
	tax

	; Offset
	clc
	lda gPlayerDirFlag
	and #$0f
	bne no_ofs

	inx
	inx
	inx

	no_ofs:

	jsr applyRandomOffset

	pla
	plp
	rts
.endproc

.proc advanceRandomRegister
	php
	pha
	phy


	ldy gRandomReg
	tya
	and #$0001
	eor gRandomReg
	sta gRandomReg

	tya
	and #$0004
	lsr
	lsr
	eor gRandomReg
	sta gRandomReg
	
	tya
	and #$0008
	lsr
	lsr
	lsr
	eor gRandomReg
	sta gRandomReg

	tya
	and #$0020
	lsr
	lsr
	lsr
	lsr
	lsr
	eor gRandomReg

	asl
	asl
	asl
	asl
	asl
	asl
	asl
	asl
	asl
	asl
	asl
	asl
	asl
	asl
	asl
	sta gRandomReg

	tya
	lsr
	ora gRandomReg
	sta gRandomReg


	ply
	pla
	plp
	rts
.endproc

; out X: in X + random
.proc applyRandomOffset
	php
	pha

	lda gRandomReg
	and #$1f
	sta gSpritePosTemp
	
	txa
	clc
	adc gSpritePosTemp
	tax

	pla
	plp
	rts
.endproc


.proc EmptyInt
	rti
.endproc

; カートリッジ情報
.segment "CARTINFO"
	.byte	"WALKTEST             "	; Game Title
	.byte	$00				; 0x01:HiRom, 0x30:FastRom(3.57MHz)
	.byte	$00				; ROM only
	.byte	$08				; 32KB=256KBits
	.byte	$00				; RAM Size (8KByte * N)
	.byte	$00				; NTSC
	.byte	$01				; Licensee
	.byte	$00				; Version
	.byte	$9a, $46, $65, $b9		; checksum(empty here)
	.byte	$ff, $ff, $ff, $ff		; unknown

	.word	EmptyInt	; Native:COP
	.word	EmptyInt	; Native:BRK
	.word	EmptyInt	; Native:ABORT
	.word	VBlank		; Native:NMI
	.word	$0000		; 
	.word	EmptyInt	; Native:IRQ

	.word	$0000	; 
	.word	$0000	; 

	.word	EmptyInt	; Emulation:COP
	.word	EmptyInt	; 
	.word	EmptyInt	; Emulation:ABORT
	.word	VBlank		; Emulation:NMI
	.word	Reset		; Emulation:RESET
	.word	EmptyInt	; Emulation:IRQ/BRK
