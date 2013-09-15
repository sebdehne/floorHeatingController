
	udata_shr
REG_CRC16_LO	res	1
REG_CRC16_HI	res	1

	global	REG_CRC16_LO
	global	REG_CRC16_HI
	
	udata
f_crc16_index	res	1
f_crc16_temp	res	1

	code
	
	
; Input: W = new 8-bit byte 
;        f_crc16_crcLo:f_crc16_crcHi - current 16-bit CRC
;
; Output:
;        f_crc16_crcLo:f_crc16_crcHi - updated 16-bit CRC
;
; Memory used:
;  f_crc16_index
;  f_crc16_temp
;
; Cycles:
;   23 (excluding return)

CRC16
	global	CRC16
	XORWF   REG_CRC16_LO,W
	MOVWF   f_crc16_index

	MOVF    REG_CRC16_HI,W
	MOVWF   REG_CRC16_LO           ;f_crc16_crcLo = crc >> 8

    CLRF    f_crc16_temp            ;Holds the CRC pattern for the low byte
    CLRC                    ;
    RRF     f_crc16_index,W         ;W =  0.i7.i6.i5.i4.i3.i2.i1 C=i0
    XORWF   f_crc16_index,F         ;F = 0i7.i7i6.i6i5.i5i4.i4i3.i3i2.i2i1.i1i0
    RRF     f_crc16_temp,F          ;t = i0.0.0.0.0.0.0.0  C=0
        
	RRF     f_crc16_index,W         ;W = 0.0i7.i7i6.i6i5.i5i4.i4i3.i3i2.i2i1 C=i1i0
    MOVWF   REG_CRC16_HI           ;f_crc16_crcHi = 0.0i7.i7i6.i6i5.i5i4.i4i3.i3i2.i2i1
    RRF     f_crc16_temp,F          ;t = i1i0.i0.0.0.0.0.0.0 C=0

    RLF     f_crc16_index,F         ;W = i7i6.i6i5.i5i4.i4i3.i3i2.i2i1.i1i0.0 C=i7
    XORWF   f_crc16_index,F         ;F = X.X.i7i6i5i4.X.X.X.i3i2i1i0.X
        
    SWAPF   f_crc16_index,W         ;F = X.X.i3i2i1i0.X.X.X.i7i6i5i4.X
    XORWF   f_crc16_index,F         ;F = X.X.P.X.X.X.P.X  where P= parity(f_crc16_index)

    ; at this point, the parity of the f_crc16_index byte is now at bits 1 and 5 of f_crc16_index.

    MOVF    f_crc16_temp,W          ;W = i1i0.i0.0.0.0.0.0.0 
    BTFSC   f_crc16_index,1         ;If P==1
	XORLW  1               ;W = i1i0.i0.0.0.0.0.0.P
    XORWF   REG_CRC16_LO,F         ;f_crc16_crcLo = (crc>>8) ^ i1i0.i0.0.0.0.0.0.P

    MOVLW   0xC0
    BTFSC   f_crc16_index,1
    XORWF  REG_CRC16_HI,F         ;f_crc16_crcHi = P.Pi7.i7i6.i6i5.i5i4.i4i3.i3i2.i2i1

    return
        
	end