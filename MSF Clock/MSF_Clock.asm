/*	=== MSF time signal receiver clock ===
 
 	ATtiny2313 @ 12MHz

	(C) 2010 Paul Qureshi


	PD3/INT1	-	MSF inverted output
	PD4			-	MSF power on

	PD0			-	Melody Generator Data
	PD2			-	Melody Generator Attention

	PB7			-	SET
	PB6			-	DOWN
	PB5			-	UP

	Display digits: 3-2-1-0 (i.e. 3 is left-most, 0 is right-most)
*/

.include "tn4313def.inc"

;----------------------------------------------------------------------
; Register and I/O definitions
;----------------------------------------------------------------------

.def	secs		= R2
.def	mins		= R3
.def	hours		= R4

.def	sregsave	= R5	; used by interrupts
.def	timer		= R6	; 100Hz timer incremented by timer0 interrupt
.def	mux			= R7	; display MUX counter
.def	digit0		= R8
.def	digit1		= R9
.def	digit2		= R10
.def	digit3		= R11
.def	dot0		= R12	; 0 = lower .
							; 1 = upper .
							; 2 = display multiplex off
							; 4 = display melody0
							; 5 = mins flashing
							; 6 = hours flashing
							; 7 = time display update by interrupt

.def	mins_s		= R13	; shadow registers
.def	hours_s		= R14
.def	cycle		= R15	; decode cycle counter

; working registers
.def	temp0		= R16
.def	temp1		= R17
.def	temp2		= R18
.def	temp3		= R19
.def	temp4		= R20
.def	temp5		= R21

.def	isig		= R22	; signal from interrupt to main program
							; 0 - minute tick
							; 1 - hour tick

.def	endhour		= R24

; pointers
; Z - UART strings

; MSF receiver
.equ	PON			= 4		; PORTD
.equ	INV			= 3		;

; RAM
.equ	MSF_SOM		= 0x0f	; start of minute
.equ	MSF_ERR		= 0xff	; error

.equ	MSFRAM		= 0x0060	; 60 bytes for MSF decoder
.equ	phours_c	= 0x00A0	; temporary MSF decoded value storage
.equ	pmins_c		= 0x00A1	;
.equ	pvalid		= 0x00A2	;

.equ	sectick		= 0x00A3	; interrupt sub-centisecond counter

.equ	alarmflags	= 0x00B0	; 0 = alarm 0 on/off
								; 1 = hour chime on/off
.equ	alarm0min	= 0x00B1
.equ	alarm0hr	= 0x00B2
.equ	alarm0mel	= 0x00B3
.equ	hrmel		= 0x00B4

; EEPROM
.equ	eepalarmf	= 0x00	; global alarm flags
.equ	eepalarm0hr	= 0x01	; alarm 0 hours
.equ	eepalarm0min= 0x02	; alarm 0 minutes
.equ	eepalarm0mel= 0x03	; alarm 0 melody
.equ	eephrmel	= 0x04	; hour chime melody

; LED display
.equ	SEG0		= 2		; PORTB
.equ	SEG1		= 3		;
.equ	SEG2		= 4		;
.equ	SEG3		= 5		; PORTD

.equ	DAT			= 6		; PORTD
.equ	LAT			= 0		; PORTB
.equ	CLK			= 1		;

; Melody Generator
.equ	MEL_ATT		= 1		; PORTD
.equ	MEL_DAT		= 0		;

; PPS
.equ	PPS			= 2		; PORTD


;----------------------------------------------------------------------
; Vector table
;----------------------------------------------------------------------

.cseg

