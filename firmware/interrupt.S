#include <avr/io.h>

.section .text

.global INT0_vect
.global INT1_vect

.extern state
.extern buttonsLive
.extern millis
.extern lastSwitchedTime

#define BTNREG _SFR_IO_ADDR (GPIOR0)

INT0_vect:
	push r24
	in r24, _SFR_IO_ADDR (SREG)
	push r24
	
	sbic    _SFR_IO_ADDR(PIND), PD2			; if pin 2 == LOW
	rjmp    padmode_rising
	
	lds     r24, state
	cpi     r24, 0x04						; if state == ST_CD32
	breq    output_next_button
	sbi     _SFR_IO_ADDR(DDRB), PB0			; PB0 = OUTPUT (Arduino pin 8, PIN_BTNREGOUT, PIN_BTN2)
	cbi     _SFR_IO_ADDR(DDRD), PD3			; PD3 = INPUT (Arduino pin 3, PIN_BTNREGCLK, PIN_BTN1)
	cbi     _SFR_IO_ADDR(PORTD), PD3		; No pull-up (?)

	; Old attachInterrupt() code
	;~ cli
	;~ lds     r24, 0x0069     ; 0x800069 <__TEXT_REGION_LENGTH__+0x7e0069>
	;~ ori     r24, 0x0C       ; 12
	;~ sts     0x0069, r24     ; 0x800069 <__TEXT_REGION_LENGTH__+0x7e0069>
	;~ sbi     0x1d, 1 ; 29
	;~ sei
	
	ldi     r24, 0x04
	sts     state, r24			; state = 4 (ST_CD32);

output_next_button:
	lds     r24, buttonsLive
	sbrs    r24, 0
	rjmp    sr_out_hi
	sbi     _SFR_IO_ADDR(PORTB), PB0		; SR OUTPUT = HIGH
	rjmp    shift_button_reg

sr_out_hi:
	cbi     _SFR_IO_ADDR(PORTB), PB0		; SR OUTPUT = LOW
	;~ lds     r24, buttonsLive     ; 0x800106 <buttonsLive>
	;~ ldi     r25, 0x00       ; 0
	;~ asr     r25
	;~ ror     r24
	
shift_button_reg:
	lsr r24				; buttonsLive still untouched in r24, >> 1
	out     BTNREG, r24       				; BTNREG = buttonsLive >> 1
	rjmp v0end

padmode_rising:
	push r22
	push r23
	push r25
	call    millis
	sts     lastSwitchedTime, r22     ; 0x800239 <lastSwitchedTime>
	sts     lastSwitchedTime + 1, r23     ; 0x80023a <lastSwitchedTime+0x1>
	sts     lastSwitchedTime + 2, r24     ; 0x80023b <lastSwitchedTime+0x2>
	sts     lastSwitchedTime + 3, r25     ; 0x80023c <lastSwitchedTime+0x3>
	pop r25
	pop r23
	pop r22

v0end:
	pop r24
	out _SFR_IO_ADDR (SREG), r24
	pop r24
	
	reti


INT1_vect:
	; Save context
	push r24
	in r24, _SFR_IO_ADDR (SREG)
	push r24
	
	in      r24, BTNREG        ; 42
	sbrs    r24, 0
	rjmp    .+4             ; 0x144 <_Z11onClockEdgev+0xa>
	sbi     0x05, 0 ; 5
	rjmp    .+2             ; 0x146 <_Z11onClockEdgev+0xc>
	cbi     0x05, 0 ; 5
	lsr r24				; buttonsLive still untouched in r24
	out     BTNREG, r24       ; 42

	
	; Restore context
	pop r24
	out _SFR_IO_ADDR (SREG), r24
	pop r24

	reti
