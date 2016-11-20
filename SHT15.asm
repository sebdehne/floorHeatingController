	errorlevel  -302

#include "config.inc"


#ifndef CLOCKSPEED
	error	"CLOCKSPEED must be defined, for example: .8000000"
#endif



SHT15Data	udata	0x30
d1							res 1
d2							res 1
d3							res 1
temp						res 1
bytes_to_read				res 1
loop_cnt					res 1
loop_cnt2					res 1
SHT15_databuffer			res 3
	global	SHT15_databuffer

	code

;
; Library for the SHT-15 sensor. 
;
; NOTE: It is recommended to run a watchdog timer 
;       which can reset the microcontroller for the situation
;       where it is waiting for input from the sensor but doesn`t 
;       get any. The library has currently no own timeout handling.
;
; All delay/timing code (_delay_* methods) are for 8Mhz and need to be adjusted
; when running at different speed


; call to setup the module
; sensor is powered off
SHT15_Init
	global	SHT15_Init
	banksel	TRISB
	bcf		TRISB, 6 ; CLK port
	banksel	PORTA
	return

; reads the raw temperature data from the sensor
; and stores that in the SHT15_databuffer register
; 3 bytes: 2 bytes for temp-data and 1 for crc8
SHT15_get_temp
	global SHT15_get_temp
	movlw	b'00000011' ; cmd for temperature
	movwf	temp
	movlw	.3 ; 2 data bytes + 1 crc byte
	movwf	bytes_to_read
	call	SHT15_ReadRegister
	return

; reads the raw humidity data from the sensor
; and stores that in the SHT15_databuffer register
; 3 bytes: 2 bytes for temp-data and 1 for crc8
SHT15_get_humidity
	global	SHT15_get_humidity
	movlw	b'00000101' ; cmd for humidity
	movwf	temp
	movlw	.3 ; 2 data bytes + 1 crc byte
	movwf	bytes_to_read
	call	SHT15_ReadRegister
	return

; sends the reset command
SHT15_reset
	global	SHT15_reset
	movlw	b'00011110' ; cmd for reset
	call	send_command
	call	_delay_20ms
	return

; low-battery voltage detection, can only be 
; used after a measurement
; Uses and modifies the SHT15_databuffer register
; 
; returns:
; sets the STATUS, Z to 0 if the VDD > 2.47
; sets the STATUS, Z to 1 if the VDD < 2.47
SHT15_BatteryCheck
	global	SHT15_BatteryCheck
	movlw	b'00000111' ; cmd for status register
	movwf	temp
	movlw	.2 ; 1 status byte + 1 crc byte
	movwf	bytes_to_read
	call	SHT15_ReadRegister
	bcf		STATUS, Z
	btfsc	SHT15_databuffer, 6
	bsf		STATUS, Z
	return

; =========================================
; below this line, all internal methods
; =========================================

; sends the command in temp and stores the response in SHT15_databuffer
; sets STATUS, Z to 1 if error
; sets STATUS, Z to 0 if success
SHT15_ReadRegister
	call	send_start
	movf	temp, W
	call	send_command
	btfsc	STATUS, Z
	goto	SHT15_ReadRegister_done ; abort here since cmd was not OK

	; wait for measurement done 	
	call	_delay_5us
	call	_delay_5us
	call	_delay_5us
	; wait for DATA line to be pulled low by sensor
SHT15_ReadRegister_wait
	call	_delay_5us
	call	data_read
	btfsc	STATUS, Z
	goto	SHT15_ReadRegister_wait ; data line not low yet, wait more
	
	; read data from sensor
	call	read_data

	; TODO: verify CRC

	bcf		STATUS, Z
SHT15_ReadRegister_done
	return

data_send_low
	banksel	TRISB
	bcf		TRISB, 4 ; output pin
	banksel	PORTA
	bcf		PORTB, 4
	return
data_send_high
	banksel	TRISB
	bsf		TRISB, 4 ; input pin, pull-up will do the work
	banksel	PORTA
	return
data_read
	banksel	TRISB
	bsf		TRISB, 4 ; input pin
	banksel	PORTA
	bcf		STATUS, Z
	btfsc	PORTB, 4
	bsf		STATUS, Z
	return
sck_high
	bsf		PORTB, 6
	return
sck_low
	bcf		PORTB, 6
	return


send_start
	call	_delay_5us
	call	sck_high
	call	_delay_5us
	call	_delay_5us
	call	data_send_low
	call	_delay_5us
	call	_delay_5us
	call	sck_low
	call	_delay_5us
	call	_delay_5us
	call	sck_high
	call	_delay_5us
	call	_delay_5us
	call	data_send_high
	call	_delay_5us
	call	_delay_5us
	call	sck_low
	call	_delay_5us
	call	_delay_5us
	call	data_send_low
	call	_delay_5us
	call	_delay_5us
	call	_delay_5us
	call	_delay_5us
	call	_delay_5us
	call	_delay_5us
	call	_delay_5us
	call	_delay_5us
	return

; reads number of bytes specified in bytes_to_read
read_data
	movlw	SHT15_databuffer
	movwf	FSR
	bcf		STATUS, IRP
read_data_byte
	movlw	.8
	movwf	loop_cnt2
read_data_byte_bit
	rlf		INDF, F
	; wait A
	call	_delay_5us
	; raise clock
	call	sck_high
	; wait B
	call	_delay_5us
	; read DATA
	call	data_read
	bsf		INDF, 0
	btfss	STATUS, Z
	bcf		INDF, 0

	; wait C	
	call	_delay_5us
	; clear clock
	call	sck_low
	; wait D
	call	_delay_5us
	; more bits to read?
	decfsz	loop_cnt2, F
	goto	read_data_byte_bit
	; send ACK
	call	data_send_low
	; wait A
	call	_delay_5us
	; raise clock
	call	sck_high
	; wait B
	call	_delay_5us
	; wait C
	call	_delay_5us
	; clear clock
	call	sck_low
	; wait D
	call	_delay_5us
	call	data_read ; release data line
	; more bytes to read?
	incf	FSR, F
	decfsz	bytes_to_read, F
	goto	read_data_byte

read_data_done
	return

; sends command in W, and sets 
; STATUS, Z to 1 for NACK
; STATUS, Z to 0 for ACK
send_command
	; store value in W into temp
	movwf	temp
	; prepare the loop
	movlw	.8
	movwf	loop_cnt
	; send the bits now
send_command_loop
	; read the next bit
	rlf		temp, F

	; configure DATA line now
	btfss	STATUS, C
	goto	send_command_loop_low
	goto	send_command_loop_high

send_command_loop_high
	call	data_send_high
	goto	send_command_loop_cnt
send_command_loop_low
	call	data_send_low
	goto	send_command_loop_cnt
send_command_loop_cnt

	; wait A
	call	_delay_5us
	; rais clock
	call	sck_high
	; wait B
	call	_delay_5us
	; wait C
	call	_delay_5us
	; clear clock
	call	sck_low
	; wait D
	call	_delay_5us
	; loop for more bits
	decfsz	loop_cnt, F
	goto	send_command_loop

	; read ACK/NACK
	; wait A for slave to set DATA line
	call	_delay_5us
	; rais clock
	call	sck_high
	; wait B
	call	_delay_5us
	; read DATA (ACK/NACK) now and store bit in temp0
	call	data_read
	bsf		temp, 0
	btfss	STATUS, Z
	bcf		temp, 0
	; wait C
	call	_delay_5us
	; clear clock
	call	sck_low
	; wait D
	call	_delay_5us

	; move temp0 to Z
	bsf		STATUS, Z
	btfss	temp, 0
	bcf		STATUS, Z

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