% детекция 

% Проблемы 04.12 
% d.moskovskikh
% Обдумать возможность корреляции во временной области
% Оценка канала не по комплексно сопряжённой 

s3_trace_data = struct(); 

% lte_current_signal -> lte_current_signal_ofdma_decoded

% пока что рассмотрим опять же идеальные условия
% полоса сигнала соответствует 3GPP (не нужно bp фильтр ставить)
% для неидеальных условий будем дорабатывать этот файл
% и дорабатывать s2_preprocessing

% см 3GPP 36.211 Table 6.12-1: OFDM parameters

% длительность одного OFDM символа в семплах соответствует FFT + CP

% опять же. 160 и 140 - размер CP для 30.72MHz
if eq(SET_INITIAL_OFDMA_SYMBOLS_PER_SLOT, 7)
    OFDMA_FIRST_SLOT_CP_SAMPLES = 160 * LTE_TIME_UNIT_FACTOR;
    OFDMA_ETC_SLOTS_CP_SAMPLES = 144 * LTE_TIME_UNIT_FACTOR;
end 

if eq(SET_INITIAL_OFDMA_SYMBOLS_PER_SLOT, 6) 
    OFDMA_FIRST_SLOT_CP_SAMPLES = 512 * LTE_TIME_UNIT_FACTOR;
    OFDMA_ETC_SLOTS_CP_SAMPLES = 512 * LTE_TIME_UNIT_FACTOR;
end 

assert(OFDMA_FIRST_SLOT_CP_SAMPLES <= prb_lte_params_selected.fft_size ...
    && OFDMA_ETC_SLOTS_CP_SAMPLES <= prb_lte_params_selected.fft_size, ...
    "Cyclic prefix mast be аааа"); 

if (SET_CHANNEL_EVA_ENABLE || SET_CHANNEL_EPA_ENABLE ...
   || SET_CHANNEL_ETU_ENABLE || SET_CHANNEL_AWGN_NOISE > 0 || ...
   SET_CHANNEL_DOPLER_OFFSET_HZ > 0) && exist("lte_received_signal", "var")
    lte_s3_signal = lte_received_signal;
else 
    lte_s3_signal = lte_current_signal;
end 

s3(lte_s3_signal, ...
    OFDMA_FIRST_SLOT_CP_SAMPLES, ...
    OFDMA_ETC_SLOTS_CP_SAMPLES, ...
    SET_INITIAL_OFDMA_SYMBOLS_PER_SLOT, ...
    evalin("base", "lte_primary_syncronization_seq"), ...
    evalin("base", "lte_secondary_syncronization_seq"));