.org 0
		rjmp	reset		;RESET External Pin, Power-on Reset, Brown-out, and Watchdog Reset
		rjmp	t1caint		;INT0 External Interrupt Request 0
		reti				;INT1 External Interrupt Request 1
		reti				;TIMER1 CAPT Timer/Counter1 Capture Event
		rjmp	t1caint		;TIMER1 COMPA Timer/Counter1 Compare Match A
		reti				;TIMER1 OVF Timer/Counter1 Overflow
		reti				;TIMER0 OVF Timer/Counter0 Overflow
		reti				;USART, RXC USART, Rx Complete
		reti				;USART, UDRE USART Data Register Empty
		reti				;USART, TXC USART, Tx Complete
		reti				;ANA_COMP Analog Comparator
		reti				;PCINT
		rjmp	t1cbint		;TIMER1 COMPB Match B
		rjmp	t0caint		;TIMER0 COMPA Match A
		reti				;TIMER0 COMPB Match B
		reti				;USI START
		reti				;USI OVERFLOW
		reti				;EE READY
		reti				;WDT OVERFLOW



;----------------------------------------------------------------------
; timer0 COMPA interrupt
; 100Hz timer
;----------------------------------------------------------------------

t0caint:
		in		sregsave, sreg
		inc		timer
		out		sreg, sregsave
		reti



;----------------------------------------------------------------------
; timer1 COMPA interrupt
; Time register update
;----------------------------------------------------------------------

t1caint:
		in		sregsave, sreg
		push	sregsave
		push	temp0
		push	temp1

		; subseconds tick
		lds		temp0, sectick
		inc		temp0
		andi	temp0, 0b00000011
		sts		sectick, temp0
		tst		temp0
		brne	t1ca_exit

		; seconds tick
		inc		secs
		ldi		temp0, 60
		cp		secs, temp0
		brne	t1ca_exit

		; minutes stick
		clr		secs
		inc		mins
		ori		isig, (1<<0)				; minute tick
		cp		mins, temp0
		brne	t1ca_no_rollover_mins

		; hours tick
		clr		mins
		inc		hours
		ori		isig, (1<<1)				; hour tick
		ldi		temp0, 24
		cp		hours, temp0
		brne	t1ca_update_display
		clr		hours

t1ca_no_rollover_mins:
		;rcall	check_alarm
t1ca_update_display:
		sei									; enable display mux interrupt to keep
											; running
		sbrs	dot0, 7
		rcall	set_digits


t1ca_exit:
		pop		temp1
		pop		temp0
		pop		sregsave
		out		sreg, sregsave
		reti


;----------------------------------------------------------------------
; timer1 COMPB interrupt
; Display multiplex
;----------------------------------------------------------------------

t1cbint:
		in		sregsave, sreg
		push	sregsave
		;sei									; allow other interrupts to run
		push	temp0
		push	temp1

t1_display_mux:
		; display mux
		sbrc	dot0, 2						; multiplex on/off?
		rjmp	t1_done

		mov		temp0, mux

		mov		temp1, mux					; increment mux
		inc		temp1
		andi	temp1, 0b00000011
		mov		mux, temp1

		cpi		temp0, 0					; find and decode correct digit
		brne	t1_mux_not_0
		sbi		PORTD, SEG3
		mov		temp0, digit0
		rcall	shift_out
		cbi		PORTB, SEG0
		rjmp	t1_done

t1_mux_not_0:
		cpi		temp0, 1
		brne	t1_mux_not_1
		sbi		PORTB, SEG0
		mov		temp0, digit1
		//sbrc	dot0, 0
		//ori		temp0, (1<<7)
		rcall	shift_out
		cbi		PORTB, SEG1
		rjmp	t1_done

t1_mux_not_1:
		cpi		temp0, 2
		brne	t1_mux_not_2
		sbi		PORTB, SEG1
		mov		temp0, digit2
		sbrc	dot0, 0
		ori		temp0, (1<<7)
		rcall	shift_out
		cbi		PORTB, SEG2
		rjmp	t1_done

t1_mux_not_2:
		sbi		PORTB, SEG2
		mov		temp0, digit3
		rcall	shift_out
		cbi		PORTD, SEG3
		;rjmp	t1_done

t1_done:
		pop		temp1
		pop		temp0
		pop		sregsave
		out		sreg, sregsave
		reti



;----------------------------------------------------------------------
; Reset
;----------------------------------------------------------------------

