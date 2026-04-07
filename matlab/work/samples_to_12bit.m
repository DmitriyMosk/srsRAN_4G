%% Configuration
precalc.pss(); % look up variable -> lte_primary_syncronization_seq

required_len    = 1640000; 
start_idx       = 14000; % с 0 до 8к идут нули, но я решил позабавиться

use_noise       = true;
use_pss         = false;
use_pss_nid     = 0;     % 0, 1, или 2
use_pss_freq    = false; % true = частотная область (62 элемента), false = временная (после IFFT)

matFile         = matfile(".\large\converted\srsENB_signal_time_domain_6_prb.dat.mat", "Writable", false);
used_samples    = matFile.srs_signal_complex; 

assert(~(use_pss && use_noise), "Too many options selected");

if (use_pss) 
    pss_freq = lte_primary_syncronization_seq{use_pss_nid + 1};

    fft_size = 256;  % 128, 256, 512, 1024, 2048
    pss_padded = zeros(fft_size, 1);
    
    center = fft_size / 2 + 1;

    pss_padded(center - 31 : center - 1) = pss_freq(1:31);   % нижние 31
    pss_padded(center + 1 : center + 31) = pss_freq(32:62);  % верхние 31
    % DC (индекс center) остаётся нулём
    
    fprintf('FFT size: %d, DC index: %d, PSS at [%d:%d, %d, %d:%d]\n', ...
        fft_size, center, center-31, center-1, center, center+1, center+31);
    
    if (use_pss_freq)
        % Частотная область
        complex_vec = pss_padded;
        fprintf('Using PSS in frequency domain, NID=%d\n', use_pss_nid);
    else
        % Временная область через IFFT
        pss_time = ifft(ifftshift(pss_padded)) * sqrt(fft_size);
        complex_vec = pss_time;
        fprintf('Using PSS in time domain, NID=%d, length=%d\n', use_pss_nid, fft_size);
    end
end

if (use_noise) 
    rng(42);
    
    if (required_len ~= 0)
        complex_vec = (randn(required_len, 1) + 1i*randn(required_len, 1)) / sqrt(2);
    else 
        complex_vec = (randn(1e5, 1) + 1i*randn(1e5, 1)) / sqrt(2);
    end
    fprintf('Using noise signal, length=%d\n', numel(complex_vec));
end

if (~use_pss && ~use_noise)
    % Используем семплы из файла
    if (required_len ~= 0)
        complex_vec = used_samples(start_idx:(start_idx + required_len - 1), 1);
    else 
        complex_vec = used_samples;
    end
    fprintf('Using file samples, start_idx=%d, length=%d\n', start_idx, numel(complex_vec));
end

flen = numel(complex_vec);

headroom = 2; % attenuate by 6 dB to avoid clipping
[I, Q, FS, clipI, clipQ] = complex_float_to_12bit(complex_vec, headroom);

fprintf('Quantization: FS=%.6f, clipI=%.2f%%, clipQ=%.2f%%\n', FS, clipI*100, clipQ*100);

if (clipI > 0.01 || clipQ > 0.01)
    warning('Clipping detected! Consider increasing headroom.');
end

forSigAnalyze = complex(double(I), double(Q));

addr_width = ceil(log2(flen));
fprintf('Address width: %d bits, depth=%d samples\n', addr_width, flen);

% output 

output_filename = sprintf('pss_nid%d_%s_12bit.hex', use_pss_nid, ...
    ternary(use_pss_freq, 'freq', 'time'));
write_signed16_iq_hexfile(output_filename, I, Q, 0, addr_width);
fprintf('Saved to: %s\n', output_filename);

output_filename_32 = sprintf('pss_nid%d_%s_32bit_packed.hex', ...
    use_pss_nid, ternary(use_pss_freq, 'freq', 'time'));

write_signed_packed32_qi_hexfile(output_filename_32, I,Q,0,addr_width)

figure;
subplot(2,2,1);
plot(real(complex_vec), 'b.-'); 
title('Original Real'); grid on;

subplot(2,2,2);
plot(imag(complex_vec), 'r.-'); 
title('Original Imag'); grid on;

subplot(2,2,3);
plot(double(I), 'b.-'); 
title('Quantized I (12-bit)'); grid on;
ylim([-2048, 2047]);

subplot(2,2,4);
plot(double(Q), 'r.-'); 
title('Quantized Q (12-bit)'); grid on;
ylim([-2048, 2047]);

