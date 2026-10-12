
$NOLIST
$MODMAX10
$LIST
	
; Reset vector
org 0x0000
    ljmp main

; Timer/Counter 0 overflow interrupt vector
org 0x000B
	ljmp Timer0_ISR

; Timer/Counter 1 overflow interrupt vector 
org 0x001B
	ljmp Timer1_ISR
	
; Serial port receive/transmit interrupt vector 
;NOTE: (Not sure if this is needed or not)
org 0x0023 
	reti
	
; Timer/Counter 2 overflow interrupt vector
org 0x002B
	reti
	
;                     1234567890123456    <- This helps determine the location of the counter
;-----------------------------------;
; String Print                      ;
;-----------------------------------;

Profile_one_message:            db 'Profile 1       ', 0
Profile_two_message:            db 'Profile 2       ', 0
Custom_profile_message:         db 'Custom Profile  ', 0
Clear_message:		            db '                ', 0
Options_message:	            db 'Options         ', 0
start_message:                  db 'Temp:           ', 0
start_message2:                 db 'Time:          F', 0
custom_soak_time_message:       db 'Soak time:      ', 0
custom_reflow_time_message:     db 'Reflow time:    ', 0
custom_soak_temp_message:       db 'Soak temp:      ', 0
custom_reflow_temp_message:     db 'Reflow temp:    ', 0
custom_cooling_temp_message:    db 'Cooling temp:   ', 0
ramp_to_soak_message:           db 'Ramp-to-Soak:   ', 0
soak_message:                   db 'Soak:           ', 0
ramp_to_peak_message:           db 'Ramp-to-Reflow: ', 0
reflow_message:                 db 'Reflow:         ', 0
Cooling_message:                db 'Cooling:        ', 0
Done_message:                   db 'Turned off:     ', 0
Quarter_done:			        db '####		    ', 0
Half_done:				        db '########        ', 0
Three_Quarter_done:		        db '############    ', 0
Complete_done:			        db '################', 0
no_bar:					        db 'Reflow not start', 0
smart_mode_message:             db 'Smart Mode      ', 0


on_message: db 'on ', 0
off_message: db 'off', 0

;-----------------------------------;
; Regular Variables                 ;
;-----------------------------------;

dseg at 30h

x:		ds	4
y:		ds	4
bcd:	ds	5
temp_ref:	ds	4
temp_save:   ds  4
;Copy pasted from ACD

Count1ms:     ds 2 ; Used to determine when a second has passed
Count1ms_Timer1:     ds 2
BCD_counter:  ds 1 ; The BCD counter incrememted in the ISR and displayed in the main loop
;Taken from ISR example

ramp_to_soak_flag: ds 1
soak_flag: ds 1
ramp_to_peak_flag: ds 1
reflow_flag: ds 1
cooling_flag: ds 1
routine_done_flag: ds 1
speaker_flag: ds 1

profile: ds 1
LCD_display_profile: ds 1
unit:	ds 1

counter: ds 1	;Used to keep time for the soak and reflow states (maybe cooling too, tbd)
start_stop: ds 1 ;If 0, reflow process is stopped. If 1, reflow process is happening. 
pwm_duty_cycle: ds 1

custom_soak_time: ds 1
custom_reflow_time: ds 1

custom_soak_temp: ds 1
custom_reflow_temp: ds 1
custom_cooling_temp: ds 1
servo_angle: ds 2

;-----------------------------------;
; One Bit Variables                 ;
;-----------------------------------;
bseg
mf:		dbit 1 ;Taken from ACD
second_flag: dbit 1  ;taken from ISR
half_second_flag: dbit 1
pwm_mode: dbit 1
options_mode: dbit 1
door_closed_ir_sensor: dbit 1
door_open_in_cycle: dbit 1
smart_mode: dbit 1
error_flag: dbit 1
ir_sensor_off: dbit 1

;-----------------------------------;
; Static Variables                  ;
;-----------------------------------;

CLK   EQU 33333333
BAUD   EQU 115200
T2LOAD EQU 65536-(CLK/(32*BAUD))
;These ones came from Lab3, and therefore is only for the other chip we've been using

;TIMER0_RATE   EQU 1000     ; 1000Hz, for a timer tick of 1ms
;TIMER0_RELOAD EQU ((65536-(CLK/(12*TIMER0_RATE))))
;for timer 0, taken from ISR and edited

TIMER0_RELOAD EQU 0xFECC 
;Don't ask. Just know that 9 interrupts every millisecond. 

TIMER1_RATE	  EQU 1000
TIMER1_RELOAD EQU ((65536-(CLK/(12*TIMER1_RATE))))

cseg

;-----------------------------------;
; LCD Pins                          ;
;-----------------------------------;
ELCD_RS equ P1.7
; ELCD_RW equ Px.x ; Not used.  Connected to ground 
ELCD_E  equ P1.1
ELCD_D4 equ P0.7
ELCD_D5 equ P0.5
ELCD_D6 equ P0.3
ELCD_D7 equ P0.1

;-----------------------------------;
; Output Pins                       ;
;-----------------------------------;

OVEN_RELAY	equ p3.7
FAN     equ p3.4
SPEAKER equ p3.5
LED_BLUE equ p3.0  ;red wire
LED_GREEN equ p3.3 ;black wire
LED_RED equ p3.2   ;orange wire
SERVO equ p2.7

;-----------------------------------;
; Input Pins                        ;
;-----------------------------------;

Button_1 equ KEY.0
Button_2 equ KEY.1
ENTER equ KEY.2
OPTIONS equ KEY.3
CYCLE_OPTIONS equ KEY.4
SUB_OPTIONS equ P3.6 ; White wire
TOGGLE_DISPLAY equ P1.3 ; Gray wire
TEMP_UNIT_TOGGLE equ p3.1 ; Red wire
IR_SENSOR equ p1.5 ;Purple wire

$NOLIST
$include(LCD_4bit_DE10Lite_no_RW.inc) ; A library of LCD related functions and utility macros
$include(math32.inc)
$LIST


;===================== SECTION BREAK =========================

;Initialization subroutines:

;-----------------------------------;
; Routine to initialize the ISR     ;
; for timer 0 ( Second counter)     ;
;-----------------------------------;
Timer0_Init:
	mov a, TMOD
	anl a, #0xf0 
	orl a, #0x01 
	mov TMOD, a
	
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)

	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	
    setb ET0 
    setb TR0  
	ret

;-----------------------------------------;
; Routine to initialize the ISR     	  ;
; for PWM				   	              ;
;-----------------------------------------;

Timer1_Init:
	mov a, TMOD
	anl a, #0x0f
	orl a, #0x10
	mov TMOD, a
	mov TH1, #high(TIMER1_RELOAD)
	mov TL1, #low(TIMER1_RELOAD)
    setb ET1
    setb TR1   
	clr pwm_mode
	clr a
    mov pwm_duty_cycle, a
    clr a
    mov servo_angle+0, a
    mov servo_angle+1, a
	ret

;-----------------------------------------;
; Routine to initialize the ISR     	  ;
; for timer 2 (Serial port / Baud rate)	  ;
;-----------------------------------------;
Timer2_Init:

	; Configure serial port and baud rate
	clr TR2 ; Disable timer 2
	mov T2CON, #30H ; RCLK=1, TCLK=1 
	mov RCAP2H, #high(T2LOAD)  
	mov RCAP2L, #low(T2LOAD)
	setb TR2 ; Enable timer 2
	mov SCON, #52H
	ret
	