reset:
		ldi		temp0, LOW(RAMEND)			; initialization of stack
		out		SPL, temp0

		; PORTA
		ldi		temp0, 0xff
		out		PORTA, temp0
		ldi		temp0, 0
		out		DDRA, temp0

		; PORTB
		ldi		temp0, 0xff
		out		PORTB, temp0
		ldi		temp0, 0b00011111			; outputs except for USI
		out		DDRB, temp0

		; PORTD
		; inputs with pull-ups, PON high (off), melody generator outputs start high 
		; PPS as input, no pull-up
		ldi		temp0,~(1<<PON)
		out		PORTD, temp0
		ldi		temp0, (1<<PON)|(1<<DAT)|(1<<SEG3)|(1<<MEL_ATT)|(1<<MEL_DAT)
		out		DDRD, temp0

		; Set up UART
		;ldi		temp0, 0x00					; 9600 baud
		;out		UBRRH, temp0
		;ldi		temp0, 0x4d
		;out		UBRRL, temp0
		;ldi		temp0, 0
		;out		UCSRA, temp0
		;ldi		temp0, (1<<TXEN)
		;out		UCSRB, temp0
		;ldi		temp0, (1<<UCSZ1)|(1<<UCSZ0)
		;out		UCSRC, temp0

		; 2Hz clock input
		ldi		temp0, (1<<ISC00)			; trigger on any edge
		out		MCUCR, temp0
		ldi		temp0, (1<<INT0)
		out		GIMSK, temp0

		; timer0 (100Hz counter for MSF decoding)
		ldi		temp0, (1<<WGM01)			; CTC mode
		out		TCCR0A, temp0
		ldi		temp0, (1<<CS02)|(1<<CS00)	; 1024 prescaler
		out		TCCR0B, temp0
		ldi		temp0, (1<<OCIE0A)			; output compare A interrupt enable
		out		TIMSK, temp0
		ldi		temp0, 0
		out		TIFR, temp0
		ldi		temp0, 0x74					; 100Hz (0.163%)
		out		OCR0A, temp0
		ldi		temp0, 0					; clear counter
		out		TCNT0, temp0

		; timer1 (display multiplex)
		clr		mux
		ldi		temp0, 0					; CTC mode
		out		TCCR1A, temp0
		ldi		temp0, (1<<WGM12)|(1<<CS11)	; CTC mode, 8 prescaler
		out		TCCR1B, temp0
		ldi		temp0, 0
		out		TCCR1C, temp0
		in		temp0, TIMSK
		;ori	temp0, (1<<OCIE1A)|(1<<OCIE1B)		; output compare 1A interrupt enable
		ori		temp0, (1<<OCIE1B)			; output compare 1B interrupt enable
		out		TIMSK, temp0
		ldi		temp0, 0x0e					; 400Hz (0.000%)
		ldi		temp1, 0xa5
		out		OCR1AH, temp0
		out		OCR1AL, temp1
		ldi		temp0, 0x0e					; 400Hz (0.000%)
		ldi		temp1, 0xa5
		out		OCR1BH, temp0
		out		OCR1BL, temp1

		ldi		temp0, 0					; clear counter
		out		TCNT1H, temp0
		out		TCNT1L, temp0

		; initial time values
		ldi		temp0, 0
		mov		hours, temp0
		;ldi		temp0, 59
		mov		mins, temp0
		;ldi		temp0, 58
		mov		secs, temp0
		ldi		temp0, 0
		sts		sectick, temp0

		rcall	set_digits

		; UART debugging output
		;ldi		ZH, HIGH(2*str_header)
		;ldi		ZL, LOW(2*str_header)
		;rcall	uart_puts

		; clear MSF ram 
		ldi		temp0, 0
		sts		MSFRAM, temp0

		; default alarms off
		ldi		temp0, 0
		sts		alarmflags, temp0
		sts		alarm0hr, temp0
		sts		alarm0min, temp0
		sts		alarm0mel, temp0
		sts		hrmel, temp0

		clr		isig						; reset interrupt signals

		; EEPROM config 
		ldi		temp0, (1<<EEMPE)			; atomic write mode
		out		EECR, temp0

		rcall	eeprom_load_alarm

		;ldi		temp0, 0
		;rcall	play_melody

		sei

		// test decoder //
		;rcall	load_test
		;rcall	msf_decode
		;rcall	set_digits

		rjmp	main



