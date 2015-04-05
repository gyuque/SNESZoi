.macro mWaitVBlankStart
	.local vbwait

	sep	#$20
.a8

vbwait:
	lda $4210
	and #$80
	bne vbwait

	rep	#$20
.a16

.endmacro


.macro mWaitVBlankEnd
	.local vewait

	sep	#$20
.a8

vewait:
	lda $4210
	and #$80
	beq vewait

	rep	#$20
.a16

.endmacro
