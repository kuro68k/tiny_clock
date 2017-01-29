;----------------------------------------------------------------------
; Recieve MSF time signal
;----------------------------------------------------------------------

msf_return2:
		rjmp	msf_return					; short jump

msf_receive:
		rcall	display_off

		sbi		DDRD, PON
		cbi		PORTD, PON					; receiver module on

		ldi		temp0, 0
		sts		MSFRAM, temp0

		ldi		XH, HIGH(MSFRAM)
		ldi		XL, LOW(MSFRAM)
		ldi		temp0, 0
		ldi		temp1, 64
msf_clear_ram:
		st		X+, temp0
		dec		temp1
		brne	msf_clear_ram

		sts		phours_c, temp0
		sts		pmins_c, temp0
		sts		pvalid, temp0

		clr		mins_s
		clr		hours_s
		clr		temp0
		clr		temp1
		clr		temp2
		clr		temp3
		clr		temp4
		clr		temp5						; MSF bit counter
		clr		cycle

msf_bit_loop:
		cp		hours, endhour				; give up when hour = endhour
		breq	msf_return2
		sbis	PIND, INV
		rjmp	msf_bit_loop

		;cli
		clr		temp0
		out		TCNT0, temp0
		clr		timer
		;sei

		;clr		dot0
		;inc		dot0
		;ldi		temp0, (1<<7)
		;rcall	shift_out

		rcall	delay_1ms					; debounce

msf_pulse_measurement:
		cp		hours, endhour				; give up after 1 hour
		breq	msf_return2

		sbic	PIND, INV					; wait for high pulse to start
		rjmp	msf_pulse_measurement
		mov		temp0, timer				; save pulse length
		rcall	delay_5ms					; filter out anything less than 5ms
		sbic	PIND, INV 
		rjmp	msf_pulse_measurement

		// temp0 - length of pulse //
		// temp2 - decoded bit //

		ldi		temp2, 'e'					; decoded bit, starts as error

		; decode pulse length
		cpi		temp0, 9					; < 90ms = pulse too short
		brlt	msf_bit_loop

		cpi		temp0, 15
		brge	msf_pulse_200ms				; 90-150ms = short pulse = 0
		ldi		temp2, '0'
		rjmp	msf_pulse_done

msf_pulse_200ms:
		cpi		temp0, 19
		brlt	msf_bit_loop				; < 190ms = pulse too short
		cpi		temp0, 26
		brge	msf_pulse_300ms				; 190-250ms = long pulse = 1
		ldi		temp2, '1'
		rjmp	msf_pulse_done

msf_pulse_300ms:
		cpi		temp0, 29
		brlt	msf_bit_loop				; < 290ms = pulse too short
		cpi		temp0, 35
		brge	msf_pulse_500ms				; 290-310ms = long pulse = 1
		ldi		temp2, 'L'
		rjmp	msf_pulse_done

msf_pulse_500ms:
		cpi		temp0, 48
		brlt	msf_bit_loop				; < 490ms = pulse too short
		cpi		temp0, 55
		brge	msf_bit_loop				; 490-510ms = start of minute
		;ldi		temp1, MSF_SOM 
		ldi		temp2, 'S'
		rjmp	msf_pulse_done

msf_pulse_long:								; >510ms = error
		ldi		temp2, 't'
		;rjmp	msf_pulse_done

msf_pulse_done:
		; Wait until start of next pulse is about to happen
		; to filter out other MSF pulses and noise
		ldi		temp0, 95					; 950ms comparison
msf_wait_until_950ms:
		rcall	delay_1ms
		cp		timer, temp0
		brlt	msf_wait_until_950ms

		// handle start of signal marker
		cpi		temp2, 'S'					; was that the start of the minute marker?
		brne	msf_store_not_start

		clr		temp5						; restart storage

		lds		temp0, MSFRAM 				; check if stream looks valid since last start
		cpi		temp0, 'S'
		brne	msf_store_not_start

		rcall	msf_decode
		ldi		temp0, 3					; decode complete?
		cp		cycle, temp0
		breq	msf_return

msf_store_not_start:
		cpi		temp5, 61					; overflow?
		brne	msf_store_not_overflow
		clr		temp5
msf_store_not_overflow:

		cpi		temp5, 0					; MSF bit counter
		brne	msf_store_not_byte_0
		ldi		XH, HIGH(MSFRAM)
		ldi		XL, LOW(MSFRAM)
msf_store_not_byte_0:
		st		X+, temp2
		inc		temp5

		mov		temp0, temp2
		cpi		temp0, 'S'
		brne	debug_not_s
		ldi		temp0, '\n'
		rcall	uart_write
		;ldi		temp0, '\r'
		;rcall	uart_write
		ldi		temp0, 'S'
debug_not_s:
		rcall	uart_write

		rjmp	msf_bit_loop


;debug_error
;		ldi		temp0, 'z'
;		rcall	uart_write

