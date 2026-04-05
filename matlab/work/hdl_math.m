% модель math_iq_xcorr.sv via math_fma_macro.sv
% MCA - FMA с обратной связью
% A * B + C 

% имитированные два массива 
% комплексных чисел
I_y = int16([1, 2, 3, 4, 3, 2, 1]); % Re
Q_y = int16([3, 2, 1, 5, 3, 1, 6]); % Im

assert(numel(I_y) == numel(Q_y), "I_y and Q_y sizes not equal");

% Комплексно сопряжённый фрагмент
% I_y и Q_y 
I_s = int16([4, 3, 2]);
Q_s = int16([5, 3, 1]);

assert(numel(I_y) == numel(Q_y), "I_s and Q_s sizes not equal");

idx_s = 1;

% аккумулятор для реальной части
acc_re_1 = int32(0);
acc_re_2 = int32(0);

% аккумулятор для мнимой части
acc_im_1 = int32(0);
acc_im_2 = int32(0);

% y * conj(s) = (Iy+jQy)*(Is - jQs)

max_mag = 0; max_mag_sum = 0;

for idx_iq = 1:numel(I_y)
    Iy = int32(I_y(idx_iq));
    Qy = int32(Q_y(idx_iq));
    Is = int32(I_s(idx_s));
    Qs = int32(Q_s(idx_s));

    % Re += Iy*Is + Qy*Qs
    acc_re_1 = fma(Iy, Is, acc_re_1);
    acc_re_2 = fma(Qy, Qs, acc_re_2);

    % Im += Iy*Qs + Qy*Is
    acc_im_1 = fma(Iy, Qs, acc_im_1);
    acc_im_2 = fma(Qy, Is, acc_im_2);

    fprintf("acc_re_1=%d, acc_re_2=%d, acc_im_1=%d, acc_im_2=%d\n", ...
        acc_re_1, acc_re_2, acc_im_1, acc_im_2);

    idx_s = idx_s + 1;
    
    if idx_s > numel(I_s)
        idx_s = 1;
        
        acc_re = acc_re_1 + acc_re_2;
        acc_im = acc_im_2 - acc_im_1;
        
        mag2 = acc_re*acc_re + acc_im*acc_im;
        mag2_sum = acc_re + acc_im; 

        if (mag2 > max_mag) 
            max_mag = mag2;
        end 
        
        if (mag2_sum > max_mag_sum)
            max_mag_sum = mag2_sum;
        end 

        fprintf("pow=%d sum=%d acc_re=%d acc_im=%d\n", mag2, max_mag_sum, ...
            acc_re, acc_im);
        
        acc_re_1 = int32(0); acc_re_2 = int32(0);
        acc_im_1 = int32(0); acc_im_2 = int32(0);
    end
end

% fma operation example
function f = fma(a,b,c)
    f = a * b + c;
end 

ref_y = complex(double(I_y), double(Q_y));
ref_s = conj(complex(double(I_s), double(Q_s))); % уже комплексно сопряжённое

ref_y_seq_s = ref_y(4:6);

r = sum(ref_y_seq_s .* ref_s);
max_ref = real(r)^2 + imag(r)^2;

assert(max_ref == max_mag, sprintf("%d != %d\n", max_ref, max_mag));
fprintf("max_ref = max_mag = %d\n", max_mag);

% acc_re_1=4, acc_re_2=15, acc_im_1=5, acc_im_2=12
% acc_re_1=10, acc_re_2=21, acc_im_1=11, acc_im_2=18
% acc_re_1=16, acc_re_2=22, acc_im_1=14, acc_im_2=20
% pow=1480 sum=32
% acc_re_1=16, acc_re_2=25, acc_im_1=20, acc_im_2=20
% acc_re_1=25, acc_re_2=34, acc_im_1=29, acc_im_2=29
% acc_re_1=29, acc_re_2=35, acc_im_1=31, acc_im_2=31
% pow=4096 sum=64
% acc_re_1=4, acc_re_2=30, acc_im_1=5, acc_im_2=24
% max_ref = max_mag = 4096