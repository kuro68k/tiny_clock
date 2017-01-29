@ECHO OFF
"C:\Program Files (x86)\Atmel\AVR Tools\AvrAssembler2\avrasm2.exe" -S "E:\code\AVR\MSF Clock\labels.tmp" -fI -W+ie -C V2 -o "E:\code\AVR\MSF Clock\MSF_Clock.hex" -d "E:\code\AVR\MSF Clock\MSF_Clock.obj" -e "E:\code\AVR\MSF Clock\MSF_Clock.eep" -m "E:\code\AVR\MSF Clock\MSF_Clock.map" "E:\code\AVR\MSF Clock\MSF_Clock.asm"
