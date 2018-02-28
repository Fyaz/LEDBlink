;****************** main.s ***************
; Program written by: Faiyaz Mostofa & Zaine
; Date Created: 2/4/2017
; Last Modified: 2/28/2018
; Brief description of the program:
;   A collection of operations are done in this program (at once):
;	- A Green LED blinks repeatedly indicating that the program is running
;	- A Red LED blinks on and off based on different patterns which can be changed by a switch (8Hz).
;	  The LED will cycle through different patterns as specified below:
;	    :on for (1/40s) -> on for (1/20s) -> on for (3/40s) -> on for (1/10s) -> always on -> always off -> loop:
;	  The delays for the blinking is handled by SysTick.s
;	- The Red LED also has a breathing function can be activated by holding the internal button @ PF4 on the micro-controller.
;	  The delays for the breathing is handled by the delay function @ the end of this file.
;   - A debugging capture tool that runs 3rd time the loop finishes.
; Hardware connections (External: One button and one LED)
;  PE1 is Button input  (1 means pressed, 0 means not pressed)
;  PE0 is a Red LED output (1 activates external LED on protoboard)
;  PF2 is a Green LED output (1 activates external LED on protoboard)
;  PF4 is builtin button SW1 on Launchpad (Internal)
;        Negative Logic (0 means pressed, 1 means not pressed)

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
GPIO_LOCK_KEY      EQU 0x4C4F434B  	; Unlocks the GPIO_CR register
SYSCTL_RCGCGPIO_R  EQU 0x400FE608
; System Clock reigsters
NVIC_ST_CTRL_R        EQU 0xE000E010
NVIC_ST_RELOAD_R      EQU 0xE000E014
NVIC_ST_CURRENT_R     EQU 0xE000E018

NVIC_ST_CTRL_COUNT    EQU 0x00010000  ; Count flag
NVIC_ST_CTRL_CLK_SRC  EQU 0x00000004  ; Clock Source
NVIC_ST_CTRL_INTEN    EQU 0x00000002  ; Interrupt enable
NVIC_ST_CTRL_ENABLE   EQU 0x00000001  ; Counter mode
NVIC_ST_RELOAD_M      EQU 0x00FFFFFF  ; Counter load value

;Variables that hold the maximum values 
MAX_DELAY		   EQU 0x0C		  ; The interval size of the delays (in 10ms)
								  ;	0x1864A8 (in cycles)
BREATHE_DELAY_MAX  EQU 0x5E00	  ; The delay required

     IMPORT TExaS_Init
	 IMPORT SysTick_Init
	 IMPORT SysTick_Wait10ms
	 
     THUMB
;------------Global Variables-------------------------------------------------------------------
     AREA    DATA, ALIGN=2
     
	;Blinking variables
delay_inc	 	  SPACE 4	; how to increment the delays when we need to change them (1/5 of MAX_DELAY)
delay_off		  SPACE 4	; how long the LED will stay off (in cycles)
delay_on		  SPACE 4	; how long the LED will stay on (in cycles)
prev_button_state SPACE	1	; captures whether a button has been released or pushed
green_counter	  SPACE 1	; it counts everytime the main loop is run and toggles the blue LED after a certain time is met.
	
	;Debuggin variables
data_capture  	SPACE 50	; Array of 50 8-byte numbers
time_capture	SPACE 200	; Array of 50 32-byte numbers
debug_capture_counter	SPACE	1	; it counts everytime the main loop is run and captures debugging data after a certain amount of loops
	
NEntries 		SPACE 1		; Number of entries in either array	
	
     AREA    |.text|, CODE, READONLY, ALIGN=2
     THUMB
     EXPORT  Start
		 
;---------Main Code-----------------------------------------------------------------------------
Start
 ; TExaS_Init sets bus clock at 80 MHz
    BL  TExaS_Init ; voltmeter, scope on PD3
    BL  Debug_Init ;	Initializes the Debugging Tools
	BL 	SysTick_Init;	Initializes the SysTick (method in SysTick.s)
	BL	Ports_Init;		Initializes Ports E,F
						; PE0 = Red LED output
						; PE1 = positive logic Input (Switch)
						; PF2 = Green LED output
						; PF4 = Hold switch for breathing functionality
						
