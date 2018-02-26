;****************** main.s ***************
; Program written by: Faiyaz Mostofa
; Date Created: 2/4/2017
; Last Modified: 2/14/2018
; Brief description of the program
;   The LED toggles at 8 Hz and a varying duty-cycle
; Hardware connections (External: One button and one LED)
;  PE1 is Button input  (1 means pressed, 0 means not pressed)
;  PE0 is LED output (1 activates external LED on protoboard)
;  PF4 is builtin button SW1 on Launchpad (Internal)
;        Negative Logic (0 means pressed, 1 means not pressed)
; Overall functionality of this system is to operate like this
;   1) Make PE0 an output and make PE1 and PF4 inputs.
;   2) The system starts with the the LED toggling at 8Hz,
;      which is 8 times per second with a duty-cycle of 20%.
;      Therefore, the LED is ON for (0.2*1/8)th of a second
;      and OFF for (0.8*1/8)th of a second.
;   3) When the button on (PE1) is pressed-and-released increase
;      the duty cycle by 20% (modulo 100%). Therefore for each
;      press-and-release the duty cycle changes from 20% to 40% to 60%
;      to 80% to 100%(ON) to 0%(Off) to 20% to 40% so on
;   4) Implement a "breathing LED" when SW1 (PF4) on the Launchpad is pressed:
;      a) Be creative and play around with what "breathing" means.
;         An example of "breathing" is most computers power LED in sleep mode
;         (e.g., https://www.youtube.com/watch?v=ZT6siXyIjvQ).
;      b) When (PF4) is released while in breathing mode, resume blinking at 8Hz.
;         The duty cycle can either match the most recent duty-
;         cycle or reset to 20%.
;      TIP: debugging the breathing LED algorithm and feel on the simulator is impossible.
; PortE device registers
GPIO_PORTE_DATA_R  EQU 0x400243FC
GPIO_PORTE_DIR_R   EQU 0x40024400
GPIO_PORTE_AFSEL_R EQU 0x40024420
GPIO_PORTE_DEN_R   EQU 0x4002451C
; PortF device registers
GPIO_PORTF_DATA_R  EQU 0x400253FC
GPIO_PORTF_DIR_R   EQU 0x40025400
GPIO_PORTF_AFSEL_R EQU 0x40025420
GPIO_PORTF_PUR_R   EQU 0x40025510
GPIO_PORTF_DEN_R   EQU 0x4002551C
GPIO_PORTF_LOCK_R  EQU 0x40025520
GPIO_PORTF_CR_R    EQU 0x40025524
GPIO_LOCK_KEY      EQU 0x4C4F434B  ; Unlocks the GPIO_CR register
SYSCTL_RCGCGPIO_R  EQU 0x400FE608
;Variables that hold the maximum values 
MAX_DELAY		   EQU 0x1864A8		;0x249700	   ; The interval size of the delays
BREATHE_DELAY_MAX   EQU 0x5E00					   ; The delay required

     IMPORT  TExaS_Init
     THUMB
     AREA    DATA, ALIGN=2
;global variables go here
     AREA    |.text|, CODE, READONLY, ALIGN=2
     THUMB
     EXPORT  Start

;RO = holds the location for the output register
;R1 = used to hold the data from the registers (will be used to edit data)
;R2 = Register that holds the value for the MAX_DELAY
;R3 = temporary variable (Ex: used in delay as increment)
;R4 = contains the increments of the delay (1/5 of MAX_DELAY)
;R5 = contains the current delay for off
;R6 = contains the current delay for on
;R7 = temporary variable mainly used for subroutine parameters
;R8 = temporary variable (each bit keeps track of a different value)
;	= bit 0: the bit for whether the button has been pushed or not
;	= bit 1: the bit for whether to be in the breathing animation or not
;R9 = holds the location for PORTF_DATA

;-----------------------------------------------------------------------------------------------
Start
 ; SysTick_Init sets Systick for 12.5 ns
 ; disable SysTick during setup
    LDR R1, =NVIC_ST_CTRL_R
    MOV R0, #0            ; Clear Enable         
    STR R0, [R1] 