function s3( ...
    lte_signal_time_domain, ...
    lte_first_ofdm_symbol_len, ...
    lte_etc_ofdm_symbol_len, ...
    lte_ofdm_symbol_per_slot, ...
    lte_pss_variants, ...
    lte_sss_variants) 

    prb_lte_params_selected = evalin("base", "prb_lte_params_selected");
    end_sample = length(lte_signal_time_domain);

    % %
    % N - колчиество семплов в сигнале
    N = numel(lte_signal_time_domain);

    % Размерность FFT
    Nfft = prb_lte_params_selected.fft_size;

    % ф-я ддля вычисления точек корреляции cp и сигнала
    % lte_one_ofdm_symbol_len - в случае с OFDMA ещё и является ОКНОМ
    % изначально что было
    %
    % НИЖЕ ПРОСТО ПРИМЕР!!
    % [0,...,127] - типа первые 128 символов OFDM после IFFT
    % т.к. в канал они отправляются с 0, то
    % 
    % [127,...,0][127,...,108] ... [127,...,0][127,...,108]
    % [payload]  [cp]              [payload]  [cp]
    %
    % И на стороне RX
    % [108,...,127][0,...,127] ... [108,...,127][0,...,127]
    % 0....................................................last

    function [corr_taps, metrics] = ofdm_corr_point(signal, ofdm_cp_length, ...
            fft_size, threshold)
        
        corr_taps = zeros(length(signal), "logical");
        metrics   = zeros(length(signal), "single");

        for i=1:length(corr_taps) 
            window = prb_lte_params_selected.fft_size + cp;
            tmp = lte_signal_time_domain(sample:sample + window - 1);
            
            tmp_cp = tmp(1:cp); % пример! [108,...,127]
            tmp_pl = tmp(cp + 1:end); % пример! [0,...,127]

        end 
        

    end 

    correlation_metric = zeros(end_sample, 1);

    % мы ищем PSS, так что 
    % возьмём CP = 9;
    
    pss_scores_all          = zeros(N,3);    % по 3 вариантам NID2
    pss_best_score          = zeros(N,1);
    pss_best_id             = -1*ones(N,1);
    pss_phy_root_id         = 0;                      % id eNB

    % CP для PSS
    cp = lte_etc_ofdm_symbol_len;

    % окно для lte OFDM символа
    window = Nfft + cp;

    for sample = 1:N
        if (sample + window + 1 >= N) 
            break;
        end 

        tmp = lte_signal_time_domain(sample:sample + window - 1);

        % тут надо сделать одно допущение
        
        % cp_window;
        % symbol_window;

        tmp_cp = tmp(1:cp); % пример! [108,...,127]
        tmp_pl = tmp(cp + 1:end); % пример! [0,...,127]

        % то с чем мы будем искать корреляцию
        tmp_cp_do = tmp_pl(end - cp + 1:end);
        
        % энергия циклического префикса 
        E_cp = sum(abs(tmp_cp).^2);

        % энергия части символа OFDM, из которой 
        % создали (возможно) циклический префикс
        E_cp_do = sum(abs(tmp_cp_do).^2); 
        
        % ну.. тут понятно, если энергия = 0
        % то гг.
        if E_cp == 0 || E_cp_do == 0, continue; end
    
        % Отношение энергии "захваченного" CP
        % к энергии "возможного" CP
        E_factor = E_cp / E_cp_do; 

        % считаем корреляцию между tmp_cp 
        % и его сопряжённой копией в другом месте
        Rh = sum(tmp_cp .* conj(tmp_cp_do));
        
        % мы смотрим только на ЭНЕРГИЮ
        % и нормируем
        Rh_norm = (abs(Rh)^2) / (E_cp * E_cp_do);
        
        % save this
        correlation_metric(sample) = Rh_norm;
        
        % 50/50 типа
        if (Rh_norm >= 0.3) 
            pl_demuxed = fft(tmp_pl,prb_lte_params_selected.fft_size,1);
            pl_demuxed_len = length(pl_demuxed);

            % Выбор 62 поднесущих для PSS (без DC):
            % Определим индексы для FFT
            % DC = 1; положительные частоты: 2..(Nfft/2+1), отрицательные: (Nfft/2+2)..Nfft

            idx_pos62 = 2:(1+31);             % 2..32
            idx_neg62 = pl_demuxed_len-31+1 : pl_demuxed_len;     % 98..128 (31 штук)

            Xp = [pl_demuxed(idx_neg62); pl_demuxed(idx_pos62)];

            pss_refs = lte_pss_variants;    % 3 x 62 (каждая строка — опора в частотной области, без DC)
            Xp_col   = Xp(:);               % 62x1 наблюдение
            
            % search pss 
            if pss_phy_root_id == 0
                scores = zeros(3,1);
                for v = 1:3
                    r = pss_refs{v}(:).';        % 62x1 => 1x62
                    scores(v) = phy.fn.complex_corr_norm_sqabs(r, Xp_col);
                end

                pss_scores_all(sample,:) = scores.';
                [best_score, best_nid2]  = max(scores);
                pss_best_score(sample)   = best_score;
                pss_best_id(sample)      = best_nid2 - 1; % 0,1,2
                
                % ну типа опять 50/50
                if best_score > 0.5
                    pss_phy_root_id          = best_nid2 - 1;
                end 
               
                assignin("base", "PHY_FRAME_DETECTED_PSS", pss_phy_root_id);
            else 
                r = pss_refs{pss_phy_root_id + 1}(:).';        % 62x1 => 1x62
                scores = phy.fn.complex_corr_norm_sqabs(r, Xp_col);
                
                pss_scores_all(sample:pss_phy_root_id + 1) = scores;
                pss_best_score(sample) = scores;
                % pss_scores_all(sample, )
            end 

            pss_best_id(sample)      = best_nid2 - 1; % 0,1,2

            if best_score > 0.5
                assignin('base','last_pss_nid2',best_nid2-1);
                assignin('base','last_pss_score',best_score);
            end

            %lte_pss_variants
        end 
    end 

    figure('Name', 'CP Correlation Metric');

    plot(1:length(correlation_metric), abs(correlation_metric), 'b-', 'LineWidth', 1.5);
    xlabel('Sliding window (samples)');
    ylabel('normalize(R_{h})');
    title('function R_{h}');
    grid on;

    % correlation_metric = correlation_metric .* 1000;

    assignin('base', 'correlation_metric', correlation_metric);
    assignin('base', "pl_demuxed", pl_demuxed);

    figure('Name','CP metric and PSS scores');
    t = (1:end_sample).';
    tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
    
    nexttile;
    plot(t, correlation_metric); hold on;
    grid on; xlabel('sample'); ylabel('R_h (norm)');
    title('CP-корреляция (нормированная)');
    
    nexttile;
    
    plot(t, pss_best_score, 'b-','LineWidth',1.2); hold on;
    plot(t, pss_scores_all(:,1),'--','Color',[0 0.45 0.74]);
    plot(t, pss_scores_all(:,2),'--','Color',[0.85 0.33 0.10]);
    plot(t, pss_scores_all(:,3),'--','Color',[0.47 0.67 0.19]);

    grid on; xlabel('sample'); ylabel('Score');
    
    legend('best','NID2=0','NID2=1','NID2=2','Location','northeast');
    title('PSS корреляционные метрики');
    
    assignin('base','correlation_metric',correlation_metric);
    assignin('base','pss_scores_all',pss_scores_all);
    assignin('base','pss_best_score',pss_best_score);
    assignin('base','pss_best_id',pss_best_id);

    %%% УАА, ОЦЕНКА КАНАЛА

    pss_rh_best_peaks_idxs = find(pss_best_score > 0.6);

    fprintf("Finded peaks idxs: %s", ...
        strjoin(string(pss_rh_best_peaks_idxs), ", "));

    assert(numel(pss_rh_best_peaks_idxs) > 0, "Some problem Dmitry");

    % sample_n_max - семпл, где корреляция по PSS максимальна
    % искал по графику
    sample_n_max = pss_rh_best_peaks_idxs(2);
   
    % длина окна OFDM-символа (полезная часть + CP)
    Nfft   = prb_lte_params_selected.fft_size;
    cp     = lte_etc_ofdm_symbol_len;
    window = Nfft + cp;
    
    % вырезаем целый PSS OFDM-символ (с CP)
    segment = lte_signal_time_domain(sample_n_max : ...
                                     sample_n_max + window - 1);
    
    % полезная часть OFDM-символа (без CP)
    segment_pl = segment(cp+1:end);
    assignin("base", "PSS_RX_FOR_CONJ_EST_TD", segment_pl); 
    assert(numel(segment_pl) == Nfft); % на всякий..

    % FFT по Nfft
    Y = fft(segment_pl, Nfft);
    
    % Длина спектра
    Nfft = length(Y);
    
    % Индексы 62 поднесущих PSS (без DC):
    % DC = 1, положительные частоты: 2..(Nfft/2+1), отрицательные: (Nfft/2+2)..Nfft
    idx_pos62 = 2:(1+31);                        % +1..+31
    idx_neg62 = Nfft-31+1 : Nfft;                % -31..-1
    Xp = [Y(idx_neg62); Y(idx_pos62)];           % 62x1

    % Определённый ранее NID2 для PSS
    pss_nid2 = pss_phy_root_id;         % 0,1 или 2

    pss_ref = lte_pss_variants{pss_nid2 + 1}(:);   % 62x1
     
    assignin("base", "PSS_REF_FOR_CONJ_EST_FD", pss_ref);
    assignin("base", "PSS_RX_FOR_CONJ_EST_FD", Xp); 

    % Оценка частотного отклика канала на PSS-поднесущих
    H_pss = Xp ./ (pss_ref + eps);
    
    % В момент пика корреляции мы 
    % Оценка канала с помощью умножения на сопряжённое
    H_pss_conj = Xp .* conj(pss_ref);
    
    % Вектор "номеров" поднесущих: -31..-1, +1..+31
    subcarriers = [-31:-1 1:31].';

    figure('Name','Test');
    plot(subcarriers, imag(H_pss_conj), '-o','LineWidth',1.5);
    hold on; plot(subcarriers, real(H_pss_conj), '+','LineWidth',1.5); hold off;
    grid on;
    xlabel('Номер поднесущей (относительный)');
    ylabel('|H(f)|, dB');
    title('АЧХ по PSS');
    
    H_amp = 20*log10(abs(H_pss));    % АЧХ в dB
    H_phase = angle(H_pss);          % ФЧХ в рад
    
    figure('Name','Channel estimate from PSS');
    
    subplot(2,1,1);
    plot(subcarriers, H_amp, '-o','LineWidth',1.5);
    grid on;
    xlabel('Номер поднесущей (относительный)');
    ylabel('|H(f)|, dB');
    title('АЧХ по PSS');
    
    subplot(2,1,2);
    plot(subcarriers, H_phase, '-o'); grid on;
    grid on;
    xlabel('Номер поднесущей (относительный)');
    ylabel('\angleH(f), рад');
    title('ФЧХ по PSS');

    Xp_comp = Xp ./ (H_pss + eps);

    % через conj
    Xp_comp2 = Xp .* conj(H_pss_conj) ./ (abs(H_pss_conj).^2 + eps);

    Hp_test = Xp_comp ./ (pss_ref + eps);
    % через conj
    pss_ref = pss_ref .* 10;
    Hp_test2 = Xp_comp .* (conj(pss_ref) + eps);

    H_amp = 20*log10(abs(Hp_test));    % АЧХ в dB
    H_phase = angle(Hp_test);          % ФЧХ в рад
    
    figure('Name','Channel estimate from PSS');
    
    subplot(2,1,1);
    plot(subcarriers, H_amp, '-o','LineWidth',1.5);
    grid on;
    xlabel('Номер поднесущей (относительный)');
    ylabel('|H(f)|, dB');
    title('АЧХ по PSS');
    
    subplot(2,1,2);
    plot(subcarriers, H_phase, '-o'); grid on;
    grid on;
    xlabel('Номер поднесущей (относительный)');
    ylabel('\angleH(f), рад');
    title('ФЧХ по PSS');

    score = phy.fn.complex_corr_norm_sqabs(pss_ref.', Xp)
    score = phy.fn.complex_corr_norm_sqabs(pss_ref.', Xp_comp)
    score = phy.fn.complex_corr_norm_sqabs(pss_ref.', Xp_comp2)

    %%% 
    
    if (exist("lte_channel_truth_hH", "var"))
        ref        = evalin('base','lte_channel_truth_hH');
        Fs         = ref.Fs;
        pathGains  = ref.pathGains;              
        pathDelays = ref.pathDelays(:);          % секунды
    
        n_sym_start = sample_n_max + cp;
        n_sym_end   = n_sym_start + Nfft - 1;
        
        g_eff = squeeze(mean(pathGains(n_sym_start:n_sym_end,:), 1)).';
    
        deltaF_Hz = 15e3;
        f_sub     = subcarriers * deltaF_Hz;      % 62x1
        
        H_true_pss = zeros(length(subcarriers),1,'like',g_eff);
        for i = 1:length(subcarriers)
            fm = f_sub(i);
            phase_vec = exp(-1j*2*pi*fm*pathDelays);   % Lx1
            H_true_pss(i) = sum(g_eff(:) .* phase_vec(:));
        end
    
        H_est_amp_db  = 20*log10(abs(H_pss));
        H_true_amp_db = 20*log10(abs(H_true_pss));
        
        H_est_phase   = angle(H_pss);
        H_true_phase  = angle(H_true_pss);
        
        figure('Name','Channel estimate vs TRUE (PSS, pathGains ref)');
        subplot(2,1,1);
        plot(subcarriers, unwrap(H_est_amp_db), '-o','LineWidth',1.5); hold on;
        plot(subcarriers, unwrap(H_true_amp_db), 'r-x','LineWidth',1.2);
        grid on;
        xlabel('Номер поднесущей (относительный)');
        ylabel('abs(H(f)), dB');
        legend('Оценка по PSS','Истинный канал','Location','best');
        title('АЧХ: оценка vs Rayleigh truth');
        
        subplot(2,1,2);
        plot(subcarriers, unwrap(H_est_phase), '-o','LineWidth',1.5); hold on;
        plot(subcarriers, unwrap(H_true_phase), 'r-x','LineWidth',1.2);
        grid on;
        xlabel('Номер поднесущей (относительный)');
        ylabel('\angleH(f), рад');
        legend('Оценка по PSS','Истинный канал','Location','best');
        title('ФЧХ: оценка vs Rayleigh truth');
    end 
    
    Xp_norm      = Xp      ./ max(abs(Xp));
    Xp_comp_norm = Xp_comp ./ max(abs(Xp_comp));
    
    figure('Name','PSS IQ before/after equalization');
    
    subplot(1,2,1);
    plot(real(Xp_norm), imag(Xp_norm), 'bo','MarkerSize',5,'LineWidth',1.0); hold on;
    plot(real(pss_ref), imag(pss_ref), 'r+','MarkerSize',6,'LineWidth',1.0);
    grid on; axis equal;
    xlabel('I'); ylabel('Q');
    title('PSS do eq (Xp)');
    legend('rx PSS','ref PSS','Location','best');
    
    subplot(1,2,2);
    plot(real(Xp_comp_norm), imag(Xp_comp_norm), 'go','MarkerSize',5,'LineWidth',1.0); hold on;
    plot(real(pss_ref),      imag(pss_ref),      'r+','MarkerSize',6,'LineWidth',1.0);
    grid on; axis equal;
    xlabel('I'); ylabel('Q');
    title('PSS after eq (Xp\_comp)');
    legend('rx eq PSS','ref PSS','Location','best');
    
    % % dopler_est
    % Fs = prb_lte_params_selected.sample_rate;
    % 
    % Nfft = prb_lte_params_selected.fft_size;
    % cp   = lte_etc_ofdm_symbol_len;
    % Lsym = Nfft + cp;
    % 
    % % 1) PSS-символ
    % seg_rx_sym = lte_signal_time_domain(sample_n_max : sample_n_max + Lsym - 1);
    % seg_rx     = seg_rx_sym(cp+1:end);
    % 
    % % 2) Опорный PSS во времени
    % H_ref      = zeros(Nfft,1);
    % idx_pos62  = 2:(1+31);
    % idx_neg62  = Nfft-31+1:Nfft;
    % H_ref(idx_neg62) = pss_ref(1:31);
    % H_ref(idx_pos62) = pss_ref(32:62);
    % 
    % s_td = ifft(H_ref, Nfft);                   % Nfft×1
    % 
    % % ФАЗОР!!
    % z   = (seg_rx(:) .* conj(s_td(:)));
    % length(angle(H_pss)) 
    % length(angle())
    % phi = unwrap(angle(z) ./ (angle(H_pss) + eps));                     % фаза длиной Nfft
    % 
    % % 4) Оценка наклона по 4 сегментам
    % Ns   = Nfft;
    % Q    = 4;                                   % число сегментов
    % segL = floor(Ns / Q);                       % длина сегмента (в сэмплах)
    % 
    % slopes = zeros(Q,1);
    % 
    % for q = 1:Q
    %     n_start = (q-1)*segL;                   % индекс в терминах n
    %     n_end   = q*segL - 1;
    %     if q == Q
    %         n_end = Ns-1;                       % последний сегмент до конца
    %     end
    % 
    %     i0 = n_start + 1;
    %     i1 = n_end   + 1;
    % 
    %     dphi = phi(i1) - phi(i0);
    %     dn   = n_end - n_start;
    % 
    %     slopes(q) = dphi / dn;                  % локальный dphi/dn
    % end
    % 
    % a_approx   = mean(slopes);                  % усреднённый наклон
    % cfo_est_hz = a_approx * Fs / (2*pi);        % CFO
    % 
    % fprintf('CFO_TRUE=%.2f Hz, CFO_est(PSS-TD, 4-seg)=%.2f Hz\n', ...
    %     evalin("base", "SET_CHANNEL_DOPLER_OFFSET_HZ"), cfo_est_hz);
    % 
    % assignin('base','CFO_EST_PSS_TD', cfo_est_hz);

    Fs   = prb_lte_params_selected.sample_rate;
    Nfft = prb_lte_params_selected.fft_size;
    cp   = lte_etc_ofdm_symbol_len;
    Lsym = Nfft + cp;
    
    % 1) Вырезаем PSS-символ с CP
    seg_rx_sym = lte_signal_time_domain(sample_n_max : sample_n_max + Lsym - 1);
    seg_rx     = seg_rx_sym(cp+1:end);          % Nfft×1
    
    % 2) Опорный PSS во времени (только полезная часть)
    H_ref      = zeros(Nfft,1);
    idx_pos62  = 2:(1+31);
    idx_neg62  = Nfft-31+1:Nfft;
    H_ref(idx_neg62) = pss_ref(1:31);
    H_ref(idx_pos62) = pss_ref(32:62);
    
    s_td = ifft(H_ref, Nfft);
    
    % 3) Убираем известный сигнал: z[n] ≈ h_eff[n] * exp(j*phi_CFO[n])
    z = seg_rx(:) .* conj(s_td(:));             % TD-фазор
    
    mag_z  = abs(z)
    phi_z  = unwrap(angle(z))
    
    figure('Name','z[n] magnitude and phase');
    subplot(2,1,1);
    plot(mag_z);
    xlabel('n'); ylabel('|z[n]|');
    title('|z[n]| (амплитуда эфф. канала)'); grid on;
    
    subplot(2,1,2);
    plot(phi_z);
    xlabel('n'); ylabel('\phi_z[n], rad');
    title('Фаза z[n] (CFO + фазовый канал)'); grid on;
    
    % 1. Оценка SNR по PSS
    % Сглаживаем H_pss (простое скользящее среднее по 4 соседним поднесущим), 
    % чтобы отделить медленный канал от быстрого шума
    H_smooth = smoothdata(H_pss, 'gaussian', 4); 
    
    % Сигнал (оценка)
    Signal_est = H_smooth .* pss_ref;
    
    % Шум (остаток)
    Noise_est  = Xp - Signal_est;
    
    P_signal = mean(abs(Signal_est).^2);
    P_noise  = mean(abs(Noise_est).^2);
    
    snr_pss_db = 10*log10(P_signal / (P_noise + eps));
    fprintf('SNR_est (PSS) = %.2f dB\n', snr_pss_db);
    
    
    % 2. Полоса когерентности (Bc) через RMS delay spread
    % Получаем PDP (Power Delay Profile) через IFFT от АЧХ канала
    % Берём Nfft (или 64/128) точек для IFFT
    h_impulse = ifft(H_pss, 64);       % 64 точки достаточно для грубой оценки
    pdp       = abs(h_impulse).^2;     % профиль мощности
    
    % Временная ось задержек (0..63) * Ts
    % Но у нас PSS прорежен (каждая поднесущая), IFFT даст алиасинг, 
    % но для грубой оценки tau_rms сойдёт.
    % Шаг по времени при IFFT-64 на полосе 62 поднесущих (≈1МГц) -> 1мкс
    % Точнее: шаг tau = 1 / (Bandwidth). Bandwidth PSS ≈ 62 * 15kHz ≈ 930 kHz.
    % dt ≈ 1 / 930e3 ≈ 1.075 мкс.
    
    dt_us = 1 / (62 * 15e3) * 1e6;     % шаг в мкс
    tau_axis = (0:63).' * dt_us;
    
    % Считаем RMS delay spread
    p_sum     = sum(pdp);
    tau_avg   = sum(pdp .* tau_axis) / p_sum;
    tau2_avg  = sum(pdp .* (tau_axis.^2)) / p_sum;
    tau_rms_us = sqrt(tau2_avg - tau_avg^2);
    
    % Полоса когерентности (для корр 0.5)
    Bc_kHz = 1 / (5 * tau_rms_us * 1e-6) / 1e3;
    
    fprintf('RMS Delay Spread = %.2f us\n', tau_rms_us);
    fprintf('Coherence Bandwidth (Bc) ~ %.2f kHz\n', Bc_kHz);
    
    assignin('base', 'SNR_PSS_DB', snr_pss_db);
    assignin('base', 'TAU_RMS_US', tau_rms_us);
    assignin('base', 'BC_KHZ', Bc_kHz);

