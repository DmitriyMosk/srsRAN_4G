% convert_mat_to_hackrf_iq
% Convert LTE 15 PRB waveform from MAT-file into raw interleaved int8 IQ
% samples suitable for hackrf_transfer.
%
% Notes:
%   - This script assumes the MAT-file contains variable `srs_signal_complex`.
%   - For 15 PRB in this project, Fs = 3.84e6 and LTE occupied bandwidth is
%     about 2.7 MHz (12 * 15 * 15 kHz).
%   - HackRF expects raw interleaved signed int8 IQ samples:
%       I0, Q0, I1, Q1, ...
%   - When using a baseband filter in HackRF, choose the nearest supported
%     bandwidth that is not narrower than the LTE occupied bandwidth.

clear;
clc;

script_dir = fileparts(mfilename("fullpath"));
input_mat_path = fullfile(script_dir, "converted", "srsENB_signal_time_domain_15_prb.dat.mat");
output_iq_path = fullfile(script_dir, "converted", "srsENB_signal_time_domain_15_prb_hackrf.iq");
sample_rate = 3.84e6;
n_prb = 15;
peak_headroom = 0.85;
lte_band = 7;
earfcn_dl = 2850;
band7_f_dl_low_mhz = 2620.0;
band7_n_offs_dl = 2750;
center_frequency_hz = round((band7_f_dl_low_mhz + 0.1 * (earfcn_dl - band7_n_offs_dl)) * 1e6);

expected_bandwidth_hz = 12 * n_prb * 15e3;
expected_fft_size = 256;

fprintf("convert_mat_to_hackrf_iq:\n");
fprintf("\tinput_mat_path: %s\n", input_mat_path);
fprintf("\toutput_iq_path: %s\n", output_iq_path);
fprintf("\tsample_rate: %.0f Hz\n", sample_rate);
fprintf("\tn_prb: %d\n", n_prb);
fprintf("\tpeak_headroom: %.2f\n", peak_headroom);
fprintf("\tlte_band: %d\n", lte_band);
fprintf("\tearfcn_dl: %d\n", earfcn_dl);
fprintf("\tcenter_frequency: %.1f MHz\n", center_frequency_hz / 1e6);
fprintf("\texpected_fft_size: %d\n", expected_fft_size);
fprintf("\texpected_lte_bandwidth: %.1f kHz\n", expected_bandwidth_hz / 1e3);

if ~isfile(input_mat_path)
    error("Input MAT-file not found: %s", input_mat_path);
end

file_info = whos("-file", input_mat_path);
variable_names = string({file_info.name});

if ~any(variable_names == "srs_signal_complex")
    error("Variable 'srs_signal_complex' not found in MAT-file: %s", input_mat_path);
end

m = matfile(input_mat_path, "Writable", false);
x = m.srs_signal_complex;
x = x(:);

if isempty(x)
    error("Input signal is empty: %s", input_mat_path);
end

if ~isnumeric(x)
    error("Input signal must be numeric. Actual class: %s", class(x));
end

input_class = class(x);

if any(~isfinite(real(x))) || any(~isfinite(imag(x)))
    error("Input signal contains NaN or Inf values.");
end

x = double(x);
peak = max(abs(x));

if peak <= 0
    error("Input signal peak is zero. Cannot normalize.");
end

if peak_headroom <= 0 || peak_headroom > 1
    error("peak_headroom must be in the range (0, 1]. Actual value: %.3f", peak_headroom);
end

scale = (127 * peak_headroom) / peak;
x_scaled = x * scale;

i_int = round(real(x_scaled));
q_int = round(imag(x_scaled));

clip_count_i = nnz(i_int < -128 | i_int > 127);
clip_count_q = nnz(q_int < -128 | q_int > 127);

i_int = min(max(i_int, -128), 127);
q_int = min(max(q_int, -128), 127);

i_int8 = int8(i_int);
q_int8 = int8(q_int);

iq_interleaved = zeros(2 * numel(x), 1, "int8");
iq_interleaved(1:2:end) = i_int8;
iq_interleaved(2:2:end) = q_int8;

fid = fopen(output_iq_path, "wb");
if fid == -1
    error("Failed to open output file for writing: %s", output_iq_path);
end

cleanup_obj = onCleanup(@() fclose(fid));
written_count = fwrite(fid, iq_interleaved, "int8");

if written_count ~= numel(iq_interleaved)
    error("Short write: expected %d int8 values, wrote %d.", numel(iq_interleaved), written_count);
end

clear cleanup_obj;

signal_duration_sec = numel(x) / sample_rate;
output_info = dir(output_iq_path);
expected_size_bytes = 2 * numel(x);

fprintf("\t--\n");
fprintf("\tIQ pairs: %d\n", numel(x));
fprintf("\tduration: %.6f sec\n", signal_duration_sec);
fprintf("\tinput_class: %s\n", input_class);
fprintf("\tpeak_before_scaling: %.12g\n", peak);
fprintf("\tscale: %.12g\n", scale);
fprintf("\tclip_count_i: %d\n", clip_count_i);
fprintf("\tclip_count_q: %d\n", clip_count_q);
fprintf("\toutput_size_bytes: %d\n", output_info.bytes);
fprintf("\texpected_size_bytes: %d\n", expected_size_bytes);
fprintf("\toutput_file: %s\n", output_iq_path);

if output_info.bytes ~= expected_size_bytes
    error("Output file size mismatch: expected %d bytes, got %d bytes.", ...
        expected_size_bytes, output_info.bytes);
end

fid_verify = fopen(output_iq_path, "rb");
if fid_verify == -1
    error("Failed to reopen output file for verification: %s", output_iq_path);
end

cleanup_verify = onCleanup(@() fclose(fid_verify));
raw_verify = fread(fid_verify, inf, "int8=>int8");

if mod(numel(raw_verify), 2) ~= 0
    error("Verification failed: output IQ file contains odd number of int8 values.");
end

i_verify = double(raw_verify(1:2:end));
q_verify = double(raw_verify(2:2:end));
x_verify = complex(i_verify, q_verify);

verify_peak = max(abs(x_verify));
verify_mean_abs = mean(abs(x_verify));

clear cleanup_verify;

fprintf("\tverify_peak_int8_domain: %.12g\n", verify_peak);
fprintf("\tverify_mean_abs_int8_domain: %.12g\n", verify_mean_abs);

hackrf_cmd = sprintf( ...
    'hackrf_transfer -t "%s" -f %.0f -s %.0f -x <txvga> -a 1 -R', ...
    char(output_iq_path), center_frequency_hz, sample_rate);

fprintf("\t--\n");
fprintf("\tExample hackrf_transfer command:\n");
fprintf("\t%s\n", hackrf_cmd);
fprintf("\tHint: for LTE %d PRB at Fs = %.2f MHz, occupied bandwidth is about %.2f MHz.\n", ...
    n_prb, sample_rate / 1e6, expected_bandwidth_hz / 1e6);
fprintf("\tHint: selected LTE Band %d example uses EARFCN DL %d (%.1f MHz).\n", ...
    lte_band, earfcn_dl, center_frequency_hz / 1e6);
fprintf("\tHint: option -R enables endless repeat of the IQ file until you stop hackrf_transfer.\n");
fprintf("\tHint: choose HackRF baseband filter bandwidth not narrower than the LTE signal.\n");
