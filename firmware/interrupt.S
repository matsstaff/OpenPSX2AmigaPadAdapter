; GCC Calling Conventions:
;
; - Call-used registers (r18-r27, r30-r31): May be allocated by gcc for local
;   data. You may use them freely in assembler subroutines. Calling C
;   subroutines can clobber any of them - the caller is responsible for saving
;   and restoring.
; - Call-saved registers (r2-r17, r28-r29): May be allocated by gcc for local
;   data. Calling C subroutines leaves them unchanged. Assembler subroutines are
;   responsible for saving and restoring these registers, if changed. r29:r28
;   (Y pointer) is used as a frame pointer (points to local data on stack) if
;   necessary. The requirement for the callee to save/preserve the contents of
;   these registers even applies in situations where the compiler assigns them
;   for argument passing.
; - Fixed registers (r0, r1): Never allocated by gcc for local data, but often
;   used for fixed purposes:
;   - r0 - temporary register, can be clobbered by any C code (except interrupt
;     handlers which save it), may be used to remember something for a while
;     within one piece of assembler code
;   - r1 - assumed to be always zero in any C code, may be used to remember
;     something for a while within one piece of assembler code, but must then be
;     cleared after use (clr r1). This includes any use of the [f]mul[s[u]]
;     instructions, which return their result in r1:r0. Interrupt handlers save
;     and clear r1 on entry, and restore r1 on exit (in case it was non-zero).
;
; Function call conventions:
; - Arguments - allocated left to right, r25 to r8. All arguments are aligned to
;               start in even-numbered registers (odd-sized arguments, including
;               char, have one free register above them). This allows making
;               better use of the movw instruction on the enhanced core.
;               If too many, those that don't fit are passed on the stack.
; - Return values: 8-bit in r24 (not r25!), 16-bit in r25:r24, up to 32 bits in
;                  r22-r25, up to 64 bits in r18-r25. 8-bit return values are
;                  zero/sign-extended to 16 bits by the called function
;                  (unsigned char is more efficient than signed char - just clr
;                  r25). Arguments to functions with variable argument lists
;                  (printf etc.) are all passed on stack, and char is extended
;                  to int.



#include <avr/io.h>

.section .text

.global INT0_vect
.global INT1_vect

.extern state

; These are taken from enum State
#define ST_CD32 4
#define ST_JOYSTICK_TEMP 5

; Register holding button status to be shifted out
#define BTNREG _SFR_IO_ADDR (GPIOR1)

; Register holding the button value being updated by the main loop, which is
; sampled when PIN_PADMODE goes low
; Note that this is testable with SBIS/SBIC
#define BTNLIVE _SFR_IO_ADDR (GPIOR0)

#define BTN_BLUE 0
#define BTN_RED 1

; Called on PIN_PADMODE changing, shall set things up, sample buttons and shift
; out first bit on FALLING edges, only store timestamp on RISING edges
INT0_vect:
	sbic _SFR_IO_ADDR (PIND), PD2			; if pin 2 == LOW
	rjmp padmode_rising
	
padmode_falling:
	; Entering ST_CD32

	; Output status of first button as soon as possible
	sbi _SFR_IO_ADDR (DDRB), PB0			; PB0 = OUTPUT (Arduino pin 8, PIN_BTNREGOUT, PIN_BTN2)
	sbis BTNLIVE, 0
	cbi _SFR_IO_ADDR (PORTB), PB0			; SR OUTPUT = LOW
	sbic BTNLIVE, 0
	sbi _SFR_IO_ADDR (PORTB), PB0			; SR OUTPUT = HIGH

	; Now on to completing mode switching stuff. No registers nor SREG have been
	; altered so far, but now we need to save the context
	push r24
	in r24, _SFR_IO_ADDR (SREG)
	push r24

	; Sample input values which will be shifted out on subsequent clock inputs
	; BTNREG = BTNLIVE >> 1
	; MSB will be zeroed during shifting, this will report non-existing button 8
	; as pressed for the ID sequence
	in r24, BTNLIVE
	lsr r24
	out BTNREG, r24
	
	; Enable INT1, i.e. interrupt on clock edges
	cbi _SFR_IO_ADDR (DDRD), PD3			; PD3 = INPUT (Arduino pin 3, PIN_BTNREGCLK, PIN_BTN1)
	sbi _SFR_IO_ADDR (PORTD), PD3			; Activate pull-up
	sbi _SFR_IO_ADDR (EIFR), INTF1			; Clear any pending interrupts
	sbi	_SFR_IO_ADDR (EIMSK), INT1
	
	; Set state to ST_CD32
	ldi r24, ST_CD32
	sts state, r24

	; Restore context
	pop r24
	out _SFR_IO_ADDR (SREG), r24
	pop r24
	reti
	
padmode_rising:
	; Switching back to ST_JOYSTICK
	
	; Set pin directions and set levels according to buttons, as waiting for the
	; main loop to do it takes too much time (= a few ms, for some reason)
	sbis BTNLIVE, BTN_BLUE
	sbi _SFR_IO_ADDR (DDRB), PB0			; PB0 = OUTPUT
	sbic BTNLIVE, BTN_BLUE
	cbi _SFR_IO_ADDR (DDRB), PB0			; PB0 = INPUT
	cbi _SFR_IO_ADDR (PORTB), PB0			; No pull-up
	
	; PD3 is already in input mode with pull-up, disable it
	sbis BTNLIVE, BTN_RED
	sbi _SFR_IO_ADDR (DDRD), PD3
	sbic BTNLIVE, BTN_RED
	cbi _SFR_IO_ADDR (DDRD), PD3
	cbi _SFR_IO_ADDR (PORTD), PD3			; No pull-up
	
	; Disable INT1
	cbi _SFR_IO_ADDR (EIMSK), INT1
	
	; Set state to ST_JOYSTICK
	push r24
	ldi r24, ST_JOYSTICK_TEMP
	sts state, r24
	pop r24

	reti




; Called on clock pin rising, shall shift out next bit
INT1_vect:
	push r24

	; Output status of next button as soon as possible
	in r24, BTNREG
	sbrs r24, 0
	cbi _SFR_IO_ADDR (PORTB), PB0			; SR OUTPUT = LOW
	sbrc r24, 0
	sbi _SFR_IO_ADDR (PORTB), PB0			; SR OUTPUT = HIGH

	; Keep a copy of old SREG in r25 since the lsr below will alter it
	push r25
	in r25, _SFR_IO_ADDR (SREG)

	; BTNREG >>= 1
	; MSB will be zeroed during shifting, this will report non-existing button 9
	; and 10 as pressed for the ID sequence
	lsr r24									; BTNREG still untouched in r24
	out BTNREG, r24

	; Restore context
	out _SFR_IO_ADDR (SREG), r25
	pop r25
	pop r24
	reti
