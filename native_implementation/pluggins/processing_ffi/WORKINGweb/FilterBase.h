//
// Created by Stanislav Mircic  <stanislav at backyardbrains.com>
//

#ifndef SPIKE_RECORDER_ANDROID_FILTERBASE_H
#define SPIKE_RECORDER_ANDROID_FILTERBASE_H

#include <cstdint>

//
// Base class that is inherited by all filters
//
namespace backyardbrains {

    namespace filters {

        class FilterBase {
        public:
            FilterBase();

            void initWithSamplingRate(float sr);

            void setCoefficients();

            void filter(int16_t *data, int32_t numFrames, bool flush = false);

            void filterContiguousData(double *data, int32_t numFrames);

        protected:

            void intermediateVariables(double Fc, double Q);

            double one;
            double samplingRate;
            double gInputKeepBuffer[2];
            double gOutputKeepBuffer[2];
            double omega, omegaS, omegaC, alpha;
            double coefficients[5];
            double a0, a1, a2, b0, b1, b2;
        private:
        };
    }}
#endif //SPIKE_RECORDER_ANDROID_FILTERBASE_H
