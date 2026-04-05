%% Curves for choosing K_LANES at different SYS_CLK
clear; clc;

% ---------------------------
% Fixed parameters (your case)
% ---------------------------
fs     = 1.92e6;     % Hz (effective rate after CIC/decimation)
Ns2p   = 9200;       % S2P activation period in fs-clock samples

B      = 9600;       % buffer length in samples (5 ms at 1.92 MHz)
W      = 128;        % PSS window length in samples
SR     = 1;          % pipeline/shift-reg latency (SYS cycles)

% Derived
P      = B - W + 1;      % number of scan positions (slide-by-1)
Twin   = SR + W;         % cycles per window (your model)

% Sweep K
Kmax   = 8;             % show only first K values for readability
Kvec   = 1:Kmax;

% Required cycles per buffer
G      = ceil(P ./ Kvec);
Treq   = G .* Twin;      % SYS cycles

% SYS clock candidates (MHz)
fsy_list = [50e6 75e6 100e6 150e6 200e6];

%% ---------------------------
% Plot 1: Efficiency (margin) eta(K) = Tavail / Treq
% ---------------------------
figure; hold on; grid on;

for i = 1:numel(fsy_list)
    Tavail = Ns2p * (fsy_list(i) / fs);      % available SYS cycles per S2P interval
    eta    = Tavail ./ Treq;                % margin
    plot(Kvec, eta, 'LineWidth', 1.6);
end

yline(1.0, '--', 'LineWidth', 1.2); % eta=1 boundary (real-time)  % :contentReference[oaicite:1]{index=1}
xlabel('K\_LANES');
ylabel('\eta(K) = T_{avail} / T_{req}');
title(sprintf('Real-time margin vs K (fs=%.2f MHz, Ns2p=%d, P=%d, Twin=%d)', fs/1e6, Ns2p, P, Twin));
legend(string(fsy_list/1e6) + " MHz", 'Location', 'northeastoutside');

xlim([1 Kmax]);                      % :contentReference[oaicite:2]{index=2}
xticks(1:2:Kmax);                    % fewer x labels            % :contentReference[oaicite:3]{index=3}

%% ---------------------------
% Plot 2: Required SYS_CLK frequency vs K
% f_sys_min(K) = Treq(K)*fs / Ns2p
% ---------------------------
f_sys_min = (Treq * fs) / Ns2p;      % Hz

figure; hold on; grid on;
plot(Kvec, f_sys_min/1e6, 'k', 'LineWidth', 2.0);

for i = 1:numel(fsy_list)
    yline(fsy_list(i)/1e6, '--', 'LineWidth', 1.0);
end

xlabel('K\_LANES');
ylabel('Required SYS\_CLK, MHz');
title('Minimal SYS\_CLK required for real-time vs K');
leg = ["f_{sys,min}(K)", string(fsy_list/1e6) + " MHz"];
legend(leg, 'Location', 'northeastoutside');

xlim([1 Kmax]);
xticks(1:2:Kmax);

%% ---------------------------
% Print Kmin for each SYS_CLK
% ---------------------------
fprintf('--- Kmin for each SYS_CLK (eta>=1) ---\n');
for i = 1:numel(fsy_list)
    Tavail = Ns2p * (fsy_list(i) / fs);
    eta    = Tavail ./ Treq;
    idx    = find(eta >= 1.0, 1, 'first');
    if isempty(idx)
        fprintf('SYS=%6.0f MHz: not achievable up to K=%d\n', fsy_list(i)/1e6, Kmax);
    else
        fprintf('SYS=%6.0f MHz: Kmin=%2d | eta=%.3f | Treq=%d cycles | Tavail=%.1f cycles\n', ...
            fsy_list(i)/1e6, Kvec(idx), eta(idx), Treq(idx), Tavail);
    end
end