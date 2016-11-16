;**********************************************
; Module for a wireless data transmission
;
; Based on manchester encoding
;
;**********************************************

#include "config.inc"

#ifndef CLOCKSPEED
	error	"CLOCKSPEED must be defined, for example: .8000000"
#endif
#ifndef	RF_TX_PORT
	error	"RF_TX_PORT must be defined, for example: PORTA, 0"
#endif
#ifndef	RF_DST_ADDR
	error	"RF_DST_ADDR must be defined, for example: .1"
#endif
#ifndef	RF_SRC_ADDR
	error	"RF_DST_ADDR must be defined, for example: .2"
#endif



RfTxData		udata 0x40; 8 bytes
Temp			res	1
Temp2			res	1
Counter			res	1
d1				res	1
d2				res	1
RfTxMsgAddr		res	1
RfTxMsgLen		res	1
	global	RfTxMsgAddr
	global	RfTxMsgLen

	; From the crc16.asm module
	extern	REG_CRC16_LO
	extern	REG_CRC16_HI
	extern	CRC16

	code
	
RF_TX_Init
	global	RF_TX_Init

	banksel	TRISA
	bcf		TRISA, 2 ; PORTA2 as output
	banksel	PORTA

	call	RF_TX_End
	return
	
RF_TX_SendMsg
	global	RF_TX_SendMsg
	
	; calculate the CRC16
	call	RF_Calc_CRC16	
	
	; send the start-bit
	call	RF_TX_Start

	; send the dst
	movlw	RF_DST_ADDR
	call	RF_TX_SendW
	; send the src
	movlw	RF_SRC_ADDR
	call	RF_TX_SendW
	; send the len
	movfw	RfTxMsgLen
	call	RF_TX_SendW
	; send the content

	movfw	RfTxMsgAddr
	movwf	FSR
	bcf		STATUS, IRP
RF_TX_SendMsg_Loop
	movfw	INDF
	call	RF_TX_SendW
	incf	FSR, F
	decfsz	RfTxMsgLen, F
	goto	RF_TX_SendMsg_Loop

	
	; transmit the crc1
	movfw	REG_CRC16_LO
	call	RF_TX_SendW
	; transmit the crc2
	movfw	REG_CRC16_HI
	call	RF_TX_SendW

	; send the stop-bit
	call	RF_TX_End


	call	BitDelay
	call	BitDelay
	call	BitDelay
	return
	
RF_Calc_CRC16
	clrf	REG_CRC16_LO
	clrf	REG_CRC16_HI
	
	movlw	RF_DST_ADDR
	call	CRC16
	movlw	RF_SRC_ADDR
	call	CRC16
	movfw	RfTxMsgLen
	call	CRC16
	
	; the msg itself
	movfw	RfTxMsgLen  ; copy the len
	movwf	Temp

	movfw	RfTxMsgAddr
	movwf	FSR
	bcf		STATUS, IRP
RF_Calc_CRC16_Loop
	movfw	INDF	; pick up the value at specified addr
	call	CRC16
	incf	FSR, F
	decfsz	Temp, F
	goto	RF_Calc_CRC16_Loop

	; done
	return

RF_TX_Start
	bsf		RF_TX_PORT
	call 	BitDelay
	return
	
RF_TX_SendW
	movwf	Temp
	movlw	.8 			; transmit 8 bits
	movwf	Counter
_f_transmit_w_next
	rrf		Temp, F
	btfsc	STATUS, C
	goto	_f_transmit_w_hi
_f_transmit_w_lo
	bsf		RF_TX_PORT
	call	BitDelay
	bcf		RF_TX_PORT
	call	BitDelay
	goto	_f_transmit_w_done
_f_transmit_w_hi
	bcf		RF_TX_PORT
	call	BitDelay
	bsf		RF_TX_PORT
	call	BitDelay
	goto	_f_transmit_w_done
_f_transmit_w_done
	decfsz	Counter, F
	goto 	_f_transmit_w_next
	return
	
RF_TX_End
	bcf		RF_TX_PORT
	call 	BitDelay
	return

_f_transmit_w
	return
	

; 8Mhz
	if CLOCKSPEED == .8000000
_delay_10us
			;16 cycles
	movlw	0x05
	movwf	d1
_delay_10us_0
	decfsz	d1, f
	goto	_delay_10us_0

			;4 cycles (including call)
	return
	else 
	if .4000000
_delay_10us
			;6 cycles
	goto	$+1
	goto	$+1
	goto	$+1

			;4 cycles (including call)
	return
	endif
	endif

; 4Mhz

BitDelay ; 0.0005 s
	if CLOCKSPEED == .4000000
		movlw	0xA5
		movwf	d1
	else
		if CLOCKSPEED == .8000000
			movlw	0xC6
			movwf	d1
			movlw	0x01
			movwf	d2
		else
			error "Unsupported clockspeed"
		endif
	endif
BitDelay_loop
	if CLOCKSPEED == .4000000
		decfsz	d1, f
		goto	BitDelay_loop
	else
		if CLOCKSPEED == .8000000
			decfsz	d1, f
			goto	$+2
			decfsz	d2, f
			goto	BitDelay_loop
			goto	$+1
			nop
		else
			error "Unsupported clockspeed"
		endif
	endif
	return
	
	end