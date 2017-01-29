;----------------------------------------------------------------------
; Shift out temp0
;----------------------------------------------------------------------

shift_out:
		push	temp0
		push	temp1

		cbi		PORTB, CLK					; start state
		cbi		PORTB, LAT

		ldi		temp1, 8					; loop counter
shift_out_loop:
		sbrs	temp0, 7
		cbi		PORTD, DAT
		sbrc	temp0, 7
		sbi		PORTD, DAT
		nop
		sbi		PORTB, CLK
		nop
		cbi		PORTB, CLK
		rol		temp0
		dec		temp1
		brne	shift_out_loop

		sbi		PORTB, LAT
		nop
		cbi		PORTB, LAT

		pop		temp1
		pop		temp0
		ret



;----------------------------------------------------------------------
; Set Digits based on hours/mins
;----------------------------------------------------------------------

set_digits:
		push	temp0
		push	temp1
		push	temp2

		sbrc	dot0, 4						; 0 = normal, 1 = temp0
		rjmp	set_digits_mel0

		mov		temp0, hours

		sbrs	dot0, 7						; 0 = actual time, 1 = alarm time
		rjmp	set_digits_hours
		lds		temp0, alarm0hr
		sbrs	dot0, 6						; hours flashing?
		rjmp	set_digits_hours
		sbrs	timer, 5					; off part of flashing cycle?
		rjmp	set_digits_hours
		clr		digit3
		clr		digit2
		rjmp	set_digits_mins

set_digits_hours:
		rcall	dec2bcd

		; digit 3 (hours-tens)
		mov		temp1, temp0
		swap	temp1
		andi	temp1, 0x0f
		clr		digit3						; no display if hour = 0X
		cpi		temp1, 0					;
		breq	set_digits_digit2			;
		ldi		ZH, HIGH(sevenseg * 2)
		ldi		ZL, LOW(sevenseg * 2)
		ldi		temp2, 0
		add		ZL, temp1
		adc		ZH, temp2
		lpm
		mov		digit3, r0

set_digits_digit2:
		; digit 2 (hours-units)
		mov		temp1, temp0
		andi	temp1, 0x0f
		ldi		ZH, HIGH(sevenseg * 2)
		ldi		ZL, LOW(sevenseg * 2)
		ldi		temp2, 0
		add		ZL, temp1
		adc		ZH, temp2
		lpm
		mov		digit2, r0

set_digits_mins:
		mov		temp0, mins

		sbrs	dot0, 7						; 0 = actual time, 1 = alarm time
		rjmp	set_digits_minutes
		lds		temp0, alarm0min
		sbrs	dot0, 5						; minutes flashing?
		rjmp	set_digits_minutes
		sbrs	timer, 5					; off part of flashing cycle?
		rjmp	set_digits_minutes
		clr		digit1
		clr		digit0
		rjmp	set_digits_return

set_digits_minutes:
		rcall	dec2bcd

		; digit 1 (minutes-tens, inverted)
		mov		temp1, temp0
		swap	temp1
		andi	temp1, 0x0f
		ldi		ZH, HIGH(sevenseg_inv * 2)
		ldi		ZL, LOW(sevenseg_inv * 2)
		ldi		temp2, 0
		add		ZL, temp1
		adc		ZH, temp2
		lpm
		mov		digit1, r0

		; digit 0
		mov		temp1, temp0
		andi	temp1, 0x0f
		ldi		ZH, HIGH(sevenseg * 2)
		ldi		ZL, LOW(sevenseg * 2)
		ldi		temp2, 0
		add		ZL, temp1
		adc		ZH, temp2
		lpm
		mov		digit0, r0

set_digits_return:		
		pop		temp2
		pop		temp1
		pop		temp0
		ret


set_digits_mel0:
		clr		digit1
		clr		digit2
		clr		digit3
		ldi		ZH, HIGH(sevenseg * 2)
		ldi		ZL, LOW(sevenseg * 2)
		;lds		temp1, alarm0mel
		mov		temp1, temp0
		inc		temp1
		ldi		temp2, 0
		add		ZL, temp1
		adc		ZH, temp2
		lpm
		mov		digit0, r0
		rjmp	set_digits_return



;----------------------------------------------------------------------
; Display on/off
;----------------------------------------------------------------------

display_off:
		push	temp0
		in		temp0, TIMSK
		andi	temp0, ~(1<<OCIE1B)			; disable multiplex interrupt
		out		TIMSK, temp0

		mov		temp0, dot0
		ori		temp0, (1<<2)				; multiplex off
		mov		dot0, temp0

		cbi		PORTB, SEG0					; turn off segments
		cbi		PORTB, SEG1
		cbi		PORTB, SEG2
		cbi		PORTD, SEG3

		ldi		temp0, (1<<6)
		rcall	shift_out
		cbi		PORTB, SEG2					; dot segment on
		pop		temp0
		ret

display_on:
		push	temp0
		in		temp0, TIMSK
		ori		temp0, (1<<OCIE1B)			; enable multiplex interrupt
		out		TIMSK, temp0
		mov		temp0, dot0
		andi	temp0, ~(1<<2)
		mov		dot0, temp0
		pop		temp0
		ret



;----------------------------------------------------------------------
; 7 segment display codes
;----------------------------------------------------------------------

;		1			8   4
;	  6   2			  3   5
;		7			    7
;     5   3			  2   6
;		4	8			1

; 0 - F, 0 = off, 1 = on
sevenseg:
.db	0b00111111, 0b00000110, 0b01011011, 0b01001111, 0b01100110, 0b01101101, 0b01111101, 0b00000111
.db 0b01111111, 0b01101111, 0b01110111, 0b01111100, 0b00111001, 0b01011110, 0b01111001, 0b01110001

sevenseg_inv:
.db 0b00111111, 0b00110000, 0b01011011, 0b01111001, 0b01110100, 0b01101101, 0b01101111, 0b00111000
.db 0b01111111, 0b01111110, 0b01111110, 0b01100111, 0b00001111, 0b01110011, 0b01001111, 0b01001110
