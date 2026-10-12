# Programmable Reflow Oven Controller

An 8051 assembly-based reflow oven controller written on an Intel DE10-lite FPGA board developed as part of an ELEC 291 project at UBC. The system automates the PCB soldering process by monitoring temperature, controlling heating output, and guiding the oven through configurable reflow profiles.

## Features

- **Programmable Reflow Profiles:** Options Menu: A multi-level menu on a 16x2 LCD to supports preset profiles and customizable soak time, reflow time, and temperature targets.
- **Temperature Monitoring:** Reads analog temperature sensor signals through a K-type thermocouple with cold-junction compensation to an ADC and converts measurements for display and control.
- **Validated Accuracy:** Readings were validated against a lab multimeter from 25–240°C, staying within the ±1°C.
- **Closed-Loop Temperature Control:** Uses temperature thresholds, PWM-based output control, and a PWM controlled cooling fan to regulate heating throughout the reflow cycle.
- **LCD User Interface:** Displays temperature, elapsed time, current operating stage, and reflow progress.
- **Hardware Integration:** Interfaces with a heater relay, fan, servo, IR sensor, LEDs, and speaker.
- **Smart Mode:** Uses IR sensor input to support automated operation and detect interruptions during a reflow cycle.
- **Serial Communication:** Transmits temperature measurements over UART via USB-serial for PC-side strip-chart plotting.
- **Fault Handling:** Automatically aborts the reflow process if safety checkpoints are not satisfied, with a 10-beep error alarm and a servo motor automatically opening the oven door.

## Technical Implementation

- **Language:** CV-8052 Assembly
- **Platform:** DE10-Lite
- **Peripherals:** ADC, SSR, timers, interrupts, GPIO, UART, LCD, and seven-segment displays
- **Control Techniques:** Finite-state sequencing, timer-driven routines, PWM, and threshold-based temperature regulation