;		rjmp	msf_bit_loop		


msf_return:
		sbi		PORTD, PON
		rcall	display_on
		ret



;----------------------------------------------------------------------
; Decode MSF bitstream
;----------------------------------------------------------------------

msf_decode:
		push	temp0
		push	temp1
		push	temp2

		ldi		temp0, '\n'
		rcall	uart_write
		ldi		temp0, '\r'
		rcall	uart_write

		rcall	msf_checksum				; checksum hours and minutes
		sts		pvalid, temp0
		rcall	uart_write
		ldi		temp0, ' '
		rcall	uart_write

		ldi		XH, HIGH(MSFRAM)
		ldi		XL, LOW(MSFRAM)
		adiw	XL, 17						; skip to year

		ldi		temp2, '0'					; for UART

		; year in 8 bit BCD 
		ldi		temp0, '2'
		rcall	uart_write
		ldi		temp0, '0'
		rcall	uart_write

		ldi		temp0, 0					; tens
		ldi		temp1, 4
		rcall	MSF_BCD_decode
		add		temp0, temp2
		rcall	uart_write
		ldi		temp0, 0					; units
		ldi		temp1, 4
		rcall	MSF_BCD_decode
		add		temp0, temp2
		rcall	uart_write

		ldi		temp0, '/'
		rcall	uart_write

		; month in 5 bit BCD 
		ldi		temp0, 0					; tens
		ldi		temp1, 1
		rcall	MSF_BCD_decode
		add		temp0, temp2
		rcall	uart_write
		ldi		temp0, 0					; units
		ldi		temp1, 4
		rcall	MSF_BCD_decode
		add		temp0, temp2
		rcall	uart_write

		ldi		temp0, '/'
		rcall	uart_write

		; day in 6 bit BCD 
		ldi		temp0, 0					; tens
		ldi		temp1, 2
		rcall	MSF_BCD_decode
		add		temp0, temp2
		rcall	uart_write
		ldi		temp0, 0					; units
		ldi		temp1, 4
		rcall	MSF_BCD_decode
		add		temp0, temp2
		rcall	uart_write

		; day of week 
		adiw	XL, 3

		ldi		temp0, ' '
		rcall	uart_write
		
		; hours in 6 bit BCD 
		clr		temp0
		ldi		temp1, 2					; tens
		rcall	MSF_BCD_decode				; result in temp0
		rcall	mul10						; multiply by 10, result in temp1
		mov		hours_s, temp1				; copy to shadow register
		add		temp0, temp2
		rcall	uart_write
		
		clr		temp0
		ldi		temp1, 4					; units
		rcall	MSF_BCD_decode
		add		hours_s, temp0				; add to shadow register
		add		temp0, temp2
		rcall	uart_write

		ldi		temp0, ':'
		rcall	uart_write

		; minutes in 7 bit BCD 
		ldi		temp0, 0
		ldi		temp1, 3
		rcall	MSF_BCD_decode
		rcall	mul10
		mov		mins_s, temp1
		add		temp0, temp2
		rcall	uart_write

		ldi		temp0, 0
		ldi		temp1, 4
		rcall	MSF_BCD_decode
		add		mins_s, temp0
		add		temp0, temp2
		rcall	uart_write

		ldi		temp0, ' '
		rcall	uart_write

		; sanity check
		ldi		temp0, 0					; error counter

		tst		hours_s						; hours not < 0 
		brge	sanity_h_not_neg
		inc		temp0
sanity_h_not_neg:
		ldi		temp1, 24					; hours < 24
		cp		hours_s, temp1
		brlt	sanity_h_not_over
		inc		temp0
sanity_h_not_over:
		tst		mins_s						; mins not < 0
		brge	sanity_m_not_neg
		inc		temp0
sanity_m_not_neg:
		ldi		temp1, 60					; mins < 60
		cp		mins_s, temp1
		brlt	sanity_m_not_over
		inc		temp0
sanity_m_not_over:

		tst		temp0
		breq	sanity_pass
		
		; sanity check failed
		;ldi		ZH, HIGH(2*str_sanity_fail)
		;ldi		ZL, LOW(2*str_sanity_fail)
		;rcall	uart_puts

		clr		cycle						; start over
		rjmp	msf_decode_exit

sanity_pass:
		;ldi		ZH, HIGH(2*str_sanity_ok)
		;ldi		ZL, LOW(2*str_sanity_ok)
		;rcall	uart_puts

		lds		temp0, pvalid				; see if checksum passed too
		cpi		temp0, 'V'
		breq	msf_time_valid

		; sanity check passed but checksum wrong
		clr		cycle						; start over
		rjmp	msf_decode_exit

msf_time_valid:
		inc		cycle
		ldi		temp0, 2					; after two valid cycles check continuity
		cp		cycle, temp0
		breq	msf_decode_cycle2

		; not cycle 2
		sts		phours_c, hours_s			; save this cycle's data
		sts		pmins_c, mins_s
		rjmp	msf_decode_exit

