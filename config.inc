;--------------------------
; config.inc
;--------------------------

	list	p=16f690
#include    <p16f690.inc>

;**********************************************
; Memory config
;
; main.asm        : 11 bytes 0x20
; CRC16           :  4 bytes 0x2c
; ChipCap2        : 11 bytes 0x30
; rf_protocol_tx  :  8 bytes 0x40
; rf_protocol_rx  : 13 bytes 0x50

;**********************************************
; Port config:
; 
; RA0 - RX-rssi
; RA1 - RX-rssi-ref
; RA2 - TX-signal
; RA3 - <empty>
; RA4 - LED2
; RA5 - Relay out
; 
; RB4 - I2c DAT
; RB5 - <empty>
; RB6 - I2c SCK
; RB7 - Power 20mA
; 
; RC0 - <empty>
; RC1 - <empty>
; RC2 - <empty>
; RC3 - <empty>
; RC4 - <empty>
; RC5 - LED1
; RC6 - <empty>
; RC7 - <empty>
;**********************************************
#define CLOCKSPEED      		.8000000	; 8 MHz Osc
;#define CLOCKSPEED       		.4000000	; 4 MHz Osc
#define	OSCTUNE_VALUE			.0


;***************************************
; Switches power to the sensors
;***************************************
#define	PWR						PORTB, 7

;***************************************
; Values required by ChipCap2.asm
;***************************************
#define ChipCal2_I2C_ADDR		b'01010000'
#define	ChipCap2_SCK			PORTB, 6
#define	ChipCap2_DATA			PORTB, 4

;***************************************
; Values required by rf_protocol_tx.asm
;***************************************
#define RF_TX_PORT              PORTA, 2
#define RF_DST_ADDR             .1             ; receiver has id 1
#define RF_SRC_ADDR             .27            ; local addr

;***************************************
; Values required by rf_protocol_rx.asm
;***************************************
#define	RF_RX_PORT_RSSI			PORTA, 0    ; C1IN+
#define	RF_RX_PORT_RSSI_REF		PORTA, 1    ; C12IN0-
#define	RF_RX_LOCAL_ADDR		.27			; local addr

