% какая-то обработка последовательности на входе, либо
% вычисление доп параметров
% в идеале тут должна быть фильтрация. 

fprintf("s2 summary:\n");
s2();

function s2()  
    phy_channel_static_dopler_offset_hz = evalin("base", "SET_CHANNEL_DOPLER_OFFSET_HZ");
    s2_phy_ch_static_dopler(phy_channel_static_dopler_offset_hz);
 
    phy_channel_awgn_noise = evalin("base", "SET_CHANNEL_AWGN_NOISE");
    s2_phy_ch_awgn(phy_channel_awgn_noise);
    
    phy_channel_epa_enabled = evalin("base", "SET_CHANNEL_EPA_ENABLE");
    s2_phy_ch_epa(phy_channel_epa_enabled);

    phy_channel_eva_enabled = evalin("base", "SET_CHANNEL_EVA_ENABLE");
    s2_phy_ch_eva(phy_channel_eva_enabled); 

    phy_channel_etu_enabled = evalin("base", "SET_CHANNEL_ETU_ENABLE");
    s2_phy_ch_etu(phy_channel_etu_enabled); 

    if (evalin("base", "USE_SIGNAL_DRAW_SPECTROGRAM_AND_SIGNAL") == true) 
        LTE_TIME_UNIT   = evalin("base", "LTE_TIME_UNIT");
        prm             = evalin("base", "prb_lte_params_selected");
        Fs              = prm.sample_rate;           % Гц
        NFFT            = prm.fft_size;
        SCS             = evalin("base","SET_OFDMA_SUBCARRIER_SPACE"); % Гц
        

        if (phy_channel_eva_enabled || phy_channel_epa_enabled ...
           || phy_channel_etu_enabled || phy_channel_static_dopler_offset_hz > 0 ...
           || phy_channel_awgn_noise > 0) ...
           && exist("lte_channel_signal", "var")
            
            x = evalin("base", "lte_received_signal");
        else 
            x = evalin("base", "lte_current_signal");
        end 

        x = x(:);
        N = length(x);
        t = (0:N-1).' * LTE_TIME_UNIT;               % сек
        t_ms = t*1e3;

        % set(0,'DefaultAxesFontName','Times New Roman');
        % set(0,'DefaultAxesFontSize',12);
        % set(0,'DefaultLineLineWidth',1.2);
        % set(0,'DefaultAxesGridAlpha',0.25);
        % set(0,'DefaultTextColor','k', ...
        % 'DefaultAxesXColor','k', ...
        % 'DefaultAxesYColor','k');
       
        figure('Name','LTE Signal: Time and Spectrogram');
       

        plot(t_ms, real(x), 'b'); hold on;
        plot(t_ms, imag(x), 'r');
        grid on; box on;
        xlabel('Время, мс');
        ylabel('Амплитуда');
        legend('I','Q','Location','northeast');
        title(sprintf('I/Q компоненты (Fs = %.3f МГц, N_{FFT} = %d)', Fs/1e6, NFFT));
        
        Nwin = NFFT;
        win = rectwin(Nwin);

        [~,F,T,P] = spectrogram(x, win, 0, NFFT, Fs, 'centered');

        Pdb = 10*log10(abs(P) + eps);
        F_kHz = F/1e3;           % кГц
        T_ms  = T*1e3;           % мс
        
        figure('Name','LTE Signal: Time and Spectrogram');

        imagesc(T_ms, F_kHz, Pdb); axis xy;
        colormap(parula); colorbar;
        c = clim; clim([c(2)-60 c(2)]);       % динамический диапазон 60 dB
        grid on; box on;
        xlabel('Время, мс');
        ylabel('Частота, кГц');
        title(sprintf('Спектрограмма (окно %d, N_{FFT} = %d)', Nwin, NFFT));
        
        annotation('textbox',[0.14 0.92 0.3 0.05], 'String', ...
           sprintf('SCS = %.0f Гц', SCS), ...
           'FontSize',14, "EdgeColor", "none");
        
        hold on;
        if N > 0
            Tsf = 1e-3;                        
            for tm = 0:Tsf:floor(t(end)/Tsf)*Tsf
                xline(tm*1e3,'k:','Alpha',0.15);
            end
        end
    end 
    
    fprintf("\tchannel AWGN: %s\n", string(phy_channel_awgn_noise));
    fprintf("\tchannel EVA: %s\n", string(phy_channel_eva_enabled));
    fprintf("\tchannel EPA: %s\n", string(phy_channel_epa_enabled)); 
    fprintf("\tchannel ETU: %s\n", string(phy_channel_etu_enabled));
    fprintf("\tchannel F DOPLER: %s Hz\n", string(phy_channel_static_dopler_offset_hz));

    %lte_toolbox_run();
