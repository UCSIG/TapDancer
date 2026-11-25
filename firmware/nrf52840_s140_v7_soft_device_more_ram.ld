/* Linker script to configure memory regions. 
Allocates more ram for the soft device:

Regular config:
  RAM (rwx) :  ORIGIN = 0x20006000, LENGTH = 0x20040000 - 0x20006000

New config:
  RAM (rwx) :  ORIGIN = 0x20008000, LENGTH = 0x20040000 - 0x20008000

https://learn.adafruit.com/bluefruit-nrf52-feather-learning-guide/hathach-memory-map
*/

SEARCH_DIR(.)
GROUP(-lgcc -lc -lnosys)

MEMORY
{
  FLASH (rx)     : ORIGIN = 0x27000, LENGTH = 0xED000 - 0x27000

  /* SRAM required by Softdevice depend on
   * - Attribute Table Size (Number of Services and Characteristics)
   * - Vendor UUID count
   * - Max ATT MTU
   * - Concurrent connection peripheral + central + secure links
   * - Event Len, HVN queue, Write CMD queue
   */ 
  RAM (rwx) :  ORIGIN = 0x20008000, LENGTH = 0x20040000 - 0x20008000
}

SECTIONS
{
  . = ALIGN(4);
  .svc_data :
  {
    PROVIDE(__start_svc_data = .);
    KEEP(*(.svc_data))
    PROVIDE(__stop_svc_data = .);
  } > RAM
  
  .fs_data :
  {
    PROVIDE(__start_fs_data = .);
    KEEP(*(.fs_data))
    PROVIDE(__stop_fs_data = .);
  } > RAM
} INSERT AFTER .data;

/* "C:\Users\JF\.platformio\packages\framework-arduinoadafruitnrf52-seeed\cores\nRF5\linker\nrf52_common.ld" */
INCLUDE "nrf52_common.ld"
