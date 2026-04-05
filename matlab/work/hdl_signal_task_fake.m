%% 1) Загрузка PSS в частоте и перевод в TD (128)
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
        vals(end+1,1) = v;
    end
end
fclose(fid);

assert(mod(numel(vals),2)==0, 'Odd number of samples (I/Q interleaving broken).');

I = double(vals(1:2:end));
Q = double(vals(2:2:end));
rx = complex(I, Q);

N = length(rx);
fprintf('IQ pairs: %d\n', N);

% Это filter(h,1,rx) где h = conj(flipud(pss))

m = cell(3,1);
y = cell(3,1);
pk = zeros(3,1);
peak_idx1 = zeros(3,1); % 1-based индекс пика в y
start1 = zeros(3,1);    % 1-based старт окна
start0 = zeros(3,1);    % 0-based старт окна
stop1  = zeros(3,1);    % 1-based стоп окна
stop0  = zeros(3,1);    % 0-based стоп окна

for p=1:3
    h = conj(flipud(pss_td{p}));
    y{p} = filter(h, 1, rx);              % длина N
    m{p} = abs(real(y{p})) + abs(imag(y{p}));

    % валидная область: начиная с n=M (1-based) => первые M-1 точек неполные
    valid = M:N;

    [pk(p), ii] = max(m{p}(valid));
    peak_idx1(p) = valid(ii);            % 1-based индекс пика (конец окна)

    start1(p) = peak_idx1(p) - (M-1);    % 1-based старт окна
    stop1(p)  = start1(p) + (M-1);

    start0(p) = start1(p) - 1;           % 0-based старт
    stop0(p)  = stop1(p) - 1;
end

fprintf('\n=== RESULTS (matched filter like RTL) ===\n');
for p=1:3
    fprintf('PSS%d: peak_idx1=%d | start1=%d stop1=%d | start0=%d stop0=%d | metric=%.6g\n', ...
        p-1, peak_idx1(p), start1(p), stop1(p), start0(p), stop0(p), pk(p));
end

[~, win] = max(pk);
fprintf('WIN: PSS%d (start0=%d)\n', win-1, start0(win));

n = (1:N).';
start_axis = n - (M-1);

figure;
for p=1:3
    subplot(3,1,p);
    x = start_axis(M:N);
    yy = m{p}(M:N);

    plot(x, yy);
    grid on;
    hold on;
    xline(start1(p), '--');

    % --- для PSS1: выделяем точки по заданной сетке ---
    if p == 2
        first_peak = 2194;     % первый индекс по графику
        peak_step  = 9600;     % расстояние между соседними пиками
        every_n    = 1;       % выделяем каждый 16-й

        mark_step = peak_step * every_n;   % 9600 * 16

        mark_x = first_peak:mark_step:x(end);
        mark_x = mark_x(mark_x >= x(1) & mark_x <= x(end));

        % переводим значения x в индексы массива yy
        mark_idx = mark_x - x(1) + 1;

        plot(mark_x, yy(mark_idx), 'o', ...
             'MarkerSize', 4, ...
             'LineWidth', 1);
    end

    title(sprintf('PSS%d: metric vs start (1-based)', p-1));
    xlabel('start sample (1-based)');
    ylabel('|Re|+|Im|');
end