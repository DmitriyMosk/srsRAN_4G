#pragma once

// https://www.3gpp.org/dynareport?code=36-series.htm
// https://www.etsi.org/deliver/etsi_ts/136100_136199/136101/11.30.00_60/ts_136101v113000p.pdf
// https://www.etsi.org/deliver/etsi_ts/136100_136199/136101/12.10.01_60/ts_136101v121001p.pdf

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define LTE_EARFCN_STEP_KHZ 100U
#define LTE_INVALID_BAND 0U

typedef struct {
    uint16_t band;
    uint32_t earfcn_min;
    uint32_t earfcn_max;
    uint32_t dl_low_khz;
} lte_earfcn_band_t;

// 3GPP TS 36.101 Table 5.7.3-1, limited to the bands used by this project.
static const lte_earfcn_band_t LTE_EARFCN_BANDS[] = {
    {  1U,     0U,   599U, 2110000U },
    {  2U,   600U,  1199U, 1930000U },
    {  3U,  1200U,  1949U, 1805000U },
    {  4U,  1950U,  2399U, 2110000U },
    {  5U,  2400U,  2649U,  869000U },
    {  7U,  2750U,  3449U, 2620000U },
    {  8U,  3450U,  3799U,  925000U },
    { 12U,  5010U,  5179U,  729000U },
    { 13U,  5180U,  5279U,  746000U },
    { 17U,  5730U,  5849U,  734000U },
    { 18U,  5850U,  5999U,  860000U },
    { 19U,  6000U,  6149U,  875000U },
    { 20U,  6150U,  6449U,  791000U },
    { 25U,  8040U,  8689U, 1930000U },
    { 26U,  8690U,  9039U,  859000U },
    { 28U,  9210U,  9659U,  758000U },
    { 32U,  9920U, 10359U, 1452000U },
    { 38U, 37750U, 38249U, 2570000U },
    { 39U, 38250U, 38649U, 1880000U },
    { 40U, 38650U, 39649U, 2300000U },
    { 41U, 39650U, 41589U, 2496000U },
    { 66U, 66436U, 67335U, 2110000U },
};

static inline size_t lte_earfcn_band_count(void)
{
    return sizeof(LTE_EARFCN_BANDS) / sizeof(LTE_EARFCN_BANDS[0]);
}

static inline const lte_earfcn_band_t *lte_band_info(uint16_t band)
{
    size_t idx = 0U;

    for (idx = 0U; idx < lte_earfcn_band_count(); ++idx) {
        if (LTE_EARFCN_BANDS[idx].band == band) {
            return &LTE_EARFCN_BANDS[idx];
        }
    }

    return NULL;
}

static inline const lte_earfcn_band_t *lte_earfcn_find_band(uint32_t earfcn)
{
    size_t idx = 0U;

    for (idx = 0U; idx < lte_earfcn_band_count(); ++idx) {
        if ((earfcn >= LTE_EARFCN_BANDS[idx].earfcn_min) &&
            (earfcn <= LTE_EARFCN_BANDS[idx].earfcn_max)) {
            return &LTE_EARFCN_BANDS[idx];
        }
    }

    return NULL;
}

static inline uint16_t lte_earfcn_to_band(uint32_t earfcn)
{
    const lte_earfcn_band_t *band = lte_earfcn_find_band(earfcn);

    return (band != NULL) ? band->band : LTE_INVALID_BAND;
}

static inline bool lte_band_earfcn_to_dl_freq_khz(uint16_t band,
                                                   uint32_t earfcn,
                                                   uint32_t *dl_freq_khz)
{
    const lte_earfcn_band_t *band_info = lte_band_info(band);

    if ((band_info == NULL) || (dl_freq_khz == NULL)) {
        return false;
    }

    if ((earfcn < band_info->earfcn_min) || (earfcn > band_info->earfcn_max)) {
        return false;
    }

    *dl_freq_khz = band_info->dl_low_khz +
                   ((earfcn - band_info->earfcn_min) * LTE_EARFCN_STEP_KHZ);

    return true;
}

static inline bool lte_earfcn_to_dl_freq_khz(uint32_t earfcn, uint32_t *dl_freq_khz)
{
    const lte_earfcn_band_t *band_info = lte_earfcn_find_band(earfcn);

    if (band_info == NULL) {
        return false;
    }

    return lte_band_earfcn_to_dl_freq_khz(band_info->band, earfcn, dl_freq_khz);
}

static inline double lte_earfcn_to_dl_freq_mhz(uint32_t earfcn)
{
    uint32_t dl_freq_khz = 0U;

    if (!lte_earfcn_to_dl_freq_khz(earfcn, &dl_freq_khz)) {
        return -1.0;
    }

    return (double)dl_freq_khz / 1000.0;
}
