Room sensor
===============

Assembly code which I use in my temperature and humidity room sensors, developed for PIC16F690 microcontroller.
The SHT15 sensor is used for temperature and humidity. It also provides low-battery voltage detection.

See https://github.com/sebdehne/pic8libs for all libs.

Operation overview:
- sleep for 60 seconds
- measure light sensor
- power up SHT15 sensor
- measure temperature
- measure humidity
- get battery voltage status
- power down SHT15 sensor
- send results over RF
- go back to top