;----------------------------------------------------------------------
; Main loop
;----------------------------------------------------------------------

main:
		; find correct time from MSF receiver
		ldi		endhour, 25					; never stop getting the correct time
main_find_time_loop:
		rcall	msf_receive

		clr		dot0
		inc		dot0
		rcall	set_digits

		; wait until not 3AM 
		ldi		temp2, 3
main_wait_not_3am:
		sleep
		rcall	button_input
		; alarm check
		sbrc	isig, 0
		rcall	check_alarm
		; hour chime
		sbrc	isig, 1
		rcall	hour_chime
		; reset interrupt signals
		clr		isig
		cp		hours, temp2
		breq	main_wait_not_3am

		; re-sync time at 3AM 
		ldi		temp2, 3
main_wait_for_3am:
		sleep
		rcall	button_input
		; alarm check
		sbrc	isig, 0
		rcall	check_alarm
		; hour chime
		sbrc	isig, 1
		rcall	hour_chime
		; reset interrupt signals
		clr		isig
		cp		hours, temp2
		brne	main_wait_for_3am
/*
		mov		mins, temp0
		inc		temp0
debug_wait:
		cp		mins, temp0
		brne	debug_wait
*/
		clr		cycle
		ldi		endhour, 4					; give up if not synced by 4AM 
		rjmp	main_find_time_loop



;----------------------------------------------------------------------
; Check alarm against current time
;----------------------------------------------------------------------

check_alarm:
		push	temp0
		push	temp1

		lds		temp0, alarmflags
		sbrs	temp0, 0					; alarm on?
		rjmp	check_alarm_return
		
		lds		temp1, alarm0hr
		cp		hours, temp1
		brne	check_alarm_return
		lds		temp1, alarm0min
		cp		mins, temp1
		brne	check_alarm_return

		lds		temp0, alarm0mel
		rcall	play_melody
		andi	isig, ~(1<<1)				; cancel hour chime in case alarm
		rjmp	check_alarm_return			; is at 00 minutes

check_alarm_return:
		pop		temp1
		pop		temp0
		ret



;----------------------------------------------------------------------
; Handle all button input
;----------------------------------------------------------------------

hour_chime:
		push	temp0
		; top of the hour?
		tst		mins
		brne	hour_chime_skip
		; don't play for hours 00-07
		ldi		temp0, 8
		cp		hours, temp0
		brlo	hour_chime_skip
		lds		temp0, hrmel
		rcall	play_melody
hour_chime_skip:
		pop		temp0
		ret



;----------------------------------------------------------------------
; Handle all button input
;----------------------------------------------------------------------

button_input:
		sbic	PINB, 7						; SET button
		ret

		push	temp0
		push	temp1
		push	temp2

		cli									; set up 100Hz timer
		clr		temp0
		out		TCNT0, temp0
		clr		timer
		sei

		; only enter SET mode if button is held for 1 second
		ldi		temp0, 100					; 100 ticks = 1 second
button_check_set_held:
		sbic	PINB, 7
		rjmp	button_return
		cp		timer, temp0
		brlo	button_check_set_held

		; turn off display update by interrupt
		mov		temp0, dot0
		ori		temp0, (1<<7)
		andi	temp0, ~(1<<0)
		mov		dot0, temp0




		// Alarm on/off //
		lds		temp0, alarmflags
		ldi		temp1, 0b01110111			; A
		mov		digit3, temp1
		rcall	button_on_off_mode
		sts		alarmflags, temp0




		// set alarm hours //
		rcall	button_release_keys

		mov		temp0, dot0
		ori		temp0, 0b11000000			; hours flashing
		mov		dot0, temp0

		;clr		timer

