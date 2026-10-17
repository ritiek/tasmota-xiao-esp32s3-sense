#ifndef _USER_CONFIG_OVERRIDE_H_
#define _USER_CONFIG_OVERRIDE_H_

// Seeed Studio XIAO ESP32S3 Sense (OV3660 + PDM mic + microSD)

#undef  STA_SSID1
#define STA_SSID1         "your-2.4GHz-ssid"
#undef  STA_PASS1
#define STA_PASS1         "your-password"

#undef  PROJECT
#define PROJECT           "xiao-sense"
#undef  FRIENDLY_NAME
#define FRIENDLY_NAME     "XIAO ESP32S3 Sense"

// Pins (index = GPIO0..21, then GPIO33..48):
//   GPIO0 Button1 | GPIO7/8/9 SPI CLK/MISO/MOSI | GPIO21 SDCard CS (also the active-low user LED)
//   Camera: XCLK 10, SIOD 40, SIOC 39, D1..D8 = 15,17,18,16,14,12,11,48, VSYNC 38, HREF 47, PCLK 13
//   PDM mic: CLK 42 as I2S WS, DATA 41 as I2S DIN
//   GPIO1-6, 43, 44 = header pads D0-D5, D6, D7 left as User
//   GPIO19/20 = USB, GPIO35-37 = octal PSRAM
#undef  USER_TEMPLATE
#define USER_TEMPLATE "{\"NAME\":\"XIAO ESP32S3 Sense\",\"GPIO\":[32,1,1,1,1,1,1,736,672,704,4992,5094,5093,5184,5092,5088,5091,5089,5090,0,0,6720,0,0,0,0,0,5120,5056,5024,7872,7840,1,1,0,0,5152,5095],\"FLAG\":0,\"BASE\":1}"
#undef  MODULE
#define MODULE            USER_MODULE
#undef  FALLBACK_MODULE
#define FALLBACK_MODULE   USER_MODULE

// Runs once after a settings reset (first boot after a full flash).
// OV3660 is mounted upside down: flip it back and apply Espressif's OV3660 tuning.
// Mic: PDM, 16 kHz (what TFL "MIC" keyword spotting needs).
#undef  USER_BACKLOG
#define USER_BACKLOG      "WcFlip 1;WcBrightness 1;WcSaturation -2;WcResolution 11;I2SConfig {\"Rx\":{\"Mode\":1,\"SampleRate\":16000}}"

#endif  // _USER_CONFIG_OVERRIDE_H_
