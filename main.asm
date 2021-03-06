	errorlevel  -302


	#include "config.inc" 
	
	__CONFIG       _CP_OFF & _CPD_OFF & _WDT_ON & _BOR_OFF & _PWRTE_ON & _INTRC_OSC_NOCLKOUT  & _MCLRE_OFF & _FCMEN_OFF & _IESO_OFF

mainData		udata 0x20 ; 11 bytes -> 0x2b
d1				res	1
d2				res 1
d3				res	1
temp			res 1
Values			res	5 ; 2temp + 2humidity + 1heater


	; imported from the rf_protocol_tx module
	extern	RfTxMsgAddr
	extern	RfTxMsgLen
	extern	RF_TX_Init
	extern	RF_TX_SendMsg
	; imported from the rf_protocol_rx module
	extern	RF_RX_Init			; method
	extern	RF_RX_ReceiveMsg	; method
	extern	RfRxMsgBuffer  		; variable
	extern	RfRxMsgLen		    ; variable
	extern	RfRxReceiveResult	; variable
	; imported from the crc16 module:
	extern	REG_CRC16_HI	; variable
	extern	REG_CRC16_LO	; variable
	extern	CRC16			; method
	; imported from the SHT15 module
	extern	SHT15_Init
	extern	SHT15_get_temp
	extern	SHT15_get_humidity
	extern	SHT15_databuffer

Reset		CODE	0x0
	pagesel	_init
	goto	_init
	code
	
_init
	; set the requested clockspeed
	banksel	OSCCON
	if CLOCKSPEED == .8000000
		movlw	b'01110000'
	else
		if CLOCKSPEED == .4000000
			movlw	b'01100000'
		else
			error	"Unsupported clockspeed"
		endif
	endif
	movwf	OSCCON
	
	; set the OSCTUNE value now
	banksel	OSCTUNE
	movlw	OSCTUNE_VALUE
	movwf	OSCTUNE

	; Configure no watch-dog timer
	banksel	OPTION_REG
	movlw	b'00001111' ; 111 == 128 pre-scaler & WDT selected
		;	  ||||||||---- PS PreScale 
		;	  |||||||----- PS PreScale
		;	  ||||||------ PS PreScale
		;	  |||||------- PSA -  0=Assign prescaler to Timer0 / 1=Assign prescaler to WDT
		;	  ||||-------- TOSE - LtoH edge
		;	  |||--------- TOCS - Timer0 uses IntClk
		;	  ||---------- INTEDG - falling edge RB0
		;	  |----------- NOT_RABPU - pull-ups enabled
	movwf	OPTION_REG
	banksel	WDTCON
	movlw	b'00010111' ; 1011 == 65536 ((65536 * 128 (pre-scale))/32000Hz = ~ 4,37 min)
;	movlw	b'00001100' ; 0110 == 2048 ((65536 * 64 (pre-scale))/32000Hz = ~ 4 sec)
	;            |||||
	;            ||||+--- 0=disabled watchdog timer SWDTEN
	;            |||+---- pre-scaler WDTPS0
	;            ||+----- pre-scaler WDTPS1
	;            |+------ pre-scaler WDTPS2
	;            +------- pre-scaler WDTPS3
	movwf	WDTCON

	; Select the clock for our A/D conversations
	BANKSEL	ADCON1
	MOVLW 	B'01010000'	; ADC Fosc/16
	MOVWF 	ADCON1

	; all ports to digital
	banksel	ANSEL
	movlw	b'00000000'
	movwf	ANSEL
	movlw	b'00000000'
	movwf	ANSELH

	; Configure PortA
	BANKSEL TRISA
	movlw	b'00000000' ; all output
	movwf	TRISA
	
	; Configure PortB
	BANKSEL	TRISB
	movlw	b'00000000' ; all output
	movwf	TRISB
	
	; Set entire portC as output
	BANKSEL TRISC
	movlw	b'00000000'	; all output
	movwf	TRISC

	; set all output ports to LOW
	banksel	PORTA
	clrf	PORTA
	clrf	PORTB
	clrf	PORTC

	; init libraries
	call	RF_RX_Init
	call	RF_TX_Init
	call	SHT15_Init
	;call	ChipCap2_Init

	; reset values
	clrw
	movwf	Values
	movwf	Values+1
	movwf	Values+2
	movwf	Values+3
	movwf	Values+4

	; init done
	call	power_on
	
	call	BlinkLong
	call	BlinkLong

_main

	;call	Delay_5s
	;movlw	.1
	;goto	shortcut
	
	;========================================
	; Listen for command over RF
	;========================================
	; read something from the air
	call	RF_RX_ReceiveMsg

	movfw	RfRxReceiveResult
	sublw	.1
	btfss	STATUS, Z
	goto	RfError

	; 
	; Does destination match us?
	; 
	movfw	RfRxMsgBuffer
	sublw	RF_RX_LOCAL_ADDR
	btfsc	STATUS, Z
	goto	_process_msg

	; not for us
	call	BlinkLong
	goto	_main_loop_cnt

RfError		; blink out the result
	movfw	RfRxReceiveResult
	movwf	temp
