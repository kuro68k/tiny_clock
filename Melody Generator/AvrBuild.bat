@ECHO OFF
"C:\Program Files (x86)\Atmel\AVR Tools\AvrAssembler2\avrasm2.exe" -S "E:\code\AVR\Melody Generator\labels.tmp" -fI -W+ie -o "E:\code\AVR\Melody Generator\Melody.hex" -d "E:\code\AVR\Melody Generator\Melody.obj" -e "E:\code\AVR\Melody Generator\Melody.eep" -m "E:\code\AVR\Melody Generator\Melody.map" "E:\code\AVR\Melody Generator\mg.asm"
