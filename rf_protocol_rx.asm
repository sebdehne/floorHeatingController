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


#define	c_read_max_len		.15

; 4Mhz:
;#define	c_read_max_error	.1
;#define	c_read_double		.4
;#define	c_read_timeout		.9

; 8Mhz:
#define	c_read_max_error	.1
#define	c_read_double		.50
#define	c_read_timeout		.90

RfRxData					udata 0x50 ; 22 bytes
rssi						res	1
timer						res	1
f_read_bit_string_err_cnt	res	1
f_read_bit_string_buf		res	1
f_read_bit_string_buf_pos	res	1
f_get_rssi_max_hi			res	1
f_get_rssi_max_lo			res	1
DelayCounter1				res	1
DelayCounter2				res	1
MsgBuffer					res	10
RfRxMsgLen					res	1
	global	MsgBuffer
	global	RfRxMsgLen

	code

RF_RX_Init
	global	RF_RX_Init

	; configure comparator module C1
	banksel	ANSEL
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

RF_RX_ReceiveMsg
	global	RF_RX_ReceiveMsg
	
	; try to read a message from the air
	call	RF_RX_ReadBitString ; perform reading now
	; Done reading
	
	bcf		STATUS, Z
	btfss	rssi, 6 
	goto	RF_RX_ReceiveMsg_error
	
	; test that RfRxMsgLen != 0
	movfw	RfRxMsgLen
	ANDLW	0xFF
	goto	RF_RX_ReceiveMsg_done

RF_RX_ReceiveMsg_error	
	bsf		STATUS, Z
	goto	RF_RX_ReceiveMsg_done

RF_RX_ReceiveMsg_done
	return
	
;
;
; rssi variable bit explaination:
; rssi, 0 => rssi (the read value)
; rssi, 1 => currentlyReading (boolean whether we are currently busy reading or standby)
; rssi, 2 => reading what (which value are we currently reading)
; rssi, 3 => double (boolean to indicate whether this read cycle seems to be a double)
; rssi, 4 => is first bit (boolean to indicate whether this seems to be the start-bit)
; rssi, 5 => timeout detected (argument for buffer())
; rssi, 6 => return value for both f_read_bit_string and add_buffer() (1 == OK; 0 == failure)
; rssi, 7 => true: currently reading 1/2 of a set of encoded bits (decoding state; used in f_add_buffer())
; upon return:
;   RfRxMsgLen contains the length of the msg
; 
RF_RX_ReadBitString
	; configure the address to which we write the current byte
	movlw	LOW MsgBuffer
	movwf	FSR
	bcf		STATUS, IRP
	clrf	rssi
	clrf	RfRxMsgLen
	incf	RfRxMsgLen, F ; we count 1, 2, 3, etc (instead of 0, 1, 2, 3)
	movlw	d'8'
	movwf	f_read_bit_string_buf_pos
f_read_bit_string_loop
	call	RF_RX_GetRSSI
	btfss	rssi, 1
	goto	_not_reading
	goto	_reading
_not_reading
	btfss	rssi, 0
	goto	f_read_bit_string_loop ; we are not reading and have received a 0
_switch_to_reading
	clrf	timer
	incf	timer, F
	bsf		rssi, 1 ; currentlyReading => 1
	bsf		rssi, 2 ; readingValue HI
	bsf		rssi, 4 ; is first bit
	movlw	c_read_max_error          ; pre-load the error-counter
	movwf	f_read_bit_string_err_cnt
	goto	f_read_bit_string_loop
_reading
	INCF	timer, F
	btfsc	rssi, 2
	goto	_reading_high
_reading_low
	btfss	rssi, 0
	goto	_reading_low_continue
_reading_low_switch_to_hi
	; can we tolerate this as an error
	decfsz	f_read_bit_string_err_cnt, F
	goto	f_read_bit_string_loop    ; we are inside the toleranse range, skip event
	call	f_buffer_add
	btfss	rssi, 6
	goto	_done ; ERROR detected
	bsf		rssi, 2 ; no error, continue
	bcf		rssi, 3
	clrf	timer
	movlw	c_read_max_error          ; pre-load the error-counter
	movwf	f_read_bit_string_err_cnt
	;addwf	timer, F
	goto	f_read_bit_string_loop
_reading_low_continue
	; check for double bits
	movfw	timer
	SUBLW	c_read_double
	btfsc	STATUS, Z
	bsf		rssi, 3 ; gone over double limit
	; check for timeout
	movfw	timer
	SUBLW	c_read_timeout
	btfss	STATUS, Z
	goto	f_read_bit_string_loop ; read more
	; timeout reached, we are finished
	bsf		rssi, 5
	call	f_buffer_add
	decf	RfRxMsgLen, F
	goto	_done ; OK, we are done: Using the return value from buffer_add
_reading_high
	btfss	rssi, 0
	goto	_reading_high_switch_to_low
_reading_high_continue
	movfw	timer
	SUBLW	c_read_double
	btfsc	STATUS, Z
	bsf		rssi, 3 ; gone over double limit
	movfw	timer
	SUBLW	c_read_timeout
	btfss	STATUS, Z
	goto	f_read_bit_string_loop ; read more
	; timeout
	bcf		rssi, 6 ; report failure
	goto	_done
