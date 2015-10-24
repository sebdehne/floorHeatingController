Room sensor
===============

Assembly code which I use in my temperature and humidity room sensors, developed for PIC16F690 microcontroller.
The ChipCap2 sensor is used for temperature and humidity. It also provides low-battery voltage detection.

See https://github.com/sebdehne/pic8libs for all libs.

Operation overview:
- sleep for 60 seconds
- power up ChipCap2 sensor
- measure temperature
- measure humidity
- power down ChipCap2 sensor
- measure light sensor
- send results over RF
- go back to top