end 

function s2_phy_ch_awgn(sigma_noise)
    if isempty(sigma_noise) || sigma_noise<=0
        return;
    end

    x = evalin('base','lte_current_signal');
    x = x(:);

    rng(5489,'twister');
    
    n = (sigma_noise/sqrt(2)) * (randn(size(x)) + 1i*randn(size(x)));

    y = x + n;
    assignin('base','lte_received_signal',y);
end

function s2_phy_ch_static_dopler(offset_hz) 
    if isempty(offset_hz) || offset_hz <= 0
        return;
    end
    
    prm = evalin("base", "prb_lte_params_selected");
    x = evalin("base", "lte_current_signal"); 

    Fs = prm.sample_rate; 
    N  = length(x); 
    n  = (0:N-1).';

    y = x .* ...
        exp(1j*2*pi*offset_hz * n/Fs);
    
    assignin("base", "lte_received_signal", y);
end 

% Reylaight Rayleigh distribution

function s2_phy_ch_epa(is_enabled)
    if ~is_enabled, return; end
    fD = evalin("base", "SET_CHANNEL_EPA_DOPLER_SHIFT_HZ");

    % 3GPP 36.101 B.2.1 Delay profiles
    % B.2.1-2 Extended Pedestrian A model 
    model = struct();
    
    model.tau_ns = [0 30 70 90 110 190 410]; 
    model.pg_db = [0.0 -1.0 -2.0 -3.0 -8.0 -17.2 -20.8]; 

    apply_raylaight_profile(model, fD, "EPA")
end

function s2_phy_ch_eva(is_enabled)
    if ~is_enabled, return; end
    fD = evalin("base", "SET_CHANNEL_EVA_DOPLER_SHIFT_HZ");

    % 3GPP 36.101 B.2.1 Delay profiles
    % B.2.1-3 Extended Vehicular A model 
    model = struct(); 

    model.tau_ns = [0 30 150 310 370 710 1090 1730 2510];
    model.pg_db  = [0 -1.5 -1.4 -3.6 -0.6 -9.1 -7.0 -12.0 -16.9];

    apply_raylaight_profile(model, fD, "EVA");
end

function s2_phy_ch_etu(is_enabled)
    if ~is_enabled, return; end
    fD = evalin("base", "SET_CHANNEL_ETU_DOPLER_SHIFT_HZ");

    % 3GPP 36.101 B.2.1 Delay profiles
    % B.2.1-4 Extended Typical Urban model 
    model = struct(); 

    model.tau_ns = [0 50 120 200 230 500 1600 2300 5000];
    model.pg_db  = [-1 -1 -1 0 0 0 -3 -5 -7];

    apply_raylaight_profile(model, fD, "ETU");
end