% z[n] ~ h_eff[n] (если CFO небольшой / компенсирован)
z = seg_rx(:) .* conj(s_td(:));      % как ты делал

Nsym = length(z);
maxLag = 32;                         % максимум лагов в сэмплах внутри символа

R_h = zeros(maxLag+1,1);
for tau = 0:maxLag
    R_h(tau+1) = mean( z(1:Nsym-tau) .* conj(z(1+tau:Nsym)) );
end

% Нормированная автокорреляция |R_h[tau]| / R_h[0]
R_h_norm = abs(R_h) / (abs(R_h(1)) + eps);

n_axis = (0:maxLag).';              % лаг в сэмплах
t_axis = n_axis / Fs * 1e6;         % лаг в мкс

figure('Name','Time autocorrelation of effective channel (within PSS symbol)');
subplot(2,1,1);
plot(n_axis, R_h_norm, '-o','LineWidth',1.5);
grid on;
xlabel('\tau, samples');
ylabel('|R_h(\tau)| / |R_h(0)|');
title('Нормированная временная автокорреляция h_{eff}[n] внутри PSS');

subplot(2,1,2);
plot(t_axis, R_h_norm, '-o','LineWidth',1.5);
grid on;
xlabel('\tau, \mus');
ylabel('|R_h(\tau)| / |R_h(0)|');
title('Нормированная автокорреляция vs время задержки');


    %%% оценка и т.д.
    % собираем всё имеющееся в кучу
    % 
    % correlation_metrics - нормированная величина корреляции с CP
    % pss_best_corr - корреляция с истинным PSS базовой станции
    % pss_rh_best_peaks_idxs - индексы пиков корреляции из pss_best_corr > threshold (0.8)
    


    % Fs = prb_lte_params_selected.sample_rate;
    % Ts = 1/Fs;
    % 
    % % Ожидаемая длина слота 0.5 ms в семплах (для контроля)
    % Tslot_ms = 0.5;
    % slot_samp_ideal = round(Tslot_ms*1e-3 / Ts);
    % fprintf('Ожидаемая длина слота (0.5 ms): %d семплов\n', slot_samp_ideal);
    % 
    % % Метрики PSS из цикла
    % pss_metric = pss_best_score(:);   % N×1
    % pss_id     = pss_best_id(:);      % N×1, значения 0/1/2 или -1
    % 
    % % Берём только тот NID2, который реально детектирован
    % nid2_det = pss_phy_root_id;       % 0,1,2
    % metric_nid = pss_metric;
    % metric_nid(pss_id ~= nid2_det) = 0;   % обнуляем все чужие корни
    % 
    % th_pss = 0.5;                    
    % min_dist = round(0.3*slot_samp_ideal); % чтобы не ловить 10 соседних отсчётов одного и того же пика
    % 
    % [~, pss_locs] = findpeaks(metric_nid, ...
    %     'MinPeakHeight', th_pss, ...
    %     'MinPeakDistance', min_dist);
    % 
    % fprintf('Cnt PSS = %d (NID2=%d, score>=%.2f)\n', ...
    %     numel(pss_locs), nid2_det, th_pss);
    % 
    % 
    % % jitter_samp; 
    % 
    % if numel(pss_locs) >= 2
    %     dPSS_samp = diff(pss_locs);           % расстояние между соседними PSS, семплы
    %     jitter_samp = dPSS_samp - slot_samp_ideal;
    % 
    %     fprintf('RMS-jitter-pss: %.3f sampls\n', ...
    %         sqrt(mean(jitter_samp.^2)));
    % 
    %     % График расстояний и дрожания
    %     figure('Name','PSS-to-PSS spacing');
    %     plot(1:length(dPSS_samp), dPSS_samp);
    %     grid on;
    %     xlabel('dist in samples');
    %     ylabel('\Delta n, samples');
    %     title('Jit plot')
    % end
    % 
    % if ~isempty(pss_locs)
    %     sample_n_pss0 = pss_locs(1);
    %     fprintf('first pss idx %d (%.4f ms)\n', ...
    %         sample_n_pss0, sample_n_pss0*Ts*1e3);
    % end
    % 
    % % здесь теперь есть массив jitter_samp (который хранит в себе смещение
    % % в семплах)
    % 
    % dist(sample_n_pss0, pss_locs(2))
    % 
    Fs = prb_lte_params_selected.sample_rate;
    Ts = 1/Fs;

    % 1) Вырезаем тот же PSS-символ из приёмного сигнала (как и для FFT)
    Nfft = prb_lte_params_selected.fft_size;
    cp   = lte_etc_ofdm_symbol_len;
    Lsym = Nfft + cp;

    seg_rx = lte_signal_time_domain(sample_n_max : sample_n_max + Lsym - 1);  % (Lsym×1)

    % 2) Строим опорный временной PSS-символ (IFFT от pss_ref)
    % Заполняем частотную сетку Nfft, как при передаче
    H_ref = zeros(Nfft,1);
    idx_pos62 = 2:(1+31);
    idx_neg62 = Nfft-31+1:Nfft;
    H_ref(idx_neg62) = pss_ref(1:31);
    H_ref(idx_pos62) = pss_ref(32:62);

    s_td = ifft(H_ref, Nfft);          % полезная часть PSS в TD
    s_td_cp = [s_td(end-cp+1:end); s_td];   % добавляем CP, Lsym×1

    % 3) Убираем известный сигнал, остаётся чистая экспонента CFO
    z = seg_rx(:) .* conj(s_td_cp(:));      % z[n] ≈ exp(j*2*pi*CFO*n/Fs)

    % 4) Фаза и её линейная аппроксимация
    n_loc = (0:Lsym-1).';                   % локальный индекс внутри символа
    phi = unwrap(angle(z));

    p = polyfit(double(n_loc), double(phi), 1);   % phi ≈ a*n + b
    a = p(1);

    % 5) CFO-оценка: a ≈ 2*pi*CFO/Fs
    cfo_est_hz = a * Fs / (2*pi);

    fprintf('CFO_TRUE=%.2f Hz, CFO_est(PSS-TD)=%.2f Hz\n', ...
        evalin("base", "SET_CHANNEL_DOPLER_OFFSET_HZ"), cfo_est_hz);

     

    % часть 2. Компенсация CFO
    % ОЧЕНЬ ГРУБО И НЕ АКТУАЛЬНО!! 
    % ЭТО ПРОСТО КОСТЫЛЬ НА ДАЛЬНЕЙШУЮ МОДЕЛЬ

    %

    % длина полного OFDM-символа (CP + полезная часть)
    Nfft = prb_lte_params_selected.fft_size;
    cp   = lte_etc_ofdm_symbol_len;
    Lsym = Nfft + cp;

    sample_n_max = pss_rh_best_peaks_idxs(2);

    % начало SSS-символа: он идёт ровно перед PSS
    sss_start = sample_n_max - Lsym;
    assert(sss_start > 0, 'SSS start index < 1, err idx');

    % вырезаем SSS-символ (с CP)
    segment_sss = lte_signal_time_domain(sss_start : sss_start + Lsym - 1);

    % полезная часть SSS (без CP)
    segment_sss_pl = segment_sss(cp+1:end);
    assert(numel(segment_sss_pl) == Nfft);

    % FFT
    Y_sss = fft(segment_sss_pl, Nfft);

    % центральные 62 поднесущие (аналогично PSS)
    idx_pos62 = 2:(1+31);             % +1..+31
    idx_neg62 = Nfft-31+1:Nfft;       % -31..-1
    Xsss = [Y_sss(idx_neg62); Y_sss(idx_pos62)];   % 62x1

    Xsss_eq = Xsss .* conj(H_pss_conj) / (abs(H_pss_conj).^2 + eps);

    % SSS - это bpsk
    figure('Name','SSS constellation (central 62 subcarriers) not equalized');
    plot(real(Xsss_eq), imag(Xsss_eq), 'r+','MarkerSize',5,'LineWidth',1.0);
    hold on;
    plot(real(Xsss), imag(Xsss), "w*", "MarkerSize", 5, "LineWidth", 1.0);
    hold off;
    grid on; axis equal;
    xlabel('I'); ylabel('Q');
    xlim([min(real(Xsss)) - 1000 ; max(real(Xsss)) + 1000]);
    ylim([min(imag(Xsss)) - 1000 ; max(imag(Xsss)) + 1000])
    title('SSS constellation');

    sss_table = lte_sss_variants{pss_phy_root_id};

    scores = zeros(numel(sss_table), 1, "single");

    for i=1:numel(sss_table) 
        scores(i) = phy.fn.complex_corr_norm_sqabs(sss_table{i}.', real(Xsss_eq));
    end 

    sss_idx = find(scores > 0.9); 

    fprintf("PCI: %s", string(pss_sss.get_pci(sss_idx - 1, pss_phy_root_id)));
end 