; Setting up variables
Configure
	LDR	R1, =MAX_DELAY;		
	MOV	R2, #5;					
	UDIV R2, R1, R2;		split the max delay into 5 equal sections
	LDR	R1, =delay_inc;
	STR	R2, [R1];			delay_inc = (MAX_DELAY / 5)
	
	LDR	R1, =delay_inc;
	LDR	R2, [R1];
	MOV	R3, #4;
	MUL	R2, R2, R3;	
	LDR	R1, =delay_off;	
	STR	R2, [R1];			Default: the delay_off starts @ 4/5 of the MAX_DELAY
	
	LDR	R1, =delay_inc;
	LDR	R2, [R1];
	LDR R1, =delay_on;
	STR	R2, [R1];			Default: the delay_on on starts @ 1/5 of the MAX_DELAY
	
	LDR	R1, =green_counter;
	MOV	R2, #0;
	STRB R2, [R1];			Initially set the green_counter to 0
	LDR	R1, =debug_capture_counter;
	MOV	R2, #0;
	STRB R2, [R1];			Initially set the debug_counter to 0
	
    CPSIE  I    ; TExaS voltmeter, scope runs on interrupts

; The main loop engine
main_loop  

	BL	Check_Debug;	; Check if we need to record debugging statistics
	BL	Check_Green		; Check whether to toggle the green LED on or not
	BL	Check_Breathe	; Check if whether we need to make the LED Breathe

;If a button @ PE1 is pushed, increment the blinking pattern
Blink_ifPushed
	LDR	R1, =GPIO_PORTE_DATA_R;
	LDR R2, =prev_button_state;
	LDRB R2, [R2];
	LDR	R3, [R1];				<- R3 holds the data from the PortE data register
	AND	R3, R3, #0x02;			Check whether the button has been pushed or not
	CMP R3, R2;					<- Check if the button is in the same state as before 
	BEQ Blink;
	LDR	R2, =prev_button_state;
	STRB R3, [R2];
; If the button is pushed, set PE4 to 1
	CMP	R3, #0x00;			If the button is pushed
	BNE	Blink_incrementDuty;
	B Blink;
Blink_incrementDuty
; Incrementing the duty time
	LDR	R2, =delay_inc;
	LDR	R2, [R2];				
	LDR	R1, =delay_off;			
	LDR	R3, [R1];				
	SUB	R3, R3, R2;				Decrement the off time
	STR	R3, [R1];
	LDR	R1, =delay_on;
	LDR	R3, [R1];
	ADD	R3, R3, R2;				Increment the on time
	STR R3, [R1];
;Check if the duty time needs to be reset (always on -> always off)
	LDR	R1, =delay_off;
	LDR	R2, [R1];
	CMP	R2, #0;
	BPL	Blink;				If the the off time is < 0 (off < 0%, on > 100%), reset the values to off = 100%, on = 0%
	LDR	R2, =MAX_DELAY;
	LDR R1, =delay_off;
	STR R2, [R1];
	LDR	R1, =delay_on;
	MOV	R2, #0;					Reset the on time to 0 (light is always off)
	STR	R2, [R1];
Blink
; Turn off the light and wait
	LDR	R1, =GPIO_PORTE_DATA_R;
	LDR	R2, [R1];
	BIC	R2, #0x01;
	STR	R2, [R1];
	LDR R2, =delay_off;
	LDR R0, [R2];
	BL	SysTick_Wait10ms	;BL	delay;	Delay the program for a amount of time specified in R0
; Turn on the light and wait
	LDR	R1, =GPIO_PORTE_DATA_R;
	LDR	R2, [R1];
	ORR	R2, #0x01;		
	STR	R2, [R1];
	LDR R2, =delay_on;
	LDR R0, [R2];
	BL	SysTick_Wait10ms	;BL	delay
	
    B   main_loop
;-----------------------------------------------------------------------------------------------
Breathe_Start
; a subroutine that handles all the breathing functionality by completly reworking everything
	PUSH {R0-R7};
	PUSH {R8, LR};
	
	; Setting up variables
	LDR R0, =GPIO_PORTE_DATA_R;
	LDR	R9, =GPIO_PORTF_DATA_R;
	LDR	R2, =BREATHE_DELAY_MAX;
	MOV	R3, #500;
	UDIV R4, R2, R3;			The increments of the delay
	ADD	R5, R2, #0;				Default: off for 4/5 of 80Hz
	MOV	R6, #0;					Default: on for 1/5 of 80Hz
	ADD	R7, R2, #0;
	
Breathe_loop  
	LDR	R1, [R9];				<- R1 holds the data from the data register