; set reload to maximum reload value
    LDR R1, =NVIC_ST_RELOAD_R 
    LDR R0, =0x00FFFFFF;    ; Specify RELOAD value
    STR R0, [R1]            ; reload at maximum       
; writing any value to CURRENT clears it
    LDR R1, =NVIC_ST_CURRENT_R 
    MOV R0, #0              
    STR R0, [R1]            ; clear counter
; enable SysTick with core clock
    LDR R1, =NVIC_ST_CTRL_R    
    MOV R0, #0x0005    ; Enable but no interrupts (later)
    STR R0, [R1]       ; ENABLE and CLK_SRC bits set
    BX  LR 
; Systick Finished initializing (No int.)
 ; TExaS_Init sets bus clock at 80 MHz
    BL  TExaS_Init ; voltmeter, scope on PD3
 ; Initialization
	LDR	R0, =SYSCTL_RCGCGPIO_R;
	LDR	R1, [R0];
	ORR	R1, R1, #0x30;			Start up Port F and Port E
	STR	R1, [R0];
	NOP;
	NOP;
 ; Configure Port E
	LDR	R0, =GPIO_PORTE_DIR_R;
	LDR	R1, [R0];
	ORR	R1, R1, #0x01;			PE0 is set to output (LED)
	BIC	R1, R1, #0x12;			PE1,4 are set to input (buttons)
	STR	R1, [R0];
	LDR	R0, =GPIO_PORTE_AFSEL_R;
	LDR	R1, [R0];
	MOV	R1, #0;					Disables the "alternate functions" in the port
	STR	R1,	[R0];
	LDR	R0, =GPIO_PORTE_DEN_R;
	LDR	R1, [R0];
	MOV	R1, #0xFF;				1 means enable digital I/O
	STR	R1, [R0];
; Configure Port F
	LDR R1, =GPIO_PORTF_LOCK_R; 	2) unlock the lock register
	LDR R0, =GPIO_LOCK_KEY;		unlock GPIO Port F Commit Register
	STR R0, [R1];
	LDR R1, =GPIO_PORTF_CR_R;     enable commit for Port F
	MOV R0, #0xFF;                1 means allow access
	STR R0, [R1];
	LDR R1, =GPIO_PORTF_DIR_R;    5) set direction register
	MOV R0,#0x0E;
	STR R0, [R1];
	LDR R1, =GPIO_PORTF_AFSEL_R;  6) regular port function
	MOV R0, #0;                   0 means disable alternate function
	STR R0, [R1];
	LDR R1, =GPIO_PORTF_PUR_R;    pull-up resistors for PF4,PF0
	MOV R0, #0x11;                1)enable for negative logic
	STR R0, [R1];
	LDR R1, =GPIO_PORTF_DEN_R;    7) enable Port F digital port
	MOV R0, #0xFF;                1 means enable digital I/O
	STR R0, [R1];
; Setting up variables
Configure
	LDR	R0, =GPIO_PORTE_DATA_R;	R0 holds the location for the Data location of Port E
	LDR	R9, =GPIO_PORTF_DATA_R;	R9 holds the location for the Data location of Port F
	LDR	R2, =MAX_DELAY;
	MOV	R3, #5;
	UDIV R4, R2, R3;			The increments of the delay
	MOV	R3, #4;
	MUL	R5, R4, R3;				Default: off for 4/5 of 80Hz
	MOV	R3, #1;
	MUL	R6, R4, R3;				Default: on for 1/5 of 80Hz
	ADD	R7, R2, #0;
	
    CPSIE  I    ; TExaS voltmeter, scope runs on interrupts

loop  
; The main loop engine
	LDR	R1, [R9];
; If the button is pushed, Start breathing
	AND	R3, R1, #0x10;			Check whether the button has been pushed or not
	CMP	R3, #0x00;
	BNE	ifPushed;				If SW1 is pushed, start the breathing
	B Breathe_Start;