msf_decode_cycle2:
		lds		temp0, phours_c				; check if hours are the same
		cp		hours_s, temp0
		brne	msf_decode_nonconsecutive
		
		lds		temp0, pmins_c				; check if mins are consecutive
		inc		temp0						; doesn't work with minutes 59/00!
		cp		mins_s, temp0
		brne	msf_decode_nonconsecutive

msf_decode_complete:
		;ldi		ZH, HIGH(2*str_cycle_complete)
		;ldi		ZL, LOW(2*str_cycle_complete)
		;rcall	uart_puts

		ldi		temp0, 3					; signal decoding finished
		mov		cycle, temp0

		cli
		mov		hours, hours_s
		mov		mins, mins_s
		clr		secs
		ldi		temp0, 0
		sts		sectick, temp0
		ldi		temp0, 0
		sts		sectick, temp0
		out		TCNT1H, temp0
		out		TCNT1L, temp0
		sei

msf_decode_exit:
		;ldi		temp0, '\n'
		;rcall	uart_write
		;ldi		temp0, '\r'
		;rcall	uart_write

		pop		temp2
		pop		temp1
		pop		temp0

		ret

msf_decode_nonconsecutive:
		;lds		temp0, phours_c
		;mov		hours, temp0
		;lds		temp0, pmins_c
		;mov		mins, temp0
		;rcall	set_digits
		; last decoded stream was OK so keep it
		clr		cycle						; back to cycle 1
		inc		cycle
		sts		phours_c, hours_s			; save this cycle's data
		sts		pmins_c, mins_s
		;ldi		ZH, HIGH(2*str_times_not_consecutive)
		;ldi		ZL, LOW(2*str_times_not_consecutive)
		;rcall	uart_puts
		rjmp	msf_decode_exit



;----------------------------------------------------------------------
; Checksum hours and minutes of MSF signal
; If valid return "V" in temp0, otherwise return "I"
;----------------------------------------------------------------------

msf_checksum:
		push	temp1
		push	temp2

		clr		temp0						; bit count

		ldi		XH, HIGH(MSFRAM)
		ldi		XL, LOW(MSFRAM)
		adiw	XL, 39						; bits 39-51 to sum
		ldi		temp1, 39

msf_checksum_loop:
		ld		temp2, X+
		cpi		temp2, '1'
		brne	msf_checksum_not_1
		inc		temp0
msf_checksum_not_1:
		inc		temp1
		cpi		temp1, 52
		brne	msf_checksum_loop

		lds		temp2, MSFRAM+57			; parity bit
		cpi		temp2, '1'
		brne	msf_checksum_even
		inc		temp0
msf_checksum_even:
		mov		temp1, temp0				; shuffle to return result in temp0
		ldi		temp0, 'I'					; default = invalid
		sbrs	temp1, 0					; if even then invalid
		ldi		temp0, 'V'

		pop		temp2
		pop		temp1

		ret



;----------------------------------------------------------------------
; Multiply by 10
; temp0 - byte to multiply
; temp1 - result
;----------------------------------------------------------------------

mul10:
		push	temp0
		push	temp2

		clr		temp1
		ldi		temp2, 10
		cpi		temp0, 0					; check for zero 
		breq	mul10finished
mul10loop:
		add		temp1, temp2
		dec		temp0
		brne	mul10loop

mul10finished:
		pop		temp2
		pop		temp0
		ret


;----------------------------------------------------------------------
; Byte-per-bit decoder
; temp0 - byte to write bits to
; temp1 - number of bits to read
;----------------------------------------------------------------------

MSF_BCD_decode:
		push	temp2
MSF_BCD_decode_loop:
		lsl		temp0
		ld		temp2, X+
		cpi		temp2, '0'					; anything not 0 is considered a 1
		breq	MSF_BCD_decode_0
		ori		temp0, 1
MSF_BCD_decode_0:
		dec		temp1
		brne	MSF_BCD_decode_loop
		pop		temp2
		ret



;----------------------------------------------------------------------
; Load test MSF string
;----------------------------------------------------------------------
/*
load_test:
		ldi		temp0, 60
		ldi		ZH, HIGH(2*testmsf)
		ldi		ZL, LOW(2*testmsf)
		ldi		XH, HIGH(msfram)
		ldi		XL, LOW(msfram)
load_test_loop:
		lpm
		adiw	ZL, 1
		st		X+, r0
		dec		temp0
		brne	load_test_loop
		ret
*/

;debug_error2:
;		rjmp	debug_error



;----------------------------------------------------------------------
; Test data
;----------------------------------------------------------------------

testmsf:
;.db "S000000000000000000010000001111001110101000101001001011111L0"
;.db "S000000000000000000010000010000001010001000111010000011111L0"
;    012345678901234567890123456789012345678901234567890123456789
;			   1		 2		   3		 4		   5
;											