button_alarm_hours0:
		rcall	set_digits
		in		temp2, PINB
		andi	temp2, 0b11100000
		cpi		temp2, 0b11100000
		breq	button_alarm_hours0

		sbrs	temp2, 7					; SET
		rjmp	button_a0hr_done

		sbrs	temp2, 6					; DOWN = off
		rjmp	button_a0hr_not_down
		lds		temp0, alarm0hr
		dec		temp0
		brpl	button_a0hr_down_pos
		ldi		temp0, 23
button_a0hr_down_pos:
		sts		alarm0hr, temp0
		rcall	button_key_repeat
button_a0hr_not_down:

		sbrs	temp2, 5					; UP = on
		rjmp	button_a0hr_not_up
		lds		temp0, alarm0hr
		inc		temp0
		cpi		temp0, 24
		brlo	button_a0hr_up_under
		ldi		temp0, 0
button_a0hr_up_under:
		sts		alarm0hr, temp0
		rcall	button_key_repeat
button_a0hr_not_up:

		rjmp	button_alarm_hours0

button_a0hr_done:



		// set alarm minutes //
		rcall	button_release_keys

		mov		temp0, dot0
		andi	temp0, ~0b01000000
		ori		temp0,  0b10100000			; mins flashing
		mov		dot0, temp0

		;clr		timer

button_alarm_mins0:
		rcall	set_digits
		in		temp2, PINB
		andi	temp2, 0b11100000
		cpi		temp2, 0b11100000
		breq	button_alarm_mins0

		sbrs	temp2, 7					; SET
		rjmp	button_a0min_done

		sbrs	temp2, 6					; DOWN = off
		rjmp	button_a0min_not_down
		lds		temp0, alarm0min
		dec		temp0
		brpl	button_a0min_down_pos
		ldi		temp0, 59
button_a0min_down_pos:
		sts		alarm0min, temp0
		rcall	button_key_repeat
button_a0min_not_down:

		sbrs	temp2, 5					; UP = on
		rjmp	button_a0min_not_up
		lds		temp0, alarm0min
		inc		temp0
		cpi		temp0, 60
		brlo	button_a0min_up_under
		ldi		temp0, 0
button_a0min_up_under:
		sts		alarm0min, temp0
		rcall	button_key_repeat
button_a0min_not_up:

		rjmp	button_alarm_mins0

button_a0min_done:



		// Alarm 0 Melody selection //
		rcall	button_release_keys
		lds		temp0, alarm0mel
		rcall	button_mel_mode
		sts		alarm0mel, temp0



		// Hour chime on/off //
		;rcall	button_release_keys
		lds		temp4, alarmflags
		bst		temp4, 1
		bld		temp0, 0
		ldi		temp1, 0b01110110			; H
		mov		digit3, temp1
		rcall	button_on_off_mode
		bst		temp0, 0					; move the bit into the right place
		bld		temp4, 1
		sts		alarmflags, temp4

		// Hour Chime Melody selection //
		rcall	button_release_keys
		lds		temp0, hrmel
		rcall	button_mel_mode
		sts		hrmel, temp0


		
button_restore_display:
		; turn display update by interrupt back on
		mov		temp0, dot0
		ori		temp0, (1<<0)
		andi	temp0, 0b00001111
		mov		dot0, temp0
		rcall	set_digits

		rcall	eeprom_save_alarm

button_return:
		pop		temp2
		pop		temp1
		pop		temp0
		ret



;----------------------------------------------------------------------
; Button handling utilities
;----------------------------------------------------------------------

button_on_off_mode:
		sbrc	temp0, 0					; alarm on/off bit
		rcall	button_set_display_on
		sbrs	temp0, 0					; alarm on/off bit
		rcall	button_set_display_off
		rcall	button_release_keys

