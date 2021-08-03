; Copyright (c) 2021 ozforester. All rights reserved.
; Use of this source code is goverened by a MIT license
; that can be found in the LICENSE file.

; ATmega8 @4MHz internal osc. (H:D9, L:23)
; JHD162A HD44780
; via twi extension PCF8574AT

; Well I couldn't use an lcd busy-flag via twi. Maybe that's  timing issue.. I surrender (:

#undef __SFR_OFFSET
#define __SFR_OFFSET 0
#include <avr/io.h>

; twi status
#define START     0x08
#define REP_START 0x10
#define SLAW_ACK  0x18
#define SLAW_NACK 0x20
#define DATAW_ACK  0x28
#define DATAW_NACK 0x30
#define SLAR_ACK  0x40
#define SLAR_NACK  0x48
#define DATAR_ACK  0x50
#define DATAR_NACK 0x58

; pcf(twi) data bits
#define rs 0
#define rw 1
#define  e 2
#define bl 3
#define p4 4
#define p5 5
#define p6 6
#define p7 7

; registers
accum = 0			; r0
temp  = 16			; good worker (.set)
char  = 17			; msg char
tcntr = 18			; time counter
counter = 19                    ; delay counter reg
code = 20                       ; blink code reg
address = 21                    ; twi address reg
data = 22                       ; twi data reg
len = 23			; string length

.section .eeprom

msg1: .asciz "Hi, stranger," 	; eeprom space :0E000000 6D65206F7A666F72657374657200 AD
				; ihex         S140000DD m e   o z f o r e s t e r  0 CS

.section .text

msg2: .asciz "me ozforester"	;

.global main			;
.global TIMER0_OVF_vect		;

main:				;
        rcall timer_init        ;
        rcall delay_20ms        ;
        rcall delay_20ms        ;
        rcall delay_20ms        ;
        rcall twi_init          ; 100kHz
        rcall delay_20ms        ;
        rcall delay_20ms        ;
        rcall twi_scan          ; downwards 127..0
        cpi address, 0          ; 0 when no answer
        brne main1              ; scan success
        rcall error             ; error
        main1:                  ;
        rcall delay_20ms        ;
        rcall lcd_init          ;
	rcall error
        rcall lcd_print_eeprom  ;
        rcall lcd_print_flash   ;
	;rcall error		; special j-tag led (:
	loop:			;
	rjmp loop 		;
ret				;

; -------------- L C D   H D 4 4 7 8 0 ------------

lcd_cur:			; temp 40 cursor position only
        rcall twi_start         ;
        rcall twi_sla_w         ;
        rcall lcd_wait_bf       ;
        andi data, 0x0F         ; clear data bits
        rcall d7_high           ; 1xxx - set dram
        rcall d5_high           ; x100 - address 6:4
        rcall instr_w           ;
        rcall lcd_e_pulse       ; take
        ;rcall instr_w          ; 0000 - address 3:0
	nop			;
        rcall lcd_e_pulse       ;
        rcall twi_stop          ;
ret				;

lcd_home:			;
        rcall twi_start         ;
        rcall twi_sla_w         ;
        rcall lcd_wait_bf       ;
        andi data, 0x0F         ; clear data bits
        rcall instr_w           ; 0000 - display
        rcall lcd_e_pulse       ; take
        rcall d5_high           ; 001* - home
        ;rcall instr_w          ;
        rcall lcd_e_pulse       ;
        rcall twi_stop          ;
ret				;

lcd_clear:                      ;
        rcall twi_start         ;
        rcall twi_sla_w         ;
        rcall lcd_wait_bf       ;
        andi data, 0x0F         ; clear data bits
        rcall instr_w           ; set
        rcall lcd_e_pulse       ; take
        rcall d4_high           ; 0001 - clear
        ;rcall instr_w          ;
        rcall lcd_e_pulse       ;
	rcall twi_stop		;
ret                             ;

lcd_print_flash:		;
        rcall twi_start         ;
        rcall twi_sla_w         ;
        ldi ZL, lo8(msg2)    ;
	ldi ZH, hi8(msg2)	;
        lpm char, Z	        ;
	ldi len, 1		;
        rcall lcd_char           ;
	adiw Z, 1
        lpm char, Z             ;
        rcall lcd_char           ;
	rcall twi_stop
ret                             ;

lcd_print_eeprom:		;
        ldi char, msg1          ;
	rcall lcd_msg		;
	rcall lcd_cur		;
ret				;

lcd_msg:     			;
        rcall twi_start         ;
        rcall twi_sla_w         ;
        clr temp                ;
        out EEARH, temp         ;
        out EEARL, char         ; eeprom address
	mov len, char		;
	lm1:			;
        sbic EECR, EERE         ; wait EERE clear
	rjmp lm1		;
        sbi EECR, EERE		; set read enable
	nop			;
        in char, EEDR           ; read eeprom
	cpi char, 0		; till 0
	breq lm2		;
	rcall lcd_char		;
	inc len 		; inc address
	out EEARL, len		; next eeprom symbol
	rjmp lm1		;
	lm2:			;
        rcall twi_stop          ;
ret                             ;

;lcd_strlen:			; count length of msg
;        ;ldi len, 7             ; debugging
;	;ret			; debugging
;	push zh			; save msg pointer
;	push zl			; to stack
;	clr len			; clear counter
;	sl1:			;
;	lpm			; read msg byte into r0
;	mov char, accum		; copy r0 into char
;	cpi char, 0		; end of string? (seems it always non zero)
;	breq sl2		; '0' string terminator
;	inc len			; increment length counter
;	inc zl			; increment Z
;	rjmp sl1		; and continue read flash
;	sl2:			;
;	pop zl			; restore flash pointer
;	pop zh			; from stack
;	;ldi len, 7		; debugging
;ret				;

lcd_char:			; send one char
        ; high nibble		;
	rcall data_r
        rcall lcd_wait_bf       ; check busy flag
        rcall data_w            ;
	andi data, 0x0F		; clear data bits
	sbrc char, 7		; xxxx----
	rcall d7_high		; High
        sbrc char, 6            ;
        rcall d6_high       	;
        sbrc char, 5            ;
        rcall d5_high       	;
        sbrc char, 4            ;
        rcall d4_high       	;
	rcall twi_data_w	;
        rcall lcd_e_pulse       ;
	; low nibble		;
        andi data, 0x0F         ; clear data bits again
        sbrc char, 3            ; ----xxxx
        rcall d7_high       	;     Low
        sbrc char, 2            ;
        rcall d6_high       	;
        sbrc char, 1            ;
        rcall d5_high       	;
        sbrc char, 0            ;
        rcall d4_high       	;
	rcall twi_data_w	;
        rcall lcd_e_pulse 	;
ret				;

lcd_init:			; optimize when out of pmem
        rcall delay_20ms        ; >= 40 ms
        rcall delay_20ms        ;
	rcall twi_start		;
	rcall twi_sla_w		;

        rcall bl_low            ; backlight bit

	rcall d4_high		; four high order bits are transferred before the four low order
	rcall d5_high		; 0011 - init1
	rcall d6_low		;
	rcall d7_low		;
	rcall instr_w		; lcd instruction write mode
	rcall twi_data_w	; send data register contents
	rcall lcd_e_pulse	; 1

        rcall delay_1ms         ;
        rcall delay_1ms         ;
        rcall delay_1ms         ;

	rcall twi_data_w	;
        rcall lcd_e_pulse       ; 2

        rcall delay_100us       ;

	rcall twi_data_w	;
	rcall lcd_e_pulse	; 3

        rcall delay_100us       ;

        rcall d4_low            ; 0010 - pre function set
	rcall twi_data_w	;
        rcall lcd_e_pulse       ; 4

        rcall delay_100us       ; flag chech & 4-bit mode next

        rcall d5_high           ; 0010 - function set
	rcall twi_data_w	;
	rcall lcd_e_pulse	; 5
        rcall d7_high           ;
	rcall d5_low		; 1000 - 2 lines, 5x8 font
	rcall twi_data_w	;
        rcall lcd_e_pulse       ; 6
	; here we need to read bf-bit
	; so be switched between writing instruction (rs=0, rw=0)
	; and reading instruction (rs=0, rw=1)
	; but there is only last section use a new bf routine
	; for easy debugging
	; go ahead to 'H' char semding section

        rcall lcd_wait_bf       ; Busy Flag
	rcall d7_low		; 0000 - display
	rcall twi_data_w	;
        rcall lcd_e_pulse       ; 7
	rcall d7_high		; 1000 - off
	rcall twi_data_w	;
        rcall lcd_e_pulse       ; 8

        rcall lcd_wait_bf       ;
	rcall d7_low		; 0000 - display
	rcall twi_data_w	;
        rcall lcd_e_pulse       ; 9
        rcall d4_high           ; 0001 - clear
	rcall twi_data_w	;
        rcall lcd_e_pulse       ; 10
        rcall lcd_wait_bf       ;
	rcall d4_low		; 0000 - entry
	rcall twi_data_w	;
        rcall lcd_e_pulse       ; 11
        rcall d6_high           ;
        rcall d5_high           ; 0110 - mode
	rcall twi_data_w	;
        rcall lcd_e_pulse       ; 12

        rcall lcd_wait_bf       ;
	rcall d6_low		;
	rcall d5_low		; 0000 - display
	rcall twi_data_w	;
        rcall lcd_e_pulse       ; 13
        rcall d7_high           ;
        rcall d6_high           ; 1100 - on
        rcall d5_high           ; 1110 - cursor
        rcall d4_high           ; 1111 - blink
        rcall bl_high	        ; p3
	rcall twi_data_w	;
        rcall lcd_e_pulse       ; 14
        ;rcall lcd_wait_bf_real  ;
	;rcall data_w		; write data mode
        ;rcall d7_low            ;
        ;rcall d5_low            ; 0100 - 'H' high bits
        ;rcall d4_low            ;
        ;rcall twi_data_w        ;
        ;rcall lcd_e_pulse       ; 13
        ;rcall d7_high           ;
        ;rcall d6_low            ; 1000 - 'H' low bits
        ;rcall twi_data_w        ;
        ;rcall lcd_e_pulse       ; 14
	rcall twi_stop		;
        rcall delay_20ms        ; voila
ret				;

lcd_wait_bf:			; wait until busy flag cleared
        rcall delay_1ms 	; debugging
        rcall delay_1ms         ; debugging
        rcall delay_1ms 	; debugging
ret                     	;

lcd_wait_bf_real:                ; wait till flag resets

	; только что завершилась передача двух тетрад первого символа
	; требуется определить момент готовности lcd к приему следующего
	; символа путем проверки бизи-флага

	; с точки зрения lcd контроллера проверка флага:
	; читается на rs низкий уровень и на rw - высокий
	; читается положительный импульс на выводе E
	; отображаю бизи-флаг на вывод D7 и адрес в D6:0

	; с точки зрения pcf5874:
	; мастер шлет p0=0,p1=1, изменяю регистр состояния
	; мастер шлет p2=1, затем p2=0, ок - тоже дергаю бит в регистре туда-сюда
	; изменилось состояние D7 со стороны lcd, но мастер пока не собирался его читать, курю
	; мастер готовится к чтению p7 - шлет в него состояние 1
	; смотрю, что там с D7 со стороны lcd и отображаю его в регистре
	; мастер преходит в режим чтения, я ему подтверждаю
	; засылаю ему байт регистра, и он присылает nack

	rcall instr_r		; в 16 регистре бит 0 сбросить, бит 1 установить
        rcall twi_data_w        ; отослать нвоое состояние на pcf
	lwb:			;
	rcall lcd_e_pulse	; защелкнуть
	nop
        rcall d7_high           ; подготовить бит 7 pcf к чтению
        rcall twi_data_w        ;
	nop
        rcall twi_start         ; перейти в состояние мастер-приемник
        rcall twi_sla_r         ;
	rcall twi_data_r	; считать регистр данных twi в 16 регистр
	nop
        rcall twi_start         ; перейти в состояние мастер-передатчик
        rcall twi_sla_w         ;
	nop
        rcall lcd_e_pulse       ; фейковый клок для чтения ненужного адреса
        nop
        sbrc data, p7		; проверить бизи-флаг в 16 регистре
        rjmp lwb                ;

        ;rcall delay_1ms         ; debugging проверил, дело не в пропуске флага
        ;rcall delay_1ms         ; debugging
        ;rcall delay_1ms         ; debugging

ret



lcd_e_pulse:                    ;
        rcall e_high            ;
	rcall twi_data_w	;
        nop                    ;
        rcall e_low             ;
	rcall twi_data_w	;
ret                             ;

lcd_backlight_on:		;
	rcall twi_start		;
	rcall twi_sla_w		;
	rcall bl_high		;
	rcall twi_data_w	;
	rcall twi_stop		;
ret				;

lcd_backlight_off:		;
        rcall twi_start         ;
        rcall twi_sla_w         ;
 	rcall bl_low		;
        rcall twi_data_w        ;
        rcall twi_stop          ;
ret				;

instr_w:                    ; instrustion write
        rcall rs_low        ;
        rcall rw_low        ;
ret                         ;

instr_r:                    ; busy flag or address
        rcall rs_low        ;
        rcall rw_high       ;
ret                         ;

data_w:                     ; data write
        rcall rs_high       ;
        rcall rw_low        ;
ret                         ;

data_r:                     ; data read
        rcall rs_high       ;
        rcall rw_high       ;
ret                         ;

d4_low:                 ;
        cbr data, 1<<p4 ;
ret	                ;

d4_high:                ;
        sbr data, 1<<p4 ;
ret                     ;

d5_low:                 ;
        cbr data, 1<<p5 ;
ret                     ;

d5_high:                ;
        sbr data, 1<<p5 ;
ret                     ;

d6_low:                 ;
        cbr data, 1<<p6 ;
ret                     ;

d6_high:                ;
        sbr data, 1<<p6 ;
ret                     ;

d7_low:                 ;
        cbr data, 1<<p7 ;
ret                     ;

d7_high:                ;
        sbr data, 1<<p7 ;
ret                     ;

rs_low:		        ;
        cbr data, 1<<rs ;
ret			;

rs_high:	        ;
        sbr data, 1<<rs ;
ret			;

rw_low:                 ;
        cbr data, 1<<rw ;
ret			;

rw_high:                ;
        sbr data, 1<<rw ;
ret			;

e_low:                  ;
        cbr data, 1<<e  ;
ret			;

e_high:                 ;
        sbr data, 1<<e  ;
ret			;

bl_high:		;
	sbr data, 1<<bl	;
ret			;

bl_low:		        ;
        cbr data, 1<<bl ;
ret                     ;

; ----------------- T W I --------------

twi_scan:			;
	ldi address, 127	; goes down
	twscan1:		;
	rcall twi_start		; start/rep_start
	rcall twi_sla_w		; slave addres + w
	cpi temp, 0xFF		; touched?
	brne twscan2		; if not cleared
	clr temp		; (temp=0x00)
	subi address, 1		; else next address
	cpi address, 0		; last address
	breq twscan2		; exit with zero address
	rjmp twscan1		;
	twscan2:		;
	rcall twi_stop		;
ret				;

twi_data_r:                                     ;
        ldi temp, ((1<<TWINT)|(1<<TWEN))        ; reset flag +nack
        out TWCR, temp                          ;
        tdr1:                                   ;
        in temp, TWCR                           ; check if
        sbrs temp, TWINT                        ; flag set?
        rjmp tdr1                               ; not yet, repeat
	in data, TWDR				; data<-
ret                                             ;

twi_data_w:					;
        tdw1:                                   ;
        in temp, TWCR                           ;
        sbrs temp, TWINT                        ; ready?
        rjmp tdw1                               ; not yet, repeat
	out TWDR, data				; data->
	ldi temp, ((1<<TWINT)|(1<<TWEN))	;
	out TWCR, temp				; go
	tdw2:					;
	in temp, TWCR				;
	sbrs temp, TWINT			; sent?
	rjmp tdw2				; not yet, repeat
	in temp, TWSR				; check status
	andi temp, 0xF8				;
	cpi temp, DATAW_ACK			; 0x28
	breq tdw3				; ok
        rcall error	                        ; led
	tdw3:					;
ret						;

twi_sla_r:                                      ;
        mov temp, address                       ; slave address (e.g. 0x3F as pcf of mine)
        lsl temp                                ; <<address + 0, R/W = W
	ori temp, 0x01				; +1, R/W = R
        out TWDR, temp                          ;
        ldi temp, ((1<<TWINT)|(1<<TWEN))        ;
        out TWCR, temp                          ; go
        slar1:                                  ;
        in temp, TWCR                           ;
        sbrs temp, TWINT                        ; sent
        rjmp slar1                              ;
        in temp, TWSR                           ; read status
        andi temp, 0xF8                         ;
        cpi temp, SLAR_ACK                      ; 0x40
        breq slar2                              ; acked
        rcall error                             ;
        slar2:                                  ;
ret                                             ;

twi_sla_w:					;
	mov temp, address			; slave address (e.g. 0x3F as pcf of mine)
	lsl temp				; <<address + 0, R/W = W
	out TWDR, temp				;
	ldi temp, ((1<<TWINT)|(1<<TWEN))	;
	out TWCR, temp				; go
	slaw1:					;
        in temp, TWCR                           ;
        sbrs temp, TWINT                        ; sent
        rjmp slaw1                              ;
        in temp, TWSR                           ; read status
        andi temp, 0xF8                         ;
        cpi temp, SLAW_ACK                      ; 0x18
	breq slaw2				; acked (stay temp untouched if scanned)
	;rcall error				; uncomment if used w/o autodetect
	ser temp				; else (temp=0xFF)
	slaw2:					;
ret						;

twi_start:						;
	ldi temp, ((1<<TWINT)|(1<<TWSTA)|(1<<TWEN))	;
	out TWCR, temp					; go
	start1:						;
	in temp, TWCR					;
	sbrs temp, TWINT				; sent
        rjmp start1                                     ;
	in temp, TWSR					; read status
	andi temp, 0xF8					;
	cpi temp, START					; start acked? 0x08
	breq start2					;
        cpi temp, REP_START                             ; 0x10
        breq start2                                     ; maybe rep. acked?
	rcall error					; error led
	start2:						;
ret							; acked

twi_stop:						;
	ldi temp, ((1<<TWINT)|(1<<TWEN)|(1<<TWSTO))	;
        out TWCR, temp                                  ;
ret							;

twi_init:			; 100 kHz @4MHz clock
	ldi temp, 0b00001100	; 4000000 / ( 16 + 2*TWBR * 4^TWPS )
	out TWBR, temp		; 0x0c
        in temp, TWSR	        ;
	ori temp, 0b00000000	; 1
	out TWSR, temp		;
ret				;

; -------------- T I M E R 0 -------------

delay_1s:			;
	rcall delay_100ms     	;
        rcall delay_100ms       ;
        rcall delay_100ms       ;
        rcall delay_100ms       ;
        rcall delay_100ms       ;
        rcall delay_100ms       ;
        rcall delay_100ms       ;
        rcall delay_100ms       ;
        rcall delay_100ms       ;
        rcall delay_100ms       ;
ret				;

delay_100ms:			;
        rcall delay_20ms	;
        rcall delay_20ms        ;
        rcall delay_20ms        ;
        rcall delay_20ms        ;
	rcall delay_20ms 	;
ret				;

delay_20ms:                     ;
        ldi temp, 20            ;
	d20:			;
	rcall delay_1ms		;
	subi temp, 1		;
	brne d20		;
ret 		                ;

delay_1ms:                      ;
        ldi tcntr, 40           ;
        d1:                     ;
        cpi tcntr, 0            ;
        brne d1                 ;
ret                             ;

delay_100us:                    ;
        ldi tcntr, 4            ;
        du1:                    ;
        cpi tcntr, 0            ;
        brne du1                ;
ret		                ;

timer_init:                             ;
        ldi temp, (1<<CS00)             ; prescaler 1, 0.25 us
        out TCCR0, temp                 ;
        ldi temp, 155                   ; 25 us
        out TCNT0, temp                 ;
        ldi temp, (1<<TOIE0)            ;
        out TIMSK, temp                 ;
        sei                             ; go
ret                                     ;

TIMER0_OVF_vect:                ;
	cli			;
        push temp               ; save temp
        in temp, SREG           ; save SREG
	push temp
        ldi temp, 155           ; next 25 us
        out TCNT0, temp         ;
        subi tcntr, 1           ; delay counter--
	pop temp
        out SREG, temp          ; restore SREG
        pop temp                ; restore temp
	sei			;
reti 		                ;

; ----------------- D E B U G -----------

error:				; debug led
        sbi DDRD, PD7           ; D7 output
        cbi PORTD, PD7          ; D7 low
        sbi PORTD, PD7          ; D7 high
ret				;

brake:	rjmp brake		; debug loop

__vector_default:	reti	;

.end
