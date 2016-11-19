	errorlevel  -302

#include "config.inc"


#ifndef RF_RX_PORT_RSSI
	error	"RF_RX_PORT_RSSI must be defined, for example: PORTA,0"
#endif
#ifndef RF_RX_PORT_RSSI_REF
	error	"RF_RX_PORT_RSSI_REF must be defined, for example: PORTA,0"
#endif
#ifndef RF_RX_LOCAL_ADDR
	error	"RF_RX_LOCAL_ADDR must be defined, for example: .1"
#endif
#ifndef CLOCKSPEED
	error	"CLOCKSPEED must be defined, for example: .8000000"
#endif


#define	BUFFER_LEN		15
#define	SUBLW_BUFFER_LEN	sublw	.15	


RfRxData					udata 0x50 ; 24 bytes
RfRxMsgBuffer				res BUFFER_LEN
RfRxMsgLen					res 1 ; counts number of bytes recorded in buffer
BitBuffer					res 1 ; used to record bits
BitLen						res 1 ; counts down towards zero, indicating remaining number og bits to read for this byte
Value						res 1 ; hold the current RSSI value
d1							res 1 ;
d2							res 1 ;
temp						res 2 ; 
RfRxReceiveResult			res 1 ; return value of receive routine.
	global	RfRxMsgBuffer
	global	RfRxMsgLen
	global	RfRxReceiveResult


	; imported from the crc16 module
	extern	REG_CRC16_LO
	extern	REG_CRC16_HI
	extern	CRC16

	code

RF_RX_Init
	global	RF_RX_Init

	; configure comparator module C1
	banksel	ANSEL ; 
	BSF		ANSEL, ANS0	; C1IN+
	BSF		ANSEL, ANS1	; C12IN0-
	banksel	TRISA
	BSF		TRISA, ANS0	; C1IN+
	BSF		TRISA, ANS1	; C12IN0-
	banksel	CM1CON0
	movlw	b'10000000'
	movwf	CM1CON0

	banksel	PORTA	; assume that this was the state upon entry :-)
	
	return

;
; RfRxReceiveResult == 1 -> Success
; RfRxReceiveResult == 2 -> Error, in the middle of a byte
; RfRxReceiveResult == 3 -> buffer overflow
; RfRxReceiveResult == 4 -> message length too low
; RfRxReceiveResult == 5 -> invalid crc16
RF_RX_ReceiveMsg
	global	RF_RX_ReceiveMsg

	; read message from the air into RfRxMsgBuffer
	call	ReadMessage

	; only continue if RfRxReceiveResult == 1
	movfw	RfRxReceiveResult
	sublw	.1
	btfss	STATUS, Z
	goto	RF_RX_ReceiveMsg_done
	
	; validate message length; need at least 6: DST, SRC, LEN, MSG1, CRC16, CRC16
	movfw	RfRxMsgLen
	sublw	.6
	btfss	STATUS, C
	goto	RF_RX_ReceiveMsg_msg_len_ok  ; message len > 6
	btfsc	STATUS, Z
	goto	RF_RX_ReceiveMsg_msg_len_ok	 ; message len == 6
	movlw	.4							 ; message len < 6
	movwf	RfRxReceiveResult
	goto	RF_RX_ReceiveMsg_done
RF_RX_ReceiveMsg_msg_len_ok

	;
	; validate CRC16 
	;
    clrf    REG_CRC16_LO
    clrf    REG_CRC16_HI
    movfw	RfRxMsgLen
    movwf	temp
	decf	temp, F ; do that we don't use the CRC itself in the calc
	decf	temp, F ; do that we don't use the CRC itself in the calc
	; configure the address to which we write the current byte
	movlw	LOW	RfRxMsgBuffer
	movwf	FSR
	bcf		STATUS, IRP
RF_RX_ReceiveMsg_crc_loop
	movfw	INDF
	call	CRC16
	incf	FSR, F
	decfsz	temp, F
	goto	RF_RX_ReceiveMsg_crc_loop
	
	; 
	; 2) Does CRC match?
	; 
	; read the 1st crc byte
	movfw	INDF
	SUBWF	REG_CRC16_LO, F
	btfss	STATUS, Z
	goto	RF_RX_ReceiveMsg_crc_error
	; set the pointer one address forward
	incf	FSR, F
	; read the 2nd crc byte
	movfw	INDF
	SUBWF	REG_CRC16_HI, F
	btfss	STATUS, Z
	goto	RF_RX_ReceiveMsg_crc_error
	goto	RF_RX_ReceiveMsg_crc_ok

RF_RX_ReceiveMsg_crc_error
	movlw	.5
	movwf	RfRxReceiveResult
	goto	RF_RX_ReceiveMsg_done
RF_RX_ReceiveMsg_crc_ok

	; done

RF_RX_ReceiveMsg_done
	return

;
; waits for a message to arrive and stores it into RfRxMsgBuffer and
; uses RfRxMsgLen to report number of bytes received. Possible return values:
;
; RfRxReceiveResult == 1 -> Success
; RfRxReceiveResult == 2 -> Ended in the middle of a byte
; RfRxReceiveResult == 3 -> went over BUFFER_LEN
;
; One complete bit (0->1 or 1->0) is assumed to take around 1ms
ReadMessage
	movlw	.2
	movwf	RfRxReceiveResult
	clrf	BitBuffer
	clrf	RfRxMsgLen
	movlw	.8
	movwf	BitLen
	movlw	LOW RfRxMsgBuffer
	movwf	FSR
	bcf		STATUS, IRP