;===================== SECTION BREAK =========================

;Subroutines:

;---------------------------------;
; ISR for timer 0                 ;
;---------------------------------;
Timer0_ISR:

    clr TR0
	mov TH0, #high(TIMER0_RELOAD)
	mov TL0, #low(TIMER0_RELOAD)
	setb TR0  
	
	push acc
	push psw

    lcall speaker_start
	
	; Increment the 16-bit one mili second counter
	inc    Count1ms+0    ; Increment the low 8-bits first
	mov a, Count1ms+0 ; If the low 8-bits overflow, then increment high 8-bits
	jnz Inc_Done
	inc Count1ms+1

Inc_Done:

	; Check if second has passed
	mov a, Count1ms+0
	cjne a, #low(9000), Timer0_ISR_done ; Warning: this instruction changes the carry flag!
	mov a, Count1ms+1
	cjne a, #high(9000), Timer0_ISR_done
	
	; 1000 milliseconds have passed.  Set a flag so the main program knows
	setb second_flag ; Let the main program know second had passed
	
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	; Increment the BCD counter
	mov a, BCD_counter
	add a, #0x01
	da a ; Decimal adjust instruction.  Check datasheet for more details!
	mov BCD_counter, a

    mov a, routine_done_flag
    jnz routine_done_speaker
    jb error_flag, routine_done_speaker
    mov speaker_flag, #0x00
    
routine_done_speaker:
    
    lcall check_ir_sensor
    lcall flag_check
    lcall serial_read
    lcall Display_Voltage_7seg

    jb options_mode, Timer0_ISR_done
    lcall display
	
Timer0_ISR_done:
	pop psw
	pop acc
	reti

;---------------------------------;
; ISR for timer 1                 ;
;---------------------------------;
Timer1_ISR:
	clr TR1
	mov TH1, #high(TIMER1_RELOAD)
	mov TL1, #low(TIMER1_RELOAD)
	setb TR1
	
	push acc
	push psw
	
	inc Count1ms_Timer1+0
	mov a, Count1ms_Timer1+0
	jnz Inc_Done_Timer1
	inc Count1ms_Timer1+1
	
Inc_Done_Timer1:
	jnb pwm_mode, pwm_off
	lcall pwm_switching
	ljmp Timer1_ISR_done
	
pwm_off:
	clr FAN
    clr SERVO
	clr a
	mov Count1ms_Timer1+0, a
	mov Count1ms_Timer1+1, a
	ljmp Timer1_ISR_done

Timer1_ISR_done:
	pop psw
	pop acc
	reti


;------------------------------------;
; Artin's Subroutines                ;
;------------------------------------;

;--------------------------;
;PWM switching subroutine  ;
;--------------------------;

pwm_done:
	ret
check_10ms:
	; Check if one second has passed
	mov a, Count1ms_Timer1+0
	cjne a, #10, pwm_done ; Warning: this instruction changes the carry flag!
	
	; Reset to zero the milli-seconds counter, it is a 16-bit variable
	clr a
	mov Count1ms_Timer1+0, a
	mov Count1ms_Timer1+1, a
	ret
	
pwm_switching:
	mov a, cooling_flag
	cjne a, #0, pwm_switching_with_servo_check
	mov a, start_stop
	cjne a, #1, pwm_switching_with_fan
    clr a
	mov servo_angle+0, a
    mov servo_angle+1, a
	ljmp pwm_switching_with_fan
pwm_switching_with_fan:
	mov a, Count1ms_Timer1+0
	clr c
	subb a, pwm_duty_cycle
	jc power_pwm_on
	clr FAN
	ljmp check_10ms
	
power_pwm_on:
	setb FAN
	ljmp check_10ms
	
pwm_switching_with_servo_check:
	mov a, servo_angle+0
	cjne a, #255, pwm_switching_with_servo
    mov a, servo_angle+1
    cjne a, #255, pwm_switching_with_servo_2
	ljmp pwm_switching_with_fan


pwm_switching_with_servo:
	inc servo_angle+0
	mov a, Count1ms_Timer1+0
	clr c
	subb a, #2
	jc power_pwm_on_with_servo
	clr SERVO
	ljmp pwm_switching_with_fan

power_pwm_on_with_servo:
	setb SERVO
	ljmp pwm_switching_with_fan


pwm_switching_with_servo_2:
	inc servo_angle+1
	mov a, Count1ms_Timer1+0
	clr c
	subb a, #2
	jc power_pwm_on_with_servo_2
	clr SERVO
	ljmp pwm_switching_with_fan

power_pwm_on_with_servo_2:
	setb SERVO
	ljmp pwm_switching_with_fan

