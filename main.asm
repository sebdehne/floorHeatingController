	errorlevel  -302


	#include "config.inc" 
	
	__CONFIG       _CP_OFF & _CPD_OFF & _WDT_OFF & _BOR_OFF & _PWRTE_ON & _INTRC_OSC_NOCLKOUT  & _MCLRE_OFF & _FCMEN_OFF & _IESO_OFF
	
	
	udata
d1				res	1
d2				res 1
d3				res	1
Values			res	7 ; 2temp + 2humidity + 2light (includes low-bat bit) + 1counter


	; imported from the sht15 module
	extern	SHT15_Init			; method
	extern	SHT15_power_on		; method
	extern	SHT15_power_off		; method
	extern	SHT15_get_temp		; method
	extern	SHT15_get_humidity	; method
	extern	SHT15_BatteryCheck	; method
	extern	SHT15_databuffer	; two byte for results
	; imported from the rf_protocol_tx module
	extern	RF_TX_PowerOn
	extern	RF_TX_PowerOff
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
	
	; setup option register
	; timer pre-scaler set to 64
	banksel	OPTION_REG
	movlw	b'00001100'	
	movwf	OPTION_REG
	; configure the watch-dog timer now
	CLRWDT
	movlw	b'00010011' ; 65536 + enable
	banksel	WDTCON
	movwf	WDTCON

	; Configure the watch-dog timer, but disable it for now
	banksel	OPTION_REG
		;	  ||||||||---- PS0 - Timer 0:  
		;	  |||||||----- PS1
		;	  ||||||------ PS2
		;	  |||||------- PSA -  Assign prescaler to Timer0
		;	  ||||-------- TOSE - LtoH edge
		;	  |||--------- TOCS - Timer0 uses IntClk
		;	  ||---------- INTEDG - falling edge RB0
		;	  |----------- NOT_RABPU - pull-ups enabled
	movlw	b'00001110' ; 110 == 64 pre-scaler & WDT selected
	movwf	OPTION_REG
	banksel	WDTCON
	movlw	b'00010010' ; 1001 == 16384 (~ 32 seconds)
	movlw	b'00010000' ; 1000 == 8192 (= ca 16 seconds)
	movlw	b'00001100' ; 0110 ==  2048 (~  4 seconds)
	;            |||||
	;            ||||+--- disable watchdog timer SWDTEN
	;            |||+---- pre-scaler WDTPS0
	;            ||+----- pre-scaler WDTPS1
	;            |+------ pre-scaler WDTPS2
	;            +------- pre-scaler WDTPS3
	movwf	WDTCON
	
	; set the OSCTUNE value now
	banksel	OSCTUNE
	movlw	OSCTUNE_VALUE
	movwf	OSCTUNE

	; Select the clock for our A/D conversations
	BANKSEL	ADCON1
	MOVLW 	B'01010000'	; ADC Fosc/16
	MOVWF 	ADCON1

	; all ports to digital, except AN11 / RB5
	banksel	ANSEL
	movlw	b'00000000'
	movwf	ANSEL
	movlw	b'00001000'
	movwf	ANSELH

	; Configure PortA
	BANKSEL TRISA
	movlw	b'00000000' ; all output
	movwf	TRISA
	
	; Configure PortB
	BANKSEL	TRISB
	movlw	b'00100000' ; all out, except RB5
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
	call	SHT15_Init

	; reset values
	movlw	.0
	movwf	Values
	movwf	Values+1
	movwf	Values+2
	movwf	Values+3
	movwf	Values+4
	movwf	Values+5
	movwf	Values+6

	; init done

_main
	; sleep
	; watch-dog timer is used for wake-up
	banksel	WDTCON
	bsf		WDTCON, SWDTEN
	SLEEP
	banksel	WDTCON
	bcf		WDTCON, SWDTEN

	;========================================
	; start - measure light level
	;========================================
	call	light_power_on
	call	light_measure
	call	light_power_off
	;========================================
	; done - measure light level
	;========================================


	;========================================
	; start - measure temp & humidity
	;========================================
	call	SHT15_power_on
	call	SHT15_get_temp

	; move temp data into main buffer
	banksel	SHT15_databuffer
	movfw	SHT15_databuffer
	banksel	Values
	movwf	Values
	banksel	SHT15_databuffer
	movfw	SHT15_databuffer+1
	banksel	Values
	movwf	Values+1

	call	SHT15_get_humidity
	; move temp data into main buffer
	banksel	SHT15_databuffer
	movfw	SHT15_databuffer
	banksel	Values
	movwf	Values+2
	banksel	SHT15_databuffer
	movfw	SHT15_databuffer+1
	banksel	Values
	movwf	Values+3

	call	SHT15_BatteryCheck
	; low-battery bit goes into the first bit of the two light level bytes
	banksel	Values
	bsf		Values+4, 7
	btfss	STATUS, Z
	bcf		Values+4, 7
		
	call	SHT15_power_off
	;========================================
	; done - measure temp & humidity
	;========================================

	; inc counter
	incf	Values+6, f


	;========================================
	; start - send data over RF
	;========================================
	call	RF_TX_PowerOn
	; Load the value's location and send the msg
	movlw	HIGH	Values
	movwf	MsgAddr
	movlw	LOW		Values
	movwf	MsgAddr+1
	movlw	.7
	movwf	MsgLen
	; and transmit the data now
	call	RF_TX_SendMsg
	; done
	call	RF_TX_PowerOff
	;========================================
	; done  - send data over RF
	;========================================

	goto	_main


light_power_on
	banksel	PORTB
	bsf		PORTB, 4
	return
light_power_off
	banksel	PORTB
	bcf		PORTB, 4
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
	
	end