button_on_off_wait:
		in		temp2, PINB
		andi	temp2, 0b11100000
		cpi		temp2, 0b11100000
		breq	button_on_off_wait
		
		sbrs	temp2, 7					; SET
		rjmp	button_on_off_done
		sbrs	temp2, 6					; DOWN = off
		andi	temp0, ~(1<<0)
		sbrs	temp2, 5					; UP = on
		ori		temp0, (1<<0)
		rjmp	button_on_off_mode

button_on_off_done:
		ret



button_mel_mode:
		push	temp0
		mov		temp0, dot0
		andi	temp0, ~0b01000000
		ori		temp0,  0b10010000			; melody selection mode
		mov		dot0, temp0
		pop		temp0

button_mel_mode_loop:
		rcall	set_digits
		in		temp2, PINB
		andi	temp2, 0b11100000
		cpi		temp2, 0b11100000
		breq	button_mel_mode_loop

		sbrs	temp2, 7					; SET
		rjmp	button_mel_done

		sbrs	temp2, 6					; DOWN = off
		rjmp	button_mel_not_down
		;lds		temp0, alarm0mel
		dec		temp0
		brpl	button_mel_down_pos
		ldi		temp0, 4
button_mel_down_pos:
		;sts		alarm0mel, temp0
		rcall	button_key_repeat
button_mel_not_down:

		sbrs	temp2, 5					; UP = on
		rjmp	button_mel_not_up
		;lds		temp0, alarm0mel
		inc		temp0
		cpi		temp0, 5
		brlo	button_mel_up_under
		ldi		temp0, 0
button_mel_up_under:
		;sts		alarm0mel, temp0
		rcall	button_key_repeat
button_mel_not_up:

		rjmp	button_mel_mode_loop

button_mel_done:
		ret



button_key_repeat:
		push	temp0
		clr		timer
		ldi		temp0, 30					; 0.5 seconds
button_key_repeat_loop:
		rcall	set_digits
		cp		timer, temp0
		brlo	button_key_repeat_loop
button_key_repeat_return:
		pop		temp0
		ret



button_release_keys:
		clr		timer
		ldi		temp1, 20					; must be off for 20ms consecutively
button_release_keys_loop:
		in		temp2, PINB
		andi	temp2, 0b11100000
		cpi		temp2, 0b11100000
		brne	button_release_keys
		cp		timer, temp1
		brlo	button_release_keys_loop
		ret



button_set_display_off:
		;ldi		temp2, 0
		;mov		digit3, temp2
		ldi		temp2, 0b00111111			; O
		mov		digit2, temp2
		ldi		temp2, 0b01001110			; F inv
		mov		digit1, temp2
		ldi		temp2, 0b01110001			; F
		mov		digit0, temp2
		ret



button_set_display_on:
		;ldi		temp2, 0
		;mov		digit3, temp2
		ldi		temp2, 0
		mov		digit2, temp2
		ldi		temp2, 0b00111111			; O inv
		mov		digit1, temp2
		ldi		temp2, 0b00110111			; N
		mov		digit0, temp2
		ret

;0b01011100	; o
;0b01100011 ; o inv
;0b01110001	; f/F
;0b01001110	; f/F inv
;0b01010100 ; n
;0b00110111	; N



;----------------------------------------------------------------------
; Send play command to melody generator
; temp0 - melody number to play
;----------------------------------------------------------------------

play_melody:
		push	temp0
		cbi		PORTD, MEL_ATT
		rcall	delay_1ms

play_melody_loop:
		cpi		temp0, 0
		breq	play_melody_exit
		dec		temp0
		cbi		PORTD, MEL_DAT
		rcall	delay_1ms
		sbi		PORTD, MEL_DAT
		rcall	delay_1ms
		rjmp	play_melody_loop

play_melody_exit:
		sbi		PORTD, MEL_ATT
		pop		temp0
		ret



;----------------------------------------------------------------------
; Other files
;----------------------------------------------------------------------

.include "display.asm"
.include "utils.asm"
.include "msf.asm"
.include "strings.asm"