Breathe_ifPushed	
	AND	R3, R1, #0x10;			Check whether the button has been pushed or not
	CMP	R3, #0x10;				Keep Breathing until the button is released.
	BNE	Breathe_incrementDuty;
	B Breathe_Stop;
	
Breathe_incrementDuty
; Incrementing the duty time
	SUB	R5, R5, R4;				Decrement the off time
	ADD	R6, R6, R4;				Increment the on time
	CMP	R5, #0;
	BMI Breathe_Verse;
	BEQ Breathe_Verse;			Check if we've stopped or froze the delay of the light (either R5 or R6 reach zero)
	CMP	R6, #0;
	BPL Breathe;
Breathe_Verse
	MOV	R3, #-1;
	MUL	R4, R4, R3;				Once we reach a maximum, down/up or up depending on the scenario
	SUB	R5, R5, R4;				Decrement the off time
	ADD	R6, R6, R4;				Increment the on time
Breathe
; Turn off the light and wait
	BIC	R1, #0x01;		
	STR	R1, [R0];
	PUSH {R0, R1};
	ADD	R0, R5, #0;
	BL	delay;					Delay the program for a amount of time specified in R7
	POP {R0, R1};
; Turn on the light and wait
	ORR	R1, #0x01;		
	STR	R1, [R0];
	PUSH {R0, R1};
	ADD	R0, R6, #0;
	BL	delay;
	POP {R0, R1};
	
    B   Breathe_loop  
	
Breathe_Stop
	POP {R8,LR};
	POP {R0-R7};

	BX LR;
	
;-------CHECK_debug-----------------------------------------------------------------------------
; Wait 5 duty cycles, then save the points in the Dubugging arrays
Check_Debug
	PUSH {R0, R1};
	PUSH {R2, LR};
	LDR	R1, =debug_capture_counter;
	LDRB R2, [R1];	
	ADD	R2, R2, #1;			debug_capture_counter++;
	STRB R2, [R1];
	CMP	R2, #3;
	BNE	Check_Debug_Leave;
	BL	Debug_Capture;		if(debug_capture_counter == 3) capture data
	MOV	R2, #0;
	STRB R2, [R1];
Check_Debug_Leave
	POP	{R2, LR};
	POP {R0, R1};
	BX LR;					
	
;-------CHECK_Green-----------------------------------------------------------------------------
; Wait 5 duty cycles, then save the points in the Dubugging arrays
Check_Green
	PUSH {R0, R1};
	PUSH {R2, LR};
	LDR	R1, =green_counter;
	LDRB R2, [R1];
	ADD	R2, R2, #1;			green_counter++
	STRB R2, [R1];
	CMP	R2, #3;
	BNE	Check_Green_Leave;	
	BL	Toggle_Green;		if(green_counter == 3) toggle Green LED
	MOV	R2, #0;
	STRB R2, [R1];
Check_Green_Leave
	POP	{R2, LR};
	POP {R0, R1};
	BX LR;		

;-------CHECK_Breathe-----------------------------------------------------------------------------
; If the button @ PF4 is pushed, Start breathing
Check_Breathe
	PUSH {R0, R1};
	PUSH {R2, LR};
	LDR	R1, =GPIO_PORTF_DATA_R;
	LDR	R2, [R1];
	AND	R2, R2, #0x10;			Check whether the button has been pushed or not
	CMP	R2, #0x00;
	BNE	Check_Breathe_Leave;	If SW1 is pushed, start the breathing
	BL Breathe_Start;
Check_Breathe_Leave
	POP	{R2, LR};
	POP {R0, R1};
	BX	LR;
	
;-------DEBUG_Init------------------------------------------------------------------------------
    ;Initiliazing Debug Dump
	;R10 = data_capture pointer
	;R11 = time_capture pointer
Debug_Init
   	LDR R10, =data_capture
	LDR R11, =time_capture;		Created pointers

	PUSH {R0, R1}
	PUSH {R2, R3}
	MOV R0, #0x08;		8 bits in data_capture
	MOV R1, #50;
	
setting_data_capture
	SUB R1,R1, #0x01
	MOV R2, #0xFF;		; Fill the data array with 0xFF (signifying empty)
	STRB R2, [R10]
	ADD R10, R10, R0
	CMP R1, #0x0;
	BNE setting_data_capture
	
	MOV R1, #50;
	MOV	R2, #0x04;
	MUL R0,R0, R2;
