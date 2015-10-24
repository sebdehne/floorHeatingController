;--------------------------
; config.inc
;--------------------------

	list	p=16f690
#include    <p16f690.inc>

;**********************************************
; Port config:
; 
; RA0 - <empty>
; RA1 - <empty>
; RA2 - <empty>
; RA3 - <empty>
; RA4 - <empty>
; RA5 - <empty>
; 
; RB4 - light_sensor_pwr
; RB5 - light_sensor_adc (AN11)
; RB6 - <empty>
; RB7 - <empty>
; 
; RC0 - ChipCap2_PWR
; RC1 - ChipCap2_SCK
; RC2 - ChipCap2_DATA
; RC3 - RF_TX_PWR
; RC4 - RF_TX_PORT
; RC5 - <empty>
; RC6 - <empty>
; RC7 - <empty>
;**********************************************
;#define CLOCKSPEED      		.8000000	; 8 MHz Osc
#define CLOCKSPEED       		.4000000	; 4 MHz Osc
#define	OSCTUNE_VALUE			.0


;***************************************
; Values required by ChipCap2.asm
;***************************************
#define ChipCal2_I2C_ADDR		b'01010000'
#define	ChipCap2_PWR			PORTC, 0
#define	ChipCap2_SCK			PORTB, 6
#define	ChipCap2_DATA			PORTB, 4

;***************************************
; Values required by rf_protocol.asm
;***************************************
#define RF_TX_PWR               PORTC, 3
#define RF_TX_PORT              PORTC, 4
#define RF_DST_ADDR             .1              ; receiver has id 1
#define RF_SRC_ADDR             .6              ; local addr


