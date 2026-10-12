$MODMAX10

; The Special Function Registers below were added to 'MODMAX10' recently.
; If you are getting an error, uncomment the three lines below.

; ADC_C DATA 0xa1
; ADC_L DATA 0xa2
; ADC_H DATA 0xa3

	CSEG at 0
	ljmp mycode

dseg at 30h

x:		ds	4
y:		ds	4
bcd:	ds	5

temp_ref:	ds	4


bseg

mf:		dbit 1

FREQ   EQU 33333333
BAUD   EQU 115200
T2LOAD EQU 65536-(FREQ/(32*BAUD))

CSEG

InitSerialPort:
	; Configure serial port and baud rate
	clr TR2 ; Disable timer 2
	mov T2CON, #30H ; RCLK=1, TCLK=1 
	mov RCAP2H, #high(T2LOAD)  
	mov RCAP2L, #low(T2LOAD)
	setb TR2 ; Enable timer 2
	mov SCON, #52H
	ret

putchar:
    JNB TI, putchar
    CLR TI
    MOV SBUF, a
    RET

SendString:
    CLR A
    MOVC A, @A+DPTR
    JZ SSDone
    LCALL putchar
    INC DPTR
    SJMP SendString
SSDone:
    ret

$include(math32.asm)

cseg
; These 'equ' must match the wiring between the DE10Lite board and the LCD!
; P0 is in connector JPIO.  Check "CV-8052 Soft Processor in the DE10Lite Board: Getting
; Started Guide" for the details.
ELCD_RS equ P1.7
; ELCD_RW equ Px.x ; Not used.  Connected to ground 
ELCD_E  equ P1.1
ELCD_D4 equ P0.7
ELCD_D5 equ P0.5
ELCD_D6 equ P0.3
ELCD_D7 equ P0.1
$NOLIST
$include(LCD_4bit_DE10Lite_no_RW.inc) ; A library of LCD related functions and utility macros
$LIST

; Look-up table for 7-seg displays
myLUT:
    DB 0xC0, 0xF9, 0xA4, 0xB0, 0x99        ; 0 TO 4
    DB 0x92, 0x82, 0xF8, 0x80, 0x90        ; 4 TO 9
    DB 0x88, 0x83, 0xC6, 0xA1, 0x86, 0x8E  ; A to F

Wait50ms:
;33.33MHz, 1 clk per cycle: 0.03us
	mov R0, #30
Wait50ms_L3:
	mov R1, #74
Wait50ms_L2:
	mov R2, #250
Wait50ms_L1:
	djnz R2, Wait50ms_L1 ;3*250*0.03us=22.5us
    djnz R1, Wait50ms_L2 ;74*22.5us=1.665ms
    djnz R0, Wait50ms_L3 ;1.665ms*30=50ms
    ret

Display_Voltage_7seg:
	
	mov dptr, #myLUT

	mov a, bcd+1
	swap a
	anl a, #0FH
	movc a, @a+dptr
	anl a, #0x7f ; Turn on decimal point
	mov HEX3, a
	
	mov a, bcd+1
	anl a, #0FH
	movc a, @a+dptr
	mov HEX2, a

	mov a, bcd+0
	swap a
	anl a, #0FH
	movc a, @a+dptr
	mov HEX1, a
	
	mov a, bcd+0
	anl a, #0FH
	movc a, @a+dptr
	mov HEX0, a
	
	ret

Display_Voltage_LCD:
	Set_Cursor(2,1)
	mov a, #'T'
	lcall ?WriteData
	mov a, #'='
	lcall ?WriteData

	mov a, bcd+1
	swap a
	anl a, #0FH
	orl a, #'0'
	lcall ?WriteData
	
	mov a, #'.'
	lcall ?WriteData
	
	mov a, bcd+1
	anl a, #0FH
	orl a, #'0'
	lcall ?WriteData

	mov a, bcd+0
	swap a
	anl a, #0FH
	orl a, #'0'
	lcall ?WriteData
	
	mov a, bcd+0
	anl a, #0FH
	orl a, #'0'
	lcall ?WriteData
	
	ret
	