loop
	call	BlinkShort
	decfsz	temp, F
	goto	loop
	goto	_main_loop_cnt

_process_msg
	; 
	; 4) process the msg - extract the command
	; 
	movlw	LOW	RfRxMsgBuffer
	movwf	FSR
	bcf		STATUS, IRP
	incf	FSR, F	; src
	incf	FSR, F	; len
	incf	FSR, F	; value
	movfw	INDF
	movwf	temp
	; command is now in temp

shortcut
	;
	; 5) which command is it?
	;
	; command 2?
	bcf		STATUS,Z
	movfw	temp
	sublw	.2
	btfsc	STATUS, Z
	goto	_main_command_2

	; command 3?
	bcf		STATUS,Z
	movfw	temp
	sublw	.3
	btfsc	STATUS, Z
	goto	_main_command_3

_main_command_1
	goto	_main_send_ack
_main_command_2
	call	HeaterOn
	goto	_main_send_ack
_main_command_3
	call	HeaterOff
	goto	_main_send_ack
	
_main_send_ack
	call	power_off
	call	Delay_100ms
	call	power_on
	
	;========================================
	; start - measure temp & humidity
	;========================================
	call	SHT15_get_temp
	movfw	SHT15_databuffer
	movwf	Values
	movfw	SHT15_databuffer+1
	movwf	Values+1

	call	SHT15_get_humidity
	movfw	SHT15_databuffer
	movwf	Values+2
	movfw	SHT15_databuffer+1
	movwf	Values+3

	;========================================
	; done - measure temp & humidity
	;========================================

	; read heater status
	movlw	.0
	btfsc	PORTA, 5
	movlw	.1
	movwf	Values+4

	;========================================
	; start - send data over RF
	;========================================
	; Load the value's location and send the msg
	movlw	LOW		Values
	movwf	RfTxMsgAddr
	movlw	.5
	movwf	RfTxMsgLen
	; and transmit the data now
	call	RF_TX_SendMsg
	; done
	;========================================
	; done  - send data over RF
	;========================================

	clrwdt ; reset WDT

_main_loop_cnt
	goto	_main


BlinkShort
	bsf		PORTA, 4
	call 	Delay_100ms
	call 	Delay_100ms
	bcf		PORTA, 4
	call 	Delay_100ms
	call 	Delay_100ms
	return
BlinkLong
	bsf		PORTA, 4
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	bcf		PORTA, 4
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	call 	Delay_100ms
	return
HeaterOn
	bsf		PORTC, 5
	bsf		PORTA, 5
	return
HeaterOff
	bcf		PORTC, 5
	bcf		PORTA, 5
	return

power_on

	; switch on devices
	bsf		PWR

	; need to give the ChipCap IC some startup time
	call	_delay_20ms; after 20ms - only zeros are returned
	call	_delay_20ms; after 40ms - only the temp is returned
	call	_delay_20ms; need at least 60ms to get all data out	return

	return

power_off
	; switch off devices
	bcf		PWR

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

	if CLOCKSPEED == .8000000
_delay_20ms
			;39993 cycles
	movlw	0x3E
	movwf	d1
	movlw	0x20
	movwf	d2
_delay_20ms_0
	decfsz	d1, f
	goto	$+2
	decfsz	d2, f
	goto	_delay_20ms_0

			;3 cycles
	goto	$+1
	nop

			;4 cycles (including call)
	return
	else 
	if CLOCKSPEED == .4000000
_delay_20ms
			;19993 cycles
	movlw	0x9E
	movwf	d1
	movlw	0x10
	movwf	d2
_delay_20ms_0
	decfsz	d1, f
	goto	$+2
	decfsz	d2, f
	goto	_delay_20ms_0

			;3 cycles
	goto	$+1
	nop

			;4 cycles (including call)
	return
	endif
	endif


Delay_1ms
	if CLOCKSPEED == .4000000
			;993 cycles
		movlw	0xC6
		movwf	d1
		movlw	0x01
		movwf	d2
	else
		if CLOCKSPEED == .8000000
					;1993 cycles
			movlw	0x8E
			movwf	d1
			movlw	0x02
			movwf	d2
		else
			error "Unsupported clockspeed
		endif
	endif
Delay_1ms_0
	decfsz	d1, f
	goto	$+2
	decfsz	d2, f
	goto	Delay_1ms_0

			;3 cycles
	goto	$+1
	nop
			;4 cycles (including call)
	return

Delay_100ms
			;199993 cycles
	movlw	0x3E
	movwf	d1
	movlw	0x9D
	movwf	d2
Delay_100ms_0
	decfsz	d1, f
	goto	$+2
	decfsz	d2, f
	goto	Delay_100ms_0

			;3 cycles
	goto	$+1
	nop

			;4 cycles (including call)
	return


Delay_5s
			;9999995 cycles
	movlw	0x5A
	movwf	d1
	movlw	0xCD
	movwf	d2
	movlw	0x16
	movwf	d3
Delay_5s_0
	decfsz	d1, f
	goto	$+2
	decfsz	d2, f
	goto	$+2
	decfsz	d3, f
	goto	Delay_5s_0

			;1 cycle
	nop

			;4 cycles (including call)
	return

	end