setting_time_capture
	MOV	R2, #0x01;
	SUB R1,R1, R2;
	MOV R2, #0xFFFFFFFF; ; Fill the time array with 0xFFFFFFFF (signifying empty)
	STR R2, [R10]
	ADD R10, R10, R0
	CMP R1, #0x0;
	BNE setting_time_capture
	
	LDR R10, =data_capture
	LDR R11,=time_capture
	POP {R2, R3}
	POP {R0, R1}
	BX LR
	
;-------DEBUG_CAPTURE---------------------------------------------------------------------------
;saves one data point
Debug_Capture		
   	PUSH {R0,R1}
	LDR R0 , =NEntries
	LDR R0, [R0]
	CMP R0 , #50
	BEQ DONE_C
	LDR R0, =GPIO_PORTE_DATA_R
	AND R0, R0, #0x02;		Capturing Pins E0 and E1
	LSR R0, R0, #0x03;
	LDR R1, =GPIO_PORTE_DATA_R
	AND R1,R1,#0x01;
	AND R0,R0,R1;
	LDR R1, =NVIC_ST_CURRENT_R;	Capturing Time
	STRB R0, [R10];			Finished Storing Data
	
	STR R1, [R11]
	ADD R10, R10, #0x01
	ADD R11, R11, #0x04
	LDR R0, =NEntries
	LDR R1, [R0]
	ADD R1,R1, #0x01
	STR R1, [R0]
	
DONE_C	POP {R0,R1}
	BX LR;

;-------Toggle Green LED (PF2)------------------------------------------------------------------
;Toggles the Green LED on and off (PF2)
Toggle_Green
	PUSH {R0, R1};
	LDR	R0, =GPIO_PORTF_DATA_R;
	LDR	R1, [R0];
	EOR	R1, #0x04;
	STR	R1, [R0];
	POP {R0, R1};
	BX LR;
	
;-----------------------------------------------------------------------------------------------
delay
; a subroutine that loops using the value at R0
	PUSH {R0, R1};
	MOV	R1, #0;
delayLoop
	CMP	R0, R1;			Loop until temporary value, R1, reaches R0
	BEQ	delayDone;
	ADD	R1, R1, #1;	
	B	delayLoop;
delayDone
	POP {R0, R1};
	BX LR;
	
;-----------------------------------------------------------------------------------------------
; Port Initialization
Ports_Init
	PUSH {R0, R1};
	PUSH {R2, LR};
	LDR	R0, =SYSCTL_RCGCGPIO_R;
	LDR	R1, [R0];
	ORR	R1, R1, #0x30;			Start up Port F and Port E
	STR	R1, [R0];
	NOP;
	NOP;
 ; Configure Port E
	LDR	R0, =GPIO_PORTE_DIR_R;
	LDR	R1, [R0];
	ORR	R1, R1, #0x01;				PE0 is set to output (LED)
	BIC	R1, R1, #0x12;				PE1,4 are set to input (buttons)
	STR	R1, [R0];
	LDR	R0, =GPIO_PORTE_AFSEL_R;
	LDR	R1, [R0];
	MOV	R1, #0;						Disables the "alternate functions" in the port
	STR	R1,	[R0];
	LDR	R0, =GPIO_PORTE_DEN_R;
	LDR	R1, [R0];
	MOV	R1, #0xFF;					1 means enable digital I/O
	STR	R1, [R0];
; Configure Port F
	LDR R1, =GPIO_PORTF_LOCK_R; 	2) unlock the lock register
	LDR R0, =GPIO_LOCK_KEY;			unlock GPIO Port F Commit Register
	STR R0, [R1];
	LDR R1, =GPIO_PORTF_CR_R;   	enable commit for Port F
	MOV R0, #0xFF;              	1 means allow access
	STR R0, [R1];
	LDR R1, =GPIO_PORTF_DIR_R;  	5) set direction register
	MOV R0,#0x0E;
	STR R0, [R1];
	LDR R1, =GPIO_PORTF_AFSEL_R;	6) regular port function
	MOV R0, #0;                   	0 means disable alternate function
	STR R0, [R1];
	LDR R1, =GPIO_PORTF_PUR_R;    	pull-up resistors for PF4,PF0
	MOV R0, #0x11;                	1)enable for negative logic
	STR R0, [R1];
	LDR R1, =GPIO_PORTF_DEN_R;    	7) enable Port F digital port
	MOV R0, #0xFF;                	1 means enable digital I/O
	STR R0, [R1];
	POP  {R2, LR};
	POP	 {R0, R1};
	BX LR;
;-----------------------------------------------------------------------------------------------
    ALIGN      ; make sure the end of this section is aligned
    END        ; end of file