_reading_high_switch_to_low
	; can we tolerate this as an error
	decfsz	f_read_bit_string_err_cnt, F
	goto	f_read_bit_string_loop    ; we are inside the toleranse range, skip event
	btfss	rssi, 4 ; Was this the first bit?
	goto	_add    ; no it was not, add bit to buffer
	bcf		rssi, 4 ; Yes it was. Clear the first-bit boolean
	btfss	rssi, 3 ; Is this a double as well?
	goto	_reading_high_switch_to_low_done ; no it was not a double, then continue reading low without adding
	bcf		rssi, 3 ; yes it was, clear double flag to skip the first bit
_add
	call	f_buffer_add
	btfss	rssi, 6
	goto	_done ; ERROR detected
_reading_high_switch_to_low_done
	bcf		rssi, 2 ; going to read low
	bcf		rssi, 3 ; 
	clrf	timer
	movlw	c_read_max_error          ; pre-load the error-counter
	movwf	f_read_bit_string_err_cnt
	;addwf	timer, F
	goto	f_read_bit_string_loop
_done
	return
f_buffer_add	; inner sub to store the read value into the buffer
	; test for max_len
	movfw	RfRxMsgLen
	sublw	c_read_max_len
	btfsc	STATUS, Z
	goto	f_buffer_add_failure ; we went over max
	; ----- BEGIN adding bit to buffer -----
	btfss	rssi, 7 ; was last bit un-decoded?
	goto	f_buffer_add_undecoded
f_buffer_add_decoded
	bcf		rssi, 7 ; so that we know in what state we are
	btfss	f_read_bit_string_buf, 7
	goto	f_buffer_add_decoded_low 
f_buffer_add_decoded_hi              ; previous bit was a 1
	btfsc	rssi, 2
	goto	f_buffer_add_failure
	bcf		f_read_bit_string_buf, 7 ; "10" -> "0"
	goto	f_buffer_add_done	
f_buffer_add_decoded_low             ; previous bit was a 0
	btfss	rssi, 2
	goto	f_buffer_add_failure
	bsf		f_read_bit_string_buf, 7 ; "01" -> "1"
	goto	f_buffer_add_done	
f_buffer_add_undecoded
	; pre-load the current bit into C
	bcf		STATUS, C
	btfsc	rssi, 2
	bsf		STATUS, C
	; shift C into the buffer
	rrf		f_read_bit_string_buf, F
	bsf		rssi, 7 ; so that we know in what state we are
	goto	f_buffer_add_done
f_buffer_add_failure
	bcf		rssi, 6 ; failure detected during decoding
	goto	f_buffer_add_completed
	; ----- END adding bit to buffer -----
f_buffer_add_done
	btfsc	rssi, 7
	goto	f_buffer_add_done_next
	decfsz	f_read_bit_string_buf_pos, F
	goto	f_buffer_add_done_next
	; buffer register full,  store it in memory and get ready for next round
	movlw	d'8'
	movwf	f_read_bit_string_buf_pos
	
	; store the byte now
	movfw	f_read_bit_string_buf
	movwf	INDF
	; set the pointer one address forward
	incf	FSR, F
	; update the number of bytes stores in the buffer so far
	incf	RfRxMsgLen, F
f_buffer_add_done_next
	; Done adding bit, do we need to add another one?
	bsf		rssi, 6 ; no failure at this point, set return value
	btfss	rssi, 3 ; was it a double
	goto	f_buffer_add_completed ; no it was not
	btfsc	rssi, 5 ; yes it was, was it a timeout as well?
	goto	f_buffer_add_completed ; yes. timeout & double => single add. Thus we are done
	bcf		rssi, 3 ; no it was not, thus add a second bit to the buffer
	goto	f_buffer_add
f_buffer_add_completed
	bcf		rssi, 5 ; clear input argument
	return
	
; reads current status from the receiver using the RSSI port
; set bit 0 in "rssi" to the read value (1 for hi, 0 for low)
RF_RX_GetRSSI
	banksel	CM1CON0
	btfsc	CM1CON0, C1OUT
	goto	RF_RX_GetRSSI_hi
	goto	RF_RX_GetRSSI_lo
RF_RX_GetRSSI_hi
	banksel	PORTA
	bsf		rssi, 0
	goto	RF_RX_GetRSSI_done
RF_RX_GetRSSI_lo
	banksel	PORTA
	bcf		rssi, 0
	goto	RF_RX_GetRSSI_done
RF_RX_GetRSSI_done	
	return
	

Delay_1ms
	if CLOCKSPEED == .4000000
			;993 cycles
		movlw	0xC6
		movwf	DelayCounter1
		movlw	0x01
		movwf	DelayCounter2
	else
		if CLOCKSPEED == .8000000
					;1993 cycles
			movlw	0x8E
			movwf	DelayCounter1
			movlw	0x02
			movwf	DelayCounter2
		else
			error "Unsupported clockspeed
		endif
	endif
Delay_1ms_0
	decfsz	DelayCounter1, f
	goto	$+2
	decfsz	DelayCounter2, f
	goto	Delay_1ms_0

			;3 cycles
	goto	$+1
	nop
			;4 cycles (including call)
	return

	end