ifPushed
	LDR	R1, [R0];				<- R1 holds the data from the data register	
; If the button is pushed, set PE4 to 1
	AND	R3, R1, #0x02;			Check whether the button has been pushed or not
	CMP	R3, #0x00;			If the button is pushed
	BNE	incrementDuty;
	ORR	R8, #0x01;				<- Set R8 to 1 since the button was pushed.
	B blink;
incrementDuty
; Incrementing the duty time
	AND	R3, R8, #0x01;
	CMP	R3, #0x01;				
	BNE	blink;				If the button has been pushed, but is not being pushed
	SUB	R5, R5, R4;				Decrement the off time
	ADD	R6, R6, R4;				Increment the on time
	BIC	R8, #0x01;
	CMP	R5, #0;
	BPL	blink;				If the the off time is < 0 (off < 0%, on > 100%), reset the values to off = 100%, on = 0%
	ADD	R5, R5, R2;				If off is negative, reset off time to max
	MOV	R6, #0;					Reset the on time to 0 (light is always off)
blink
; Turn off the light and wait
	BIC	R1, #0x01;		
	STR	R1, [R0];
	ADD	R7, R5, #0;
	BL	delay;			Delay the program for a amount of time specified in R7
; Turn on the light and wait
	ORR	R1, #0x01;		
	STR	R1, [R0];
	ADD	R7, R6, #0;
	BL	delay;
	
    B   loop
;-----------------------------------------------------------------------------------------------
Breathe_Start
; a subroutine that handles all the breathing functionality by completly reworking everything
	PUSH {r0-r7};	save the values of the of R0--R7
	; Setting up variables
	LDR	R2, =BREATHE_DELAY_MAX;
	MOV	R3, #300;
	UDIV R4, R2, R3;			The increments of the delay
	MOV	R3, #295;
	MUL	R5, R4, R3;				Default: off for 4/5 of 80Hz
	MOV	R3, #5;
	MUL	R6, R4, R3;				Default: on for 1/5 of 80Hz
	ADD	R7, R2, #0;
	
Breathe_loop  
; The main loop engine
	LDR	R1, [R9];				<- R1 holds the data from the data register
Breathe_ifPushed	
; If the button is pushed, Stop breathing
	AND	R3, R1, #0x10;			Check whether the button has been pushed or not
	CMP	R3, #0x10;
	BNE	Breathe_incrementDuty;
	B Breathe_Stop;
	
Breathe_incrementDuty
; Incrementing the duty time
	SUB	R5, R5, R4;				Decrement the off time
	ADD	R6, R6, R4;				Increment the on time
	CMP	R5, #0;
	BMI Verse;
	BEQ Verse;					Check if we've stopped or froze the delay of the light (either R5 or R6 reach zero)
	CMP	R6, #0;
	BPL Breathe_blink;
Verse
	MOV	R3, #-1;
	MUL	R4, R4, R3;				Once we reach a maximum, down/up or up depending on the scenario
	SUB	R5, R5, R4;				Decrement the off time
	ADD	R6, R6, R4;				Increment the on time
Breathe_blink
; Turn off the light and wait
	BIC	R1, #0x01;		
	STR	R1, [R0];
	ADD	R7, R5, #0;
	BL	delay;			Delay the program for a amount of time specified in R7
; Turn on the light and wait
	ORR	R1, #0x01;		
	STR	R1, [R0];
	ADD	R7, R6, #0;
	BL	delay;
	
    B   Breathe_loop  
	
Breathe_Stop
	POP	 {r0-r7};	restore the values of R0--R7
	B loop;
;-----------------------------------------------------------------------------------------------
; a subroutine that loops using the value at R7
delay
	MOV	R3, #0;
delayLoop
	CMP	R7, R3;			Loop until temporary value R3 reaches R2
	BEQ	delayDone;
	ADD	R3, R3, #1;	
	B	delayLoop;
delayDone
	BX LR;
;-----------------------------------------------------------------------------------------------
    ALIGN      ; make sure the end of this section is aligned
    END        ; end of file
