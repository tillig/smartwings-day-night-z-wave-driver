# SmartWings Day/Night Z-Wave Driver

The [SmartWings day/night cellular shades](https://www.smartwingshome.com/collections/day-night-shades) is a set of window shades with two motors - one to control an upper set of cellular shades (sheer) and one to control a lower set (opaque). You can choose the percentage of sheers/blackout/fully-open you want by controlling the independent motors.

For the Z-Wave motor, "testing" has been shown as being ongoing for years. What this has resulted in is the Z-Wave integration is slim - it largely treats the blinds as "single motor," where the blinds are "all the way open" or "sheers are 100%" but there's nothing in-between. The goal of this driver is to get this to work so I can actually control my blinds automatically via Google Home + Samsung SmartThings.

## History

I bought three sets of the day/night shades with the Z-Wave motor, not realizing it wouldn't work 100%. At the time, Matter was still emerging and I didn't want to pay a lot extra for a proprietary SmartWings app/integration. I have other Z-Wave/Zigbee devices and it seemed like the safe bet.

I have a Samsung SmartThings hub and it works wonderfully for integrating these other Z-Wave devices.

Unfortunately, on adding the Z-Wave blinds to SmartThings, what I noticed is that it appears to add _two devices_ per set of blinds:

1. An entry that has blinds which doesn't control things right. The blinds are "all the way open" or "sheers are 100%" but there's nothing in-between.
2. Some sort of "dummy" looking device that is unrecognized. It does not do anything.

At one point, the SmartWings website directed you to install a custom driver for the blinds which was "being tested" and "under development." That has since disappeared and I can't find it anymore. My guess is it never worked so it got unlisted. Now the blinds are using the default SmartThings window treatments driver, which does not support these dual-motor kinds of shades.

I've been unable to find a solution to this, so I'm going to try to make one myself.

## Reference

- [SmartWings Z-Wave Programming Guide](./assets/smartwings-z-wave-programming-guide.pdf): Retrieved [from their site](https://cdn.shopify.com/s/files/1/0573/0215/5461/files/SmartWings_Z-wave_Motor_Programming_Guide_cb52ae04-036e-446c-bff2-6e944bedbb5f.pdf?v=1754441184) for local reference/indexing. I am not sure if this covers dual-motor blinds to the detail of single motor blinds.
- [SmartThings Developer Center](https://developer.smartthings.com/) - Information on creating [device integrations](https://developer.smartthings.com/docs/devices/device-basics) for interacting with Z-Wave and other device types.
- [SmartThings Edge driver for Z-Wave window treatments](https://github.com/SmartThingsCommunity/SmartThingsEdgeDrivers/tree/main/drivers/SmartThings/zwave-window-treatment) - This is what drives the blinds by default.
