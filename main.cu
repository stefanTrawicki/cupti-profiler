#include <cupti_target.h>
#include <cupti_profiler_target.h>
#include <nvperf_host.h>
#include <cuda.h>
#include <string>
#include <stdio.h>
#include <stdlib.h>
#include <Metric.h>
#include <Eval.h>
#include <FileOp.h>

#define L2_CACHE_READS  "lts__t_sectors_op_read.sum"
#define L2_CACHE_WRITES "lts__t_sectors_op_write.sum"

#define EXIT_WAIVED 2

#define NVPW_API_CALL(apiFuncCall)                                             \
do {                                                                           \
    NVPA_Status _status = apiFuncCall;                                         \
    if (_status != NVPA_STATUS_SUCCESS) {                                      \
        fprintf(stderr, "%s:%d: error: function %s failed with error %d.\n",   \
                __FILE__, __LINE__, #apiFuncCall, _status);                    \
        exit(EXIT_FAILURE);                                                    \
    }                                                                          \
} while (0)

#define CUPTI_API_CALL(apiFuncCall)                                            \
do {                                                                           \
    CUptiResult _status = apiFuncCall;                                         \
    if (_status != CUPTI_SUCCESS) {                                            \
        const char *errstr;                                                    \
        cuptiGetResultString(_status, &errstr);                                \
        fprintf(stderr, "%s:%d: error: function %s failed with error %s.\n",   \
                __FILE__, __LINE__, #apiFuncCall, errstr);                     \
        exit(EXIT_FAILURE);                                                    \
    }                                                                          \
} while (0)

#define DRIVER_API_CALL(apiFuncCall)                                           \
do {                                                                           \
    CUresult _status = apiFuncCall;                                            \
    if (_status != CUDA_SUCCESS) {                                             \
        fprintf(stderr, "%s:%d: error: function %s failed with error %d.\n",   \
                __FILE__, __LINE__, #apiFuncCall, _status);                    \
        exit(EXIT_FAILURE);                                                    \
    }                                                                          \
} while (0)

#define RUNTIME_API_CALL(apiFuncCall)                                          \
do {                                                                           \
    cudaError_t _status = apiFuncCall;                                         \
    if (_status != cudaSuccess) {                                              \
        fprintf(stderr, "%s:%d: error: function %s failed with error %s.\n",   \
                __FILE__, __LINE__, #apiFuncCall, cudaGetErrorString(_status));\
        exit(EXIT_FAILURE);                                                    \
    }                                                                          \
} while (0)

#define HANDLE_COMPATABILITY(params) \
do { \
    if (params.isSupported != CUPTI_PROFILER_CONFIGURATION_SUPPORTED) { \
        std::cerr << "Unable to profile on device " << deviceNum << ::std::endl; \
        if (params.architecture == CUPTI_PROFILER_CONFIGURATION_UNSUPPORTED) { \
            std::cerr << "\tdevice architecture is not supported" << ::std::endl; \
        } \
        if (params.sli == CUPTI_PROFILER_CONFIGURATION_UNSUPPORTED) { \
            std::cerr << "\tdevice sli configuration is not supported" << ::std::endl; \
        } \
        if (params.vGpu == CUPTI_PROFILER_CONFIGURATION_UNSUPPORTED) { \
            std::cerr << "\tdevice vgpu configuration is not supported" << ::std::endl; \
        } \
        else if (params.vGpu == CUPTI_PROFILER_CONFIGURATION_DISABLED) { \
            std::cerr << "\tdevice vgpu configuration disabled profiling support" << ::std::endl; \
        } \
        if (params.confidentialCompute == CUPTI_PROFILER_CONFIGURATION_UNSUPPORTED) { \
            std::cerr << "\tdevice confidential compute configuration is not supported" << ::std::endl; \
        } \
        if (params.cmp == CUPTI_PROFILER_CONFIGURATION_UNSUPPORTED) { \
            std::cerr << "\tNVIDIA Crypto Mining Processors (CMP) are not supported" << ::std::endl; \
        } \
        exit(EXIT_WAIVED); \
    } \
} while (0)

bool run(std::vector<uint8_t>&configImage, std::vector<uint8_t>&counterDataScratchBuffer, std::vector<uint8_t>&counterDataImage, CUpti_ProfilerReplayMode profilerReplayMode, CUpti_ProfilerRange profilerRange) {
    CUcontext cuContext;
    DRIVER_API_CALL(cuCtxGetCurrent(&cuContext));
    CUpti_Profiler_BeginSession_Params beginSessionParams = {CUpti_Profiler_BeginSession_Params_STRUCT_SIZE};
    CUpti_Profiler_SetConfig_Params setConfigParams = {CUpti_Profiler_SetConfig_Params_STRUCT_SIZE};
    CUpti_Profiler_EnableProfiling_Params enableProfilingParams = {CUpti_Profiler_EnableProfiling_Params_STRUCT_SIZE};
    CUpti_Profiler_DisableProfiling_Params disableProfilingParams = {CUpti_Profiler_DisableProfiling_Params_STRUCT_SIZE};
    CUpti_Profiler_PushRange_Params pushRangeParams = {CUpti_Profiler_PushRange_Params_STRUCT_SIZE};
    CUpti_Profiler_PopRange_Params popRangeParams = {CUpti_Profiler_PopRange_Params_STRUCT_SIZE};

    beginSessionParams.ctx = NULL;
    beginSessionParams.counterDataImageSize = counterDataImage.size();
    beginSessionParams.pCounterDataImage = &counterDataImage[0];
    beginSessionParams.counterDataScratchBufferSize = counterDataScratchBuffer.size();
    beginSessionParams.pCounterDataScratchBuffer = &counterDataScratchBuffer[0];
    beginSessionParams.range = profilerRange;
    beginSessionParams.replayMode = profilerReplayMode;
    beginSessionParams.maxRangesPerPass = 1;
    beginSessionParams.maxLaunchesPerPass = 1;

    CUPTI_API_CALL(cuptiProfilerBeginSession(&beginSessionParams));

    setConfigParams.pConfig = &configImage[0];
    setConfigParams.configSize = configImage.size();

    setConfigParams.passIndex = 0;
    setConfigParams.minNestingLevel = 1;
    setConfigParams.numNestingLevels = 1;
    CUPTI_API_CALL(cuptiProfilerSetConfig(&setConfigParams));
    /* User takes the resposiblity of replaying the kernel launches */
    CUpti_Profiler_BeginPass_Params beginPassParams = {CUpti_Profiler_BeginPass_Params_STRUCT_SIZE};
    CUpti_Profiler_EndPass_Params endPassParams = {CUpti_Profiler_EndPass_Params_STRUCT_SIZE};


    // code will run each replay here
    do {
        CUPTI_API_CALL(cuptiProfilerBeginPass(&beginPassParams));

        {
            CUPTI_API_CALL(cuptiProfilerEnableProfiling(&enableProfilingParams));
            std::string rangeName = "userrangeA";
            pushRangeParams.pRangeName = rangeName.c_str();
            CUPTI_API_CALL(cuptiProfilerPushRange(&pushRangeParams));

            {
                // Actual function to run is here
                system("echo hello world");
            }

            CUPTI_API_CALL(cuptiProfilerPopRange(&popRangeParams));
            CUPTI_API_CALL(cuptiProfilerDisableProfiling(&disableProfilingParams));
        }

        CUPTI_API_CALL(cuptiProfilerEndPass(&endPassParams));
    } while (!endPassParams.allPassesSubmitted);


    CUpti_Profiler_FlushCounterData_Params flushCounterDataParams = {CUpti_Profiler_FlushCounterData_Params_STRUCT_SIZE};
    CUPTI_API_CALL(cuptiProfilerFlushCounterData(&flushCounterDataParams));
    CUpti_Profiler_UnsetConfig_Params unsetConfigParams = {CUpti_Profiler_UnsetConfig_Params_STRUCT_SIZE};
    CUPTI_API_CALL(cuptiProfilerUnsetConfig(&unsetConfigParams));
    CUpti_Profiler_EndSession_Params endSessionParams = {CUpti_Profiler_EndSession_Params_STRUCT_SIZE};
    CUPTI_API_CALL(cuptiProfilerEndSession(&endSessionParams));

    return true;
}

bool CreateCounterDataImage(
    std::vector<uint8_t>& counterDataImage,
    std::vector<uint8_t>& counterDataScratchBuffer,
    std::vector<uint8_t>& counterDataImagePrefix)
{
    CUpti_Profiler_CounterDataImageOptions counterDataImageOptions;
    counterDataImageOptions.pCounterDataPrefix = &counterDataImagePrefix[0];
    counterDataImageOptions.counterDataPrefixSize = counterDataImagePrefix.size();
    counterDataImageOptions.maxNumRanges = 1;
    counterDataImageOptions.maxNumRangeTreeNodes = 1;
    counterDataImageOptions.maxRangeNameLength = 64;

    CUpti_Profiler_CounterDataImage_CalculateSize_Params calculateSizeParams = {CUpti_Profiler_CounterDataImage_CalculateSize_Params_STRUCT_SIZE};

    calculateSizeParams.pOptions = &counterDataImageOptions;
    calculateSizeParams.sizeofCounterDataImageOptions = CUpti_Profiler_CounterDataImageOptions_STRUCT_SIZE;

    CUPTI_API_CALL(cuptiProfilerCounterDataImageCalculateSize(&calculateSizeParams));

    CUpti_Profiler_CounterDataImage_Initialize_Params initializeParams = {CUpti_Profiler_CounterDataImage_Initialize_Params_STRUCT_SIZE};
    initializeParams.sizeofCounterDataImageOptions = CUpti_Profiler_CounterDataImageOptions_STRUCT_SIZE;
    initializeParams.pOptions = &counterDataImageOptions;
    initializeParams.counterDataImageSize = calculateSizeParams.counterDataImageSize;

    counterDataImage.resize(calculateSizeParams.counterDataImageSize);
    initializeParams.pCounterDataImage = &counterDataImage[0];
    CUPTI_API_CALL(cuptiProfilerCounterDataImageInitialize(&initializeParams));

    CUpti_Profiler_CounterDataImage_CalculateScratchBufferSize_Params scratchBufferSizeParams = {CUpti_Profiler_CounterDataImage_CalculateScratchBufferSize_Params_STRUCT_SIZE};
    scratchBufferSizeParams.counterDataImageSize = calculateSizeParams.counterDataImageSize;
    scratchBufferSizeParams.pCounterDataImage = initializeParams.pCounterDataImage;
    CUPTI_API_CALL(cuptiProfilerCounterDataImageCalculateScratchBufferSize(&scratchBufferSizeParams));

    counterDataScratchBuffer.resize(scratchBufferSizeParams.counterDataScratchBufferSize);

    CUpti_Profiler_CounterDataImage_InitializeScratchBuffer_Params initScratchBufferParams = {CUpti_Profiler_CounterDataImage_InitializeScratchBuffer_Params_STRUCT_SIZE};
    initScratchBufferParams.counterDataImageSize = calculateSizeParams.counterDataImageSize;

    initScratchBufferParams.pCounterDataImage = initializeParams.pCounterDataImage;
    initScratchBufferParams.counterDataScratchBufferSize = scratchBufferSizeParams.counterDataScratchBufferSize;
    initScratchBufferParams.pCounterDataScratchBuffer = &counterDataScratchBuffer[0];

    CUPTI_API_CALL(cuptiProfilerCounterDataImageInitializeScratchBuffer(&initScratchBufferParams));

    return true;
}

int main(int argc, char* argv[]) {

    CUdevice cuDevice;
    std::vector<std::string> metrics;
    std::vector<uint8_t> counterDataImagePrefix;
    std::vector<uint8_t> configImage;
    std::vector<uint8_t> counterDataImage;
    std::vector<uint8_t> counterDataScratchBuffer;
    std::vector<uint8_t> counterAvailabilityImage;

    std::string CounterDataFileName("data.counterdata");
    std::string CounterDataSBFileName("data.counterdataSB");

    CUpti_ProfilerReplayMode profilerReplayMode = CUPTI_UserReplay;
    CUpti_ProfilerRange profilerRange = CUPTI_UserRange;

    char *metricName;

    int deviceNum = 0;
    if (argc > 1) {
        deviceNum = atoi(argv[1]);
    }

    DRIVER_API_CALL(cuInit(0));
    DRIVER_API_CALL(cuDeviceGet(&cuDevice, deviceNum));

    CUpti_Profiler_Initialize_Params profilerInitializeParams = {CUpti_Profiler_Initialize_Params_STRUCT_SIZE};
    CUPTI_API_CALL(cuptiProfilerInitialize(&profilerInitializeParams));

    CUpti_Profiler_DeviceSupported_Params params = {CUpti_Profiler_DeviceSupported_Params_STRUCT_SIZE};
    params.cuDevice = deviceNum;
    CUPTI_API_CALL(cuptiProfilerDeviceSupported(&params));

    // run the check to make sure we can run what we need to
    HANDLE_COMPATABILITY(params);

    // push the requested metrics, if not available use the defaults
    if (argc > 2) {
        metricName = strtok(argv[2], ",");
        while(metricName != NULL) {
            metrics.push_back(metricName);
            metricName = strtok(NULL, ",");
        }
    } else {
        metrics.push_back(L2_CACHE_READS);
        metrics.push_back(L2_CACHE_WRITES);
    }

    std::cout << "---- Metrics ----" << std::endl;
    for (auto &metric : metrics) {
        std::cout << metric << std::endl;
    }

    CUpti_Device_GetChipName_Params getChipNameParams = { CUpti_Device_GetChipName_Params_STRUCT_SIZE };
    getChipNameParams.deviceIndex = deviceNum;
    CUPTI_API_CALL(cuptiDeviceGetChipName(&getChipNameParams));
    std::string chipName(getChipNameParams.pChipName);

    CUcontext cuContext;
    DRIVER_API_CALL(cuCtxCreate(&cuContext, 0, cuDevice));

    CUpti_Profiler_GetCounterAvailability_Params getCounterAvailabilityParams = {CUpti_Profiler_GetCounterAvailability_Params_STRUCT_SIZE};
    getCounterAvailabilityParams.ctx = cuContext;
    CUPTI_API_CALL(cuptiProfilerGetCounterAvailability(&getCounterAvailabilityParams));

    counterAvailabilityImage.clear();
    counterAvailabilityImage.resize(getCounterAvailabilityParams.counterAvailabilityImageSize);
    getCounterAvailabilityParams.pCounterAvailabilityImage = counterAvailabilityImage.data();
    CUPTI_API_CALL(cuptiProfilerGetCounterAvailability(&getCounterAvailabilityParams));

    NVPW_InitializeHost_Params initializeHostParams = { NVPW_InitializeHost_Params_STRUCT_SIZE };
    NVPW_API_CALL(NVPW_InitializeHost(&initializeHostParams));

    if(!NV::Metric::Config::GetConfigImage(chipName, metrics, configImage, counterAvailabilityImage.data())) {
        std::cout << "Failed to create configImage" << std::endl;
        exit(EXIT_FAILURE);
    }

    if(!NV::Metric::Config::GetCounterDataPrefixImage(chipName, metrics, counterDataImagePrefix)) {
        std::cout << "Failed to create counterDataImagePrefix" << std::endl;
        exit(EXIT_FAILURE);
    }

    if(!CreateCounterDataImage(counterDataImage, counterDataScratchBuffer, counterDataImagePrefix)) {
        std::cout << "Failed to create counterDataImage" << std::endl;
        exit(EXIT_FAILURE);
    }

    if(!run(configImage, counterDataScratchBuffer, counterDataImage, profilerReplayMode, profilerRange)) {
        std::cout << "Failed to run sample" << std::endl;
        exit(EXIT_FAILURE);
    }

    CUpti_Profiler_DeInitialize_Params profilerDeInitializeParams = {CUpti_Profiler_DeInitialize_Params_STRUCT_SIZE};
    CUPTI_API_CALL(cuptiProfilerDeInitialize(&profilerDeInitializeParams));

    /* Dump counterDataImage in file */
    WriteBinaryFile(CounterDataFileName.c_str(), counterDataImage);
    WriteBinaryFile(CounterDataSBFileName.c_str(), counterDataScratchBuffer);

    /* Evaluation of metrics collected in counterDataImage, this can also be done offline*/
    NV::Metric::Eval::PrintMetricValues("A100", counterDataImage, metrics);

    exit(EXIT_SUCCESS);
}