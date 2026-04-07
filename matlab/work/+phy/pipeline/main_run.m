clear;

%% INFOOOOO
%{
    В общем у srsENB_signal_time_domain_6_prb.dat.mat
    нулевой символ находится между 
    
    PS в signalAnalyzer нуумерация с 0
    а в variable viewer с 1
    так что в (скобках) будут семплы которые удобны для 
    signal analyzer

    7681(7680) и 7818(7817) - и это точный диапазон!!! - 138 семплов
    10 - циклический префикс и 128 - полезные семплы

    [START] + [SYMBOL_LEN - 1] = SYMBOL_END; 

    7681 + 138 - 1 = 7818;

    7819(7818) - первый символ начало
    7819 + 137 - 1 = 7955 - конец

    7956 - второй символ
    7956 + 137 - 1 = 8092 - конец

    8093 - третий символ
    8093 + 137 - 1 = 8229 - конец
    
    четвёртый символ между
    8230(8299) и 8365(8366) - тоже точный диапазон
%}

%% initial params

% USE_SIGNAL_ID - сигнал, который будем обрабатывать
% Доступно:
% s1_6prb - запись 1 на 6 prb
% s1_15prb - запись 1 на 15 prb
% где 1 - количество записей для КАЖДЫХ prb
USE_SIGNAL_ID = "s1_6prb";

% для сигнала будет в отдельном окне построено два графика
% спектрограмма и график сигнала во временной области
USE_SIGNAL_DRAW_SPECTROGRAM_AND_SIGNAL = false;

% длительность сигнала в ms 
% 0 - использовать ВЕСЬ сигнал
SET_SIGNAL_LENGTH_MS = 50;

% принудительно использовать другой samplerate 
% 0 - использоавть samplerate предусмотренный 3GPP
SET_FORCE_SAMPLERATE = 0;

% принудительно использовать другой размер FFT
% 0 - использовать FFT_SIZE предусмотренный 3GPP
SET_FORCE_FFT_SIZE   = 0; 

% начальное* количество OFDM символов на слот
% доступные значения: 7 или 6
% 7 - NORMAL CP
% 6 - EXTENDED CP
% начальное* - потому что на начало работы мы не знаем размер CP
% это будет вычеслено далее в цепи обработки
% в семплах это SET_INITIAL_OFDMA_SYMBOLS_PER_SLOT 
SET_INITIAL_OFDMA_SYMBOLS_PER_SLOT = 7;

% Расстояние между поднесущими
% Пока модель построена вокруг того, что это 15кГц
% изменение приведёт к "неожиданным" эффектрам :)
SET_OFDMA_SUBCARRIER_SPACE = 15e3; 

% Для AWGN шума.
% В sigma. 
% если задан 0, шума не будет
SET_CHANNEL_AWGN_NOISE = 0.0;
% каждый следующий семпл будет зашумлён
% на SET_CHANNEL_AWGN_INCREMENTIAL_NOISE, пока не достигнут максимум
% SET_CHANNEL_AWGN_INCREMENTIAL_NOISE_RANGE, в этом случаее уменьшается на
% 0.1
SET_CHANNEL_AWGN_INCREMENTIAL_NOISE = 0.1;
SET_CHANNEL_AWGN_INCREMENTIAL_NOISE_RANGE = [0, 10];

% Канал EPA
% Включить/выключить канал EPA
SET_CHANNEL_EPA_ENABLE = false; 
% Доплеровское смещение для EPA (максимальное)
SET_CHANNEL_EPA_DOPLER_SHIFT_HZ = 7; 

% Канал EVA
% Включить/выключить канал EVA
SET_CHANNEL_EVA_ENABLE = false; 
% Доплеровское смещение для EVA (максимальное)
SET_CHANNEL_EVA_DOPLER_SHIFT_HZ = 30; 

% Канал ETU
% Включить/выключить канал ETU
SET_CHANNEL_ETU_ENABLE = false;
% Доплеровское смещение для ETU (максимальное)
SET_CHANNEL_ETU_DOPLER_SHIFT_HZ = 300; 

% Установка "статического доплера" в Гц
SET_CHANNEL_DOPLER_OFFSET_HZ = 0;

% Установка рязрядности АЦП в битах (часть модели)
SET_ADC_BIT_DEPTH = 16;

% Initial параметры базовой станции, далее будем использовать
% это в декодировании и подборе метода демодуляции
SET_ENB_STRUCT = struct( ...
        'Ng', 'Sixth', ...
        'PHICHDuration', 'Normal', ...
        'DuplexMode', 'FDD', ...
        'CyclicPrefix', 'Normal' ...
    );

% Загрузка семплов
%%%%%%%%%%%%%%%%%%
s1_load; 
%%%%%%%%%%%%%%%%%%

% 3GPP 36.211 4 Frame structure
% LTE_3GPP_BASIC_TIME_UNIT_SECONDS
% длительность одного дискретного отсчёта (sampling period)
%
% документ построен на основе того, что за 
% частоту дискретизации берётся 30.72MHz
% а минимально он может быть 1.92MHz
% параметр эквивалентен Ts в 3GPP 
LTE_3GPP_BASIC_TIME_UNIT_SECONDS = 1/(15000 * 2048);

% 3GPP 4.1 Frame structure type 1 for FDD
% LTE_3GPP_BASIC_SAMPLES_PER_FRAME
% Количество семплов на 1 кадр
%
% эквивалентно LTE_3GPP_BASIC_TIME_UNIT_SECONDS по смыслу
% количество семплов на фрейм при Fs = 30.72MHz
LTE_3GPP_BASIC_SAMPLES_PER_FRAME = 307200; 

% LTE_TIME_UNIT
% длительность одного дискретного отсчёта (sampling period)
% но это случай уже для нашей системы
LTE_TIME_UNIT = 1 / ...
    (SET_OFDMA_SUBCARRIER_SPACE * prb_lte_params_selected.fft_size);

% отношение нашего LTE_TIME_UNIT и LTE_3GPP_BASIC_TIME_UNIT_SECONDS
% важно для дальнейшего процессинга сигнала
LTE_TIME_UNIT_FACTOR = LTE_3GPP_BASIC_TIME_UNIT_SECONDS / LTE_TIME_UNIT;

% Например случай с 1.92MHz длительность одного дискретного отсчёта
% будет В 16 раз меньше!

% Количество семплов на 1 кадр
% 1 кадр = 10мс = 1 * 10e-2 секунд;
% 
LTE_SAMPLES_PER_FRAME = LTE_3GPP_BASIC_SAMPLES_PER_FRAME ... 
    * LTE_TIME_UNIT_FACTOR;

% Преобработка
s2_prepocessing;

s3_ofdma_symbols_sync_and_demux;