;--------------------------;	
; Display profiles         ;
;--------------------------;
display_profile:
	mov a, #0
    cjne a, profile, check_display_profile_two 
    Set_Cursor(2, 1)
	Send_Constant_String(#Profile_one_message)
	ret

check_display_profile_two:
    mov a, #1
    cjne a, profile, display_custom_profile   
	
display_profile_two:
	Set_Cursor(2, 1)
	Send_Constant_String(#Profile_two_message)
	ret	

display_custom_profile:
	Set_Cursor(2, 1)
	Send_Constant_String(#Custom_profile_message)
    ret


	
;--------------------------;
; Reflow profiles UI       ;
;--------------------------;
options_menu:
	Set_Cursor(1, 1)
    Send_Constant_String(#Options_message)
    setb options_mode
    lcall display_profile
	ljmp check_profiles_toggle
set_profile_one:
	mov profile, #0
	lcall display_profile

check_exit_profiles:
	jb OPTIONS, check_next_option_custom_profiles
    Wait_Milli_Seconds(#50)
    jb OPTIONS, check_next_option_custom_profiles
    jnb OPTIONS, $
exit_profiles:
    Set_Cursor(2, 1)
    Send_Constant_String(#Clear_message)
    Set_Cursor(1, 1)
    Send_Constant_String(#Clear_message)
    clr options_mode
    lcall display
    ret

check_next_option_custom_profiles:
    jb CYCLE_OPTIONS, check_profiles_toggle
    Wait_Milli_Seconds(#50)
    jb CYCLE_OPTIONS, check_profiles_toggle
    jnb CYCLE_OPTIONS, $
    ljmp change_custom_profiles 
    
check_profile_one:
    mov a, #1
    cjne a, profile, set_profile_one

set_custom_profile:
    mov profile, #2
    lcall display_profile
    ljmp check_exit_profiles
    
intermediate_check_exit_profiles:
	ljmp check_exit_profiles

check_profiles_toggle:
	jb ENTER, intermediate_check_exit_profiles
    Wait_Milli_Seconds(#50)
    jb ENTER, intermediate_check_exit_profiles
    jnb ENTER, $
    mov a, #0
    cjne a, profile, check_profile_one

    
set_profile_two:
	mov profile, #1 
	lcall display_profile
	ljmp check_exit_profiles

;--------------------------;	
; Increment custom times   ;
;--------------------------;

increment_custom_soak_time:
    mov a, custom_soak_time
    cjne a, #120, continue_increment_custom_soak_time
    mov custom_soak_time, #60
    ret
continue_increment_custom_soak_time:
    inc custom_soak_time
    ret

increment_custom_reflow_time:
    mov a, custom_reflow_time
    cjne a, #45, continue_increment_custom_reflow_time
    mov custom_reflow_time, #25
    ret
continue_increment_custom_reflow_time:
    inc custom_reflow_time
    ret

increment_custom_soak_temp:
    mov a, custom_soak_temp
    cjne a, #170, continue_increment_custom_soak_temp
    mov custom_soak_temp, #130
    ret
continue_increment_custom_soak_temp:
    inc custom_soak_temp
    ret

increment_custom_reflow_temp:
    mov a, custom_reflow_temp
    cjne a, #220, continue_increment_custom_reflow_temp
    mov custom_reflow_temp, #180
    ret
continue_increment_custom_reflow_temp:
    inc custom_reflow_temp
    ret

increment_custom_cooling_temp:
    mov a, custom_cooling_temp
    cjne a, #35, continue_increment_custom_cooling_temp
    mov custom_cooling_temp, #25
    ret
continue_increment_custom_cooling_temp:
    inc custom_cooling_temp
    ret


;--------------------------;	
; Display custom times     ;
;--------------------------;

display_custom_soak_time:
    mov x+0, custom_soak_time
    mov x+1, #0
    mov x+2, #0
    mov x+3, #0
    lcall hex2bcd
    mov a, #0x00
    cjne a, bcd+1, display_custom_soak_time_three_digits
    Set_Cursor(2, 12)
    Display_BCD(bcd+0)
    Set_Cursor(2, 11)
    Display_char(#' ')
    Set_Cursor(2, 14)
    Display_char(#' ')
    ret

display_custom_soak_time_three_digits:
    Set_Cursor(2, 13)
    Display_BCD(bcd+0)
    Set_Cursor(2, 11)
    Display_BCD(bcd+1)
    Set_Cursor(2, 11)
    Display_char(#' ')
    ret

display_custom_reflow_time:
    mov x+0, custom_reflow_time
    mov x+1, #0
    mov x+2, #0
    mov x+3, #0
    lcall hex2bcd
    Set_Cursor(2, 14)
    Display_BCD(bcd+0)
    Set_Cursor(2, 13)
    Display_char(#' ')
    ret

display_custom_soak_temp:
    mov x+0, custom_soak_temp
    mov x+1, #0
    mov x+2, #0
    mov x+3, #0
    lcall hex2bcd
    Set_Cursor(2, 13)
    Display_BCD(bcd+0)
    Set_Cursor(2, 11)
    Display_BCD(bcd+1)
    Set_Cursor(2, 11)
    Display_char(#' ')
    ret

display_custom_reflow_temp:
    mov x+0, custom_reflow_temp
    mov x+1, #0
    mov x+2, #0
    mov x+3, #0
    lcall hex2bcd
    Set_Cursor(2, 15)
    Display_BCD(bcd+0)
    Set_Cursor(2, 13)
    Display_BCD(bcd+1)
    Set_Cursor(2, 13)
    Display_char(#' ')
    ret

display_custom_cooling_temp:
    mov x+0, custom_cooling_temp
    mov x+1, #0
    mov x+2, #0
    mov x+3, #0
    lcall hex2bcd
    Set_Cursor(2, 15)
    Display_BCD(bcd+0)
    Set_Cursor(2, 14)
    Display_char(#' ')
    ret

;--------------------------;	
; Profiles Initialization  ;
;--------------------------;
    initialize_custom_profiles:
        mov custom_soak_time, #90
        mov custom_reflow_time, #35
        mov custom_soak_temp, #150
        mov custom_reflow_temp, #200
        mov custom_cooling_temp, #30
        ret


;--------------------------;	
; Custom Reflow profile UI ;
;--------------------------;

change_custom_profiles:
    ljmp initial_display_custom_soak_time
initial_display_custom_soak_time:
    Set_Cursor(2, 1)
    Send_Constant_String(#custom_soak_time_message)
    lcall display_custom_soak_time

check_exit_custom_soak_time:
	jb OPTIONS, check_next_option_custom_soak_time
    Wait_Milli_Seconds(#50)
    jb OPTIONS, check_next_option_custom_soak_time
    jnb OPTIONS, $
    ljmp exit_profiles

check_next_option_custom_soak_time:
    jb CYCLE_OPTIONS, check_next_sub_option_custom_soak_time
    Wait_Milli_Seconds(#50)
    jb CYCLE_OPTIONS, check_next_sub_option_custom_soak_time
    jnb CYCLE_OPTIONS, $
    ljmp smart_mode_toggle

check_next_sub_option_custom_soak_time:
    jb SUB_OPTIONS, check_increment_custom_soak_time
    Wait_Milli_Seconds(#50)
    jb SUB_OPTIONS, check_increment_custom_soak_time
    jnb SUB_OPTIONS, $
    ljmp initial_display_custom_reflow_time

check_increment_custom_soak_time:
    jb ENTER, check_exit_custom_soak_time
    Wait_Milli_Seconds(#50)
    jb ENTER, check_exit_custom_soak_time
    jnb ENTER, $
    lcall increment_custom_soak_time
    lcall display_custom_soak_time
    ljmp check_exit_custom_soak_time





initial_display_custom_reflow_time:
    Set_Cursor(2, 1)
    Send_Constant_String(#custom_reflow_time_message)
    lcall display_custom_reflow_time

check_exit_custom_reflow_time:
	jb OPTIONS, check_next_option_custom_reflow_time
    Wait_Milli_Seconds(#50)
    jb OPTIONS, check_next_option_custom_reflow_time
    jnb OPTIONS, $
    ljmp exit_profiles

check_next_option_custom_reflow_time:
    jb CYCLE_OPTIONS, check_next_sub_option_custom_reflow_time
    Wait_Milli_Seconds(#50)
    jb CYCLE_OPTIONS, check_next_sub_option_custom_reflow_time
    jnb CYCLE_OPTIONS, $
    ljmp smart_mode_toggle

check_next_sub_option_custom_reflow_time:
    jb SUB_OPTIONS, check_increment_custom_reflow_time
    Wait_Milli_Seconds(#50)
    jb SUB_OPTIONS, check_increment_custom_reflow_time
    jnb SUB_OPTIONS, $
    ljmp initial_display_custom_soak_temp

check_increment_custom_reflow_time:
    jb ENTER, check_exit_custom_reflow_time
    Wait_Milli_Seconds(#50)
    jb ENTER, check_exit_custom_reflow_time
    jnb ENTER, $
    lcall increment_custom_reflow_time
    lcall display_custom_reflow_time
    ljmp check_exit_custom_reflow_time








initial_display_custom_soak_temp:
    Set_Cursor(2, 1)
    Send_Constant_String(#custom_soak_temp_message)
    lcall display_custom_soak_temp

check_exit_custom_soak_temp:
	jb OPTIONS, check_next_option_custom_soak_temp
    Wait_Milli_Seconds(#50)
    jb OPTIONS, check_next_option_custom_soak_temp
    jnb OPTIONS, $
    ljmp exit_profiles

check_next_option_custom_soak_temp:
    jb CYCLE_OPTIONS, check_next_sub_option_custom_soak_temp
    Wait_Milli_Seconds(#50)
    jb CYCLE_OPTIONS, check_next_sub_option_custom_soak_temp
    jnb CYCLE_OPTIONS, $
    ljmp smart_mode_toggle

check_next_sub_option_custom_soak_temp:
    jb SUB_OPTIONS, check_increment_custom_soak_temp
    Wait_Milli_Seconds(#50)
    jb SUB_OPTIONS, check_increment_custom_soak_temp
    jnb SUB_OPTIONS, $
    ljmp initial_display_custom_reflow_temp

check_increment_custom_soak_temp:
    jb ENTER, check_exit_custom_soak_temp
    Wait_Milli_Seconds(#50)
    jb ENTER, check_exit_custom_soak_temp
    jnb ENTER, $
    lcall increment_custom_soak_temp
    lcall display_custom_soak_temp
    ljmp check_exit_custom_soak_temp






initial_display_custom_reflow_temp:
    Set_Cursor(2, 1)
    Send_Constant_String(#custom_reflow_temp_message)
    lcall display_custom_reflow_temp

check_exit_custom_reflow_temp:
	jb OPTIONS, check_next_option_custom_reflow_temp
    Wait_Milli_Seconds(#50)
    jb OPTIONS, check_next_option_custom_reflow_temp
    jnb OPTIONS, $
    ljmp exit_profiles

check_next_option_custom_reflow_temp:
    jb CYCLE_OPTIONS, check_next_sub_option_custom_reflow_temp
    Wait_Milli_Seconds(#50)
    jb CYCLE_OPTIONS, check_next_sub_option_custom_reflow_temp
    jnb CYCLE_OPTIONS, $
    ljmp smart_mode_toggle

check_next_sub_option_custom_reflow_temp:
    jb SUB_OPTIONS, check_increment_custom_reflow_temp
    Wait_Milli_Seconds(#50)
    jb SUB_OPTIONS, check_increment_custom_reflow_temp
    jnb SUB_OPTIONS, $
    ljmp initial_display_custom_cooling_temp

check_increment_custom_reflow_temp:
    jb ENTER, check_exit_custom_reflow_temp
    Wait_Milli_Seconds(#50)
    jb ENTER, check_exit_custom_reflow_temp
    jnb ENTER, $
    lcall increment_custom_reflow_temp
    lcall display_custom_reflow_temp
    ljmp check_exit_custom_reflow_temp







initial_display_custom_cooling_temp:
    Set_Cursor(2, 1)
    Send_Constant_String(#custom_cooling_temp_message)
    lcall display_custom_cooling_temp

check_exit_custom_cooling_temp:
	jb OPTIONS, check_next_option_custom_cooling_temp
    Wait_Milli_Seconds(#50)
    jb OPTIONS, check_next_option_custom_cooling_temp
    jnb OPTIONS, $
    ljmp exit_profiles

check_next_option_custom_cooling_temp:
    jb CYCLE_OPTIONS, check_next_sub_option_custom_cooling_temp
    Wait_Milli_Seconds(#50)
    jb CYCLE_OPTIONS, check_next_sub_option_custom_cooling_temp
    jnb CYCLE_OPTIONS, $
    ljmp smart_mode_toggle

 check_next_sub_option_custom_cooling_temp:
    jb SUB_OPTIONS, check_increment_custom_cooling_temp
    Wait_Milli_Seconds(#50)
    jb SUB_OPTIONS, check_increment_custom_cooling_temp
    jnb SUB_OPTIONS, $
    ljmp initial_display_custom_soak_time

 check_increment_custom_cooling_temp:
    jb ENTER, check_exit_custom_cooling_temp
    Wait_Milli_Seconds(#50)
    jb ENTER, check_exit_custom_cooling_temp
    jnb ENTER, $
    lcall increment_custom_cooling_temp
    lcall display_custom_cooling_temp
    ljmp check_exit_custom_cooling_temp

;--------------------------;	
; IR Sensor                ;
;--------------------------;

check_ir_sensor:
    mov a, start_stop
    cjne a, #0, check_door_open_in_cycle
    clr door_open_in_cycle
    jnb smart_mode, return_check_ir_sensor

    jb ir_sensor_off, check_ir_sensor_on_after_off
    jnb IR_SENSOR, return_check_ir_sensor
    setb ir_sensor_off
    ljmp return_check_ir_sensor

check_ir_sensor_on_after_off:
    jb IR_SENSOR, return_check_ir_sensor
    clr ir_sensor_off
    setb door_closed_ir_sensor

return_check_ir_sensor:
    ret

check_door_open_in_cycle:
    clr door_closed_ir_sensor
    jnb IR_SENSOR, return_check_ir_sensor
    setb door_open_in_cycle
    ljmp return_check_ir_sensor


;--------------------------;	
; IR Sensor Initialization ;
;--------------------------;

initialize_ir_sensor:
    clr smart_mode
    clr door_closed_ir_sensor
    clr door_open_in_cycle
    ret

;--------------------------;	
; Display Smart Mode State ;
;--------------------------;

display_smart_mode_state:
	jnb smart_mode, display_smart_mode_off
	Set_Cursor(2, 14)
	Send_Constant_String(#on_message)
    ret
	
display_smart_mode_off:
	Set_Cursor(2, 14)
	Send_Constant_String(#off_message)
    ret
    
;--------------------------;	
; Toggling Smart Mode      ;
;--------------------------;

smart_mode_toggle:

initial_display_smart_mode_toggle:
    Set_Cursor(2, 1)
	Send_Constant_String(#smart_mode_message)
    lcall display_smart_mode_state

check_exit_smart_mode_toggle:
	jb OPTIONS, check_next_option_smart_mode_toggle
    Wait_Milli_Seconds(#50)
    jb OPTIONS, check_next_option_smart_mode_toggle
    jnb OPTIONS, $
    ljmp exit_profiles

check_next_option_smart_mode_toggle:
    jb CYCLE_OPTIONS, smart_mode_toggling
    Wait_Milli_Seconds(#50)
    jb CYCLE_OPTIONS, smart_mode_toggling
    jnb CYCLE_OPTIONS, $
    ljmp options_menu

smart_mode_toggling:
    jb ENTER, check_exit_smart_mode_toggle
    Wait_Milli_Seconds(#50)
    jb ENTER, check_exit_smart_mode_toggle
    jnb ENTER, $
    jb smart_mode, smart_mode_off
    setb smart_mode
    lcall display_smart_mode_state
    ljmp check_exit_smart_mode_toggle
smart_mode_off:
    clr smart_mode
    lcall display_smart_mode_state
    ljmp check_exit_smart_mode_toggle
	

;------------------------------------;
; Rex's Subroutines                  ;
;------------------------------------;

;---------------------------------;
; Subroutine for: 7-seg display   ;
;---------------------------------;

Display_Voltage_7seg:
	
	mov dptr, #myLUT

	mov a, bcd+1
	swap a
	anl a, #0FH
	movc a, @a+dptr
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
	anl a, #0x7f ; Turn on decimal point
	mov HEX0, a
	
	ret

;---------------------------------;
; Subroutine for: LCD display     ;
;---------------------------------;
display:
	
	push acc
	
	Set_Cursor(1, 1)
    Send_Constant_String(#start_message)
	
	Set_Cursor(1, 7)
	mov a, bcd+1
	swap a
	anl a, #0FH
	orl a, #'0'
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
	
    mov a, #'.'
	lcall ?WriteData

    mov a, unit
	cjne a, #00, notC_display

    Display_char(#'C')
	ljmp unit_display_done
	
notC_display:
	cjne a, #01, notF_display
	Display_char(#'F')
	ljmp unit_display_done
	
notF_display:
	
	Display_char(#'K')

unit_display_done:
	
	mov a, LCD_display_profile
	
	jnz time_display_mode
	lcall display_time
	ljmp second_display_done
	
time_display_mode:
	
	dec a
	jnz mode_display_mode
	lcall display_mode
	ljmp second_display_done
	
mode_display_mode:

	dec a
	jnz  second_display_done
	lcall display_bar
	ljmp second_display_done

second_display_done:

	pop acc
	ret
	
;------------------------------------;
; assist subroutines for LCD - time  ;
;------------------------------------;
display_time:

	push acc
	
	Set_Cursor(2,1)
    Send_Constant_String(#start_message2)
	
	Set_Cursor(2,7)
	Display_BCD(bcd_counter)
	;Displays time (Purely in seconds cause I got lazy lmao)

	mov a, ramp_to_soak_flag
	jz display_ramp_soak

	Set_Cursor(2,15)
	Display_char(#'R')
	Set_Cursor(2,16)
	Display_char(#'S')
	ljmp display_time_done
	
display_ramp_soak:
	
	mov a, soak_flag
	jz display_soak

    Set_Cursor(2,15)
	Display_char(#' ')
	Set_Cursor(2,16)
	Display_char(#'S')
	ljmp display_time_done
	
display_soak:
	
	mov a, ramp_to_peak_flag
	jz display_ramp_peak
	
	Set_Cursor(2,15)
	Display_char(#'R')
	Set_Cursor(2,16)
	Display_char(#'R')
	ljmp display_time_done
	
display_ramp_peak:
	
	mov a, reflow_flag
	jz display_reflow
	
	Set_Cursor(2,15)
	Display_char(#' ')
	Set_Cursor(2,16)
	Display_char(#'R')
	ljmp display_time_done
		
display_reflow:
	
	mov a, cooling_flag
	jz display_cooling
	
	Set_Cursor(2,15)
	Display_char(#' ')
	Set_Cursor(2,16)
	Display_char(#'C')
	ljmp display_time_done
	
display_cooling:
    
    Set_Cursor(2,15)
	Display_char(#' ')
	Set_Cursor(2,16)
	Display_char(#'F')
	ljmp display_time_done
	
display_time_done:
	
	pop acc
	ret

;-------------------------------------;
; assist subroutines for LCD - mode   ;
;-------------------------------------;

display_mode:
	push acc
	
	Set_Cursor(2,1)
	Send_constant_String(#clear_message)
	Set_Cursor(2,1)
	
	mov a, ramp_to_soak_flag
	jz display_ramp_soak_mode

	Send_Constant_String(#ramp_to_soak_message)
	ljmp display_done_mode
	
display_ramp_soak_mode:
	
	mov a, soak_flag
	jz display_soak_mode

    Send_Constant_String(#soak_message)
	ljmp display_done_mode
	
display_soak_mode:
	
	mov a, ramp_to_peak_flag
	jz display_ramp_peak_mode
	
	Send_Constant_String(#ramp_to_peak_message)
	ljmp display_done_mode
	
display_ramp_peak_mode:
	
	mov a, reflow_flag
	jz display_reflow_mode
	
	Send_Constant_String(#reflow_message)
	ljmp display_done_mode
		
display_reflow_mode:
	
	mov a, cooling_flag
	jz display_cooling_mode
	
	Send_Constant_String(#cooling_message)
	ljmp display_done_mode
	
display_cooling_mode:
    
    Send_Constant_String(#done_message)
	ljmp display_done_mode
	
display_done_mode:
	
	pop acc
	ret


;-----------------------------------;
; assist subroutines for LCD - bar  ;
;-----------------------------------;
display_bar:
	push acc
	
	Set_Cursor(2,1)
	Send_constant_String(#clear_message)
	Set_Cursor(2,1)
	
	mov a, ramp_to_soak_flag
	jz display_ramp_soak_bar

	mov a, profile
    cjne a, #0x03, display_ramp_soak_not_profile3
    
    mov a, custom_soak_temp
    ljmp display_ramp_soak_profile_check

display_ramp_soak_not_profile3:
    
    mov DPTR, #soak_temperature
	movc a, @a+DPTR
	
display_ramp_soak_profile_check:
    
    mov x+0, temp_save+0
    mov x+1, temp_save+1
    mov x+2, temp_save+2
    mov x+3, temp_save+3
    
    mov y+0, a
    mov y+1, #0
    mov y+2, #0
    mov y+3, #0
    
    lcall bar_display_checks
	ljmp display_done_bar
	
display_ramp_soak_bar:
	
	mov a, soak_flag
	jz display_soak_bar

	mov a, profile
    cjne a, #0x03, display_soak_not_profile3
    
    mov a, custom_soak_time
    ljmp display_soak_profile_check

display_soak_not_profile3:
    
    mov DPTR, #soak_time
	movc a, @a+DPTR
	
display_soak_profile_check:
	
	mov x+0, BCD_counter+0
    mov x+1, #0
    mov x+2, #0
    mov x+3, #0
    
    mov y+0, a
    mov y+1, #0
    mov y+2, #0
    mov y+3, #0

	Send_constant_string(#Quarter_done)
	Set_Cursor(2,5)
    lcall bar_display_checks
    ljmp display_done_bar    
	
display_soak_bar:
	
	mov a, ramp_to_peak_flag
	jz display_ramp_peak_bar
	
	mov a, profile
    cjne a, #0x03, display_ramp_peak_not_profile3
    
    mov a, custom_reflow_temp
    ljmp display_ramp_peak_profile_check

display_ramp_peak_not_profile3:
    
    mov DPTR, #reflow_temperature
	movc a, @a+DPTR
	
display_ramp_peak_profile_check:
    
    mov x+0, temp_save+0
    mov x+1, temp_save+1
    mov x+2, temp_save+2
    mov x+3, temp_save+3
    
    mov y+0, a
    mov y+1, #0
    mov y+2, #0
    mov y+3, #0
    
    Send_constant_string(#Half_done)
    Set_Cursor(2,9)
    lcall bar_display_checks
	ljmp display_done_bar
	
display_ramp_peak_bar:
	
	mov a, reflow_flag
	jz display_reflow_bar
	
	mov a, profile
    cjne a, #0x03, display_reflow_not_profile3
    
    mov a, custom_reflow_time
    ljmp display_reflow_profile_check

display_reflow_not_profile3:
    
    mov DPTR, #reflow_time
	movc a, @a+DPTR
	
display_reflow_profile_check:
	
	mov x+0, BCD_counter+0
    mov x+1, #0
    mov x+2, #0
    mov x+3, #0
    
    mov y+0, a
    mov y+1, #0
    mov y+2, #0
    mov y+3, #0

    Send_constant_string(#three_quarter_done)
    Set_Cursor(2,13)
    lcall bar_display_checks
	ljmp display_done_bar
	
display_reflow_bar:

	mov a, cooling_flag
	jz display_cooling_bar
	
	Send_Constant_String(#Complete_done)
	ljmp display_done_bar
	
display_cooling_bar:

	Send_constant_string(#No_bar)
	
display_done_bar:
	
	pop acc
	ret
	
;-----------------------------------------;
; Subroutine for: assistant for LCD - bar ;
;-----------------------------------------;	
bar_display_checks:

	push acc
	
	mov a, y+0
	mov b, #4
	div ab
	mov y+0, a
	
	lcall x_gteq_y
	jnb mf, mid_state_display_done
 
    Display_char(#'#')
	
	mov b, #2    
    mul ab
    mov y+0, a
    
    lcall x_gteq_y
	jnb mf, mid_state_display_done
 
    Display_char(#'#')
    
    mov b, #2
    div ab
    
    mov b, #3
    mul ab
    mov y+0, a
    
    lcall x_gteq_y
	jnb mf, mid_state_display_done
 
    Display_char(#'#')
		
	
mid_state_display_done:
	
	pop acc
	ret

;---------------------------------;
; Subroutine for: speaker         ;
;---------------------------------;

speaker_toggle:
	jnb SPEAKER, speaker_on
	clr SPEAKER
	ret
speaker_on:
	setb SPEAKER
	ret

speaker_start:

    push acc

    mov a, speaker_flag
    jz speaker_done

    ;cpl SPEAKER
    lcall speaker_toggle

speaker_done:

    pop acc
    ret

;---------------------------------;
; Subroutine for: serial reading  ;
;---------------------------------;
serial_read:
    push acc

	mov ADC_C, #5
	
; Load 32-bit 'x' with 12-bit adc result
	mov x+3, #0
	mov x+2, #0
	mov x+1, ADC_H
	mov x+0, ADC_L
  
    ;Try LM335
    Load_y(5030)
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
    mov ADC_C, #1
	
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
	
	load_y(10)
	lcall div32
	
	mov temp_save+0, x+0
    mov temp_save+1, x+1
    mov temp_save+2, x+2
    mov temp_save+3, x+3
    
    mov a, unit
	cjne a, #00, notC
	ljmp convert_done
	
notC:
	cjne a, #01, notF
	
	Load_y(9)
	lcall mul32
	Load_y(5)
	lcall div32
	load_y(32)
	lcall add32
	ljmp convert_done
	
notF:
	
	Load_y(273)
	lcall add32

convert_done:
	
	lcall hex2bcd
    pop acc
    ret
;-------------------------------;
; supportings for serial read   ;
;-------------------------------;
Send_Temp_Serial:
	mov temp_save+0, x+0
    mov temp_save+1, x+1
    mov temp_save+2, x+2
    mov temp_save+3, x+3
    
    Load_y(10)
    lcall mul32  

	mov temp_ref+3, y+3
    mov temp_ref+2, y+2
    mov temp_ref+1, y+1
    mov temp_ref+0, y+0
 
 	lcall add32
 	 Load_y(10)
    lcall div32
 	
	lcall hex2bcd
	
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

	; Send tenths digit (bcd+0 low nibble)
	mov a, bcd+0
	anl a, #0FH
	orl a, #'0'
	lcall putchar

	; Send decimal point
	mov a, #'.'
	lcall putchar

	; Send newline (Python script expects this)
	mov a, #'\n'
	lcall putchar
	
	ret
	
putchar:
    JNB TI, putchar
    CLR TI
    MOV SBUF, a
    RET

;---------------------------------;
; Subroutine for: flag checking   ;
;---------------------------------;
flag_check:
    push acc

    jnb smart_mode, no_ir
    jnb door_closed_ir_sensor, no_ir
    
    clr door_closed_ir_sensor 
    lcall start_button
    
no_ir:
	
	mov a, start_stop
	jz no_error
    mov a, cooling_flag
	jnz no_error
	jnb door_open_in_cycle, no_error
	
	clr door_open_in_cycle
    setb error_flag
	lcall start_button
	
no_error:

    mov a, ramp_to_soak_flag
    jz ramp_to_soak_done
    lcall ramp_to_soak
    
ramp_to_soak_done:
	
	mov a, soak_flag
    jz soak_done
    lcall soak
    
soak_done:

	mov a, ramp_to_peak_flag
    jz ramp_to_peak_done
    lcall ramp_to_peak
    
ramp_to_peak_done:

	mov a, reflow_flag
    jz reflow_done
    lcall reflow
    
reflow_done:
    
    mov a, cooling_flag
    jz cooling_done
    lcall cooling
    
cooling_done:

    mov a, routine_done_flag
    jz done
    lcall routine_done

done:
    pop acc
    ret

;------------------------------------;
; Subroutine for: Ramp to soak state ;
;------------------------------------;
ramp_to_soak:

    push acc
    push DPH
    push DPL
    
    setb LED_BLUE 
	setb LED_GREEN
	clr LED_RED 
    
    mov a, counter
	jnz ramp_soak_setup_done
	
	mov a, BCD_counter
	add a, #60
	da a
	mov counter, a
	mov speaker_flag, #0x01
	
ramp_soak_setup_done:

	mov x+0, BCD_counter
	mov x+1, #0
	mov x+2, #0
	mov x+3, #0
	
	mov y+0, counter
	mov y+1, #0
	mov y+2, #0
	mov y+3, #0
	
	lcall x_gteq_y
	jnb mf, no_temp_check
	
	mov y+0, #50
	mov y+1, #0
	mov y+2, #0
	mov y+3, #0
	
	mov x+0, temp_save+0
    mov x+1, temp_save+1
    mov x+2, temp_save+2
    mov x+3, temp_save+3
    
    lcall x_lteq_y
    jnb mf, no_temp_check
    
    setb error_flag
    lcall start_button
    ljmp ramp_is_not_done

no_temp_check:

    setb OVEN_RELAY          ; Turn heater ON
    mov PWM_duty_cycle, #10
    ;Temporarly replaced with fan, will change back later

    mov a, profile
    cjne a, #0x03, ramp_soak_not_profile3
    
    mov a, custom_soak_temp
    ljmp ramp_soak_profile_check

ramp_soak_not_profile3:
    
    mov DPTR, #soak_temperature
	movc a, @a+DPTR
	
ramp_soak_profile_check:
	
    mov y+0, a
    mov y+1, #0
    mov y+2, #0
    mov y+3, #0

    mov x+0, temp_save+0
    mov x+1, temp_save+1
    mov x+2, temp_save+2
    mov x+3, temp_save+3
    
    lcall x_gt_y
    jnb mf, ramp_is_not_done 

    mov ramp_to_soak_flag, #0x00
    mov soak_flag, #0x01
    mov counter, #0x00  ; Reset counter for the Soak timer
    mov speaker_flag, #0x01

ramp_is_not_done:

    pop DPL
    pop DPH
    pop acc
    ret
	
;---------------------------------;
; Subroutine for: Soak state	  ;
;---------------------------------;
soak:
	push acc
	push DPH
	push DPL
	
	clr LED_BLUE 
	setb LED_GREEN
	clr LED_RED 
	
    mov a, profile
    cjne a, #0x03, soak_not_profile3
    
    mov a, custom_soak_temp
    ljmp soak_profile_check

soak_not_profile3:
    
    mov DPTR, #soak_temperature
	movc a, @a+DPTR
	
soak_profile_check:
	
	add a, #1
	
    mov y+0, a
    mov y+1, #0
    mov y+2, #0
    mov y+3, #0

    mov x+0, temp_save+0
    mov x+1, temp_save+1
    mov x+2, temp_save+2
    mov x+3, temp_save+3
    
    lcall x_gteq_y
    jb mf, soak_too_high 
    
    mov a, y+0
    add a, #1
    mov y+0, a
    
    lcall x_gteq_y
    jb mf, soak_way_too_high
    
    mov a, y+0
    subb a, #3
    
    mov y+0, a
    mov y+1, #0
    mov y+2, #0
    mov y+3, #0
    
    lcall x_lteq_y
    jb mf, soak_too_low
    
    ljmp soak_temp_set
	
soak_too_high:
    
    setb pwm_mode
    clr OVEN_RELAY
    mov PWM_duty_cycle, #5
    ljmp soak_temp_set
    
soak_way_too_high:
    
    setb pwm_mode
    clr OVEN_RELAY
    mov PWM_duty_cycle, #10
    ljmp soak_temp_set
    
    
soak_too_low:
	
	clr pwm_mode
    setb OVEN_RELAY
    
soak_temp_set:

	mov a, counter
	jnz soak_setup_done
	
	mov a, profile
    cjne a, #0x03, soak_not_profile3_2
    
    mov a, custom_soak_time
    ljmp soak_profile_check2

soak_not_profile3_2:
    
    mov DPTR, #soak_time
	movc a, @a+DPTR
	
soak_profile_check2:
	
	mov x+0, a
	mov x+1, #0
	mov x+2, #0
	mov x+3, #0
	
	lcall hex2bcd
	
	mov a, x+0
	
	add a, BCD_counter	;Such that a = current time (in BCD counter) + however long we want it to wait (in soak)
    da a
	mov counter, a
	
soak_setup_done:

	mov x+0, counter
	mov x+1, #0
	mov x+2, #0
	mov x+3, #0
	
	mov y+0, BCD_counter
	mov y+1, #0
	mov y+2, #0
	mov y+3, #0
	
	lcall x_gteq_y
	jb mf, soak_return
	
	mov counter, #0x00
	mov soak_flag, #0x00
	mov ramp_to_peak_flag, #0x01
    mov speaker_flag, #0x01
	
soak_return:

	pop DPL
	pop DPH
	pop acc
	
	ret

;-----------------------------------------;
; Subroutine for: ramp to peak state	  ;
;-----------------------------------------;
ramp_to_peak:
	push acc
    push DPH
    push DPL
    
    clr LED_BLUE 
	setb LED_GREEN
	setb LED_RED 

    setb OVEN_RELAY          ; Turn heater ON
    mov PWM_duty_cycle, #10

    mov a, profile
    cjne a, #0x03, ramp_reflow_not_profile3
    
    mov a, custom_reflow_temp
    ljmp ramp_reflow_profile_check

ramp_reflow_not_profile3:
    
    mov DPTR, #reflow_temperature
	movc a, @a+DPTR
	
ramp_reflow_profile_check:
	
    mov y+0, a
    mov y+1, #0
    mov y+2, #0
    mov y+3, #0

    mov x+0, temp_save+0
    mov x+1, temp_save+1
    mov x+2, temp_save+2
    mov x+3, temp_save+3
    
    lcall x_gt_y
    jnb mf, intermediate_ramp_is_not_done 

    mov ramp_to_peak_flag, #0x00
    mov reflow_flag, #0x01
    mov counter, #0x00  ; Reset counter for the Soak timer
    mov speaker_flag, #0x01
    ljmp ramp_is_not_done2
    
intermediate_ramp_is_not_done:
	ljmp ramp_is_not_done

ramp_is_not_done2:

    pop DPL
    pop DPH
    pop acc
    ret
	
;---------------------------------;
; Subroutine for: Reflow state	  ;
;---------------------------------;
reflow:

	push acc
	push DPH
	push DPL
	
	clr LED_BLUE 
	clr LED_GREEN
	setb LED_RED 
	
	mov a, profile
    cjne a, #0x03, reflow_not_profile3
    
    mov a, custom_reflow_temp
    ljmp reflow_profile_check

reflow_not_profile3:
    
    mov DPTR, #soak_temperature
	movc a, @a+DPTR
	
reflow_profile_check:

	add a, #1
	
    mov y+0, a
    mov y+1, #0
    mov y+2, #0
    mov y+3, #0

    mov x+0, temp_save+0
    mov x+1, temp_save+1
    mov x+2, temp_save+2
    mov x+3, temp_save+3
    
    lcall x_gteq_y
    jb mf, relay_too_high 
    
    mov a, y+0
    add a, #1
	
    mov y+0, a
    mov y+1, #0
    mov y+2, #0
    mov y+3, #0
    
    lcall x_gteq_y
    jb mf, relay_way_too_high 
    
    mov a, y+0
    subb a, #3
    
    mov y+0, a
    mov y+1, #0
    mov y+2, #0
    mov y+3, #0
    
    lcall x_lteq_y
    jb mf, relay_too_low
    
    ljmp relay_temp_set
	
relay_too_high:
    
    setb pwm_mode
    clr OVEN_RELAY
    mov PWM_duty_cycle, #5
    ljmp relay_temp_set
    
relay_way_too_high:
    
    setb pwm_mode
    clr OVEN_RELAY
    mov PWM_duty_cycle, #10
    ljmp relay_temp_set
    
relay_too_low:
	
	clr pwm_mode
    setb OVEN_RELAY
    
relay_temp_set:
	
	mov a, counter
	jnz reflow_setup_done
	
	mov a, profile
    cjne a, #0x03, reflow_not_profile3_2
    
    mov a, custom_reflow_time
    ljmp reflow_profile_check2

reflow_not_profile3_2:
    
    mov DPTR, #soak_time
	movc a, @a+DPTR
	
reflow_profile_check2:
	
	add a, BCD_counter	;Such that a = current time (in BCD counter) + however long we want it to wait (in soak)
    da a
	mov counter, a
	
reflow_setup_done:
	
	mov x+0, counter
	mov x+1, #0
	mov x+2, #0
	mov x+3, #0
	
	mov y+0, BCD_counter
	mov y+1, #0
	mov y+2, #0
	mov y+3, #0
	
	lcall x_gteq_y
	jb mf, reflow_return
	
	mov counter, #0x00
	mov reflow_flag, #0x00
	mov cooling_flag, #0x01
    mov start_stop, #0x00
    mov speaker_flag, #0x01
	
reflow_return:

	pop DPL
	pop DPH
	pop acc

	ret
	
;---------------------------------;
; Subroutine for: Cooling state	  ;
;---------------------------------;
cooling:
	push acc
	push DPH
	push DPL
	
	setb LED_BLUE 
	setb LED_GREEN
	setb LED_RED
	
	mov a, counter
    jnz no_errors
    jnb error_flag, cooling_speaker_done
	
	mov a, BCD_counter
	add a, #0x20
	da a
	mov counter, a  
	
no_errors:	

    mov a, BCD_counter	
	cjne a, counter, cooling_speaker
	
	mov speaker_flag, #0x00
	clr SPEAKER
	mov counter, #0x00
	clr error_flag
	ljmp cooling_speaker_done
	
cooling_speaker:
 	
    mov a, speaker_flag
    jz speaker_flag_switch_cooling
    
    mov speaker_flag, #0x00
    ljmp cooling_speaker_done
    
speaker_flag_switch_cooling:
    
    mov speaker_flag, #0x01
	
cooling_speaker_done:

	setb PWM_mode
	mov PWM_duty_cycle, #010
	clr OVEN_RELAY
	
	mov a, profile
    cjne a, #0x03, cooling_not_profile3
    
    mov a, custom_cooling_temp
    ljmp cooling_profile_check

cooling_not_profile3:
    
    mov DPTR, #cooling_temperature
	movc a, @a+DPTR
	
cooling_profile_check:
	
    mov y+0, a
    mov y+1, #0
    mov y+2, #0
    mov y+3, #0

    mov x+0, temp_save+0
    mov x+1, temp_save+1
    mov x+2, temp_save+2
    mov x+3, temp_save+3
    
    lcall x_gteq_y
    jb mf, cooling_return 
    
    mov a, counter
    jz error_stall_skip
    mov a, BCD_counter
    cjne a, counter, cooling_return

error_stall_skip:

	mov counter, #0x00
    mov routine_done_flag, #0x01
    mov cooling_flag, #0x00
    mov speaker_flag, #0x01
    mov start_stop, #0x00
    clr pwm_mode
    clr error_flag
	
	
cooling_return:

	pop DPL
	pop DPH
	pop acc
	
	ret

;---------------------------------------------;
; Subroutine for: Everything is done state	  ;
;---------------------------------------------;
routine_done:
	push acc
	push DPH
	push DPL
	
	setb LED_BLUE 
	clr LED_GREEN
	clr LED_RED  

    mov a, counter
    jnz five_beep_setup_done
	
	mov a, BCD_counter
	add a, #0x10
	da a
	mov counter, a
	
five_beep_setup_done:
	
	mov a, BCD_counter	
	cjne a, counter, routine_done_return
	
routine_done_skip:

	mov speaker_flag, #0x00
	mov routine_done_flag, #0x00
	clr SPEAKER
	mov counter, #0x00
	clr error_flag
	ljmp speaker_return
	
routine_done_return:
 	
    mov a, speaker_flag
    jz speaker_flag_switch
    
    mov speaker_flag, #0x00
    ljmp speaker_return
    
speaker_flag_switch:
    
    mov speaker_flag, #0x01
 	
speaker_return:

	pop DPL
	pop DPH
	pop acc
	
	ret

;-------------------------------------------;
; subroutine for: unit switching button     ;
;-------------------------------------------;
unit_switching_button:
	push acc

	inc unit
    mov a, unit
    cjne a, #3, unit_change_done

    mov unit, #0

unit_change_done:

    pop acc
    ret


;-------------------------------------------;
; subroutine for: display switching button  ;
;-------------------------------------------;
display_switching_button:
	push acc

	inc LCD_display_profile
    mov a, LCD_display_profile
    cjne a, #3, LCD_profile_change_done

    mov LCD_display_profile, #0

LCD_profile_change_done:

    pop acc
    ret

;-------------------------------------;
; Subroutine for: Start/stop button	  ;
;-------------------------------------;
start_button:
	
    mov a, start_stop
    jz start_process

    mov cooling_flag, #0x01
    mov ramp_to_soak_flag, #0x00
    mov soak_flag, #0x00
    mov ramp_to_peak_flag, #0x00
    mov reflow_flag, #0x00
    mov counter, #0x00
    mov routine_done_flag, #0x00
    mov speaker_flag, #0x01

    mov start_stop, #0x00
    
    ljmp start_button_done

start_process:

	mov ramp_to_soak_flag, #0x01
	mov cooling_flag, #0x00
    mov soak_flag, #0x00
    mov ramp_to_peak_flag, #0x00
    mov reflow_flag, #0x00
    mov routine_done_flag, #0x00
    mov start_stop, #0x01
    mov counter, #0x00

start_button_done:
	ret

;-------------------------------------;
; Subroutine for: Profile button	  ;
;-------------------------------------;
profile_button:
	push acc

    inc profile
    mov a, profile
    cjne a, #03, profile_change_done

    mov profile, #0x00

profile_change_done:

    pop acc
    ret

;------------------------------------;
; Scott's Subroutines                ;
;------------------------------------;



;===================== SECTION BREAK =========================

;main:

main:
	; Initialization
    mov SP, #0x7F
    lcall Timer0_Init
    lcall Timer1_Init
    lcall Timer2_Init

    mov P0MOD, #10101010b ; P0.1, P0.3, P0.5, P0.7 are outputs.  ('1' makes the pin output)
    mov P1MOD, #10000010b ; P1.7 and P1.1 are outputs
    mov P2MOD, #10000000b
    mov P3MOD, #10111101b
    mov p4mod, #11111111b
    ;TODO: Double check these pin assignments (i.e. input/output)
    
    ; Turn off all the LEDs
    mov LEDRA, #0 ; LEDRA is bit addressable
    mov LEDRB, #0 ; LEDRB is NOT bit addresable
    
    setb EA   ; Enable Global interrupts
    lcall ELCD_4BIT ; Configure LCD in four bit mode
    ; For convenience a few handy macros are included in 'LCD_4bit_DE1Lite.inc':
    
    setb second_flag
	mov BCD_counter, #0x00 ; Initialize counter to zero
	mov ADC_C, #0x80 ; Reset ADC
	
	mov ramp_to_soak_flag, #0x00
	mov soak_flag, #0x00
	mov ramp_to_peak_flag, #0x00
	mov reflow_flag, #0x00
	mov cooling_flag, #0x00
    mov routine_done_flag, #0x00
    mov speaker_flag, #0x00
	
	mov profile, #0x00
	mov counter, #0x00
    mov start_stop, #0x00
    mov unit, #0x00

    setb LED_BLUE 
	clr LED_GREEN
	clr LED_RED  
    
	clr TR0 ; Stop timer 0
	clr a
	mov Count1ms+0, a
	mov Count1ms+1, a
	mov BCD_counter, a
	setb TR0
	
    clr second_flag
    clr options_mode
    clr error_flag

    Set_Cursor(1, 1)
    Send_Constant_String(#start_message)
    Set_Cursor(2,1)
    Send_Constant_String(#start_message2)

    lcall initialize_ir_sensor
    lcall initialize_custom_profiles
   
	
	ljmp loop


;===================== SECTION BREAK =========================

;Forever loop:

;Warning: A good chunk of this code was written while I still have a fevor, soooo
;yeah, bewarned. 

loop:

    jb TEMP_UNIT_TOGGLE, check_display
	Wait_Milli_Seconds(#50)  ; debounce
    jb TEMP_UNIT_TOGGLE, check_display
    jnb TEMP_UNIT_TOGGLE, $ 
    lcall unit_switching_button
    ljmp check_display
	
check_display:
    
    jb TOGGLE_DISPLAY, check_start
    Wait_Milli_Seconds(#50)  ; debounce
    jb TOGGLE_DISPLAY, check_start
    jnb TOGGLE_DISPLAY, $ 
    lcall display_switching_button
    ljmp check_start
	
check_start:
    
    jb KEY.1, check_options
    Wait_Milli_Seconds(#50)  ; debounce
    jb KEY.1, check_options
    jnb KEY.1, $ 
    lcall start_button
    ljmp check_options
 
check_options:
	mov a, start_stop
	jnz loop
    jb OPTIONS, loop
    Wait_Milli_Seconds(#50)  ; debounce
    jb OPTIONS, loop
    jnb OPTIONS, $
    lcall options_menu
    ljmp loop

profile_button_skip:

    clr half_second_flag
    clr second_flag

ljmp loop
	
;===================== SECTION BREAK =========================
;data section:

soak_time: 		  DB 60, 120, 0
reflow_time: 	  DB 30, 45 , 0
cooling_time: 	  DB 20, 120, 0 ;These are just preliminary values (pre-set "profiles". Will adjust later)
							        ;NOTE: I am currently using the BCD counter to keep time, and therefore these
							        ;values represent seconds. I.e. 120 = 60 sec

soak_temperature:     DB 150, 130, 150, 0
reflow_temperature:   DB 220, 200, 220, 0
cooling_temperature:  DB 25, 30, 25, 0        ;Might need to change to voltage rather than temp. 

myLUT:
    DB 0xC0, 0xF9, 0xA4, 0xB0, 0x99        ; 0 TO 4
    DB 0x92, 0x82, 0xF8, 0x80, 0x90        ; 4 TO 9
    DB 0x88, 0x83, 0xC6, 0xA1, 0x86, 0x8E  ; A to F

END