ReadMessage_not_reading
	call	ReadValue
	btfss	Value, 0
	goto	ReadMessage_not_reading
ReadMessage_reading_bit
	call	Delay_750us
	call	ReadValue
	btfss	Value, 0
	goto	ReadMessage_reading_01
	goto	ReadMessage_reading_10

ReadMessage_reading_01 ; wait for 1 or give up after 0,5ms / 500us / (4Mhz: 500 cycles OR 8Mhz: 1000 cycles)
	if CLOCKSPEED == .4000000
	movlw	.22 ; 22 * 23 cycles = 506 cycles
	else 
	if CLOCKSPEED == .8000000
	movlw	.45 ; 45 * 23 cycles = 1035 cycles
	endif
	endif
	movwf	d1
ReadMessage_reading_01_loop ; 22 cycles
	decfsz	d1, F										; 1
	goto	ReadMessage_reading_01_ntimeout		; 2
	goto	ReadMessage_done 							; give up with RfRxReceiveResult
ReadMessage_reading_01_ntimeout
	call	ReadValue									; 17
	btfss	Value, 0									; 1
	goto	ReadMessage_reading_01_loop			; 2
	call	RecordBitHi
	goto	ReadMessage_reading_common
ReadMessage_reading_10
	; wait for 0
	call	ReadValue
	btfsc	Value, 0
	goto	ReadMessage_reading_10
	call	RecordBitLo
	goto	ReadMessage_reading_common
ReadMessage_reading_common
	; test for overflow
	movfw	RfRxReceiveResult
	sublw	.3
	btfsc	STATUS, Z
	goto	ReadMessage_done			; give up with RfRxReceiveResult == 3 - overflow
	goto	ReadMessage_reading_bit 	; continue reading
ReadMessage_done
	return

; Adds the bit from Value,0 to the buffer
;
; RfRxReceiveResult == 1 -> OK
; RfRxReceiveResult == 2 -> OK, but in the middle of a byte
; RfRxReceiveResult == 3 -> went over BUFFER_LEN
;
; 28 cycles inlucing the call instruction
RecordBitHi					; 2
	bsf		STATUS, C		; 1
	rrf		BitBuffer, F	; 1
	goto	RecordBit_cnt	; 2
RecordBitLo	
	bcf		STATUS, C
	rrf		BitBuffer, F
	goto	RecordBit_cnt
RecordBit_cnt ; 6
	decfsz	BitLen, F	; are we done reading a whole byte?
	goto	RecordBit_keep_reading_byte	; not done reading a whole byte
	goto	RecordBit_record_byte
RecordBit_keep_reading_byte
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	movlw	.2					; 1
	movwf	RfRxReceiveResult		; 1
	goto	RecordBit_done		; 2
RecordBit_record_byte
	; done reading a byte, but it into the buffer
	movfw	BitBuffer			; 1
	movwf	INDF				; 1
	; prepare for the next byte
	incf	FSR, F				; 1
	incf	RfRxMsgLen, F		; 1
	movlw	.8					; 1
	movwf	BitLen				; 1
	; test if buffer is full
	movfw	RfRxMsgLen	
#SUBLW_BUFFER_LEN
	btfss	STATUS, Z			; 2
	goto	RecordBit_record_byte_nooverfl	; 2
	goto	RecordBit_record_byte_overflow		; 2
RecordBit_record_byte_nooverfl
	nop
	movlw	.1
	movwf	RfRxReceiveResult
	goto	RecordBit_done
RecordBit_record_byte_overflow
	movlw	.3					; 1
	movwf	RfRxReceiveResult		; 1
	goto	RecordBit_done		; 2
RecordBit_done
	return

; read the current RSSI value and stores it in Value,0
; 17 cycles inlucing the call instruction
ReadValue					; 2
	banksel	CM1CON0			; 2
	btfsc	CM1CON0, C1OUT  ; 2
	goto	ReadValue_hi	; 2
	goto	ReadValue_lo	; 2
ReadValue_hi
	nop
	banksel	PORTA			; 2
	bsf		Value,0			; 1
	goto	ReadValue_done	; 2
ReadValue_lo
	banksel	PORTA			; 2
	bcf		Value,0			; 1
	goto	ReadValue_done	; 2
ReadValue_done
	return					; 2

	if CLOCKSPEED == .8000000
Delay_750us
			;1493 cycles
	movlw	0x2A
	movwf	d1
	movlw	0x02
	movwf	d2
Delay_750us_0
	decfsz	d1, f
	goto	$+2
	decfsz	d2, f
	goto	Delay_750us_0

			;3 cycles
	goto	$+1
	nop

			;4 cycles (including call)
	return
	else
	if CLOCKSPEED == .4000000
Delay_750us
			;745 cycles
	movlw	0xF8
	movwf	d1
Delay_750us_0
	decfsz	d1, f
	goto	Delay_750ns_0

			;1 cycle
	nop

			;4 cycles (including call)
	return
	endif
	endif

	end