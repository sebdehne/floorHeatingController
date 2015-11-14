	errorlevel  -302


	#include "config.inc" 
	
	__CONFIG       _CP_OFF & _CPD_OFF & _WDT_OFF & _BOR_OFF & _PWRTE_ON & _INTRC_OSC_NOCLKOUT  & _MCLRE_OFF & _FCMEN_OFF & _IESO_OFF
	
	
	udata
d1				res	1
d2				res 1
d3				res	1
Values			res	9 ; 2temp + 2humidity + 2light + 2batvolt + 1counter


	; imported from the ChipCap2 module
	extern	ChipCap2_Init				; method
	extern	ChipCap2_get_all			; method
	extern	ChipCap2_before_power_on	; method
	extern	ChipCap2_after_power_off	; method
	extern	ChipCap2_databuffer			; two bytes for humidity & two bytes for temp
	; imported from the rf_protocol_tx module
	extern	MsgAddr
	extern	MsgLen
	extern	RF_TX_Init
	extern	RF_TX_SendMsg
	


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

	; Configure the watch-dog timer, but disable it for now
	banksel	OPTION_REG
;	movlw	b'00001110' ; 110 == 64 pre-scaler & WDT selected
	movlw	b'00001110' ; 111 == 128 pre-scaler & WDT selected
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
	movlw	b'00010110' ; 1011 == 65536 ((65536 * 128 (pre-scale))/32000Hz = ~ 4,37 min)
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
	movlw	b'00001000' ; AN11 is analog
	movwf	ANSELH

	; Configure PortA
	BANKSEL TRISA
	movlw	b'00000000' ; all output
	movwf	TRISA
	
	; Configure PortB
	BANKSEL	TRISB
	movlw	b'00100000' ; all output, but RB5/AN11 is input
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
	call	RF_TX_Init
	call	ChipCap2_Init

	; reset values
	clrw
	movwf	Values
	movwf	Values+1
	movwf	Values+2
	movwf	Values+3
	movwf	Values+4
	movwf	Values+5
	movwf	Values+6
	movwf	Values+7
	movwf	Values+8

	; init done

_main
	; sleep
	; watch-dog timer is used for wake-up
	banksel	WDTCON
	bsf		WDTCON, SWDTEN
	SLEEP
	banksel	WDTCON
	bcf		WDTCON, SWDTEN

	call	power_on

	;========================================
	; start - measure temp & humidity
	;========================================
	call	ChipCap2_get_all

	; move temp data into main buffer
	banksel	ChipCap2_databuffer
	movfw	ChipCap2_databuffer
	banksel	Values
	movwf	Values
	banksel	ChipCap2_databuffer
	movfw	ChipCap2_databuffer+1
	banksel	Values
	movwf	Values+1
	; move humidity data into main buffer
	banksel	ChipCap2_databuffer
	movfw	ChipCap2_databuffer+2
	banksel	Values
	movwf	Values+2
	banksel	ChipCap2_databuffer
	movfw	ChipCap2_databuffer+3
	banksel	Values
	movwf	Values+3
	;========================================
	; done - measure temp & humidity
	;========================================

	;========================================
	; start - measure light level
	;========================================
	call	light_measure
	;========================================
	; done - measure light level
	;========================================

	call	ReadBatteryVoltage

	; inc counter
	incf	Values+8, f

	;========================================
	; start - send data over RF
	;========================================
	; Load the value's location and send the msg
	movlw	HIGH	Values
	movwf	MsgAddr
	movlw	LOW		Values
	movwf	MsgAddr+1
	movlw	.9
	movwf	MsgLen
	; and transmit the data now
	call	RF_TX_SendMsg
	; done
	;========================================
	; done  - send data over RF
	;========================================

	call	power_off

	goto	_main

ReadBatteryVoltage
	; BEGIN A/D conversation
	BANKSEL ADCON0 ;
	MOVLW 	B'10110101' ;Right justify,
	MOVWF 	ADCON0 		; Vdd Vref, 0.6V-Ref, On
	call	Delay_1ms
	BSF 	ADCON0,GO ;Start conversion
	BTFSC 	ADCON0,GO ;Is conversion done?
	GOTO 	$-1       ;No, test again
	; END A/D conversation
	BANKSEL ADRESH
	movfw	ADRESH
	BANKSEL Values
	movwf	Values+6
	BANKSEL ADRESL
	movfw	ADRESL
	BANKSEL Values
	movwf	Values+7
	return

power_on

	call	ChipCap2_before_power_on

	; switch on devices
	banksel	PORTB
	bsf		PWR

	; need to give the ChipCap IC some startup time
	call	_delay_20ms; after 20ms - only zeros are returned
	call	_delay_20ms; after 40ms - only the temp is returned
	call	_delay_20ms; need at least 60ms to get all data out	return

	return

power_off
	; switch off devices
	banksel	PORTB
	bcf		PWR

	call	ChipCap2_after_power_off

	return


light_measure
	; BEGIN A/D conversation
	BANKSEL ADCON0 ;
	MOVLW 	B'10101101' ;Right justify,
	MOVWF 	ADCON0 		; Vdd Vref, AN11, On
	call	_delay_10us
	banksel	ADCON0
	BSF 	ADCON0,GO ;Start conversion
	BTFSC 	ADCON0,GO ;Is conversion done?
	GOTO 	$-1       ;No, test again
	; END A/D conversation
	BANKSEL ADRESH
	movfw	ADRESH
	BANKSEL Values
	movwf	Values+4
	BANKSEL ADRESL
	movfw	ADRESL
	BANKSEL Values
	movwf	Values+5
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
	

	end