function [I, Q, FS, clipI, clipQ] = complex_float_to_12bit(rc, headroom, use_dither)
% complex_float_to_12bit - Convert complex float to 12-bit signed integer
%
% Outputs:
%   I     - 16-bit signed (12-bit representation) real part
%   Q     - 16-bit signed (12-bit representation) imag part
%   FS    - Full-scale normalization factor
%   clipI - Fraction of clipped samples in real part
%   clipQ - Fraction of clipped samples in imag part
%
% Inputs:
%   rc         - Complex double/single array
%   headroom   - Attenuation factor (default=2, i.e., -6dB)
%   use_dither - Enable TPDF dithering (default=true)
%                Reduces quantization noise correlation

    if (nargin < 2 || isempty(headroom))
        headroom = 2;
    end 
    
    if (nargin < 3 || isempty(use_dither))
        use_dither = true;
    end

    rc = double(rc);

    % Calculate full-scale
    FS = max(abs(rc)) * headroom;

    if (FS == 0) 
        I = int16(zeros(numel(rc), 1)); 
        Q = int16(zeros(numel(rc), 1));
        clipI = 0; 
        clipQ = 0;
        return; 
    end 

    % Normalize to [-1, 1]
    rc_c = rc / FS;
    bitDepthScale = 2^11 - 1; % 2047 for 12-bit signed
    
    % Scale to integer range (float)
    Ii = real(rc_c) * bitDepthScale; 
    Qq = imag(rc_c) * bitDepthScale;
    
    % Apply TPDF dithering before rounding
    if use_dither
        % TPDF = sum of two uniform random variables in [-0.5, 0.5]
        % This decorrelates quantization noise from signal
        % LSB amplitude: 1 quantization level
        dither_i = (rand(size(Ii)) - 0.5) + (rand(size(Ii)) - 0.5);
        dither_q = (rand(size(Qq)) - 0.5) + (rand(size(Qq)) - 0.5);
        
        Ii = Ii + dither_i;
        Qq = Qq + dither_q;
    end
    
    % Round to nearest integer
    Ii = round(Ii);
    Qq = round(Qq);

    % Saturation to [-2048, 2047]
    Ii_sat = min(max(Ii, -(bitDepthScale + 1)), bitDepthScale);
    Qq_sat = min(max(Qq, -(bitDepthScale + 1)), bitDepthScale);

    I = int16(Ii_sat);
    Q = int16(Qq_sat);
    
    % Count clipped samples
    clipI = mean(Ii ~= Ii_sat);
    clipQ = mean(Qq ~= Qq_sat);
end

function write_signed16_iq_hexfile(fname, I, Q, start_addr, addr_width_hex)
% write_signed16_iq_hexfile - Write I/Q to HEX file with address
%
% Format: @ADDR VALUE (one sample per line, interleaved I/Q)
%
% Inputs:
%   fname          - Output filename
%   I, Q           - int16 arrays (same length)
%   start_addr     - Starting address (default=0)
%   addr_width_hex - Address width in hex digits (default=4)

    if nargin < 4 || isempty(start_addr)
        start_addr = 0;
    end
    if nargin < 5 || isempty(addr_width_hex)
        addr_width_hex = 4;
    end

    assert(numel(I) == numel(Q), 'I and Q must have same length');

    fid = fopen(fname, 'w');
    assert(fid ~= -1, 'Cannot open file: %s', fname);

    addr = uint32(start_addr);

    for k = 1:numel(I)
        % Write I (real)
        fprintf(fid, '@%0*X %d\n', addr_width_hex, addr, int16(I(k)));
        addr = addr + 1;

        % Write Q (imag)
        fprintf(fid, '@%0*X %d\n', addr_width_hex, addr, int16(Q(k)));
        addr = addr + 1;
    end

    fclose(fid);
end

function write_signed_packed32_qi_hexfile(fname, I, Q, start_addr, addr_width_hex) 
% write_signed_packed32_qi_hexfile - Write I/Q to HEX file with address
% Packs Q (MSB 16 bits) and I (LSB 16 bits) into single 32-bit word
%
% Format: @ADDR 0xQQQQIIII (one complex sample per line)
%         where QQQQ = Q[15:0] (signed, sign-extended to 16 bits)
%               IIII = I[15:0] (signed, sign-extended to 16 bits)
%
% Example: I=100, Q=-200
%          Packed word = 0xFF38_0064 (Q=-200 in MSB, I=100 in LSB)
%
% Inputs:
%   fname          - Output filename
%   I, Q           - int16 arrays (same length)
%   start_addr     - Starting address (default=0)
%   addr_width_hex - Address width in hex digits (default=4)

    if nargin < 4 || isempty(start_addr)
        start_addr = 0;
    end
    if nargin < 5 || isempty(addr_width_hex)
        addr_width_hex = 4;
    end

    assert(numel(I) == numel(Q), 'I and Q must have same length');

    fid = fopen(fname, 'w');
    assert(fid ~= -1, 'Cannot open file: %s', fname);

    addr = uint32(start_addr);

    for k = 1:numel(I)
        % Приводим к int16 (гарантируем диапазон [-32768, 32767])
        i_val = int16(I(k));
        q_val = int16(Q(k));
        
        % Конвертируем signed int16 в unsigned uint16 (сохраняет битовое представление)
        i_unsigned = typecast(i_val, 'uint16');
        q_unsigned = typecast(q_val, 'uint16');
        
        % Упаковка: Q в старшие 16 бит, I в младшие 16 бит
        packed_word = bitor(bitshift(uint32(q_unsigned), 16), uint32(i_unsigned));
        
        % Запись в файл: @ADDR 0xQQQQIIII
        fprintf(fid, '@%0*X 0x%08X\n', addr_width_hex, addr, packed_word);
        addr = addr + 1;
    end

    fclose(fid);
end

function out = ternary(cond, true_val, false_val)
    if cond
        out = true_val;
    else
        out = false_val;
    end
end
