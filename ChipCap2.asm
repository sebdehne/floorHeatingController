	errorlevel  -302

#include "config.inc"

#ifndef ChipCap2_PWR
	error	"ChipCap2_PWR must be defined, for example: PORTA,0"
#endif
#ifndef ChipCap2_SCK
	error	"ChipCap2_SCK must be defined, for example: PORTA,0"
#endif
#ifndef ChipCap2_DATA
	error	"ChipCap2_DATA must be defined, for example: PORTA,0"
#endif
#ifndef CLOCKSPEED
	error	"CLOCKSPEED must be defined, for example: .8000000"
#endif



	udata_shr
d1							res 1
d2							res 1
d3							res 1
temp						res 1
bytes_to_read				res 1
loop_cnt					res 1
loop_cnt2					res 1
ChipCap2_temp				res 2
ChipCap2_humidity			res 2
	global	ChipCap2_temp
	global	ChipCap2_humidity

	udata
ChipCap2_databuffer			res 4

	code

;
; Library for the ChipCap2 sensor.
;
; This lib makes use of the PIC I2C module. Since the
; ChipCap2 supports I2C with a clock between 100KHz and 400KHz,
; this lib used Focz/16 where OCZ runs at 4000KHz. That gives a I2C clock
; of 250KHz.
;
; ChipCap2 doc: http://www.ge-mcs.com/download/moisture-humidity/916-127B.pdf
;
; NOTE: It is recommended to run a watchdog timer 
;       which can reset the microcontroller for the situation
;       where it is waiting for input from the sensor but doesn`t 
;       get any. The library has currently no own timeout handling.
;



; call to setup the module
; sensor is powered off
ChipCap2_Init
	global	ChipCap2_Init
	banksel	TRISC
	bcf		TRISC, 0 ; PWR port becomes output
	banksel	TRISB
	bcf		TRISB, 6 ; CLK port becomes output

	call	ChipCap2_power_off
	return

; powers on the sensor
ChipCap2_power_on
	global	ChipCap2_power_on

	; set DATA & CLK to high
	call	sck_high
	call	data_send_high

	; switch on device
	banksel	PORTC
	bsf		ChipCap2_PWR
	call	_delay_20ms; wait_for_startup

	return

; powers off the sensor
ChipCap2_power_off
	global	ChipCap2_power_off

	; switch off device
	banksel	PORTC
	bcf		ChipCap2_PWR

	; set DATA & CLK to low
	call	sck_low
	call	data_send_low

	return

; reads the 4 data bytes
ChipCap2_get_all
	global 	ChipCap2_get_all

	call	I2C_start_cnd

	; start reading the values by sending
	; the slave addr with the read-bit set
	movlw	ChipCal2_I2C_ADDR		; load slave addr (7 bits)
	bsf		W, 0					; set LSB to 1=read
	movwf	temp
	call	I2C_Write
	; now read all four bytes
	movlw	.4 						; 4 data bytes
	movwf	bytes_to_read
	call	I2C_Read

	call	I2C_stop_cnd

	; extract the humidity data
	banksel	ChipCap2_databuffer
	movfw	ChipCap2_databuffer
	bcf		W, 7   ; ignore the status bit
	bcf		W, 6   ;   because we are happy as long as we got 1 measurement
	movwf	ChipCap2_humidity
	movfw	ChipCap2_databuffer+1
	movwf	ChipCap2_humidity+1

	; extract the temp data
	movfw	ChipCap2_databuffer+2
	movwf	ChipCap2_temp
	movfw	ChipCap2_databuffer+3
	movwf	ChipCap2_temp+1
	; shift temp data two bits to the right
	bcf		STATUS, C
	rrf		ChipCap2_temp, F		; shift first byte to the right
	rrf		ChipCap2_temp+1, F		; shift C into the second byte
	bcf		STATUS, C				; and the same once more
	rrf		ChipCap2_temp, F		
	rrf		ChipCap2_temp+1, F

	; all done with the ChipCap2
	call	I2C_Disable

	return

; =========================================
; below this line, all internal methods
; =========================================


I2C_Setup

	return

I2C_Disable
	return


; =========================================
; reads number of bytes specified in 'bytes_to_read' into ChipCap2_databuffer
; =========================================
I2C_Read
	movlw	ChipCap2_databuffer
	movwf	FSR
	bcf		STATUS, IRP
	btfsc	ChipCap2_databuffer, 0
	bsf		STATUS, IRP
I2C_Read_byte
	movlw	.8
	movwf	loop_cnt2
I2C_Read_byte_bit
	rlf		INDF, F

	call	_delay_5us
	call	sck_high
	call	_delay_5us
	; read DATA
	call	read_bit
	bsf		INDF, 0
	btfss	STATUS, Z
	bcf		INDF, 0

	; clear clock
	call	sck_low
	call	_delay_5us
	; more bits to read?
	decfsz	loop_cnt2, F
	goto	I2C_Read_byte_bit

	; send ACK
	call	data_send_low
	call	_delay_5us
	call	sck_high
	call	_delay_5us
	call	sck_low
	call	_delay_5us

	call	read_bit ; release data line
	; more bytes to read?
	incf	FSR, F
	decfsz	bytes_to_read, F
	goto	I2C_Read_byte

I2C_Read_done
	return


; =========================================
; sends command in temp, and sets 
; STATUS, Z to 1 for NACK
; STATUS, Z to 0 for ACK
; =========================================
I2C_Write
	; prepare the loop
	movlw	.8
	movwf	loop_cnt
	; send the bits now
I2C_Write_loop
	; read the next bit
	rlf		temp, F

	; configure DATA line now
	btfss	STATUS, C
	goto	I2C_Write_loop_low
	goto	I2C_Write_loop_high

I2C_Write_loop_high
	call	data_send_high
	goto	I2C_Write_loop_cnt
I2C_Write_loop_low
	call	data_send_low
	goto	I2C_Write_loop_cnt
I2C_Write_loop_cnt

	call	_delay_5us
	call	sck_high
	call	_delay_5us
	call	sck_low
	call	_delay_5us

	; loop for more bits
	decfsz	loop_cnt, F
	goto	I2C_Write_loop

	; read ACK/NACK
	; wait A for slave to set DATA line
	call	_delay_5us
	; rais clock
	call	sck_high
	call	_delay_5us
	; read DATA (ACK/NACK) now and store bit in temp0
	call	read_bit
	bsf		temp, 0
	btfss	STATUS, Z
	bcf		temp, 0

	; clear clock
	call	sck_low
	call	_delay_5us

	; move temp0 to Z
	bsf		STATUS, Z
	btfss	temp, 0
	bcf		STATUS, Z

	return

I2C_start_cnd
	call	sck_high
	call	data_send_low
	call	_delay_5us
	call	_delay_5us
	
	call	data_send_low
	call	_delay_5us
	call	sck_low
	call	_delay_5us
	return

I2C_stop_cnd
	call	sck_low
	call	data_send_low
	call	_delay_5us
	call	_delay_5us

	call	sck_high
	call	_delay_5us
	call	data_send_high
	call	_delay_5us
	return


data_send_low
	banksel	TRISB
	bcf		TRISB, 4 ; DATA port becomes an output pin
	banksel	PORTB
	bcf		ChipCap2_DATA
	return


data_send_high
	banksel	TRISB
	bsf		TRISB, 4 ; DATA port becomes input pin, pull-up will do the work
	return


; reads current bit on DATA line and returns it in STATUS,Z
read_bit
	banksel	TRISB
	bsf		TRISB, 4 ; DATA port becomes an input pin
	banksel	PORTB
	bcf		STATUS, Z
	btfsc	ChipCap2_DATA
	bsf		STATUS, Z
	return


sck_high
	banksel	PORTB
	bsf		ChipCap2_SCK
	return


sck_low
	banksel	PORTB
	bcf		ChipCap2_SCK
	return


	if CLOCKSPEED == .8000000
_delay_5us
			;6 cycles
	goto	$+1
	goto	$+1
	goto	$+1

			;4 cycles (including call)
	return
	else 
	if CLOCKSPEED == .4000000
_delay_5us
			;1 cycle
	nop

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

	end