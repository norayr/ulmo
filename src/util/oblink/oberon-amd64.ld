/* Linker script for Ulm Oberon AMD64 binaries.
   Creates a single RWE LOAD segment with ELF headers included,
   matching the layout required by the Oberon runtime's MEMINIT code
   (single-segment binary, contiguous from file offset 0). */

OUTPUT_FORMAT("elf64-x86-64", "elf64-x86-64", "elf64-x86-64")
OUTPUT_ARCH(i386:x86-64)
ENTRY(_entry)

PHDRS
{
  oberon PT_LOAD FILEHDR PHDRS FLAGS(7);
}

SECTIONS
{
  . = 0x400000 + SIZEOF_HEADERS;

  .init   : { *(.init)   } :oberon
  .text   : { *(.text)   }
  .rodata : { *(.rodata) }
  .private : { *(.private) *(.data) *(.got) *(.got.plt) }
  .bss    : { *(.bss) *(COMMON) }

  /DISCARD/ : { *(.note*) *(.comment) *(.eh_frame*) }
}
