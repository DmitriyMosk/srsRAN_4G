% доступные metric_id 
% "l1" c_corr_metrics(c_re, c_im, "l1") 
% где c_re и c_im - подсчитанные "значения" re и im корреляции
% PS - re и im может быть получена в любой функции корреляции
% можно просто подставить сюда
function res = c_corr_metrics(c_re, c_im,metric_id) 
    % исследуемая метрика корреляции
    % Проблема: магнитуда корреляции вычисляется очень дорого
    % ибо приходится делать re^2 + im^2, а ещё это нормализовать
    % решение: использовать упрощённые метрики, например l1

    % l1
    if (metric_id == "l1") 
        res = abs(c_re) + abs(c_im);
    else 
        metric_id = "default";
    end 
    
    % Schmidl-Cox
    if (metric_id == "default")  
        % res = (c_re^2 + c_im^2)/;
    end
end 