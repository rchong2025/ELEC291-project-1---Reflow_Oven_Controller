$MODMAX10

; The Special Function Registers below were added to 'MODMAX10' recently.
; If you are getting an error, uncomment the three lines below.

; ADC_C DATA 0xa1
; ADC_L DATA 0xa2
; ADC_H DATA 0xa3

	CSEG at 0
	ljmp mycode

dseg at 30h


adcref: 	ds  4
adcLM335:	ds  4
adcOP07:	ds 	4
Tc:			ds 	4
Th:			ds 	4

x:			ds	4
y:			ds	4
bcd:		ds	5

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
	mov a, #'V'
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
	mov a, #'V'
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

Initial_Message:  db 'Voltmeter test', 0

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
    ; -----------------------------------------
    ; 1. READ REFERENCE (Channel 3) - Read this FIRST
    ; -----------------------------------------
    mov a, #3
    mov ADC_C, a          ; WRITE to ADC
    lcall WaitADC
    
    mov adcref+3, #0
    mov adcref+2, #0
    mov adcref+1, ADC_H
    mov adcref+0, ADC_L

    ; -----------------------------------------
    ; 2. READ LM335 (Channel 5)
    ; -----------------------------------------
    mov a, #5          ; Select Channel 5
    mov ADC_C, a          ; WRITE to ADC to start conversion
    lcall WaitADC         ; Wait for conversion to finish
    
    ; Save to variable
    mov adcLM335+3, #0
    mov adcLM335+2, #0
    mov adcLM335+1, ADC_H
    mov adcLM335+0, ADC_L

    ; -----------------------------------------
    ; 3. READ OP07 (Channel 4)
    ; -----------------------------------------
    mov a, #4
    mov ADC_C, a          ; WRITE to ADC
    lcall WaitADC
    
    mov adcOP07+3, #0
    mov adcOP07+2, #0
    mov adcOP07+1, ADC_H
    mov adcOP07+0, ADC_L

	mov x+3, adcLM335+3
	mov x+2, adcLM335+2
	mov x+1, adcLM335+1
	mov x+0, adcLM335+0

	Load_y(4096) ;4096 * lm335
	lcall mul32  ;multiply by 4096

   ;Load ADCref into y
	mov y+3, adcref+3
	mov y+2, adcref+2
	mov y+1, adcref+1
	mov y+0,   adcref+0
	
	;Tc Calc
	lcall div32 ;LM335/Reference = vlm335

	Load_y(2731) ;load 2.73V
	lcall sub32  ;Vlm335 - 2.37V =Numerator
	Load_y(10)
	lcall div32  ;Numerator/10 = TemperatureC
	
	;Tc Save
	mov Tc+3, x+3
	mov Tc+2, x+2
	mov Tc+1, x+1
	mov Tc+0,   x+0
	
	;Th Calc
	Load_x(333)
	
	;Load OP07 into y
	mov y+3, adcOP07+3
	mov y+2, adcOP07+2
	mov y+1, adcOP07+1
	mov y+0,   adcOP07+0
	lcall mul32 ;multiply by 333
	
	;Load ADCref into y
	mov y+3, adcref+3
	mov y+2, adcref+2
	mov y+1, adcref+1
	mov y+0,   adcref+0
	
	lcall div32 ;divide by adcRef = Th
	
	

	;x is Th
	
	;Tc Load
	mov y+3, Tc+3
	mov y+2, Tc+2
	mov y+1, Tc+1
	mov y+0, Tc+0
	
	lcall add32 ;value of x is the temperature of oven
	
    
    ; -----------------------------------------
    ; 7. DISPLAY THE RESULT
    ; -----------------------------------------
    lcall hex2bcd
    lcall Display_Voltage_7seg
    lcall Display_Voltage_LCD
    lcall Display_Voltage_Serial

    ; Delay - set R7 AFTER all math is done to avoid corruption
    mov R7, #20
delay_loop:
    lcall Wait50ms        
    djnz R7, delay_loop
    
    ljmp forever

; -----------------------------------------
; Helper: Small delay for ADC conversion
; -----------------------------------------
WaitADC:
    mov R0, #150
WaitADC_L:
    djnz R0, WaitADC_L
    ret
end