function apply_raylaight_profile(ch_model, fD_hz, tag)
    x  = evalin("base","lte_current_signal"); x = x(:);
    params = evalin("base","prb_lte_params_selected");
    Fs = params.sample_rate;

    ch = comm.RayleighChannel( ...
        'SampleRate', Fs, ...
        'PathDelays', ch_model.tau_ns .* 1e-9, ...
        'AveragePathGains', ch_model.pg_db, ...
        'MaximumDopplerShift', fD_hz, ...
        'RandomStream', 'mt19937ar with seed', ...
        'Seed', 22, 'PathGainsOutputPort', true, ...
        'NormalizePathGains', true);
    
    [y, pathGains] = ch(x);

    assignin("base","lte_received_signal", y);

    fprintf('\t%s-RAYLEIGH applied (Fs=%.3f MHz, fD=%g Hz)\n', tag, Fs/1e6, fD_hz);

    Nfft = params.fft_size;             % задержочное/частотное разрешение
    Nw   = params.fft_size;             % длина окна оценки (отсчётов)
    Nhop = Nw / 16;                     % перекрытие Nw / 16 (1/16 от ofdm символа)     
    win  = rectwin(Nw);

    N    = length(x);
    nFrm = floor((N - Nw)/Nhop) + 1;

    H_spec = zeros(Nfft, nFrm);
    t_axis = zeros(1, nFrm);

    for m = 1:nFrm
        idx = (1:Nw) + (m-1)*Nhop;
        Xw = fft(x(idx).*win, Nfft);
        Yw = fft(y(idx).*win, Nfft);
        Hw = Yw ./ (Xw + eps); % +eps, ибо в Xw могут быть нули. eps - машинная точность
        H_spec(:,m) = Hw;
        t_axis(m) = (idx(1)-1)/Fs;
    end

    h_tau_t = ifft(H_spec, Nfft, 1);
    tau_ns  = (0:Nfft-1)'/Fs*1e9;
    t_ms    = t_axis*1e3;

    figure('Name', sprintf('%s ИХ канала во времени', tag));
    surf(t_ms, tau_ns, 20*log10(abs(h_tau_t)), 'EdgeColor','none');
    axis tight; view(2); colormap("gray"); colorbar;
    xlabel('t, ms'); ylabel('\tau, ns'); title(sprintf('%s |(h(\\tau,t)|, dB', tag));
    grid on; box on;
    
    f_axis = linspace(0, Fs, Nfft);              
    f_kHz  = (f_axis - Fs/2)/1e3;                
    H_mag_db = 20*log10(abs(fftshift(H_spec,1)));
    
    figure('Name', sprintf('%s |H(f,t)| Surface (from x,y)', tag));
    surf(t_ms, f_kHz, H_mag_db, 'EdgeColor','none');
    axis tight; view(2); colormap("gray"); colorbar;
    xlabel('t, ms'); ylabel('F, kHz'); title(sprintf('%s |H(f,t)|, dB', tag));
    grid on; box on;

    H_phase = angle(fftshift(H_spec,1));    % рад, размер (Nfft * nFrm)
    
    H_phase_unwrap = H_phase;
    for k = 1:size(H_phase,1)
        H_phase_unwrap(k,:) = unwrap(H_phase(k,:));
    end
    
    figure('Name', sprintf('%s angle H(f,t) Surface (from x,y)', tag));
    surf(t_ms, f_kHz, H_phase_unwrap, 'EdgeColor','none');
    axis tight; view(2); colormap("gray"); colorbar;
    xlabel('t, ms'); ylabel('F, kHz'); title(sprintf('%s angle H(f,t), rad', tag));
    grid on; box on;

    ref = struct();
    ref.tag      = tag;
    ref.Fs       = Fs;
    ref.Nfft     = Nfft;
    ref.Nw       = Nw;
    ref.Nhop     = Nhop;
    ref.t_ms     = t_ms(:);
    ref.tau_ns   = tau_ns(:);
    ref.h_tau_t  = h_tau_t;             % (Nfft * nFrm)
    ref.f_kHz    = f_kHz(:);
    ref.H_spec   = H_spec;              % комплексная матрица (Nfft * nFrm)
    ref.pathGains = pathGains;
    ref.pathDelays = ch_model.tau_ns .* 1e-9;

    assignin("base","lte_channel_truth_hH", ref);
end

