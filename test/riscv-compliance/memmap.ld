MEMORY
  {
    RAM   (wx) : ORIGIN = 0x0, LENGTH = 4M
    RESULT (w) : ORIGIN = ORIGIN(RAM) + LENGTH(RAM), LENGTH = 64k
  }

OUTPUT_FORMAT("elf32-littleriscv", "elf32-littleriscv", "elf32-littleriscv")
OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
  .text : {
    PROVIDE (_start = .);
    *(.text*)
    . = ALIGN(4);
  } > RAM

  .rodata : {
    *(.rodata*)
    . = ALIGN(4);
  } > RAM

  .data : {
    *(.data*)
    . = ALIGN(4);
  } > RAM
  .bss : {
    *(.bss .bss.*)
    . = ALIGN(4);
  } > RAM
  /* Link testout section to upper memory region */
  .testdata :
  {
    PROVIDE(__testdata_start = .);
   *(.testdata)
  } > RESULT
}