Display_Voltage_Serial:
	mov a, #'T'
	lcall putchar
	mov a, #'='
	lcall putchar

	mov a, bcd+1
	swap a
	anl a, #0FH
	orl a, #'0'
	lcall putchar
	
	mov a, #'.'
	lcall putchar
	
	mov a, bcd+1
	anl a, #0FH
	orl a, #'0'
	lcall putchar

	mov a, bcd+0
	swap a
	anl a, #0FH
	orl a, #'0'
	lcall putchar
	
	mov a, bcd+0
	anl a, #0FH
	orl a, #'0'
	lcall putchar

	mov a, #'\r'
	lcall putchar
	mov a, #'\n'
	lcall putchar
	
	ret
	
; Send temperature as simple numeric value followed by newline
; Format: "XX.XX\n" (e.g., "23.45\n")
; This matches what the Python script expects
Send_Temp_Serial:
	; Send hundreds digit (bcd+1 high nibble)
	mov a, bcd+1
	swap a
	anl a, #0FH
	orl a, #'0'
	lcall putchar
	
	; Send tens digit (bcd+1 low nibble)
	mov a, bcd+1
	anl a, #0FH
	orl a, #'0'
	lcall putchar
	
	; Send units digit (bcd+0 high nibble)
	mov a, bcd+0
	swap a
	anl a, #0FH
	orl a, #'0'
	lcall putchar
	
	; Send decimal point
	mov a, #'.'
	lcall putchar
	
	; Send tenths digit (bcd+0 low nibble)
	mov a, bcd+0
	anl a, #0FH
	orl a, #'0'
	lcall putchar

	; Send newline (Python script expects this)
	mov a, #'\n'
	lcall putchar
	
	ret

Initial_Message:  db 'Temp', 0

mycode:
	mov SP, #7FH
	clr a
	mov LEDRA, a
	mov LEDRB, a
	
	lcall InitSerialPort
	
	; COnfigure the pins connected to the LCD as outputs
	mov P0MOD, #10101010b ; P0.1, P0.3, P0.5, P0.7 are outputs.  ('1' makes the pin output)
    mov P1MOD, #10000010b ; P1.7 and P1.1 are outputs

    lcall ELCD_4BIT ; Configure LCD in four bit mode
    ; For convenience a few handy macros are included in 'LCD_4bit_DE1Lite.inc':
	Set_Cursor(1, 1)
    Send_Constant_String(#Initial_Message)
	
	mov dptr, #Initial_Message
	lcall SendString
	mov a, #'\r'
	lcall putchar
	mov a, #'\n'
	lcall putchar
	
	mov ADC_C, #0x80 ; Reset ADC
	lcall Wait50ms

forever:
	mov a, SWA ; The first three switches select the channel to read
	anl a, #0x07
	
	
;LM335 Temp
	mov ADC_C, #5
	
; Load 32-bit 'x' with 12-bit adc result
	mov x+3, #0
	mov x+2, #0
	mov x+1, ADC_H
	mov x+0, ADC_L
  
    ;Try LM335
    Load_y(5035)
    lcall mul32
    Load_y(4095)
    lcall div32
    Load_y(2731)
    lcall sub32
    
    mov	temp_ref+3,	x+3
    mov temp_ref+2,	x+2
    mov temp_ref+1,	x+1
    mov temp_ref+0,	x+0
    
    
    
;Thermocouple
    mov ADC_C, #4
	
; Load 32-bit 'x' with 12-bit adc result
	mov x+3, #0
	mov x+2, #0
	mov x+1, ADC_H
	mov x+0, ADC_L
    
    
   	; Convert to voltage by multiplying by 5.000 and dividing by 4096
	Load_y(5000)
	lcall mul32
	Load_y(4095)
	lcall div32
	
	Load_y(1000) ; convert to microvolts
    lcall mul32
    Load_y(1230) ; 41 * 300
    lcall div32
    
    mov y+3, temp_ref+3
    mov y+2, temp_ref+2
    mov y+1, temp_ref+1
    mov y+0, temp_ref+0
    
    
    lcall add32
	lcall Send_Temp_Serial
	
	lcall hex2bcd
	lcall Display_Voltage_7seg
	lcall Display_Voltage_LCD
	;lcall Display_Voltage_Serial

	mov 	R7, #10
delay_loop:
	lcall Wait50ms
	djnz R7, delay_loop

	
	ljmp forever
	
end