function lte_toolbox_run()
    % Ожидаем, что в base уже есть:
    %  - lte_current_signal или lte_received_signal
    %  - prb_lte_params_selected (параметры eNB: NDLRB, NCellID, Ncp, ...)
    %  - SET_CHANNEL_DOPLER_OFFSET_HZ (для оценки частотного смещения)

    % === 1. Выбор входного сигнала ===
    if evalin("base","exist('lte_received_signal','var')")
        rxWaveform = evalin("base","lte_received_signal");
    else
        rxWaveform = evalin("base","lte_current_signal");
    end
    rxWaveform = rxWaveform(:);

    prm = evalin("base","prb_lte_params_selected");
    Fs  = prm.sample_rate;

    % Предполагаем, что есть структура enb, либо собираем её из prm
    if evalin("base","exist('enb','var')")
        enb = evalin("base","enb");
    else
        enb = struct();
        enb.NDLRB           = 6;     % число PRB
        enb.Ng              = 'Sixth';         % по умолчанию
        enb.PHICHDuration   = 'Normal';
        enb.CellRefP        = 1;             % число портов RS (уточнить)
        enb.DuplexMode      = 'FDD';
        enb.CyclicPrefix    = 'Normal'; % 'Normal'/'Extended'
    end

    % === 2. Оценка и компенсация частотного смещения ===
    % В простом варианте – используем известное статическое смещение,
    % позже можно заменить на оценку по RS/PSS/SSS.
    fOffCfg = evalin("base","SET_CHANNEL_DOPLER_OFFSET_HZ");
    if ~isempty(fOffCfg) && fOffCfg ~= 0
        n  = (0:numel(rxWaveform)-1).';
        rxWaveform = rxWaveform .* exp(-1j*2*pi*fOffCfg*n/Fs);
    end

    % === 3. Грубая синхронизация по PSS/SSS (LTE Toolbox) ===
    % % Для модели, где тайминг уже выровнен, можно пропустить.
    % % Здесь оставим задел.
    % [timingOffset, estCellID] = lteDLCellSearch(enb, rxWaveform);
    % enb.NCellID = estCellID;
    % rxWaveform  = rxWaveform(1+timingOffset:end,:);

    % === 4. OFDM‑демодуляция и приём PBCH/MIB ===
    % Подготовка сетки ресурсов на один субкадр (по умолчанию subframe 0)
    rxGrid = lteOFDMDemodulate(enb, rxWaveform)
    
    
    % PBCH располагается в субкадре 0, символы 0..3 слота 1, 4 слота 0/1 в 4×10мс.
    % LTE Toolbox делает всё внутри ltePBCHDecode.
    % Сначала выделяем индексы/символы PBCH:
    pbchIndices = ltePBCHIndices(enb);
    pbchRx      = rxGrid(pbchIndices);

    % Оценка канала по RS для PBCH
    cellRSIndices = lteCellRSIndices(enb,0);
    cellRSSymbols = rxGrid(cellRSIndices);
    % В простейшем варианте принимаем плоский канал Hsc (усреднённый по RS):
    Hest = mean(cellRSSymbols);
    pbchEq = pbchRx ./ (Hest + eps);

    % Декодирование PBCH/MIB
    [mibBits, ~, ~, pbchSymbols] = ltePBCHDecode(enb, pbchEq);

    % Парсинг MIB в структуру enb (lteMIB умеет и encode, и decode)
    enbFromMIB = lteMIB(mibBits);

    % Обновляем ключевые поля конфигурации соты
    enb.NDLRB           = enbFromMIB.NDLRB;
    enb.Ng              = enbFromMIB.Ng;
    enb.PHICHDuration   = enbFromMIB.PHICHDuration;
    enb.NFrame          = enbFromMIB.NFrame;

    assignin("base","lte_mib_bits", mibBits);
    assignin("base","enb_decoded", enb);

    fprintf('\tMIB decoded: NDLRB=%d, NFrame=%d, Ng=%s, PHICH=%s\n', ...
        enb.NDLRB, enb.NFrame, enb.Ng, enb.PHICHDuration);

    % === 5. Измерения RSRP / RSSI ===
    % RSRP – средняя мощность RS‑RE в ваттах/отсчёт.
    % RSSI – суммарная мощность по всем RE в полосе.

    % a) Снова формируем сетку для одного субкадра (на случай обновлённого enb)
    rxGrid = lteOFDMDemodulate(enb, rxWaveform);

    % Индексы RS для Cell‑specific RS (антипорт 0)
    rsInd = lteCellRSIndices(enb,0);
    rsSym = rxGrid(rsInd);

    % RSRP в линейной шкале (усреднённая мощность RS‑символа)
    rsrp_lin = mean(abs(rsSym).^2);

    % RSSI: суммарная мощность по всем RE в одном субкадре
    rssi_lin = mean(abs(rxGrid(:)).^2) * numel(rxGrid);

    % RSRQ = N * RSRP / RSSI, N – число PRB. [web:6][web:18][web:31][web:34]
    N_rb  = enb.NDLRB;
    rsrq_lin = (N_rb * rsrp_lin) / max(rssi_lin, eps);
    rsrq_lin = cast(rsrq_lin, "single");
    % Перевод в dBm/dB (предполагаем, что масштаб rxWaveform уже в Вт или с нормировкой,
    % при необходимости добавить референсный уровень)
    rsrp_dB  = 10*log10(single(rsrp_lin) + eps);
    rssi_dB  = 10*log10(rssi_lin + eps);
    rsrq_dB  = 10*log10(rsrq_lin + eps);

    meas = struct();
    meas.RSRP_lin = rsrp_lin;
    meas.RSSI_lin = rssi_lin;
    meas.RSRQ_lin = rsrq_lin;
    meas.RSRP_dB  = rsrp_dB;
    meas.RSSI_dB  = rssi_dB;
    meas.RSRQ_dB  = rsrq_dB;
    meas.NDLRB    = N_rb;

    assignin("base","lte_meas_rsrp_rssi_rsrq", meas);

    fprintf('\tRSRP = %.2f dB, RSSI = %.2f dB, RSRQ = %.2f dB (NDLRB=%d)\n', ...
        rsrp_dB, rssi_dB, rsrq_dB, N_rb);
end
