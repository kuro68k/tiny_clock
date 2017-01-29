;----------------------------------------------------------------------
; Decimal to BCD
; temp0 - decimal in, BCD out
;----------------------------------------------------------------------

dec2bcd:
		push	temp1
		push	temp2

		mov		temp1, temp0
		clr		temp0
		clr		temp2
dec2bcd_tens:
		cpi		temp1, 10
		brlt	dec2bcd_units
		inc		temp0
		subi	temp1, 10
		rjmp	dec2bcd_tens

dec2bcd_units:
		swap	temp0						; tens into upper nibble
		add		temp0, temp1				; units into lower nibble

		pop		temp2
		pop		temp1
		ret


;----------------------------------------------------------------------
; Delays
;----------------------------------------------------------------------

delay_5ms:									; 60000 cycles
		push	temp0
		push	temp1
		ldi		temp0, 0x63
delay_5ms_loop0:
		ldi		temp1, 0xc9
delay_5ms_loop1:
		dec		temp1
		brne	delay_5ms_loop1
		dec		temp0
		brne	delay_5ms_loop0
		pop		temp1
		pop		temp0
		ret

delay_1ms:									; 12000 cycles
		push	temp0
		push	temp1
		ldi		temp0, 0x1f
delay_1ms_loop0:
		ldi		temp1, 0x80
delay_1ms_loop1:
		dec		temp1
		brne	delay_1ms_loop1
		dec		temp0
		brne	delay_1ms_loop0
		pop		temp1
		pop		temp0
		ret

delay_500ms:								; 6000000 cycles
		push	temp0
		ldi		temp0, 100
delay_500ms_loop:
		rcall	delay_5ms
		dec		temp0
		brne	delay_500ms_loop
		pop		temp0
		ret


;----------------------------------------------------------------------
; Write character to UART
;
; temp0 - byte to send
;----------------------------------------------------------------------

uart_write:
		;sbis	UCSRA, UDRE
		;rjmp	uart_write
		;out		UDR, temp0
		ret


;----------------------------------------------------------------------
; Write string to UART
;
; Z - address of null terminated string
;----------------------------------------------------------------------

uart_puts:
/*
		push	temp0

uart_puts_char:
		lpm
		adiw	ZH:ZL, 1
		mov		temp0, r0

		cpi		temp0, 0		; end of string
		breq	uart_puts_end
		rcall	uart_write
		rjmp	uart_puts_char

uart_puts_end:
		pop		temp0
*/
		ret



;----------------------------------------------------------------------
; Load alarm settings from EEPROM
;----------------------------------------------------------------------

eeprom_load_alarm:
		push	temp0
		push	temp1
		cli

		// read alarm flags //
		rcall	eeprom_wait
		ldi		temp0, eepalarmf
		out		EEAR, temp0
		sbi		EECR, EERE
		in		temp0, EEDR

		; sanity check flags
		;mov		temp1, temp0
		;andi	temp1, (1<<0)				; 0 = alarm0 on/off
		;cp		temp1, temp0
		;brne	eeprom_la_fail

		sts		alarmflags, temp0

		// read alarm0 hour //
		rcall	eeprom_wait
		ldi		temp0, eepalarm0hr
		out		EEAR, temp0
		sbi		EECR, EERE
		in		temp0, EEDR

		; sanity check hours
		;cpi		temp0, 24
		;brge	eeprom_la_fail
		;tst		temp0
		;brmi	eeprom_la_fail

		sts		alarm0hr, temp0

		// read alarm0 minute //
		rcall	eeprom_wait
		ldi		temp0, eepalarm0min
		out		EEAR, temp0
		sbi		EECR, EERE
		in		temp0, EEDR

		; sanity check minutes
		;cpi		temp0, 60
		;brge	eeprom_la_fail
		;tst		temp0
		;brmi	eeprom_la_fail

		sts		alarm0min, temp0

		// read alarm0 melody //
		rcall	eeprom_wait
		ldi		temp0, eepalarm0mel
		out		EEAR, temp0
		sbi		EECR, EERE
		in		temp0, EEDR

		; sanity check melody
		;cpi		temp0, 5
		;brge	eeprom_la_fail
		;tst		temp0
		;brmi	eeprom_la_fail

		sts		alarm0mel, temp0

		// read hour chime melody //
		rcall	eeprom_wait
		ldi		temp0, eephrmel
		out		EEAR, temp0
		sbi		EECR, EERE
		in		temp0, EEDR
		sts		hrmel, temp0

eeprom_la_return:
		sei
		pop		temp1
		pop		temp0
		ret



eeprom_la_fail:
		;ldi		temp0, 0
		;sts		alarmflags, temp0
		;sts		alarm0hr, temp0
		;sts		alarm0min, temp0
		;rjmp	eeprom_la_return



;----------------------------------------------------------------------
; Save alarm settings to EEPROM
;----------------------------------------------------------------------

eeprom_save_alarm:
		push	temp0
		push	temp1
		cli

		// save alarm flags //
		ldi		temp0, eepalarmf
		lds		temp1, alarmflags
		rcall	eeprom_write

		// save alarm0 hour //
		ldi		temp0, eepalarm0hr
		lds		temp1, alarm0hr
		rcall	eeprom_write

		// save alarm0 minute //
		ldi		temp0, eepalarm0min
		lds		temp1, alarm0min
		rcall	eeprom_write

		// save alarm0 melody //
		ldi		temp0, eepalarm0mel
		lds		temp1, alarm0mel
		rcall	eeprom_write

		// save hour chime melody //
		ldi		temp0, eephrmel
		lds		temp1, hrmel
		rcall	eeprom_write

		// wait for EEPROM to finish before restoring interrupts //
		rcall	eeprom_wait

eeprom_sa_return:
		sei
		pop		temp1
		pop		temp0
		ret

eeprom_write:
		; address in temp0
		; data in temp1
		rcall	eeprom_wait
		out		EEAR, temp0
		out		EEDR, temp1
		sbi		EECR, EEMPE
		sbi		EECR, EEPE
		ret

;----------------------------------------------------------------------
; EEPROM utilities
;----------------------------------------------------------------------

eeprom_wait:
		sbic	EECR, EEPE
		rjmp	eeprom_wait
		ret
