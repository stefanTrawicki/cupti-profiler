Not intended for serious use, will provide explanations of how CUPTI works for metrics profiling and the required initialisation steps.

Sourced from [here](https://docs.nvidia.com/cupti/pdf/Cupti.pdf).

Fundamental Definitions
-------
* Device: An nvidia accelerator.
* Range: The area of code to profile on a device.
* Event: A countable activity on a device.
* Counter: Number of occurences of an event on a device.
* Metric: Value derived from counters.
* Pass: Some metrics cannot be calculated from a single run of a device, passes being identical repetitions of a run to finish metric collection.
* Replay: Performing the operation being repeated.
* Session: A profiling session. GPU resources allocated, profiler armed, power management disabled in session boundaries.

CUPTI Process Definitions
-------
* ConfigurationImage: A blob configuring counters we are going to collect from.
* CounterDataImage: Blob with the values gotten from the counters.
* CounterDataPrefix: CounterDataImage metadata.