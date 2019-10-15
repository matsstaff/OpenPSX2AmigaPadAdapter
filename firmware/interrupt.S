#include <avr/io.h>

.section .text

.global INT0_vect
.global INT1_vect

.extern state
.extern buttonsLive
.extern millis
.extern lastSwitchedTime
;~ .extern ST_CD32
#define ST_CD32 4

; Register holding button status to be shifted out
#define BTNREG _SFR_IO_ADDR (GPIOR0)

; Called on PIN_PADMODE changing, shall set things up, sample buttons and shift
; out first bit on FALLING edges, only store timestamp on RISING edges
INT0_vect:
	; Save context
	push r24
	in r24, _SFR_IO_ADDR (SREG)
	push r24
	
	sbic _SFR_IO_ADDR (PIND), PD2			; if pin 2 == LOW
	rjmp padmode_rising
	
	; If not yet in ST_CD32, set pin directions
	lds r24, state
	cpi r24, ST_CD32
	breq output_next_button					; Already ST_CD32, skip
	sbi _SFR_IO_ADDR (DDRB), PB0			; PB0 = OUTPUT (Arduino pin 8, PIN_BTNREGOUT, PIN_BTN2)
	cbi _SFR_IO_ADDR (DDRD), PD3			; PD3 = INPUT (Arduino pin 3, PIN_BTNREGCLK, PIN_BTN1)
	cbi _SFR_IO_ADDR (PORTD), PD3			; No pull-up (?)

	; Enable INT1, i.e. interrupt on clock edges
	;~ cli
	sbi	_SFR_IO_ADDR (EIMSK), INT1
	;~ sei
	
	; Set state to ST_CD32
	ldi r24, ST_CD32
	sts state, r24

output_next_button:
	lds r24, buttonsLive					; Sample input values which will be shifted out on subsequent clock inputs
	sbrs r24, 0
	rjmp sr_out_lo							; If LSB is 0, jump
	sbi _SFR_IO_ADDR (PORTB), PB0			; SR OUTPUT = HIGH
	rjmp shift_button_reg

sr_out_lo:
	cbi _SFR_IO_ADDR (PORTB), PB0			; SR OUTPUT = LOW
	
shift_button_reg:
	lsr r24									; buttonsLive still untouched in r24, >> 1
	out BTNREG, r24       					; BTNREG = buttonsLive >> 1
	rjmp int0_end

padmode_rising:
	; Disable INT1
	;~ cli
	cbi	     _SFR_IO_ADDR (EIMSK), INT1
	;~ sei
	
	push r22
	push r23
	push r25
	call millis
	sts lastSwitchedTime, r22
	sts lastSwitchedTime + 1, r23
	sts lastSwitchedTime + 2, r24
	sts lastSwitchedTime + 3, r25
	pop r25
	pop r23
	pop r22

int0_end:
	; Restore context
	pop r24
	out _SFR_IO_ADDR (SREG), r24
	pop r24
	
	reti




; Called on clock pin rising, shall shift out next bit
INT1_vect:
	; Save context
	push r24
	in r24, _SFR_IO_ADDR (SREG)
	push r24
	
	; BTNREG = buttonsLive >> 1
	; MSB will be zeroed during shifting, this will report non-existing button 9
	; as pressed for the ID sequence.
	in r24, BTNREG
	lsr r24									; LSB is loaded into carry flag
	out BTNREG, r24

	brcc int1_sr_out_lo						; If carry is not set (i.e. LSB was 0), jump
	sbi _SFR_IO_ADDR (PORTB), PB0			; SR OUTPUT = HIGH
	rjmp int1_end
	
int1_sr_out_lo:
	cbi _SFR_IO_ADDR (PORTB), PB0			; SR OUTPUT = LOW

int1_end:
	; Restore context
	pop r24
	out _SFR_IO_ADDR (SREG), r24
	pop r24

	reti
