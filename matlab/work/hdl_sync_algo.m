%% 1) Загрузка PSS в частоте и перевод в TD (M=128)
precalc.pss();

fft_size = 128;
center = fft_size/2 + 1;

pss_td = cell(3, 1);
for pss_id = 0:2
    pss_freq = lte_primary_syncronization_seq{pss_id + 1}; % 62x1
    pss_padded = zeros(fft_size, 1);

    pss_padded(center - 31 : center - 1) = pss_freq(1:31);
    pss_padded(center + 1 : center + 31) = pss_freq(32:62);

    pss_time = ifft(ifftshift(pss_padded)) * sqrt(fft_size);
    pss_td{pss_id+1} = pss_time(:);
end

M = length(pss_td{1});  % 128
fprintf('PSS length M=%d\n', M);

%% 2) Чтение сигнала input_signal.hex (I/Q чередуются строками)
filename = 'input_signal.hex';
fid = fopen(filename,'r');
assert(fid>0, 'Cannot open file: %s', filename);

vals = [];
while ~feof(fid)
    line = strtrim(fgetl(fid));
    if ~ischar(line) || isempty(line), continue; end
    tok = strsplit(line);
    if numel(tok) < 2, continue; end
    v = str2double(tok{2});
    if ~isnan(v)
        vals(end+1,1) = v; %#ok<AGROW>
    end
end
fclose(fid);

assert(mod(numel(vals),2)==0, 'Odd number of samples (I/Q interleaving broken).');

I = double(vals(1:2:end));
Q = double(vals(2:2:end));
rx = complex(I, Q);

N = length(rx);
fprintf('IQ pairs: %d\n', N);

%% Предполагаем, что у тебя уже есть:
% pss_td{1..3}, rx (complex), M, N
% Если нет — бери твой код загрузки PSS и чтения input_signal.hex.

BLOCK_LEN   = 1024;
STEP        = M;      % старт = phase + k*M
PHASE_STEP  = 1;      % phase += 1 на блок
PHASE_MOD   = M;

nBlocks = floor(N / BLOCK_LEN);

% ---------- FULL matched filter метрика (как reference) ----------
full_m   = cell(3,1);   % full metric по end-индексу n=1..N
full_pk  = zeros(3,1);
full_end0  = zeros(3,1); % 0-based end
full_start0 = zeros(3,1);

for p=1:3
    h = conj(flipud(pss_td{p}));
    y = filter(h,1,rx);
    m = abs(real(y)) + abs(imag(y));
    full_m{p} = m;

    valid = M:N; % 1-based end индексы
    [full_pk(p), ii] = max(m(valid));
    peak_end1 = valid(ii);          % 1-based end
    full_end0(p) = peak_end1 - 1;   % 0-based end
    full_start0(p) = full_end0(p) - (M-1);
end

% Для графика "metric vs start0":
% end1 = 1..N => start0 = (end1-1) - (M-1)
start0_axis = (0:N-1) - (M-1);      % длина N, соответствует full_m{p}(end1)
valid_mask = (start0_axis >= 0);    % валидные старты

% ---------- PHASED: считаем точки только на проверяемых стартах ----------
ph_start0 = cell(3,1);
ph_m      = cell(3,1);

% Чтобы не раздувать память, можно заранее прикинуть количество точек:
% примерно ~ nBlocks * ceil((BLOCK_LEN-M+1)/STEP) ~= 1600*8=12800
for p=1:3
    ph_start0{p} = zeros(nBlocks*16,1); % с запасом
    ph_m{p}      = zeros(nBlocks*16,1);
end
cnt = zeros(3,1);

for b = 0:(nBlocks-1)
    base0 = b * BLOCK_LEN;                 % 0-based начало блока
    phase = mod(b * PHASE_STEP, PHASE_MOD);

    starts_rel = phase : STEP : (BLOCK_LEN - M); % 0-based внутри блока

    for srel = starts_rel
        s0 = base0 + srel;                 % 0-based start в потоке
        seg = rx(s0+1 : s0+M);             % MATLAB 1-based

        for p=1:3
            c = sum(seg .* conj(pss_td{p}));
            metric = abs(real(c)) + abs(imag(c));

            cnt(p) = cnt(p) + 1;
            ph_start0{p}(cnt(p)) = s0;
            ph_m{p}(cnt(p))      = metric;
        end
    end
end

for p=1:3
    ph_start0{p} = ph_start0{p}(1:cnt(p));
    ph_m{p}      = ph_m{p}(1:cnt(p));
end

% maxima for phased
ph_pk = zeros(3,1);
ph_start0_best = zeros(3,1);
ph_end0_best   = zeros(3,1);
for p=1:3
    [ph_pk(p), ii] = max(ph_m{p});
    ph_start0_best(p) = ph_start0{p}(ii);
    ph_end0_best(p)   = ph_start0_best(p) + (M-1);
end

% ---------- ПЛОТЫ ----------
figure;
for p=1:3
    subplot(3,1,p);

    % FULL: линия
    plot(start0_axis(valid_mask), full_m{p}(valid_mask)); grid on; hold on;

    % PHASED: точки
    stem(ph_start0{p}, ph_m{p}, '.'); % точками/стемами по разреженной сетке

    % вертикали на пиках
    xline(full_start0(p), '--');    % ref start0
    xline(ph_start0_best(p), ':');  % phased best start0

    title(sprintf('PSS%d: FULL vs PHASED metric vs start0 (0-based)', p-1));
    xlabel('start0');
    ylabel('|Re|+|Im|');

    % Удобный зум вокруг ref-пика (можешь менять окно)
    xlim([full_start0(p)-4000, full_start0(p)+4000]);
end

fprintf('\n=== REF vs PHASED peaks ===\n');
for p=1:3
    fprintf('PSS%d: REF start0=%d end0=%d pk=%.6g | PH start0=%d end0=%d pk=%.6g\n', ...
        p-1, full_start0(p), full_end0(p), full_pk(p), ...
        ph_start0_best(p), ph_end0_best(p), ph_pk(p));
end

% ----------------- FULL axis (start0) -----------------
start0_axis = (0:N-1) - (M-1);   % для full_m(end1)
valid_mask  = (start0_axis >= 0);

% ----------------- FULL vs PHASED (FULL RANGE) -----------------
figure('Name','FULL RANGE: FULL vs PHASED metric vs start0','NumberTitle','off');

for p=1:3
    subplot(3,1,p);

    % FULL: линия (вся длина)
    plot(start0_axis(valid_mask), full_m{p}(valid_mask)); grid on; hold on;

    % PHASED: точки (разреженно)
    plot(ph_start0{p}, ph_m{p}, '.', 'MarkerSize', 6);

    % Пики
    xline(full_start0(p), '--', 'LineWidth', 1.0);
    xline(ph_start0_best(p), ':',  'LineWidth', 1.0);

    title(sprintf('PSS%d: FULL(line) + PHASED(points) over ALL start0', p-1));
    xlabel('start0 (0-based)');
    ylabel('|Re|+|Im|');

    % чтобы фулл график был читабельнее: ограничим по Y до ~1.2*ref_peak
    ylim([0, 1.2*full_pk(p)]);
end
