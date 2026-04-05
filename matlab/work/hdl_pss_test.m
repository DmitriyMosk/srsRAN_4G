% PSS_REF_FOR_CONJ_EST_FD
% PSS_RX_FOR_CONJ_EST_FD
% PSS_RX_FOR_CONJ_EST_TD

H_ref_div = PSS_RX_FOR_CONJ_EST_FD ./ (PSS_REF_FOR_CONJ_EST_FD + eps);

H_fd_raw = PSS_RX_FOR_CONJ_EST_FD .* conj(PSS_REF_FOR_CONJ_EST_FD);  % 62x1

z_td_raw = PSS_RX_FOR_CONJ_EST_TD .* conj(ifft(PSS_REF_FOR_CONJ_EST_FD, 128));  % 128x1


H_ref_full = zeros(128,1);
idx_neg = 128-31+1:128; idx_pos = 2:32;
H_ref_full(idx_neg) = PSS_REF_FOR_CONJ_EST_FD(1:31);
H_ref_full(idx_pos) = PSS_REF_FOR_CONJ_EST_FD(32:62);
s_td_full = ifft(H_ref_full, 128);
z_td_full = PSS_RX_FOR_CONJ_EST_TD .* conj(s_td_full);
H_td_ifft = fft(z_td_full, 128);
H_td_pss = [H_td_ifft(idx_neg); H_td_ifft(idx_pos)];   

subcarriers = [-31:-1 1:31].';

figure('Name','Оценка канала: ДЕЛЕНИЕ vs CONJ (сырые)', 'Position', [100 100 1400 900]);

subplot(2,4,1);
plot(subcarriers, 20*log10(abs(H_ref_div)+eps), 'k-o', 'LineWidth', 2.5); hold on;
plot(subcarriers, 20*log10(abs(H_fd_raw)+eps), 'b-s', 'LineWidth', 2);
plot(subcarriers, 20*log10(abs(H_td_pss)+eps), 'r-^', 'LineWidth', 2);
grid on; legend('H=Y/X (деление)', 'H=Y·X* (FD)', 'H=TD→FD', 'Location','best');
title('АЧХ |H[k]|'); xlabel('k'); ylabel('dB');

subplot(2,4,2);
plot(subcarriers, unwrap(angle(H_ref_div)), 'k-o', 'LineWidth', 2.5); hold on;
plot(subcarriers, unwrap(angle(H_fd_raw)), 'b-s', 'LineWidth', 2);
plot(subcarriers, unwrap(angle(H_td_pss)), 'r-^', 'LineWidth', 2);
grid on; legend('H=Y/X', 'H=Y·X*', 'H=TD→FD');
title('ФЧХ ∠H[k]'); xlabel('k'); ylabel('rad');

subplot(2,4,3);
plot(0:127, 20*log10(abs(z_td_raw)+eps), 'g-', 'LineWidth', 2); grid on;
title('TD: |z[n]|'); xlabel('n'); ylabel('dB'); xline(0,'r--');

pss_scale = mean(abs(PSS_REF_FOR_CONJ_EST_FD));
scale_fd = mean(abs(H_fd_raw)) / mean(abs(H_ref_div));
scale_td = mean(abs(H_td_pss)) / mean(abs(H_ref_div));

err_fd_amp = max(abs(abs(H_fd_raw) - abs(H_ref_div)*pss_scale));
err_td_amp = max(abs(abs(H_td_pss) - abs(H_ref_div)*pss_scale));
err_fd_ph = max(abs(angle(H_fd_raw) - angle(H_ref_div)));
err_td_ph = max(abs(angle(H_td_pss) - angle(H_ref_div)));

fprintf('\n=== ОШИБКИ АМПЛИТУДЫ/ФАЗЫ (с учётом scale) ===\n');
fprintf('FD amp error = %.3g, phase error = %.3g rad\n', err_fd_amp, err_fd_ph);
fprintf('TD amp error = %.3g, phase error = %.3g rad\n', err_td_amp, err_td_ph);

subplot(2,4,[5 6]);
plot(real(z_td_raw), imag(z_td_raw), 'g.', 'MarkerSize', 8); grid on; axis equal;
title('z[n] = y[n]·s*[n]'); xlabel('Re'); ylabel('Im'); xline(0,'r'); yline(0,'r');

subplot(2,4,7);
histogram(abs(PSS_REF_FOR_CONJ_EST_FD), 20, 'FaceColor', 'c', 'FaceAlpha', 0.7);
title(sprintf('PSS_REF |X[k]| (scale=%.3f)', pss_scale)); xlabel('|X|'); ylabel('Count');

subplot(2,4,8);
plot(abs(PSS_REF_FOR_CONJ_EST_FD), 'co-', 'LineWidth', 2); grid on;
title('PSS_REF |X[k]| по тонам'); xlabel('k'); ylabel('|X[k]|');